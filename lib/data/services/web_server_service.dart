import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:sqflite/sqflite.dart';

import '../models/app_user.dart';
import '../models/delta_row.dart';
import '../models/linked_device.dart';
import '../repositories/linked_device_repository_impl.dart';
import '../../domain/models/permission.dart';
import '../../domain/repositories/linked_device_repository.dart';
import 'database_helper.dart';
import 'identity_service.dart';
import 'token_service.dart';
import 'web_api_routes.dart';

/// Runs on the phone. Serves the KashCube Web SPA + REST API over LAN.
///
/// Privacy guarantee: binds only to the local network interface.
/// No traffic ever leaves the LAN — this is the WhatsApp Web model.
///
/// Lifecycle (via [WebServerProvider]):
/// ```dart
/// await WebServerService.instance.start(spaHtml: html);
/// final qr = WebServerService.instance.qrPayload;
/// // ...
/// await WebServerService.instance.stop();
/// ```
class WebServerService {
  WebServerService._();
  static final WebServerService instance = WebServerService._();

  static const int _defaultPort = 8080;

  HttpServer? _server;
  String? _sessionToken;
  String? _webDeviceId;   // device_id of the active linked_devices row
  DateTime? _lastTouchAt; // debounces last_sync_at DB writes
  String? _spaHtml;

  /// WebSocket clients subscribed to real-time events.
  final List<WebSocketChannel> _wsClients = [];

  // ── Sync handler dependencies (lazy — initialised on first use) ──────────
  IdentityService get _identity       => IdentityService.instance;
  TokenService    get _tokenService   => TokenService(_identity);
  LinkedDeviceRepository get _linkedDeviceRepo => LinkedDeviceRepositoryImpl();

  bool get isRunning => _server != null;
  String? get sessionToken => _sessionToken;
  int? get port => _server?.port;

  /// Local base URL (http://192.168.x.x:8080).
  String? get localUrl {
    if (_server == null) return null;
    final ip = _lanIp ?? _server!.address.address;
    return 'http://$ip:${_server!.port}';
  }

  /// QR payload for the browser companion (JSON, type kashcube_web_v1).
  ///
  /// The browser parses this to get the WS URL and session token.
  /// WS URL: `ws://ip:port/ws?token=<token>`
  String? get qrPayload {
    final url = localUrl;
    if (url == null || _sessionToken == null) return null;
    final ip   = _lanIp ?? _server!.address.address;
    final port = _server!.port;
    return jsonEncode({
      'type':    'kashcube_web_v1',
      'ws':      'ws://$ip:$port/ws',
      'api':     '$url/api/v1',
      'token':   _sessionToken,
      'version': 1,
    });
  }

  String? _lanIp;

  // ── Start / Stop ──────────────────────────────────────────────────────────

  /// [spaHtml] is the pre-loaded content of `assets/web_ui/index.html`,
  /// loaded via Flutter's `rootBundle` in the provider before calling start().
  Future<void> start({int port = _defaultPort, String? spaHtml}) async {
    if (isRunning) return;

    _sessionToken = const Uuid().v4().replaceAll('-', '');
    _spaHtml = spaHtml;
    _lanIp = await _resolveLanIp();
    await _registerWebSession();

    // ── API router (all /api/* routes) ──────────────────────────────────────
    // shelf_router supports parameterized handlers via dynamic dispatch:
    //   (Request, String) → FutureOr<Response>
    final apiRouter = Router()
      ..get('/v1/auth/whoami', _handleWhoami)
      ..post('/v1/auth/revoke', _handleRevoke)
      ..get('/v1/dashboard', WebApiRoutes.dashboard)
      ..get('/v1/transactions', WebApiRoutes.listTransactions)
      ..get('/v1/transactions/<id>',
          (Request req, String id) => WebApiRoutes.getTransaction(req, id))
      ..post('/v1/transactions', WebApiRoutes.createTransaction)
      ..get('/v1/parties', WebApiRoutes.listParties)
      ..get('/v1/categories', WebApiRoutes.listCategories)
      ..get('/v1/invoices', WebApiRoutes.listInvoices)
      ..get('/v1/invoices/<id>/pdf',
          (Request req, String id) => WebApiRoutes.getInvoicePdf(req, id))
      ..get('/v1/credits', WebApiRoutes.listCredits);

    // Auth middleware applied to the entire API sub-pipeline
    final apiHandler = const Pipeline()
        .addMiddleware(_authMiddleware())
        .addHandler(apiRouter.call);

    // WebSocket — single endpoint for both sync protocol and live refresh.
    // Token validation happens before the HTTP → WS upgrade so invalid
    // browsers get a plain HTTP 401 rather than a WS handshake rejection.
    final wsHandler = webSocketHandler(
      (WebSocketChannel channel, String? _) {
        _wsClients.add(channel);
        channel.stream.listen(
          (data) async {
            try {
              final msg  = jsonDecode(data as String) as Map<String, dynamic>;
              final resp = await _handleSyncMessage(msg);
              channel.sink.add(jsonEncode(resp));
            } catch (_) {
              // Ignore malformed messages; live-refresh frames carry no body.
            }
          },
          onDone:  () => _wsClients.remove(channel),
          onError: (_) => _wsClients.remove(channel),
        );
      },
    );

    final mainRouter = Router()
      ..get('/', _serveIndex)
      ..get('/ws', (Request req) async {
        final token = req.url.queryParameters['token'];
        if (token == null || token != _sessionToken) {
          return Response(
            401,
            body: jsonEncode({'error': 'Unauthorized'}),
            headers: {'content-type': 'application/json'},
          );
        }
        return wsHandler(req);
      })
      ..mount('/api/', apiHandler);

    final handler = const Pipeline()
        .addMiddleware(_corsHeaders())
        .addHandler(mainRouter.call);

    _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
  }

