# Future Vision: Bazaar Protocol — Open P2P Commerce for India

**Status:** FUTURE PLANNING — implement only after core app reaches 100%  
**Date brainstormed:** 26 March 2026  
**Last revised:** 26 March 2026 (F2 dropped; protocol-first model adopted)  
**Prerequisite:** All gaps in [ONE_APP_COMPLETE_BUSINESS_AUDIT.md](ONE_APP_COMPLETE_BUSINESS_AUDIT.md) closed first

---

## The Core Idea

KashCube is the world's best **seller back-end** that speaks an open commerce protocol. The buyer experience belongs to a competitive ecosystem of third-party apps. Nobody owns the protocol. No commission is ever taken.

This is the UPI model applied to commerce:
- NPCI owns the payment protocol, not the apps
- GPay and PhonePe compete on UX; the protocol is neutral
- **Bazaar Protocol** owns the commerce protocol; buyer apps compete on UX

---

## What KashCube Builds vs What Third Parties Build

```
┌────────────────────────────────────────────────────────┐
│  BUYER APPS  (third-party, competing, any UX)          │
│  "Bazaar" app, "Haat" app, WhatsApp bot, web buyer UI  │
└────────────────────┬───────────────────────────────────┘
                     │  Bazaar Protocol (open spec, published)
                     │  - Product feed format (JSON-LD / CMP-compatible)
                     │  - Order record schema (signed JSON)
                     │  - Transport: Nearby API / mDNS / HTTP
                     │  - Identity: Ed25519 device keys
                     │
┌────────────────────▼───────────────────────────────────┐
│  KASHCUBE  (seller-side only)                          │
│  - Broadcasts catalog via protocol                     │
│  - Receives incoming orders as pending invoices        │
│  - Owner confirms/fulfils in KashCube UI               │
│  - Signs completion record                             │
│  - All data in local SQLite — buyers never see it      │
└────────────────────────────────────────────────────────┘
```

KashCube's total surface area in the commerce layer: **broadcast + receive.** Everything between those two points is an open ecosystem problem.

---

## Why Phase F2 (Self-Hosted Server) Was Dropped

F2 required users to rent a VPS, configure Docker, set up SSL certificates, manage port forwarding, and keep a server running 24/7 — turning a kirana owner into a system administrator. That is not the KashCube user.

Every use case F2 was trying to solve is covered better without a server:

| F2 Purpose | Better Solution |
|---|---|
| Buyers browse products online | Bazaar Protocol third-party buyer apps |
| WhatsApp ordering | Phase F1 catalog CSV export (zero server) |
| Public product discovery for AI agents | CMP feed served from existing LAN server via one-button tunnel (opt-in) |
| WhatsApp Business API | Requires Meta approval; most kiranas won't qualify |

**F2 is permanently dropped from the roadmap.**

---

## Revised Roadmap

```
[NOW]     Core app → 100% complete
          (close the 3 gaps in ONE_APP_COMPLETE_BUSINESS_AUDIT.md first)

Phase F1  Catalog Export + WhatsApp Commerce Lite          [KashCube builds]
Phase F3a Publish Bazaar Protocol specification            [KashCube authors]
Phase F3b Catalog broadcast — seller-side (BLE / mDNS)    [KashCube builds]
Phase F3c Order receiver — creates pending invoices        [KashCube builds]
Phase F3d Reference buyer app (open-source seed)           [KashCube seeds]
Phase F3e Third-party buyer app ecosystem                  [Community builds]

Optional:
  CMP feed via one-button tunnel (Cloudflare Tunnel)       [F1 add-on, ~1 day]
```

---

## Phase F1 — Catalog Export + WhatsApp Commerce Lite

**No server required. Zero new infrastructure for the user.**

### 1. WhatsApp Business Catalog CSV Export
- Export item catalog in Meta's required format: `name, price, description, image_id, retailer_id, url`
- User imports CSV into the free WhatsApp Business App → instant product catalog on their WhatsApp profile
- One-tap in KashCube Settings → "Export for WhatsApp Catalog"
- **Effort:** ~1 day. No new dependencies.

### 2. Shareable Product Page (Static HTML)
- KashCube's existing local HTTP server generates a product listing page
- User shares the URL via QR code at the shop counter — customers browse on their own phone
- No internet required; works on the shop's WiFi hotspot
- **Effort:** ~1 day. Extends existing local server.

### 3. WhatsApp Order Deep-Link per Item
- Each item gets a `wa.me/?text=I+want+to+order+{item_name}` deep link
- Share as a button or QR code → customer taps → WhatsApp opens pre-filled
- Owner creates invoice from the message in existing KashCube flow
- **Effort:** ~half a day.

### 4. Optional: CMP Feed via One-Button Tunnel (for AI discovery)
- When internet is available and user opts in, the existing local server serves `/.well-known/cmp/feed.json`
- A one-button Cloudflare Tunnel makes this publicly accessible — no domain, no VPS, no configuration
- AI agents (ChatGPT Shopping, Perplexity) can discover the business's products
- **Opt-in only.** Default off. No financial data in the feed — catalog names and prices only.
- **Effort:** ~1 day.

---

## Phase F3 — Bazaar Protocol (Open P2P Commerce)

### Design Principle: Protocol, Not Platform

