# Storage Growth Management & Disaster Recovery

## Overview

KashCube stores all data 100% on-device. This document outlines strategies for managing storage growth over time and protecting users from data loss — both within the privacy-first architecture constraint (no network calls, no servers).

---

## Part 1 — Storage Growth Management

### 1.1 What Actually Takes Space

Understand the real culprits before optimising blindly:

| Data type | Typical size | Growth rate |
|---|---|---|
| SQLite DB (transactions, invoices, credits) | 1–5 MB / 10k rows | Linear, slow |
| PDF files (generated invoices/quotes) | 50–200 KB each | Fast if cached |
| Party / business card images | 200 KB–2 MB each | Moderate |
| SMS parse cache | Negligible | Very slow |

The SQLite database itself is rarely the problem — SQLite is extremely compact. **PDFs and images are the real culprits.**

---

### 1.2 PDF Strategy — Ephemeral, Never Persistent

PDFs are generated output, not source data. The DB is always the source of truth.

**Policy:**
- Generate → share/view → delete immediately after use
- Never store PDFs permanently inside the app
- If a user wants to save a PDF, that is their choice via the OS share sheet to Files/Drive/WhatsApp
- Implement a `PdfCacheManager` service that auto-deletes files older than 24 hours on app resume
- Keep at most the last 3 PDFs on disk as a convenience buffer

**Impact:** Eliminates the largest category of wasted storage for heavy invoice users.

---

### 1.3 Image Strategy — Compress Aggressively on Import

When a user picks a photo for a party or business card:
- Compress to max 800×600 px, JPEG 70% quality using `flutter_image_compress`
- Hard cap: 150 KB per image after compression
- Store in app's private directory; record path in DB
- Warn user when total image storage exceeds 20 MB
- **Orphan cleanup:** on maintenance job, scan for image files whose path is not referenced by any DB row and delete them

---

### 1.4 Tiered Data Access — Hot / Warm / Cold

For users with years of data, tier access by age:

```
HOT   → Last 90 days   → Always in memory index, fast queries
WARM  → 90 days–2 yrs  → In DB, queried on demand, normal performance
COLD  → 2+ years       → Archived (moved to separate archive.db)
```

**Implementation:**
- A separate `archive.db` SQLite file with the same schema
- A background job runs quarterly, moves rows older than 2 years
- "Archived" section visible in Reports screen on request
- No data loss — users can query archived data, just not in the main list

---

### 1.5 Intelligent Transaction Deduplication

Heavy SMS-import users accumulate duplicates over time.

- At import time, hash `(amount + date + merchant + type)` — already partially implemented
- Periodic dedup scan job: find exact-match groups and merge into one record
- Surface in Settings: "Found 23 potential duplicates" with a review screen before committing

---

### 1.6 DB Vacuuming

SQLite retains freed pages after deletes — `VACUUM` reclaims them.

- Run `PRAGMA VACUUM` on a schedule (monthly or after bulk deletes)
- Execute on a background isolate — takes ~1–2 s for small DBs
- Prevents fragmentation bloat from frequent deletes (credits settled, old drafts cleared)

---

### 1.7 Storage Health Dashboard (Settings Screen)

Make storage visible so users can self-manage:

```
Storage Usage
─────────────────────────────────────
Database         2.3 MB   ██░░░░░░
PDFs (cached)   12.4 MB   ████████   [Clear cache]
Images           8.1 MB   █████░░░   [Manage]
─────────────────────────────────────
Total           22.8 MB

Oldest transaction:  14 Feb 2025
Oldest invoice:       3 Jan 2025

[Archive data older than 2 years]
```

---

### 1.8 Priority Order

| Priority | Action | Effort |
|---|---|---|
| 1 — Now | PDF ephemeral policy + `PdfCacheManager` | 1 day |
| 2 — Now | Storage dashboard in Settings | 1 day |
| 3 — Soon | Image compression on import | Half day |
| 4 — Soon | DB VACUUM on schedule | 2 hours |
| 5 — Later | Transaction archiving (cold tier) | 2 days |
| 6 — Later | Duplicate scan + review screen | 2 days |