  Future<void> stop() async {
    if (_server == null) return;
    for (final c in List.of(_wsClients)) {
      await c.sink.close();
    }
    _wsClients.clear();
    await _server!.close(force: true);
    await _revokeWebSession();
    _server = null;
    _sessionToken = null;
    _spaHtml = null;
  }

  /// Regenerate token — existing browser sessions are immediately invalidated.
  /// A new [linked_devices] row is inserted so the next browser scan appears
  /// in the Linked Devices list with its own last-active timestamp.
  Future<void> revokeSession() async {
    await _revokeWebSession();
    _sessionToken = const Uuid().v4().replaceAll('-', '');
    await _registerWebSession();
    _push({'event': 'session_revoked'});
  }

  /// Kills the current web session without creating a new one.
  /// Called when the user revokes the web device from Linked Devices screen.
  Future<void> killWebSession() async {
    await _revokeWebSession();
    _sessionToken = null;
  }

  // ── Web session DB helpers ────────────────────────────────────────────────

  Future<void> _registerWebSession() async {
    final newId  = const Uuid().v4();
    final syncId = const Uuid().v4().replaceAll('-', '');
    _webDeviceId = newId;
    await DatabaseHelper.instance.withDatabase((db) async {
      await db.insert(
        'linked_devices',
        {
          'sync_id':              syncId,
          'device_id':            newId,
          'device_name':          'KashCube Web',
          'device_type':          'web',
          'device_os':            'browser',
          'secondary_public_key': '',
          'permission_scope':     '{"read": true}',
          'business_scope':       '[]',
          'offline_grace_days':   0,
          'created_at':           DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    });
  }

  Future<void> _revokeWebSession() async {
    final id = _webDeviceId;
    if (id == null) return;
    _webDeviceId = null;
    await DatabaseHelper.instance.withDatabase((db) async {
      await db.update(
        'linked_devices',
        {'revoked_at': DateTime.now().toIso8601String()},
        where:     'device_id = ?',
        whereArgs: [id],
      );
    });
  }

  /// Updates `last_sync_at` on the web session row, debounced to once/minute.
  Future<void> _touchLastActive() async {
    final id  = _webDeviceId;
    final now = DateTime.now();
    if (id == null) return;
    if (_lastTouchAt != null &&
        now.difference(_lastTouchAt!) < const Duration(minutes: 1)) {
      return;
    }
    _lastTouchAt = now;
    await DatabaseHelper.instance.withDatabase((db) async {
      await db.update(
        'linked_devices',
        {'last_sync_at': now.toIso8601String()},
        where:     'device_id = ?',
        whereArgs: [id],
      );
    });
  }

  // ── Real-time push ────────────────────────────────────────────────────────

  void _push(Map<String, dynamic> event) {
    final payload = jsonEncode(event);
    for (final c in List.of(_wsClients)) {
      try {
        c.sink.add(payload);
      } catch (_) {
        _wsClients.remove(c);
      }
    }
  }

  /// Notify connected browsers that a transaction was created/updated.
  void notifyTransactionChange(Map<String, dynamic> txn,
      {bool created = true}) {
    _push({
      'event': created ? 'transaction_created' : 'transaction_updated',
      'data': txn,
    });
  }

  // ── Middleware ────────────────────────────────────────────────────────────

  /// Checks `X-KashCube-Token` header or `?token=` query param.
  /// Returns 401 if missing or invalid.
  /// Also debounces a `last_sync_at` update so the Linked Devices screen
  /// shows "Last active" correctly (WhatsApp Web model).
  Middleware _authMiddleware() {
    return (Handler inner) => (Request req) async {
          final header = req.headers['x-kashcube-token'];
          final query = req.url.queryParameters['token'];
          final provided = header ?? query;
          if (provided == null || provided != _sessionToken) {
            return Response(
              401,
              body: jsonEncode({'error': 'Unauthorized'}),
              headers: {'content-type': 'application/json'},
            );
          }
          unawaited(_touchLastActive());
          return inner(req);
        };
  }

  Middleware _corsHeaders() {
    return (Handler inner) => (Request req) async {
          if (req.method == 'OPTIONS') {
            return Response.ok('', headers: _cors);
          }
          final res = await inner(req);
          return res.change(headers: _cors);
        };
  }

  static const Map<String, String> _cors = {
    'access-control-allow-origin': '*',
    'access-control-allow-methods': 'GET, POST, OPTIONS',
    'access-control-allow-headers': 'content-type, x-kashcube-token',
  };

  // ── SPA serving ───────────────────────────────────────────────────────────

  Response _serveIndex(Request req) {
    final html = _spaHtml ?? _fallbackHtml;
    return Response.ok(html,
        headers: {'content-type': 'text/html; charset=utf-8'});
  }

  // ── Auth handlers ─────────────────────────────────────────────────────────

  Response _handleWhoami(Request req) => Response.ok(
        jsonEncode({'ok': true, 'server': 'KashCube Web v1'}),
        headers: {'content-type': 'application/json'},
      );

  Future<Response> _handleRevoke(Request req) async {
    await revokeSession();
    return Response.ok(
      jsonEncode({'ok': true}),
      headers: {'content-type': 'application/json'},
    );
  }

  // ── LAN IP ────────────────────────────────────────────────────────────────

  static Future<String?> _resolveLanIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (final iface in interfaces) {
        if (iface.name.toLowerCase().contains('wlan') ||
            iface.name.toLowerCase().contains('en') ||
            iface.name.toLowerCase().contains('wifi')) {
          for (final addr in iface.addresses) {
            if (!addr.isLoopback) return addr.address;
          }
        }
      }
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (_) {}
    return null;
  }

  // ── Inline SPA ────────────────────────────────────────────────────────────
  // Used when rootBundle asset isn't available (tests, debug without build).

  static const String _fallbackHtml = '''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>KashCube Web</title>
  <style>
    *{box-sizing:border-box;margin:0;padding:0}
    body{font-family:system-ui,sans-serif;background:#f5f5f5;color:#333}
    .shell{max-width:1100px;margin:0 auto;padding:24px 16px}
    header{display:flex;align-items:center;gap:12px;margin-bottom:32px}
    header h1{font-size:1.4rem;color:#1B5E20;font-weight:700}
    .badge{background:#E8F5E9;color:#2E7D32;padding:4px 10px;border-radius:999px;font-size:.75rem;font-weight:600}
    .card{background:#fff;border-radius:12px;padding:20px;margin-bottom:16px;box-shadow:0 1px 3px rgba(0,0,0,.08)}
    .card h2{font-size:1rem;color:#555;margin-bottom:16px}
    table{width:100%;border-collapse:collapse;font-size:.9rem}
    th{text-align:left;padding:8px 12px;border-bottom:2px solid #eee;color:#888;font-weight:600;font-size:.8rem;text-transform:uppercase;letter-spacing:.05em}
    td{padding:10px 12px;border-bottom:1px solid #f0f0f0}
    .inc{color:#2E7D32;font-weight:600}.exp{color:#C62828;font-weight:600}
    .loading{color:#999;font-style:italic}
    .summary{display:grid;grid-template-columns:repeat(auto-fit,minmax(160px,1fr));gap:12px}
    .stat{text-align:center}.stat-val{font-size:1.4rem;font-weight:700;color:#1B5E20}
    .stat-lbl{font-size:.8rem;color:#888;margin-top:4px}.err{color:#C62828}
    .add-form{display:flex;flex-wrap:wrap;gap:8px;align-items:flex-end}
    .add-form label{display:flex;flex-direction:column;font-size:.8rem;color:#666;gap:4px}
    .add-form input,.add-form select{padding:8px 10px;border:1px solid #ddd;border-radius:6px;font-size:.9rem}
    .btn{background:#1B5E20;color:#fff;border:none;border-radius:6px;padding:9px 18px;cursor:pointer;font-size:.9rem;font-weight:600}
    .btn:hover{background:#2E7D32}.btn-sm{padding:6px 12px;font-size:.8rem}
    nav{display:flex;gap:8px;margin-bottom:24px}
    .tab{padding:8px 16px;border-radius:6px;cursor:pointer;font-weight:600;font-size:.85rem;background:#eee;border:none}
    .tab.active{background:#1B5E20;color:#fff}
    .hidden{display:none}
  </style>
</head>
<body>
<div class="shell">
  <header>
    <h1>KashCube Web</h1>
    <span class="badge" id="status">Connecting…</span>
  </header>

  <nav>
    <button class="tab active" onclick="switchTab('dashboard')">Dashboard</button>
    <button class="tab" onclick="switchTab('transactions')">Transactions</button>
    <button class="tab" onclick="switchTab('add')">+ Add</button>
    <button class="tab" onclick="switchTab('invoices')">Invoices</button>
    <button class="tab" onclick="switchTab('credits')">Credits</button>
  </nav>

  <!-- Dashboard -->
  <div id="tab-dashboard">
    <div class="card">
      <div class="summary" style="margin-bottom:0">
        <div class="stat"><div class="stat-val" id="s-income">—</div><div class="stat-lbl">Income (month)</div></div>
        <div class="stat"><div class="stat-val" id="s-expense" style="color:#C62828">—</div><div class="stat-lbl">Expense (month)</div></div>
        <div class="stat"><div class="stat-val" id="s-net">—</div><div class="stat-lbl">Net</div></div>
        <div class="stat"><div class="stat-val" id="s-credits" style="color:#E65100">—</div><div class="stat-lbl">Outstanding credits</div></div>
      </div>
    </div>
    <div class="card">
      <h2>Recent Transactions</h2>
      <table><thead><tr><th>Date</th><th>Note</th><th>Category</th><th>Party</th><th>Amount</th></tr></thead>
      <tbody id="recent-body"><tr><td colspan="5" class="loading">Loading…</td></tr></tbody></table>
    </div>
  </div>

  <!-- Transactions -->
  <div id="tab-transactions" class="hidden">
    <div class="card" style="display:flex;gap:8px;align-items:center;flex-wrap:wrap">
      <input id="txn-search" placeholder="Search…" style="flex:1;min-width:160px;padding:8px 10px;border:1px solid #ddd;border-radius:6px">
      <button class="btn btn-sm" onclick="loadTransactions()">Search</button>
    </div>
    <div class="card">
      <table><thead><tr><th>Date</th><th>Note</th><th>Category</th><th>Party</th><th>Method</th><th>Amount</th></tr></thead>
      <tbody id="txn-body"><tr><td colspan="6" class="loading">Loading…</td></tr></tbody></table>
      <div style="margin-top:12px;display:flex;gap:8px">
        <button class="btn btn-sm" id="btn-prev" onclick="txnPage--; loadTransactions()" disabled>← Prev</button>
        <span id="txn-pager" style="font-size:.85rem;color:#888;line-height:1.8rem"></span>
        <button class="btn btn-sm" id="btn-next" onclick="txnPage++; loadTransactions()">Next →</button>
      </div>
    </div>
  </div>

  <!-- Add Transaction -->
  <div id="tab-add" class="hidden">
    <div class="card">
      <h2 style="margin-bottom:16px">Add Transaction</h2>
      <div class="add-form" id="add-form">
        <label>Type<select id="f-type"><option value="income">Income</option><option value="expense" selected>Expense</option></select></label>
        <label>Amount (₹)<input id="f-amount" type="number" min="0.01" step="0.01" placeholder="0.00"></label>
        <label>Date<input id="f-date" type="date"></label>
        <label>Note<input id="f-note" placeholder="e.g. Supplier payment"></label>
        <label>Category<input id="f-category" placeholder="e.g. Food" list="cat-list"><datalist id="cat-list"></datalist></label>
        <label>Party<input id="f-party" placeholder="e.g. Ravi Traders" list="party-list"><datalist id="party-list"></datalist></label>
        <label>Method<select id="f-method"><option>Cash</option><option>UPI</option><option>Card</option><option>Net Banking</option><option>Wallet</option></select></label>
        <button class="btn" onclick="submitTxn()">Save</button>
      </div>
      <p id="add-msg" style="margin-top:12px;font-size:.9rem"></p>
    </div>
  </div>

  <!-- Invoices -->
  <div id="tab-invoices" class="hidden">
    <div class="card">
      <table><thead><tr><th>#</th><th>Party</th><th>Date</th><th>Due</th><th>Status</th><th>Amount</th></tr></thead>
      <tbody id="inv-body"><tr><td colspan="6" class="loading">Loading…</td></tr></tbody></table>
    </div>
  </div>

  <!-- Credits -->
  <div id="tab-credits" class="hidden">
    <div class="card">
      <table><thead><tr><th>Party</th><th>Type</th><th>Amount</th><th>Paid</th><th>Due</th><th>Status</th></tr></thead>
      <tbody id="cr-body"><tr><td colspan="6" class="loading">Loading…</td></tr></tbody></table>
    </div>
  </div>
</div>

<script>
const TOKEN = (new URLSearchParams(location.search)).get('token') || sessionStorage.getItem('kcToken') || '';
if (TOKEN) sessionStorage.setItem('kcToken', TOKEN);
if (!TOKEN) document.getElementById('status').textContent = 'No token — scan QR from phone';

const H = {'X-KashCube-Token': TOKEN};
const fmt = n => '₹' + Math.abs(n).toLocaleString('en-IN', {maximumFractionDigits:2});

let txnPage = 1;

function switchTab(name) {
  ['dashboard','transactions','add','invoices','credits'].forEach(t => {
    document.getElementById('tab-'+t).classList.toggle('hidden', t !== name);
    document.querySelectorAll('.tab')[['dashboard','transactions','add','invoices','credits'].indexOf(t)]
      .classList.toggle('active', t === name);
  });
  if (name === 'transactions') loadTransactions();
  if (name === 'invoices') loadInvoices();
  if (name === 'credits') loadCredits();
  if (name === 'add') loadAutocomplete();
}

async function api(path) {
  const r = await fetch(path, {headers: H});
  if (!r.ok) throw new Error(await r.text());
  return r.json();
}

async function loadDashboard() {
  try {
    const [dash] = await Promise.all([api('/api/v1/dashboard')]);
    document.getElementById('status').textContent = 'Connected';
    document.getElementById('s-income').textContent = fmt(dash.this_month_income);
    document.getElementById('s-expense').textContent = fmt(dash.this_month_expense);
    const net = dash.net, el = document.getElementById('s-net');
    el.textContent = (net>=0?'+':'-')+fmt(net);
    el.style.color = net>=0 ? '#2E7D32' : '#C62828';
    document.getElementById('s-credits').textContent = fmt(dash.outstanding_credits);
    document.getElementById('recent-body').innerHTML = (dash.recent_transactions||[]).map(txnHtml).join('') || noRows(5);
  } catch(e) { document.getElementById('status').textContent = 'Error: '+e.message; }
}

async function loadTransactions() {
  const q = document.getElementById('txn-search').value;
  try {
    const d = await api('/api/v1/transactions?page='+txnPage+'&limit=50&search='+encodeURIComponent(q));
    document.getElementById('txn-body').innerHTML = (d.items||[]).map(t => txnHtml(t, true)).join('') || noRows(6);
    const pages = Math.ceil(d.total/d.limit)||1;
    document.getElementById('txn-pager').textContent = 'Page '+d.page+' / '+pages+' ('+d.total+' total)';
    document.getElementById('btn-prev').disabled = d.page <= 1;
    document.getElementById('btn-next').disabled = d.page >= pages;
  } catch(e) { document.getElementById('txn-body').innerHTML = '<tr><td colspan="6" class="err">'+e.message+'</td></tr>'; }
}

async function loadInvoices() {
  try {
    const d = await api('/api/v1/invoices?limit=100');
    document.getElementById('inv-body').innerHTML = (d.items||[]).map(i =>
      '<tr><td>'+i.invoice_number+'</td><td>'+(i.party_name||'—')+'</td><td>'+i.invoice_date+'</td><td>'+(i.due_date||'—')+'</td><td>'+i.status+'</td><td>'+fmt(i.total_amount)+'</td></tr>'
    ).join('') || noRows(6);
  } catch(e) { document.getElementById('inv-body').innerHTML = '<tr><td colspan="6" class="err">'+e.message+'</td></tr>'; }
}

async function loadCredits() {
  try {
    const d = await api('/api/v1/credits?limit=100');
    document.getElementById('cr-body').innerHTML = (d.items||[]).map(c =>
      '<tr><td>'+(c.party_name||'—')+'</td><td>'+c.type+'</td><td>'+fmt(c.amount)+'</td><td>'+fmt(c.paid_amount||0)+'</td><td>'+(c.due_date||'—')+'</td><td>'+c.status+'</td></tr>'
    ).join('') || noRows(6);
  } catch(e) { document.getElementById('cr-body').innerHTML = '<tr><td colspan="6" class="err">'+e.message+'</td></tr>'; }
}

async function loadAutocomplete() {
  try {
    const [cats, parties] = await Promise.all([api('/api/v1/categories'), api('/api/v1/parties')]);
    document.getElementById('cat-list').innerHTML = (cats.items||[]).map(c=>'<option value="'+c.name+'">').join('');
    document.getElementById('party-list').innerHTML = (parties.items||[]).map(p=>'<option value="'+p.name+'">').join('');
  } catch(_) {}
  document.getElementById('f-date').value = new Date().toISOString().slice(0,10);
}

async function submitTxn() {
  const msg = document.getElementById('add-msg');
  msg.style.color='#555'; msg.textContent = 'Saving…';
  const body = {
    amount: parseFloat(document.getElementById('f-amount').value),
    type: document.getElementById('f-type').value,
    date: document.getElementById('f-date').value,
    notes: document.getElementById('f-note').value,
    category: document.getElementById('f-category').value || 'Other',
    party_name: document.getElementById('f-party').value || null,
    payment_method: document.getElementById('f-method').value,
  };
  try {
    const r = await fetch('/api/v1/transactions', {method:'POST', headers:{...H,'content-type':'application/json'}, body: JSON.stringify(body)});
    if (!r.ok) throw new Error(await r.text());
    msg.style.color='#2E7D32'; msg.textContent = '✓ Transaction saved';
    document.getElementById('f-amount').value='';
    document.getElementById('f-note').value='';
  } catch(e) { msg.style.color='#C62828'; msg.textContent = 'Error: '+e.message; }
}

function txnHtml(t, wide=false) {
  const cls = (t.type||'').includes('income')||(t.type||'').includes('received') ? 'inc' : 'exp';
  const sign = cls==='inc' ? '+' : '-';
  const extra = wide ? '<td>'+(t.payment_method||'—')+'</td>' : '';
  return '<tr><td>'+t.date+'</td><td>'+(t.note||'—')+'</td><td>'+(t.category||'—')+'</td><td>'+(t.party||'—')+'</td>'+extra+'<td class="'+cls+'">'+sign+fmt(t.amount)+'</td></tr>';
}

function noRows(cols) { return '<tr><td colspan="'+cols+'" class="loading">No data yet.</td></tr>'; }

// WebSocket live refresh
if (TOKEN) {
  const ws = new WebSocket((location.protocol==='https:' ? 'wss:' : 'ws:')+'//'+location.host+'/ws');
  ws.onmessage = e => {
    const ev = JSON.parse(e.data);
    if (['transaction_created','transaction_updated'].includes(ev.event)) loadDashboard();
    if (ev.event === 'session_revoked') { sessionStorage.removeItem('kcToken'); location.reload(); }
    if (ev.event === 'server_shutdown') document.getElementById('status').textContent = 'Server stopped';
  };
  loadDashboard();
}
</script>
</body>
</html>''';

  // ── WebSocket sync protocol handlers ─────────────────────────────────────
  //
  // Mirrors SyncServer message handling over WebSocket.
  // On web the browser is the secondary device; messages arrive over the
  // same `/ws` connection used for live-refresh push events.

  /// Routes an incoming WS message to the appropriate sync handler.
  /// Returns the response map to be JSON-encoded and sent back.
  Future<Map<String, dynamic>> _handleSyncMessage(
      Map<String, dynamic> msg) async {
    switch (msg['type'] as String?) {
      case 'pair_request':
        return _wsHandlePairRequest(msg);
      case 'delta_request':
        return _wsHandleDeltaRequest(msg);
      case 'delta_upload':
        return _wsHandleDeltaUpload(msg);
      default:
        return {'type': 'error', 'message': 'unknown_type'};
    }
  }

  Future<Map<String, dynamic>> _wsHandlePairRequest(
      Map<String, dynamic> msg) async {
    final secondaryDeviceId   = msg['device_id']   as String;
    final secondaryDeviceName = msg['device_name']  as String;
    final secondaryPublicKey  = msg['public_key']   as String;
    final deviceOs            = msg['device_os']    as String?;
    final deviceType          = msg['device_type']  as String?;
    final presetStr           = msg['preset']       as String? ?? 'owner_mirror';
    final secondaryIdentityId  = msg['secondary_identity_id']  as String?;
    final secondaryDisplayName = msg['secondary_display_name'] as String?;

    final preset = DevicePreset.fromDb(presetStr);
    final syncId = const Uuid().v4().replaceAll('-', '');

    final device = LinkedDevice(
      syncId:               syncId,
      deviceId:             secondaryDeviceId,
      deviceName:           secondaryDeviceName,
      deviceOs:             deviceOs,
      deviceType:           deviceType,
      secondaryPublicKey:   secondaryPublicKey,
      permissionScope:      _wsPermScopeForPreset(preset),
      businessScope:        '[]',
      offlineGraceDays:     7,
      preset:               preset,
      secondaryIdentityId:  secondaryIdentityId,
      secondaryDisplayName: secondaryDisplayName,
    );

    await _linkedDeviceRepo.insert(device);

    final planFeatures =
        await DatabaseHelper.instance.withDatabase(_wsLoadPlanFeatures);

    final token          = await _tokenService.issue(device, planFeatures: planFeatures);
    final primaryKeyB64  = await _identity.publicKeyBase64;
    final primaryDeviceId = await _identity.deviceId;

    return {
      'type':               'pair_response',
      'token_payload':      token.payload,
      'token_signature':    token.signatureBase64,
      'primary_public_key': primaryKeyB64,
      'primary_device_id':  primaryDeviceId,
    };
  }

  Future<Map<String, dynamic>> _wsHandleDeltaRequest(
      Map<String, dynamic> msg) async {
    if (!await _wsVerifyToken(msg)) {
      return {'type': 'error', 'message': 'invalid_token'};
    }

    final tokenPayload   = msg['token_payload'] as String;
    final decodedPayload = jsonDecode(tokenPayload) as Map<String, dynamic>;
    final callerDeviceId = decodedPayload['device_id'] as String;

    final device = await _linkedDeviceRepo.getByDeviceId(callerDeviceId);
    if (device == null || !device.isActive) {
      return {'type': 'revocation', 'message': 'device_revoked'};
    }

    final lastSyncAt = msg['last_sync_at'] as String?;
    final rows = await _wsCollectDeltas(since: lastSyncAt, device: device);

    return {
      'type':        'delta_response',
      'rows':        rows.map((r) => r.toJson()).toList(),
      'server_time': DateTime.now().toIso8601String(),
    };
  }

  Future<Map<String, dynamic>> _wsHandleDeltaUpload(
      Map<String, dynamic> msg) async {
    if (!await _wsVerifyToken(msg)) {
      return {'type': 'error', 'message': 'invalid_token'};
    }

    final tokenPayload   = msg['token_payload'] as String;
    final decodedPayload = jsonDecode(tokenPayload) as Map<String, dynamic>;
    final callerDeviceId = decodedPayload['device_id'] as String;

    final device = await _linkedDeviceRepo.getByDeviceId(callerDeviceId);
    if (device == null || !device.isActive) {
      return {'type': 'revocation', 'message': 'device_revoked'};
    }

    final rawRows = (msg['rows'] as List<dynamic>?) ?? [];
    final rows =
        rawRows.map((r) => DeltaRow.fromJson(r as Map<String, dynamic>)).toList();
    await _wsApplyDeltas(rows, device: device);

    return {'type': 'upload_ack', 'received_count': rows.length};
  }

  // ── Sync helpers ──────────────────────────────────────────────────────────

  static const List<String> _wsSyncableTables = [
    'transactions', 'credits', 'credit_payments', 'loans',
    'parties',      'accounts', 'categories',     'budgets',
  ];

  static const List<String> _wsBusinessScopedTables = [
    'transactions', 'credits', 'credit_payments', 'loans', 'budgets',
  ];

  Future<bool> _wsVerifyToken(Map<String, dynamic> msg) async {
    final tokenPayload = msg['token_payload']   as String?;
    final tokenSig     = msg['token_signature'] as String?;
    if (tokenPayload == null || tokenSig == null) return false;
    final pubKeyB64 = await _identity.publicKeyBase64;
    return _identity.verify(
      message:         utf8.encode(tokenPayload),
      sigBase64:       tokenSig,
      publicKeyBase64: pubKeyB64,
    );
  }

  Future<List<DeltaRow>> _wsCollectDeltas({
    String? since,
    LinkedDevice? device,
  }) =>
      DatabaseHelper.instance.withDatabase((db) async {
        final isOwner     = device?.isOwnerMirror ?? true;
        List<int> bizIds  = [];
        if (!isOwner && device != null) {
          bizIds =
              (jsonDecode(device.businessScope) as List<dynamic>).cast<int>();
        }

        final tables = isOwner ? _wsSyncableTables : _wsBusinessScopedTables;
        final rows   = <DeltaRow>[];

        for (final table in tables) {
          try {
            late List<Map<String, dynamic>> results;
            if (isOwner) {
              results = await db.query(
                table,
                where:     since != null ? 'updated_at > ?' : null,
                whereArgs: since != null ? [since] : null,
              );
            } else {
              if (bizIds.isEmpty) continue;
              final placeholders = bizIds.map((_) => '?').join(',');
              results = since != null
                  ? await db.rawQuery(
                      'SELECT * FROM $table WHERE updated_at > ? AND business_id IN ($placeholders)',
                      [since, ...bizIds],
                    )
                  : await db.rawQuery(
                      'SELECT * FROM $table WHERE business_id IN ($placeholders)',
                      bizIds,
                    );
            }
            for (final row in results) {
              rows.add(DeltaRow(
                table:     table,
                syncId:    row['sync_id']    as String? ?? '',
                version:   row['version']    as int?    ?? 0,
                updatedAt: row['updated_at'] as String? ??
                           row['created_at'] as String? ??
                           DateTime.now().toIso8601String(),
                operation: row['deleted_at'] != null ? 'delete' : 'upsert',
                payload:   row['deleted_at'] == null
                    ? Map<String, dynamic>.from(row)
                    : null,
              ));
            }
          } catch (_) {
            continue;
          }
        }
        return rows;
      });

  Future<void> _wsApplyDeltas(List<DeltaRow> rows,
      {LinkedDevice? device}) =>
      DatabaseHelper.instance.withDatabase((db) async {
        final isOwner    = device?.isOwnerMirror ?? true;
        List<int> bizIds = [];
        if (!isOwner && device != null) {
          bizIds =
              (jsonDecode(device.businessScope) as List<dynamic>).cast<int>();
        }
        for (final row in rows) {
          if (!_wsSyncableTables.contains(row.table)) continue;
          if (!isOwner) {
            if (bizIds.isEmpty) continue;
            final bid = row.payload?['business_id'];
            if (bid == null || !bizIds.contains(bid as int)) continue;
          }
          if (row.isUpsert && row.payload != null) {
            await db.insert(row.table, row.payload!,
                conflictAlgorithm: ConflictAlgorithm.replace);
          } else if (row.isDelete) {
            await db.update(
              row.table,
              {'deleted_at': DateTime.now().toIso8601String()},
              where:     'sync_id = ?',
              whereArgs: [row.syncId],
            );
          }
        }
      });

  Future<Map<String, dynamic>> _wsLoadPlanFeatures(Database db) async {
    final subRows =
        await db.query('subscription', limit: 1);
    final plan = subRows.isNotEmpty
        ? (subRows.first['plan'] as String? ?? 'free')
        : 'free';
    final featureRows = await db.query('plan_features',
        where: 'plan = ?', whereArgs: [plan]);
    final features = <String, dynamic>{};
    for (final row in featureRows) {
      features[row['feature'] as String] = {
        'enabled': (row['enabled'] as int?) == 1,
        'limit':   row['limit_value'] as int? ?? 0,
      };
    }
    if (subRows.isNotEmpty) {
      await db.update('subscription',
          {'shareable_plan_features': jsonEncode(features)});
    }
    return features;
  }

  static String _wsPermScopeForPreset(DevicePreset preset) {
    if (preset == DevicePreset.ownerMirror) return '{}';
    late AppUserRole role;
    switch (preset) {
      case DevicePreset.manager:
        role = AppUserRole.manager;
      case DevicePreset.cashier:
        role = AppUserRole.cashier;
      case DevicePreset.auditor:
        role = AppUserRole.auditor;
      default:
        role = AppUserRole.custom;
    }
    final scope = <String, Map<String, bool>>{};
    for (final module in PermissionModule.all) {
      final p = RolePreset.forModule(role, module);
      scope[module] = {
        'canView':   p.canView,
        'canCreate': p.canCreate,
        'canEdit':   p.canEdit,
        'canDelete': p.canDelete,
      };
    }
    return jsonEncode(scope);
  }
}