KashCube authors an open protocol specification. **KashCube builds only the seller side.** Buyer-side UX, discovery interfaces, and ordering apps are built by third parties — competing, independent, KashCube has no control over them.

This is the UPI model:
- NPCI published the UPI spec; Google Pay and PhonePe built competing buyer apps
- The protocol is neutral; the apps compete on UX
- **Bazaar Protocol** is the spec; third-party apps are the buyers

### What KashCube Builds (Seller Side Only)

| Component | What It Does | Effort |
|---|---|---|
| Catalog broadcast | BLE / mDNS advertisement: "shop name, categories, catalog hash" | ~1 week |
| **Mesh discovery beacon relay** | Re-broadcast nearby shop beacons (TTL=3, 28 bytes) — extends discovery range without a hub | ~1 week |
| Catalog serve on demand | WiFi Direct / local HTTP: full JSON-LD catalog to any requesting device | ~1 week |
| Order receiver | Accept a signed order payload → create pending invoice in KashCube | ~1 week |
| Order signing | Seller signs confirmation + receipt with Ed25519 device key | ~3 days |
| **Catalog seeding (torrent model)** | Buyers who've pulled a catalog temporarily re-serve it to peers; freshness pinned by `catalog_hash` in beacon | ~1 day |
| Settings toggle | "Accept orders from Bazaar Protocol apps" — opt-in, off by default | ~1 day |

**KashCube never builds a buyer UI.** The buyer always uses a third-party app.

### What Third Parties Build (Buyer Side)

Any developer may build a Bazaar Protocol-compatible buyer app. Examples:
- A regional-language buyer app for Tamil Nadu haats
- A voice-based zero-literacy ordering app for rural farmers
- A WhatsApp bot that bridges WhatsApp messages into protocol orders
- A web-based buyer interface for desktop purchasing agents
- A feature-phone USSD app for areas with no smartphones

All of these work with every KashCube seller automatically — no KashCube permission required.

### Transaction Record Schema

Every order is cryptographically signed by both parties and stored in their own SQLite:

```json
{
  "order_id": "uuid-v4",
  "seller_device_id": "sha256-of-ed25519-public-key",
  "buyer_device_id": "sha256-of-ed25519-public-key",
  "items": [{ "sku": "...", "qty": 2, "unit_price_inr": 45 }],
  "total_inr": 90,
  "timestamp": "2026-03-26T14:32:00+05:30",
  "payment_method": "upi_lite | cash | pending",
  "seller_signature": "base64-ed25519",
  "buyer_acknowledgement": "base64-ed25519"
}
```

- **Signed** — seller signs with device key; unforgeable
- **Immutable** — stored in both SQLite databases once confirmed
- **Verifiable** — buyer verifies seller signature without any server
- **Conflict-free** — CRDT / vector clock (existing sync engine)

### Trust and Reputation (No Central Authority)

- Each KashCube device has an Ed25519 key pair — the public key is the seller's identity
- Completed transactions accumulate as a **reputation graph**: "Device X has 340 confirmed orders, 0 disputes"
- Reputation propagates peer-to-peer — a buyer sees "12 people near you have traded with this seller"
- **Physical QR token:** Seller prints a QR of their public key, sticks it on the counter. Any new buyer scans it → sees full transaction history. No internet needed.
- New device identity = zero reputation. Anti-Sybil by design.

#### Trust Mesh — P2P Gossip Propagation (No Central Node)

Discovery mesh and trust mesh use fundamentally different propagation models — by necessity:

```
Discovery mesh  →  PUSH  — 28-byte beacon, BLE broadcast, fire-and-forget, TTL=3
Trust mesh      →  PULL  — gossip query outward, ~200-byte summary returned, max depth=3
```

Discovery beacons are tiny and directionless — any device can relay them blindly. Reputation data is signed, directed, and larger — it uses **gossip cache query**, not broadcast push.

**How it works:**

1. Each device holds its own canonical signed transaction log (ground truth — never relayed)
2. Devices cache **reputation summaries** of sellers they have directly transacted with
3. When a buyer discovers seller X via a BLE beacon:
   - **Direct pull** — request reputation log directly from seller X's device (WiFi Direct)
   - **Gossip query** — ask nearby peers: "anyone have a cached summary for `seller_id X`?"
   - A peer that has transacted with X responds with its cached summary
4. Summary packet (~200 bytes):
   ```
   { seller_id, tx_count, dispute_count, last_tx_ts, summary_hash, summary_signature }
   ```
   Small enough to relay over BLE or local WiFi.

**Web-of-Trust depth (max 3 hops — same rule as PGP):**

| Depth | Meaning | Example |
|---|---|---|
| 0 | You have no data on this seller | First encounter |
| 1 | You transacted with this seller directly | Canonical; fully trusted |
| 2 | Someone in your peer cache has transacted with this seller | "12 people near you have traded with this shop" |
| 3 | A peer-of-peer has a summary | Weak signal; shown with low confidence indicator |
| 4+ | Beyond max depth | Ignored — noise exceeds signal |

**Security properties:**

| Property | How It Holds Without a Server |
|---|---|
| Unforgeable | Each summary is Ed25519-signed by the original transacting device; relay cannot modify it |
| Anti-Sybil | New device identity = zero reputation; manufacturing fake history requires colluding key pairs |
| Self-dealing | Two sellers inflating each other — mitigated by **reputation staking** (stake something to vouch) |
| Canonical truth | Always the seller's own signed tx log; gossip summaries are hints, not authority |