---

## Part 2 — Disaster Management

### 2.1 What Disasters Actually Happen to Users

Ranked by real-world frequency:

1. **Accidental uninstall** — very common, wipes private app storage
2. **Phone stolen or lost** — common, same effect
3. **Phone factory reset** (user-initiated or OS update failure)
4. **App data cleared** (users do this to "fix" performance problems)
5. **Phone broken** (cracked screen, water damage, inaccessible data)
6. **DB corruption** — rare but catastrophic

---

### 2.2 Layer 1 — OS Auto Backup (Zero code, implement now)

Android Auto Backup and iOS iCloud Backup already back up app data if configured. Catches scenarios 1–4 automatically.

**Android** — `android/app/src/main/AndroidManifest.xml`:
```xml
<application
  android:allowBackup="true"
  android:fullBackupContent="@xml/backup_rules"
  android:dataExtractionRules="@xml/data_extraction_rules">
```

**`res/xml/backup_rules.xml`** — DB only, exclude images (they're from the user's gallery, not app-generated):
```xml
<full-backup-content>
  <include domain="database" path="kash_cube.db" />
  <exclude domain="file" path="images/" />
  <exclude domain="file" path="pdfs/" />
</full-backup-content>
```

**Key constraint:** Android Auto Backup has a **25 MB limit**. Excluding images and PDFs keeps the backup safely under 5 MB for virtually all users.

- Backup runs automatically when device is on Wi-Fi and charging
- Encrypted by Google using the user's Google account key — **the app never touches network**
- Restored automatically on fresh install (new phone, reinstall after factory reset)
- iOS equivalent: iCloud Backup, configured similarly via `Info.plist`

**Effort:** 2 XML config files, ~2 hours.

---

### 2.3 Layer 2 — DB Crash Safety (Implement now)

Prevent corruption proactively:

**WAL mode** (`PRAGMA journal_mode=WAL`):
- Better crash safety — in-progress writes don't corrupt the main DB file
- Already the default in recent `sqflite` versions; verify it's explicitly set

**Integrity check on startup:**
```dart
final result = await db.rawQuery('PRAGMA integrity_check');
if (result.first.values.first != 'ok') {
  // Offer restore from snapshot or backup
}
```
Runs in ~100 ms for small DBs. Detect corruption before the user notices data is wrong.

**Rolling "last known good" snapshot:**
- Once per day, copy `kash_cube.db` → `kash_cube_prev.db`
- If next startup fails integrity check, offer: "Restore yesterday's data?"
- Costs ~2× DB storage but is a zero-friction safety net for corruption

---

### 2.4 Layer 3 — Encrypted Export / Import (`.kashcube` format)

A portable, encrypted backup the user controls completely. The app never initiates any network call; the user decides where the file goes.

#### File Format

```
[4 bytes]   Magic:            "KSHC"
[1 byte]    Format version:   1
[16 bytes]  Salt              (random, for PBKDF2 key derivation)
[12 bytes]  IV                (random, for AES-256-GCM)
[8 bytes]   DB schema version (unencrypted — needed for migration before decryption)
[N bytes]   AES-256-GCM encrypted payload:
              - Raw SQLite DB bytes
              - Manifest JSON: { created_at, app_version, row_counts }
[16 bytes]  GCM auth tag      (tamper detection)
```

**Key derivation:** PBKDF2-SHA256, 100 000 iterations, user passphrase + salt → 32-byte AES key. The key and passphrase are never stored anywhere on device.

**Why the GCM auth tag matters:** Decryption fails loudly and safely if the file is corrupt or the passphrase is wrong. Users see a clear error, never partial/garbled data.

**Why schema version is unencrypted:** The restore code needs to know which DB migrations to run before the data is usable — without needing to decrypt first.

#### Trigger for Backup Generation

