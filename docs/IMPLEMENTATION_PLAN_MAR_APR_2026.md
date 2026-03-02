# Implementation Plan — March / April 2026

> Current date: 2 March 2026. FY flips on 1 April — **29 days**. Two parallel tracks below.
>
> **Progress:** A1 ✅ A2 ✅ A3 ✅ A4 ✅ A5 ✅ A6 ✅ B1 ✅ B2 ✅ B3 ✅ B4 ✅ B5 ✅ B6 ✅ — committed `d0a3eb6`, `c39b027`, `9a24a3b`
> **Next:** B7 Encrypted `.kashcube` export 🔄 → B8 Onboarding backup nudge

---

## Track A — Fiscal Year Management (Phase 1, MUST land before 1 April)

Phase 1 is purely mechanical — settings, service, number format, report filter, warning notification. The Year-End Closing Wizard is Phase 2 (April).

### A1 — DB Schema: FY Settings Columns ✅ DONE (`d0a3eb6`)
**File:** `lib/data/services/database_helper.dart`
**Effort:** 2 hours

Add 7 new keys to the `settings` table migration (new schema version):

```sql
-- In onUpgrade (or initial create if schema is fresh)
INSERT OR IGNORE INTO settings (key, value) VALUES
  ('fiscal_year_start_month', '4'),
  ('fiscal_year_start_day',   '1'),
  ('invoice_no_format',       'INV-{YY}-{YY+1}-{SEQ}'),
  ('quote_no_format',         'QT-{YY}-{YY+1}-{SEQ}'),
  ('auto_reset_invoice_no',   '1'),
  ('last_fy_close_date',      ''),
  ('current_fy_start',        '');
```

- Bump `_dbVersion` by 1
- Populate `current_fy_start` on first open if it is empty (backfill to the April 1 of the current FY)

---

### A2 — `FiscalYearService` ✅ DONE (`d0a3eb6`)
**New file:** `lib/data/services/fiscal_year_service.dart`
**Effort:** 1 day

Key methods (from spec, verbatim):

```dart
class FiscalYearService {
  /// Returns the FY date range that contains [date].
  DateRange getFiscalYearFor(DateTime date);

  /// Returns the currently active FY date range.
  DateRange get currentFiscalYear;

  /// "FY 2025–26" or "CY 2025".
  String getFYLabel(DateRange range);

  /// True if today is within [daysBeforeEnd] of FY end.
  bool isApproachingYearEnd({int daysBeforeEnd = 30});

  /// True if today is the first day of a new FY and sequence not yet reset.
  bool isResetDue();

  Future<String> nextInvoiceNo();
  Future<String> nextQuoteNo();
}
```

Implementation notes:
- Reads `fiscal_year_start_month` / `fiscal_year_start_day` from `SettingsRepository`
- `DateRange` is a simple value object (`start`, `end` as `DateTime`)
- `getFiscalYearFor(date)`: if date ≥ FY start month/day of its year, FY = that year → next year; else FY = prior year → that year
- Format token expansion: `{YY}` = 2-digit FY start year, `{YY+1}` = 2-digit FY end year, `{SEQ}` = zero-padded sequence
- `isResetDue()`: compares today to `current_fy_start` in settings — if today is first day of new FY and `last_fy_close_date` is not this FY's end date → reset is due

---

### A3 — Refactor `InvoiceNumberService` ✅ DONE (`d0a3eb6`)
**File:** `lib/data/services/invoice_number_service.dart`
**Effort:** 1 day

Current code is hardcoded to `DateTime.now().year` with `INV-2026-XXX` format — must be replaced.

New logic:
- Delegate to `FiscalYearService.nextInvoiceNo()` and `nextQuoteNo()`
- Format reads from settings (`invoice_no_format`, `quote_no_format`)
- Sequence counter: query `MAX(invoice_no)` filtered to current FY prefix (e.g. `LIKE 'INV-25-26-%'`)
- On FY start date (if `auto_reset_invoice_no = 1`), sequence resets to 1 automatically
- If format changes mid-year: old invoices keep their numbers; new ones use new format (settings screen warns)

---

### A4 — FY Quick Filter in Reports Screen ✅ DONE (`c39b027`)
**File:** `lib/presentation/screens/reports/reports_screen.dart`
**File:** `lib/presentation/providers/report_provider.dart`
**Effort:** 1 day

Add chip row above the existing month selector:

```
[This FY ●]  [Last FY]  [Custom]
```