```
Trust mesh (gossip, ~200B summaries, WoT depth=3)    ✅ Keep — same "no central node" guarantee
Trust central DB (KashCube server)                   ❌ Never — violates privacy architecture
```

### Payment Layers (All Offline-Compatible)

| Layer | Mechanism | Limit |
|---|---|---|
| Cash confirmation | Both devices tap "Paid in cash" — mutual acknowledgement | None |
| UPI Lite | NPCI pre-loaded on-device wallet, works offline | ₹500/transaction |
| USSD *99# | Works on 2G feature phones, no internet | Bank-dependent |

### India-Specific Use Cases

| Context | Who Benefits | Scale |
|---|---|---|
| Weekly haat / mela | Vegetable sellers, artisans, textile vendors | 6,000+ weekly markets |
| B2B sales rep visits | FMCG distributor reps at kiranas | Crores of transactions/day |
| Rural village market | Farmers selling direct to consumers | ~600M rural population |
| Exhibition / trade fair | Bulk buyers at multiple stalls | B2B commerce |
| Disaster / flood zones | Relief goods distribution, no towers | Critical infrastructure |
| Factory floor | Internal procurement, no WiFi allowed | Manufacturing SMEs |

### Competitive Position

> "The only business app that works where there is no internet — not just for bookkeeping, but for actual buying and selling."

No Vyapar, QuickBooks, Shopify, or Meesho can say this. **Completely unoccupied market position.**

### Technology Stack

| Layer | Technology | Status |
|---|---|---|
| LAN discovery | Bonsoir (mDNS/Bonjour) | ✅ already in `pubspec.yaml` |
| BLE beacon broadcast + relay | `flutter_blue_plus` or Nearby BLE advertising | ❌ to add |
| Mesh beacon relay | Bloom filter (1KB) + TTL decrement logic in Dart | ❌ to add (~100 lines) |
| Device-to-device catalog transfer | `nearby_connections` (Google Nearby Connections) | ❌ to add |
| Catalog seeding (torrent model) | In-memory LRU cache + hash verification before serving | ❌ to add (~1 day) |
| Trust gossip query | BLE / local WiFi GATT query + 200-byte summary cache | ❌ to add |
| DHT reputation routing | Kademlia-style routing table (large-scale only) | 🔶 defer |
| Cryptographic signing | `ed25519` / `pointycastle` | ❌ to add |
| Offline payment UX | UPI Lite confirmation + cash tap | ❌ UX to design |
| Conflict resolution (orders only) | CRDT vector clocks | ✅ existing sync engine |

### Monetisation

- **Seller broadcast mode** requires KashCube Business tier
- **Buyer apps** are always free to build against the protocol; no KashCube licence needed
- **No per-transaction commission. Ever.** KashCube monetises through app subscriptions, not commerce.
- Protocol governance eventually moves to an independent foundation

### Discovery: Two Modes, One Decision

#### Mode 1 — Direct Broadcast (BLE / mDNS)
Seller's device broadcasts a 28-byte beacon:
```
[kashcube_prefix (4B)] [shop_id (16B)] [category_bitmask (4B)] [catalog_hash (4B)]
```
Buyers in direct BLE range (~50–100m) receive it immediately.

#### Mode 2 — Hub Mode
One device acts as a hotspot. All sellers join it. All buyers join it. Hub aggregates and serves all catalogs. Hub range = WiFi range (~50m indoors, ~100m outdoors). Covers most organised markets.

#### Mode 3b — Mesh Discovery Beacons (kept; ordering mesh dropped)
For ad-hoc, unorganised markets with no hub device:
- Any KashCube device that hears a beacon **re-broadcasts it** with `TTL - 1`
- Hard TTL cap = 3 hops → max range ~300m (3 × 100m)
- Relay rule: IF `received_ttl > 0` AND packet not in local bloom filter → re-broadcast after random 50–200ms backoff
- **No signing required** — discovery is public; a fake beacon causes zero harm (buyer pulls catalog, sees nothing, ignores it)
- **No reliability required** — fire and forget; beacons repeat every 30s
- Local bloom filter (1KB) prevents re-relaying the same beacon

**What is explicitly dropped:** Multi-hop *order relay* — transactions require reliability, signing, delivery confirmation, and conflict resolution. That complexity is not justified. Full catalog is always pulled via direct WiFi Direct connection once a seller is discovered.

```
Mesh discovery (28-byte beacons, TTL=3)    ✅ Keep — trivial, high value for haats
Mesh ordering (signed transaction relay)   ❌ Dropped — research-grade complexity, zero Indian commerce use case
```

### Transport Mode Summary

| Mode | When Used | KashCube Builds |
|---|---|---|
| Direct P2P | Two devices within 100m, no router | ✅ |
| Hub Mode | Organised market, one device as hotspot | ✅ |
| Mesh discovery beacons | Ad-hoc gathering, no hub, range extension | ✅ (lightweight, F3b add-on) |
| Mesh order relay | Multi-hop transactions | ❌ Dropped |

### Open Questions (Resolve During Planning)