Event-driven + weekly minimum:
- Generate a new backup if `rowsChangedSinceLastBackup > 50` OR `daysSinceLastBackup >= 7`
- Run on a background `Isolate` (not `workmanager` — simpler, no extra permission)
- After generation, show a persistent notification: "Backup ready — save it somewhere safe"
- User taps → OS share sheet → they pick Drive / WhatsApp / Files / USB
- Keep at most 3 backup files locally; delete oldest on generation of a new one

#### Onboarding Nudge (shown once, after 5 transactions)

```
Your data is only on this device.
Set a backup passphrase so you never lose it.

[Set Backup Passphrase]    [Remind me later]
```

Monthly reminder if no backup taken in 30 days.

---

### 2.5 Layer 4 — Restoration Design

Backup is useless without a reliable, well-tested restore path.

#### Restore Flow

```
User picks .kashcube file
       ↓
Validate magic bytes + format version
       ↓
Read unencrypted schema version
       ↓
Prompt for passphrase → derive key (PBKDF2)
       ↓
AES-GCM decrypt → verify auth tag
  ├─ FAIL → "File is damaged or passphrase is incorrect" (max 5 attempts)
  └─ OK   ↓
Read manifest → show user: "1,243 transactions, 87 invoices — created 1 Mar 2026"
User confirms → [Full Restore]
       ↓
Write imported DB to temp file
       ↓
Run DatabaseHelper migrations: schema_version → current
       ↓
PRAGMA integrity_check on migrated DB
  ├─ FAIL → "Restore failed — backup may be incompatible"
  └─ OK   ↓
Swap temp file with live kash_cube.db → restart app
```

#### Failure Modes to Handle

| Failure | Response |
|---|---|
| Wrong passphrase | "Passphrase incorrect or file is damaged" — do not distinguish (oracle protection) |
| Corrupt file | Same error as wrong passphrase |
| Schema too new (backup from future app version) | "This backup requires a newer app version — please update" |
| Schema too old | Run forward migrations automatically |
| Partial restore requested | v1: full restore only with clear warning. Merge mode deferred to v2. |

---

### 2.6 Layer 5 — Optional: User-Provided Cloud Direct Upload

For users who want genuine automatic backup without manual file management. This is an explicit opt-in with a privacy disclosure.

**Architecture:**
```
User's Phone → AES-256 encrypt (.kashcube) → User's Google Drive / Dropbox
```
No KashCube server ever touched. The user's own OAuth credentials are used to write to their own cloud storage.

**Packages:** `google_sign_in` + `googleapis` (Drive) or Dropbox SDK

**Privacy carve-out required:** This adds `internet` permission and network code, which breaks the current zero-network guarantee. Requires:
- A dedicated opt-in screen with plain-language disclosure
- Update to Privacy Policy
- Clear "Disconnect" option that revokes token and deletes cloud backup

**Defer until after launch** unless this is a strong market differentiator at launch.

---

## Implementation Roadmap

```
Week 1
  ├─ OS Auto Backup config (AndroidManifest + backup_rules.xml)        2 hrs
  ├─ WAL mode verification                                              1 hr
  └─ Integrity check on startup + rolling prev-DB snapshot             3 hrs

Week 2
  ├─ PDF ephemeral policy + PdfCacheManager                            1 day
  └─ Storage dashboard in Settings                                     1 day

Week 3
  ├─ Encrypted export (.kashcube) — generation side                    2 days
  └─ Encrypted import — restore side + migration                       1 day

Month 2
  ├─ Event-driven backup notification                                  1 day
  ├─ Onboarding backup nudge                                           half day
  ├─ Transaction archiving (cold tier)                                 2 days
  └─ Image compression on import                                       half day

Month 3 (optional)
  └─ User-provided Google Drive / Dropbox direct upload                1 week
```

---

## Non-Goals

- **No KashCube server** — the app never initiates network calls
- **No third-party backup SDKs** that phone home
- **No automatic upload** without explicit user opt-in and plain-language disclosure
- **No merge/conflict resolution** in v1 restore (full replace only)