- `This FY` is default — replaces the current "month" default
- `Last FY` loads the prior FY date range from `FiscalYearService`
- `Custom` falls back to the existing month picker
- A `reportFYProvider` (StateProvider) controls the active FY filter; all data providers read it when mode = FY
- FY label shown in AppBar or section header: "FY 2025–26"
- **Do not remove** the monthly view — keep it, just demote it to secondary

---

### A5 — Year-End Warning Notification ✅ DONE (`c39b027`)
**File:** `lib/data/services/notification_service.dart`
**Effort:** Half day

Schedule at app startup (and on foreground resume):

| Trigger | Notification |
|---|---|
| `isApproachingYearEnd(daysBeforeEnd: 7)` AND `!isClosed` | "Your financial year ends in 7 days. Review and close FY 2024–25." |
| Last backup > 14 days old AND 7 days before FY end | "Your FY ends in 7 days and your last backup was {N} days ago — back up now." |
| Today == FY end AND `!isClosed` | "Today is the last day of FY 2024–25. Close the year before midnight." |
| Tomorrow == FY start AND `!isClosed` | "FY 2025–26 has started. Complete year-end closing for FY 2024–25." |

- Use `flutter_local_notifications` (already in `pubspec.yaml`)
- Use `NotificationService.scheduleYearEndAlerts()` called from `main.dart` after DB init
- Notifications stop once `last_fy_close_date` is set

---

### A6 — Home Screen Banner (March 25 onwards) ✅ DONE (`c39b027`)
**File:** `lib/presentation/screens/home/home_screen.dart`
**Effort:** 2 hours

Dismissible `MaterialBanner` at top of Home screen:

```
📅 FY 2024–25 ends on 31 March. Review and close on time.
                                                [Close FY →]
```

- Shown from March 25 until FY is closed or new FY starts
- `[Close FY →]` navigates to Settings → Financial Year (where the wizard will live in Phase 2; for Phase 1, just show a snackbar "Year-end closing wizard coming soon")
- Read from `FiscalYearService.isApproachingYearEnd(daysBeforeEnd: 7)`

---

### Phase 1 Summary — Timeline

| Week | Tasks | Status |
|---|---|---|
| **Week 1** (2–8 Mar) | A1 DB schema + A2 `FiscalYearService` | ✅ Done |
| **Week 2** (9–15 Mar) | A3 Refactor `InvoiceNumberService` | ✅ Done |
| **Week 3** (16–22 Mar) | A4 FY filter in Reports | ✅ Done |
| **Week 4** (23–29 Mar) | A5 Notifications + A6 Banner — must land by March 25 | ✅ Done |
| **Buffer** (30–31 Mar) | Polish, test on device, hotfix if needed | Pending |

---

## Track B — Storage Growth Management & Disaster Recovery

No hard deadline, but items B1–B3 are low-risk and high-impact — do them in parallel with Track A.

### B1 — WAL Mode + Integrity Check + Rolling Snapshot ✅ DONE (`d0a3eb6`)
**File:** `lib/data/services/database_helper.dart`
**Effort:** 3 hours

Three changes in `_initDatabase()`:

```dart
// 1. Ensure WAL mode
await db.rawQuery('PRAGMA journal_mode=WAL');

// 2. Integrity check on open
final check = await db.rawQuery('PRAGMA integrity_check');
if (check.first.values.first != 'ok') {
  // Log and offer restore from snapshot
}

// 3. Rolling snapshot — once per day
await _maybeSnapshot(db);
```

`_maybeSnapshot`:
- Reads last snapshot date from `SharedPreferences`
- If today != last snapshot date: copy `kash_cube.db` → `kash_cube_prev.db`
- On restore prompt: `BackupService.restoreFromSnapshot()`
- **Impact:** ~2× DB storage, but typical DBs are 1–5 MB — total cost < 10 MB

---

### B2 — Android `backup_rules.xml` ✅ DONE (`d0a3eb6`)
**File:** `android/app/src/main/res/xml/backup_rules.xml` (new)
**File:** `android/app/src/main/AndroidManifest.xml`
**Effort:** 2 hours

```xml
<!-- backup_rules.xml -->
<full-backup-content>
  <include domain="database" path="kash_cube.db" />
  <exclude domain="file" path="images/" />
  <exclude domain="file" path="pdfs/" />
</full-backup-content>
```

Note: archive DBs (`archive_FY*.db`) will be added when FY archiving lands in Phase 2. For now just protect the active DB.

Update `AndroidManifest.xml`:
```xml
android:allowBackup="true"
android:fullBackupContent="@xml/backup_rules"
```