1. **Battery drain** — BLE beacon relay is low-power; WiFi Direct catalog pull is on-demand only. Aggressive sleep/wake needed for the relay loop.
2. **Discovery UX** — "30 shops found nearby" — third-party buyer app's problem, but the beacon format must support `category_bitmask` filtering so apps can filter before pulling catalogs.
3. **Dispute resolution** — No server; signed receipt is the evidence; reputation staking is the deterrent.
4. **iOS** — Apple restricts Nearby-style APIs; Android-only initially; iOS buyers use third-party web buyer apps via Hub Mode hotspot.

### Delivery Sequence Within F3

```
F3a  Publish Bazaar Protocol specification (open-source, GitHub)            ~1 week
F3b  Catalog broadcast — BLE/mDNS direct + mesh beacon relay (TTL=3)       ~2 weeks
F3c  Catalog serve on demand — WiFi Direct / local HTTP                     ~1 week
F3d  Order receiver in KashCube — signed payload → pending invoice          ~1 week
F3e  Ed25519 device identity + signing infrastructure                       ~3 days
F3f  Reference buyer app (open-source, minimal, proof-of-concept)           ~2 weeks
F3g  Third-party buyer app ecosystem                                        Community
```

---

## Protocol Layer Architecture

Every transaction on the Bazaar Protocol flows through six independent, composable layers. Each layer is open and replaceable — any third party can implement an alternative at any layer without touching the others.

```
┌─────────────────────────────────────────────────────┐
│  DISCOVERY LAYER                                     │
│  BLE broadcast → mDNS → CMP feed (if internet)      │
├─────────────────────────────────────────────────────┤
│  CATALOG LAYER                                       │
│  JSON-LD product feed, served P2P on demand          │
├─────────────────────────────────────────────────────┤
│  TRUST LAYER                                         │
│  Ed25519 identity + Web-of-Trust reputation graph    │
├─────────────────────────────────────────────────────┤
│  TRANSACTION LAYER                                   │
│  Cash / UPI Lite / USSD + dual-signed SQLite record  │
├─────────────────────────────────────────────────────┤
│  FULFILLMENT LAYER                                   │
│  In-person (primary) + pluggable carrier modules     │
├─────────────────────────────────────────────────────┤
│  DISPUTE LAYER                                       │
│  Community arbitration + reputation staking          │
└─────────────────────────────────────────────────────┘
         ↕ all layers talk to each other via open protocol
```

### Layer Responsibilities

| Layer | What It Does | KashCube Builds | Third Parties Can Build |
|---|---|---|---|
| **Discovery** | Seller makes shop findable offline (BLE/mDNS) or online (CMP feed) | ✅ BLE broadcast + mDNS + CMP feed export | Alternative beacon formats, discovery aggregators |
| **Catalog** | Buyer device pulls full product JSON-LD from seller device on demand | ✅ Serve catalog via WiFi Direct / local HTTP | Catalog caching nodes, search indices |
| **Trust** | Device identity via Ed25519 key pair; reputation propagates via P2P gossip (WoT depth=3, no central DB) | ✅ Key generation, signing, reputation store, gossip cache | Reputation oracles, community attestation apps |
| **Transaction** | Mutual acknowledgement + dual-signed record written to both SQLite DBs | ✅ Signed JSON record, UPI Lite / cash UX | USSD bridges, NFC tap-to-pay adapters |
| **Fulfillment** | Goods handed over in-person; pluggable for delivery | ✅ In-person confirm flow | Courier integrations, drone/hyperlocal delivery modules |
| **Dispute** | Signed receipts as evidence; reputation staking as deterrent; peer arbitration | ✅ Signed receipt export | Community arbitration DAOs, legal document generators |

### Why Six Layers

- **Discovery and Catalog are separated** — a buyer can discover a shop exists (via a 28-byte BLE beacon) without pulling its full catalog. Catalog transfer only happens when the buyer actively chooses to browse.
- **Trust and Transaction are separated** — trust is persistent (accumulated over all transactions); transaction is per-event. A seller with 500 signed transactions has trust even if payment fails this time.
- **Fulfillment and Dispute are separated** — most transactions close at fulfillment; the dispute layer only activates on exception. Keeping them separate means dispute logic never adds latency to normal flows.

### What KashCube Does NOT Build

