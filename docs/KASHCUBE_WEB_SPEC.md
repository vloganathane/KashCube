# KashCube Web — LAN Companion Spec
# Browser access to your KashCube data over Wi-Fi — no internet, no cloud

**Version:** 1.0  
**Date:** 13 March 2026  
**Status:** IN PROGRESS — Sprint 1 underway  
**Privacy model:** 100% LAN-only. Phone is the server. Zero data leaves the device.

---

## Overview

KashCube Web lets a user access their phone's financial data from any browser on the **same Wi-Fi network** — exactly like WhatsApp Web. The phone runs a lightweight HTTP server (`shelf`). The browser loads a bundled single-page app served by that server. No KashCube cloud, no relay, no account.

```
Phone (SQLite + shelf HTTP :8080)  ←──WiFi LAN──►  Browser
         NO internet involved
```

---

## Use Cases

| Scenario | Value |
|----------|-------|
| Shop counter with desktop PC | Keyboard-friendly transaction & invoice entry |
| Accountant reviews on laptop | Read-only browse + download PDFs |
| Owner prints invoices | Browser print dialog, no phone in hand |

---

## Architecture

### Phone Side (Dart / Flutter)

```
KashCubeWebServer (shelf)
├── GET  /                           → serve bundled web UI (index.html)
├── GET  /assets/**                  → serve bundled JS/CSS/icons
├── GET  /api/v1/auth/whoami         → check session token validity
├── GET  /api/v1/dashboard           → summary card data
├── GET  /api/v1/transactions        → paginated list (page, limit, search, dateFrom, dateTo)
├── GET  /api/v1/transactions/:id    → single transaction
├── POST /api/v1/transactions        → create transaction (JSON body)
├── GET  /api/v1/parties             → party list (search)
├── GET  /api/v1/categories          → category list
├── GET  /api/v1/invoices            → invoice list (page, limit)
├── GET  /api/v1/invoices/:id/pdf    → stream PDF bytes → browser print
├── GET  /api/v1/credits             → credit/udhar list
├── WS   /ws                         → real-time push (JSON events)
└── POST /api/v1/auth/revoke         → invalidate session
```

### Browser Side (bundled SPA)

Plain HTML + vanilla JS (or Svelte pre-compiled). Built and committed as:
```
assets/web_ui/
    index.html
    app.js        ← compiled, minified
    app.css
    icons/
```

Served statically by the shelf server. No CDN, no external URLs.

---

## Pairing Flow

```
1. User opens Settings → "KashCube Web" on phone
2. App starts shelf server on :8080 (configurable)
3. Generates a UUID session token  (32 hex chars)
4. Renders QR code:  kashcube-web://<LAN-IP>:8080?token=<TOKEN>
5. User scans QR from browser companion page
   OR navigates to http://<LAN-IP>:8080 + pastes token
6. Every API request must include header:  X-KashCube-Token: <TOKEN>
7. Phone shows "Web active" chip in Settings with a Disconnect button
```

### QR Payload Format
```
kashcube-web://192.168.1.5:8080?token=a3f9c2...
```
The SPA parses this URL scheme to extract host + token and stores both in `sessionStorage` (cleared on tab close).

---

## Security

| Concern | Mitigation |
|---------|-----------|
| Unauthorized LAN access | UUID session token required on every request (401 without it) |
| Token leakage on shared WiFi | Recommend users avoid shared/public WiFi; future: self-signed TLS |
| Token persistence | Token lives only in `sessionStorage` — wiped on browser close |
| Multiple sessions | One active token at a time; new QR scan revokes previous |
| App backgrounded | Token revoked on app pause > 30 min (configurable) |
| Phone screen lock | Option to auto-revoke on lock (default: warn, don't force-revoke) |

---

## Data Model — API Responses

### `GET /api/v1/transactions`
```json
{
  "page": 1, "limit": 50, "total": 312,
  "items": [
    {
      "id": 42,
      "amount": 5000.00,
      "type": "expense",
      "note": "Supplier payment",
      "category": "Purchases",
      "party": "Ravi Traders",
      "date": "2026-03-13",
      "payment_method": "UPI",
      "created_at": "2026-03-13T14:22:00"
    }
  ]
}
```

### `POST /api/v1/transactions`
```json
{
  "amount": 1500,
  "type": "income",
  "note": "Sale — Table 3",
  "category_id": 5,
  "party_id": null,
  "date": "2026-03-13",
  "payment_method": "Cash"
}
```
Returns `201 Created` with the created row.

### `GET /api/v1/dashboard`
```json
{
  "this_month_income": 245000,
  "this_month_expense": 89000,
  "net": 156000,
  "outstanding_credits": 34500,
  "recent_transactions": [...]
}
```

---

## WebSocket Events (real-time push)

```json
{ "event": "transaction_created", "data": { ...transaction } }
{ "event": "transaction_updated", "data": { ...transaction } }
{ "event": "server_shutdown"                                  }
```

The browser reconnects automatically (exponential back-off, max 30s).

---

## Web UI Scope (v1)

| Screen | Reads | Writes |
|--------|-------|--------|
| Dashboard | ✅ | — |
| Transaction list + search | ✅ | — |
| Add transaction (quick form) | — | ✅ |
| Party list | ✅ | — |
| Invoice list + PDF print | ✅ | — |

Deliberately excluded from v1: edit/delete, credits management, reports, settings.

---

## Implementation Plan

### Sprint W1 — Phone HTTP Server

| Task | File | Notes |
|------|------|-------|
| W1-T1 | Add `shelf`, `shelf_router`, `shelf_web_socket` to pubspec | ✅ DONE |
| W1-T2 | `lib/data/services/web_server_service.dart` | shelf server, token auth middleware, CORS headers |
| W1-T3 | `lib/data/services/web_api_routes.dart` | All REST handlers (read-only first) |
| W1-T4 | `lib/presentation/screens/settings/kashcube_web_screen.dart` | QR display, status, revoke |
| W1-T5 | Wire into `settings_screen.dart` | New tile "KashCube Web" |
| W1-T6 | `lib/presentation/providers/web_server_provider.dart` | StateNotifier |

### Sprint W2 — Web UI (SPA)

| Task | Notes |
|------|-------|
| W2-T1 | Build vanilla-JS SPA in `assets/web_ui/` |
| W2-T2 | Dashboard + transaction list |
| W2-T3 | Add transaction form |
| W2-T4 | Invoice list + PDF print |
| W2-T5 | WebSocket live updates |

### Sprint W3 — Polish

| Task | Notes |
|------|-------|
| W3-T1 | Auto-revoke on app pause > N min |
| W3-T2 | Active sessions list in phone UI |
| W3-T3 | Foreground service notification ("KashCube Web is active") |
| W3-T4 | POST /api/v1/transactions write support |

---

## Dependencies Added

```yaml
shelf: ^1.4.2
shelf_router: ^1.1.4
shelf_web_socket: ^3.0.0
```

All pure Dart — no native platform channels, no network calls outside LAN.

---

## Files Created / Modified

### Sprint W1
- `pubspec.yaml` — 3 shelf packages added
- `lib/data/services/web_server_service.dart` — NEW
- `lib/data/services/web_api_routes.dart` — NEW
- `lib/presentation/providers/web_server_provider.dart` — NEW
- `lib/presentation/screens/settings/kashcube_web_screen.dart` — NEW
- `lib/presentation/screens/settings/settings_screen.dart` — add tile
- `assets/web_ui/index.html` — NEW (placeholder for Sprint W2)