---

### B3 — `PdfCacheManager` (Ephemeral PDFs, FY-Prefixed Filenames) ✅ DONE (`9a24a3b`)
**New file:** `lib/data/services/pdf_cache_manager.dart`
**Effort:** 1 day

Responsibilities:
- Generate PDFs into a `pdfs/` temp directory (not Documents)
- PDF filename format: `Invoice_INV-25-26-0042.pdf` (FY prefix from invoice number)
- On `AppLifecycleState.resumed`: delete PDFs older than 24 hours
- Keep at most last 3 PDFs on disk as convenience buffer
- `clearAll()` method called from Storage Dashboard "Clear cache" button

Wire into `InvoicePdfService` — currently generates to a path that may persist. Redirect to `PdfCacheManager.tempPath(invoiceNo)`.

---

### B4 — Storage Health Dashboard ✅ DONE (`9a24a3b`)
**File:** `lib/presentation/screens/settings/settings_screen.dart`
**New file:** `lib/presentation/screens/settings/storage_health_screen.dart`
**Effort:** 1 day

Settings entry: "Storage & Backup" → opens `StorageHealthScreen`.

Screen layout:
```
Storage Usage
─────────────────────────────────────────────
FY 2025–26  (active)     X.X MB   [bar]
PDFs (cached)            X.X MB   [bar]  [Clear cache]
Images                   X.X MB   [bar]  [Manage]
─────────────────────────────────────────────
Total                    X.X MB
─────────────────────────────────────────────
Last backup:  {date or "Never"}
[Back Up Now]
```

- Per-FY rows added as FY archiving lands (Phase 2)
- "Back Up Now" calls `BackupService.createBackup()` (plain for now; encrypted in B6)
- "Clear cache" calls `PdfCacheManager.clearAll()`
- "Never" backed up → shows in warning red using `colors.expense`

---

### B5 — Image Compression on Import ✅ DONE (`9a24a3b`)
**File:** `lib/presentation/widgets/party_form_sheet.dart` (and anywhere else images are picked)
**Effort:** Half day

`flutter_image_compress` is in `pubspec.yaml`. Currently no compression happens on image pick.

```dart
final compressed = await FlutterImageCompress.compressWithFile(
  pickedFile.path,
  minWidth: 800, minHeight: 600,
  quality: 70,
);
// Hard cap: 150 KB — if still > 150 KB, reduce quality to 50
```

Warn user in `StorageHealthScreen` when total image storage > 20 MB.

---

### B6 — DB `VACUUM` on Schedule ✅ DONE (`9a24a3b`)
**File:** `lib/data/services/database_helper.dart`
**Effort:** 2 hours

After `_maybeSnapshot()`, add:

```dart
await _maybeVacuum(db);
```

`_maybeVacuum`:
- Check `SharedPreferences` for `last_vacuum_date`
- If > 30 days ago: run `PRAGMA VACUUM` on a background `Isolate`
- Update `last_vacuum_date`
- Log duration with `debugPrint`

---

### B7 — Encrypted `.kashcube` Export 🔄 IN PROGRESS
**File:** `lib/data/services/backup_service.dart` (major rewrite)
**New dependency:** `pointycastle` (or `encrypt` package) for AES-256-GCM + PBKDF2
**Effort:** 2 days

Replace the current plain-copy `BackupService` with the encrypted format from the spec:

#### Generation side
```
1. Read kash_cube.db bytes
2. Build manifest JSON (created_at, app_version, databases: [...])
3. Concatenate: manifest JSON bytes + DB bytes
4. Generate random 16-byte salt + 12-byte IV
5. PBKDF2-SHA256(passphrase, salt, 100_000 iterations) → 32-byte AES key
6. AES-256-GCM encrypt payload → ciphertext + 16-byte auth tag
7. Write file: "KSHC" + version(1) + salt + IV + schema_version(8B) + ciphertext + auth_tag
8. Share via OS share sheet (share_plus)
```

#### Import / restore side
```
1. Validate magic bytes "KSHC"
2. Read unencrypted schema version (needed for migration planning)
3. Prompt passphrase → PBKDF2 → AES key
4. AES-GCM decrypt → verify auth tag (fail loudly on wrong passphrase)
5. Parse manifest → show preview to user
6. User confirms → for each DB: write to temp, run migrations, integrity_check
7. All pass → atomic swap with live files → restart app
```

Max 5 passphrase attempts before lockout (cooldown, not wipe).

---