- **Discovery layer:** No internet-based discovery service (no KashCube server indexing shops)
- **Catalog layer:** No catalog hosting (the seller's device is the server)
- **Trust layer:** No central reputation database (reputation lives on-device, propagates P2P)
- **Transaction layer:** No payment processor (UPI Lite is NPCI's; cash is cash)
- **Fulfillment layer:** No logistics network
- **Dispute layer:** No arbitration authority (the protocol enables arbitration; communities run it)

---

## Prior Art & Technology Evaluation

Decisions on technologies considered but evaluated against Bazaar Protocol's constraints (offline-first, privacy-absolute, no central node).

### Bridgefy (BLE Mesh Messaging SDK)

**What it is:** BLE mesh messaging SDK (Android + iOS) — battle-tested at Hong Kong protests (2019), music festivals, disaster zones. TTL-based relay, hybrid direct + mesh mode, post-2020 rebuild on Signal Protocol.

**Why not used:**
- Requires device registration with Bridgefy servers — phones home. Immediate disqualifier under KashCube privacy architecture.
- Pre-2020 version had critical academic-documented vulnerabilities (plaintext mesh relay, trivial impersonation, passive tracking). Track record matters.
- Wrong abstraction: designed for variable-length routed text messages; Bazaar Protocol's discovery layer is a 28-byte fire-and-forget beacon.
- Proprietary closed-source SDK — incompatible with an open protocol spec.

**Validation value:** Bridgefy independently arrived at TTL=3–5, bloom filter loop prevention, BLE discovery + WiFi bulk transfer, and Ed25519 signing — confirming every architectural decision already made.

```
Use Bridgefy SDK               ❌  Phones home, closed source, wrong abstraction
Use as architectural validation ✅  Confirms TTL=3, bloom filter, BLE+WiFi split
```

---

### Blockchain

**The appeal:** Immutable transaction ledger, no central authority, unforgeable reputation — exactly what Trust and Transaction layers need.

**Why it breaks down:**

| Problem | Detail |
|---|---|
| Offline-first contradiction | Blockchains need connectivity to commit. In-person haat commerce cannot wait for block confirmation. Fatal disqualifier. |
| Privacy by design violation | A blockchain is a *public* ledger. Every ₹40 transaction would be permanently, publicly visible. Violates privacy architecture. |
| Gas fees | India kirana selling ₹40 items cannot pay per-transaction gas fees on any public chain. |
| Private/permissioned chains | Just recreate a central authority — the node operator. Defeats the purpose. |
| Latency | UPI = 2s. Ethereum finality = 12–15s. Even Solana requires internet. |

**The one narrow legitimate use:**
```
Publish SHA-256(Bazaar Protocol spec v1) on-chain once.
→ Immutable timestamped proof of authorship.
→ Done once, near-zero gas cost, no transaction data involved.
```

```
Blockchain for transactions     ❌  Offline incompatibility + public ledger = two separate disqualifiers
Blockchain for spec governance  🔶  One-time hash publication only — optional, very low priority
Ed25519 + P2P gossip            ✅  Achieves the same tamper-proof guarantees, fully offline
```

---

### Torrent-Style Relays (BitTorrent)

**What BitTorrent does:** DHT (no central tracker), seeding (downloaders become uploaders), magnet link (hash + bootstrap peers, no index server), piece integrity (any peer can serve any chunk, verified against content hash).

**Applied layer by layer:**

#### Discovery layer — already is a magnet link
```
28-byte beacon:  [prefix (4B)] [shop_id (16B)] [category_bitmask (4B)] [catalog_hash (4B)]
                                                                          ↑
                               This IS a magnet link. The buyer has the content
                               identifier before connecting to anyone. ✅ Already done.
```

#### Catalog layer — seeding is a genuine win 💡
At a busy haat with 100 buyers who've already pulled Ramesh's catalog:
```
Buyer A pulls Ramesh's catalog via WiFi Direct  →  caches it (TTL=30 min)
Buyer B arrives, discovers Ramesh via beacon     →  pulls from Buyer A instead
Result: Ramesh's battery saved; catalog spreads faster; resilient if Ramesh steps away
```
Freshness guaranteed: the beacon's `catalog_hash` pins the exact version. Any cached copy that doesn't match the hash is rejected and re-fetched from source.

#### Reputation layer — DHT at scale
Gossip broadcast degrades at large fairs (500+ sellers): O(n) per query. DHT routing converges in O(log n). Worth considering at scale; deferred until actually needed.

#### Piece-based transfer — overkill
BitTorrent shines for gigabyte files. A KashCube catalog is 5–50KB. WiFi Direct delivers it in milliseconds. Chunk assembly adds protocol complexity for zero gain.

**Decision summary:**

| BitTorrent Concept | Bazaar Protocol Application | Decision |
|---|---|---|
| Magnet link = content hash | `catalog_hash` in 28-byte beacon | ✅ Already done |
| Seeding after download | Buyers cache + re-serve catalogs they've browsed (TTL=30 min, hash-verified) | ✅ Adopt — ~1 day, adds resilience |
| DHT routing table | O(log n) reputation lookup for 100+ sellers at one location | 🔶 Defer — only needed at scale |
| Piece-based transfer | Chunked catalog assembly | ❌ Overkill — catalogs are <50KB |
| No central tracker | Ed25519 + gossip (already decided) | ✅ Already decided |

---

## The "Nobody Owns It" Governance Model

Protocol changes follow open governance:
1. **KashCube authors v1** of the spec and publishes it on GitHub (MIT/Apache licensed)
2. **Reference implementation** is open-source — any developer can build a compatible app
3. **Compatibility test suite** — third-party apps run tests to call themselves "Bazaar Protocol v1 compatible"
4. **Foundation** — once ecosystem has 3+ independent implementations, governance moves to a community foundation (not KashCube alone)

KashCube's long-term role: **best-in-class seller implementation**, not protocol owner.

---

## Bootstrap Strategy — Silent Protocol Launch

The protocol has zero value until enough devices run it. The solution: **lay all the plumbing silently inside the core app** so that when the protocol is publicly announced, every existing KashCube user is already a protocol node. The announcement just surfaces what's already there.

This is the WhatsApp model — the Signal Protocol engine shipped silently for months before the "Now end-to-end encrypted" banner appeared. Users didn't set anything up. It was already done.

### What Ships Silently Inside the Core App (~1 day total)

| Task | Effort | User Visibility |
|---|---|---|
| Generate + store Ed25519 key pair on first launch (in `flutter_secure_storage`) | ~3 hours | None — silent |
| Add `/.well-known/cmp/feed.json` route to existing local HTTP server | ~4 hours | None — LAN only |
| Add `device_signature TEXT` column to `invoices` table (DB v82) | ~2 hours | None — hidden field |
| Sign invoices on every save with device key | ~2 hours | None — background |

No new user-facing screens. No new permissions. No new dependencies beyond what's already in the project.

#### Device Identity Key Pair
```dart
// Runs once on first launch — user never sees this
final keyPair = Ed25519().newKeyPairSync();
await secureStorage.write(key: 'device_private_key', value: base64(keyPair.privateKey));
await secureStorage.write(key: 'device_public_key',  value: base64(keyPair.publicKey));
```
`flutter_secure_storage` is already a dependency. Zero new packages.

#### Catalog Feed Endpoint
The local HTTP server (already running for KashCube Web) gets one new route:
```
GET /.well-known/cmp/feed.json
→ JSON-LD of item catalog (names, prices, SKUs)
→ LAN-only by default; no internet exposure
```
When a user later opts into the public tunnel, the feed is already ready.

#### Signed Invoice Records
Every invoice saved to SQLite gets a `device_signature` field — `sign(invoice_id + total + timestamp + seller_device_id)`. Stored silently. Never shown in the UI until the protocol is publicly announced.

### What Does NOT Ship Silently

These require explicit user opt-in — one Settings toggle: **"Make my shop discoverable on Bazaar Protocol"** (off by default):

| Component | Why It Cannot Be Silent |
|---|---|
| BLE / mDNS broadcast | Battery drain |
| Order receiver endpoint | Security surface — needs auth before enabling |
| Public catalog exposure | Privacy — user must choose to be discoverable |

### The Reveal Moment

When the protocol is ready to announce publicly:

```
App update notification:
"KashCube now supports the Bazaar Protocol.
Your shop identity has been ready since day one.
Tap to enable catalog broadcast."
```

Every user who installed the core app is already protocol-compatible. The toggle is the only new thing they see.

### Full Order of Operations

```
Step 1  Core app → 100% complete                        ← CURRENT PRIORITY
Step 2  Silent protocol plumbing ships in core app      ← ~1 day, zero UX change
Step 3  Reach 100K+ active sellers
Step 4  Publish Bazaar Protocol spec (open-source)
Step 5  Launch Phase F1 (catalog export) — passive
Step 6  Flip the toggle UI — broadcast goes live
Step 7  Third-party buyer apps appear (spec is already public)
Step 8  Network effect — more sellers → more buyer apps → more sellers
```

**Steps 1 and 2 happen together. Steps 3–8 happen after the core app ships.**

---

## Commerce Mesh Schema Mapping to KashCube

Commerce Mesh should be treated as an **export schema**, not KashCube's internal database schema. KashCube remains business-first (GST, HSN/SAC, stock, MRP, dealer price); the Commerce Mesh / JSON-LD feed is generated from that internal source of truth.

**Rule of thumb:**
- Store business-critical item fields directly in `item_catalog`
- Add a small number of public-commerce fields only when they have clear product value
- Store long-tail metadata in JSON or child tables
- Compute schema wrappers and derived fields at export time

### Current KashCube Source of Truth

Primary item sources today:
- `lib/data/models/item_catalog.dart`
- `lib/data/services/database_helper_tables.dart`
- `lib/data/repositories/item_catalog_repository_impl.dart`

Current first-class item fields already cover the commercial core well:
- `name`, `description`, `sku`, `category`, `unit`
- `unit_price`, `tax_pct`
- `hsn_code`, `hsn_or_sac`
- `track_inventory`, `stock_qty`, `low_stock_threshold`
- `mrp`, `dealer_price`
- `is_active`, `created_at`, `updated_at`

### Mapping Principle

```
KashCube internal model  →  Export mapper  →  Commerce Mesh / JSON-LD feed
```

Not:

```
Commerce Mesh schema  →  KashCube database design
```

If KashCube forced the internal DB to mirror the external spec 1:1, invoice workflows, GST handling, stock tracking, and Indian retail requirements would get worse.

### Top-Level Feed Object

| Commerce Mesh Field | Meaning | KashCube Mapping | Status | Recommendation |
|---|---|---|---|---|
| `@context` | Schema context | No DB field | Missing | Compute at export time |
| `@type = ItemList` | Feed wrapper type | No DB field | Missing | Compute at export time |
| `itemListElement` | Ordered array of items | Catalog query result set | Implicit only | Build from exported catalog list |

### ListItem Mapping

| Commerce Mesh Field | Meaning | KashCube Mapping | Status | Recommendation |
|---|---|---|---|---|
| `@type = ListItem` | Wrapper per item | No DB field | Missing | Compute at export time |
| `position` | Item order in feed | Repository sort order | Implicit only | Compute during export |
| `item` | `Product` or `ProductGroup` payload | `ItemCatalog` row or future variant group | Partial | Export `ItemCatalog` as `Product`; add `ProductGroup` later |

### Product Core Identity

| Commerce Mesh Field | Meaning | KashCube Mapping | Status | Recommendation |
|---|---|---|---|---|
| `@context` | Product schema context | No DB field | Missing | Compute at export time |
| `@type = Product` | Product type tag | `ItemCatalog` row | Implicit only | Compute at export time |
| `@id` | Stable URN (`urn:cmp:sku:*`) | Derive from `sku`, `sync_id`, or internal `id` | Missing | Derive initially; optional future `cmp_product_urn` |
| `name` | Product name | `item_catalog.name` | Exists | Keep first-class |
| `sku` | Seller SKU | `item_catalog.sku` | Exists | Keep first-class |

### Product Descriptive Fields

| Commerce Mesh Field | Meaning | KashCube Mapping | Status | Recommendation |
|---|---|---|---|---|
| `description` | Product description | `item_catalog.description` | Exists | Keep first-class |
| `image` | Primary image URL | No item image field today | Missing | Add optional local image path; export as LAN URL |
| `brand` | Brand object | No dedicated item brand field | Missing | Add optional `brand_name` |
| `category` | Public category string | `item_catalog.category` enum | Partial | Export enum label/string |
| `additionalProperty` | Long-tail metadata | No general metadata store | Missing | Add JSON field or child table |
| `isVariantOf` | Variant parent group | No variant model | Missing | Defer until variants are needed |
| `@cmp:media` | Rich media array | No item media model/table | Missing | Defer to dedicated media table |

### Offer / Pricing / Availability

| Commerce Mesh Field | Meaning | KashCube Mapping | Status | Recommendation |
|---|---|---|---|---|
| `offers` | Offer object | Derived from price + stock | Partial | Build at export time |
| `offers.@type = Offer` | Offer type tag | No DB field | Missing | Compute at export time |
| `offers.price` | Selling price | `item_catalog.unit_price` | Exists | Keep first-class |
| `offers.priceCurrency` | Currency code | Always `INR` in KashCube | Missing | Compute at export time |
| `offers.availability` | In stock / out of stock | Derived from `stock_qty` and/or `track_inventory` | Partial | Compute at export time |
| `offers.inventoryLevel` | Available quantity object | Derived from stock overlay | Partial | Compute at export time |
| `offers.priceValidUntil` | Price expiry | No field today | Missing | Add only if timed offers become a real feature |
| `offers.priceSpecification` | Structured pricing metadata | Derive from `unit_price`, `mrp`, `dealer_price` | Partial | Compute at export time unless pricing gets more complex |

### QuantitativeValue Mapping

| Commerce Mesh Field | Meaning | KashCube Mapping | Status | Recommendation |
|---|---|---|---|---|
| `inventoryLevel.@type = QuantitativeValue` | Type wrapper | No DB field | Missing | Compute at export time |
| `inventoryLevel.value` | Available quantity | `item_stock.stock_qty` / `stock_qty` | Exists | Compute at export time |

### PriceSpecification Mapping

| Commerce Mesh Field | Meaning | KashCube Mapping | Status | Recommendation |
|---|---|---|---|---|
| `@type = PriceSpecification` | Structured price wrapper | No DB field | Missing | Compute at export time |
| `price` | Price amount | `unit_price` | Exists | Compute/export |
| `priceCurrency` | Currency code | Always `INR` | Missing | Compute/export |

### India-Specific KashCube Fields Without First-Class Commerce Mesh Equivalents

These fields matter to KashCube more than they matter to the external schema, so they must remain first-class in the internal model.

| KashCube Field | Purpose | Commerce Mesh Strategy |
|---|---|---|
| `hsn_code` | GST compliance | Export via `additionalProperty` |
| `hsn_or_sac` | Product vs service tax code type | Export via `additionalProperty` |
| `tax_pct` | GST percentage | Export via `additionalProperty` or pricing extension |
| `mrp` | Legal retail ceiling | Export via `priceSpecification` or `additionalProperty` |
| `dealer_price` | Trade purchase price | Keep internal by default; export only if explicitly enabled |
| `low_stock_threshold` | Seller-side inventory behavior | Keep internal only; not required in public feed |

### PropertyValue / additionalProperty Mapping

| Commerce Mesh Field | Meaning | KashCube Mapping | Status | Recommendation |
|---|---|---|---|---|
| `PropertyValue.@type` | Type wrapper | No DB field | Missing | Compute at export time |
| `PropertyValue.name` | Metadata key | No generic key-value store | Missing | Store in JSON or child table |
| `PropertyValue.value` | Metadata value | No generic key-value store | Missing | Store in JSON or child table |

Best initial use of `additionalProperty` in KashCube exports:
- HSN code
- HSN/SAC type
- GST percentage
- MRP
- unit
- barcode / GTIN
- packaging info
- shelf / bin / lane identifiers

### Brand Mapping

| Commerce Mesh Field | Meaning | KashCube Mapping | Status | Recommendation |
|---|---|---|---|---|
| `brand.@type = Brand` | Type wrapper | No DB field | Missing | Compute at export time |
| `brand.name` | Brand name | No item field today | Missing | Add optional `brand_name` |

For Indian FMCG and kirana use cases, `brand_name` is worth adding early because it improves search, customer-facing catalog clarity, OCR matching, and future import normalization.

### MediaObject Mapping

| Commerce Mesh Field | Meaning | KashCube Mapping | Status | Recommendation |
|---|---|---|---|---|
| `@cmp:media` | Rich media array | No item media table | Missing | Defer to separate media model |
| `MediaObject.@type` | Media subtype (`ImageObject`, etc.) | No DB field | Missing | Compute at export time |
| `url` | Public/LAN media URL | No direct item media URL | Missing | Derive from local file path via local HTTP server |
| `contentUrl` | Direct asset URL | No field | Missing | Compute if media serving exists |
| `encodingFormat` | MIME type | No field | Missing | Compute from local file |
| `thumbnailUrl` | Thumbnail URL | No field | Missing | Defer |
| `width` | Pixel width | No field | Missing | Compute if needed |
| `height` | Pixel height | No field | Missing | Compute if needed |
| `duration` | Media duration | No field | Missing | Defer |
| `caption` | Human caption | No field | Missing | Optional later |
| `name` | Media label | No field | Missing | Optional later |
| `description` | Media description | No field | Missing | Optional later |
| `uploadDate` | Media upload date | No field | Missing | Optional later |

Important privacy rule: KashCube should store **local file paths**, not remote URLs. Export is where local media becomes a LAN URL, and only user opt-in should ever expose that beyond the LAN.

### ProductGroup / Variant Mapping

| Commerce Mesh Field | Meaning | KashCube Mapping | Status | Recommendation |
|---|---|---|---|---|
| `ProductGroup` | Parent group object | No variant/group model | Missing | Defer |
| `ProductGroup.@context` | Schema context | No DB field | Missing | Compute at export time |
| `ProductGroup.@type = ProductGroup` | Type tag | No DB field | Missing | Compute at export time |
| `ProductGroup.@id` | Stable group URN | No field | Missing | Add only when variants exist |
| `ProductGroup.name` | Group name | No field | Missing | Add only when variants exist |
| `ProductGroup.description` | Group description | No field | Missing | Add only when variants exist |
| `ProductGroup.brand` | Group brand | No field | Missing | Reuse future `brand_name` when added |
| `ProductGroup.category` | Group category | No field | Missing | Add only when variants exist |
| `productGroupID` | Stable group ID | No field | Missing | Add only when variants exist |
| `variesBy` | Variant axes (`size`, `color`, etc.) | No field | Missing | Add only when variants exist |
| `ProductGroup.@cmp:media` | Group media | No field | Missing | Defer |
| `isVariantOf.@type = ProductGroup` | Product-to-group reference type | No field | Missing | Defer |
| `isVariantOf.@id` | Product-to-group reference | No field | Missing | Defer |

KashCube today is essentially a **single sellable item model**, not a product-family / variant-matrix model. That is acceptable. Variants should only be added when there is a real product need such as sizes, colors, FMCG pack sizes, or pharma dosage families.

### Fields Already Editable in KashCube Today

Current item form already captures:
- `name`
- `sku`
- `description`
- `category`
- `unit`
- `unit_price`
- `tax_pct`
- `hsn_code`
- `hsn_or_sac`
- `mrp`
- `dealer_price`
- `track_inventory`

Missing from the current item UI for closer Commerce Mesh parity:
- `brand_name`
- `barcode` / `GTIN`
- `primary_image_path`
- arbitrary `additionalProperty` editor
- variant group / variant axes
- rich media management

### Recommended Adoption Plan

| Priority | Change | Why |
|---|---|---|
| P0 | Keep current core item model as-is | Already covers the business-critical fields |
| P0 | Export derived Commerce Mesh feed from current model | Unlocks compatibility without schema churn |
| P1 | Add `brand_name`, `primary_image_path`, `barcode` | Highest-value commerce-facing item fields |
| P1 | Add `additional_properties_json` | Handles long-tail metadata cleanly |
| P2 | Add `item_media` table | Required for rich `@cmp:media` |
| P2 | Add `product_group_id`, variant axes/values | Only when real variants are required |
| P3 | Add timed pricing (`price_valid_until`, promotional price) | Only if public offer mechanics become real |

### Final Decision Matrix

| Schema Area | KashCube Strategy |
|---|---|
| Core product identity | Store directly in `item_catalog` |
| India-specific business fields | Keep directly in `item_catalog` even if Commerce Mesh does not model them cleanly |
| Public-commerce metadata | Add a small optional commerce profile |
| Long-tail product attributes | Store in JSON or child tables |
| Wrapper / typed schema objects | Compute at export time |
| Availability / inventory | Compute from per-business stock |
| Media URLs | Derive from local files via local HTTP server |
| Variants / ProductGroup | Defer until the app truly needs variants |

**Bottom line:** KashCube can support the full Commerce Mesh schema, but not every Commerce Mesh field should become a direct column on `item_catalog`. The correct architecture is: **lean internal item model + optional commerce profile + export-time mapper**.

---

## Related Documents
- [COMMERCE_MESH_SCHEMA_MAPPING.md](COMMERCE_MESH_SCHEMA_MAPPING.md) — canonical field-by-field mapping from Commerce Mesh schema to KashCube's internal item model
- [ONE_APP_COMPLETE_BUSINESS_AUDIT.md](ONE_APP_COMPLETE_BUSINESS_AUDIT.md) — current capability gaps to close first
- [P2P_SYNC_SPEC.md](P2P_SYNC_SPEC.md) — existing LAN/P2P sync architecture (foundation for F3)
- [FLUTTER_WEB_COMPANION_SPEC.md](FLUTTER_WEB_COMPANION_SPEC.md) — KashCube Web (W1) local server foundation
- [PRIVACY_ARCHITECTURE.md](PRIVACY_ARCHITECTURE.md) — all phases must respect these constraints