### B8 — Onboarding Backup Nudge
**File:** `lib/presentation/screens/home/home_screen.dart` or first-run flow
**Effort:** Half day

After 5 transactions, show once:
```
Your data is only on this device.
Set a backup passphrase so you never lose it.

[Set Backup Passphrase]    [Remind me later]
```

Monthly reminder (via `NotificationService`) if no backup in 30 days. Track with `last_backup_date` in `SharedPreferences`.

---

### Track B Summary — Timeline

| Week | Tasks | Status |
|---|---|---|
| **Week 1** (2–8 Mar) | B1 WAL + integrity + snapshot + B2 Android backup_rules.xml | ✅ Done |
| **Week 2** (9–15 Mar) | B3 `PdfCacheManager` + B4 Storage Health Dashboard | ✅ Done |
| **Week 3** (16–22 Mar) | B5 Image compression + B6 DB VACUUM | ✅ Done |
| **Week 4** (23–29 Mar) | B7 Encrypted `.kashcube` export (generation side) | Pending |
| **April Week 1** | B7 Encrypted import + restore flow | Pending |
| **April Week 2** | B8 Onboarding nudge + FY close backup prompt (tied to Phase 2 wizard) | Pending |

---

## Phase 2 — Year-End Closing Wizard (April, after 1 Apr flip)

| Task | Effort | Depends on |
|---|---|---|
| Year-end closing wizard UI (3 steps) | 3 days | A2, A3 |
| Opening balance carry-forward | 2 days | Wizard step 2 |
| GST summary in year-end report | 1 day | A4 FY filter |
| FY archiving to `archive_FY{YYYY}.db` | 2 days | Wizard completion |
| Backup prompt in wizard Step 3 | Half day | B7 encrypted export |
| Update `backup_rules.xml` to include `archive_FY*.db` | 2 hours | Archiving |

---

## Decision Points

| Decision | Recommendation |
|---|---|
| `InvoiceNumberService` — format migration for existing invoices | Keep existing `INV-2026-XXX` invoices as-is, new invoices use FY format from settings. No renumbering. |
| `FiscalYearService` — standalone service or use case? | Service (`lib/data/services/`). Pure logic, no UI, reads settings. Promoted to domain if it grows. |
| Encryption library | Use `encrypt` package (wraps PointyCastle). Already battle-tested in Flutter. Add to `pubspec.yaml`. |
| `BackupService` rewrite — backward compat? | Existing plain `.db` backups remain restoreable via the old `restoreFromBackup()` path. New `.kashcube` is additive. |
| Storage dashboard — separate screen or section in Settings? | Separate `StorageHealthScreen` navigated to from Settings, keeps Settings clean. |

---

## Files to Create (Net New)

| File | Track |
|---|---|
| `lib/data/services/fiscal_year_service.dart` | A2 |
| `lib/data/services/pdf_cache_manager.dart` | B3 |
| `lib/presentation/screens/settings/storage_health_screen.dart` | B4 |
| `android/app/src/main/res/xml/backup_rules.xml` | B2 |
| `android/app/src/main/res/xml/data_extraction_rules.xml` | B2 |

## Files to Modify (Significant Changes)

| File | Change |
|---|---|
| `lib/data/services/database_helper.dart` | WAL mode, integrity check, snapshot, VACUUM |
| `lib/data/services/invoice_number_service.dart` | Full rewrite — FY-aware, format-configurable |
| `lib/data/services/backup_service.dart` | Phase towards encrypted `.kashcube` format |
| `lib/data/services/notification_service.dart` | FY year-end schedule |
| `lib/presentation/screens/reports/reports_screen.dart` | FY quick filter |
| `lib/presentation/providers/report_provider.dart` | FY-scoped providers |
| `lib/presentation/screens/home/home_screen.dart` | Year-end banner + backup nudge |
| `lib/presentation/screens/settings/settings_screen.dart` | "Storage & Backup" entry |
| `lib/presentation/widgets/party_form_sheet.dart` | Image compression on pick |
| `android/app/src/main/AndroidManifest.xml` | `allowBackup` + `fullBackupContent` |

---

## What NOT to Do

- Do not silently auto-archive data — archiving is triggered only by the Year-End Closing Wizard (Phase 2)
- Do not block the app on the integrity check — offer restore, allow skip
- Do not store the backup passphrase on device in any form
- Do not add network calls for backup — user owns the `.kashcube` file entirely
- Do not renumber existing invoices — only new invoices use the new FY format
- Do not remove the monthly reports view — FY filter is additive
