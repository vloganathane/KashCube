# Web Companion Media Sync (Phone <-> Browser)

Status: In progress (Phase 1 foundation landed)
Owner: KashCube app
Last updated: 2026-04-02

## Problem

Web Companion sync currently transfers table rows as JSON only.
Image fields are local file paths (`logo_path`, `business_card_image_path`) that are valid on the phone filesystem but not usable in browser runtime.

Result:
- Data rows sync.
- Actual image bytes do not sync.
- Browser may receive path strings that cannot be rendered.

## Goals

1. Support image visibility in Web Companion for phone-authored images.
2. Support browser-authored image updates that appear in mobile app.
3. Keep all transfer local-only (LAN), privacy-first, no internet calls.
4. Reuse existing WebSocket/HTTP infrastructure with minimal coupling.

## Non-goals (initial rollout)

1. Cloud media storage.
2. Third-party CDN/image services.
3. Heavy image editing pipeline in browser.

## Proposed architecture

### 1) Metadata in SQLite

Add `media_assets` table (syncable metadata):
- `media_id` (stable public ID, unique)
- `sha256`
- `mime_type`
- `byte_size`
- `origin` (`phone` or `web`)
- `local_path` (phone-side storage path; browser uses cache key)
- standard sync columns (`sync_id`, `version`, timestamps, deleted_at)

Add row-level references:
- `businesses.logo_media_id`
- `parties.business_card_media_id`

Keep old path columns for back-compat during migration:
- `businesses.logo_path`
- `parties.business_card_image_path`

### 2) Transport split

- WebSocket: control plane (handshake, progress, metadata signals).
- HTTP: data plane for image chunks/download stream.

Planned routes:
- `POST /media/upload/init`
- `POST /media/upload/chunk`
- `POST /media/upload/complete`
- `GET /media/{media_id}`

All routes must enforce the same authenticated browser session trust model already used by Web Companion.

### 3) Browser cache

- Store media payloads in IndexedDB keyed by `media_id` + `sha256`.
- Render from cache when present.
- Fetch on-demand when metadata is synced but bytes are missing.

## Rollout plan

### Phase 1 (this change set)

Foundation only:
- DB version bump to 84.
- `media_assets` table.
- Add `logo_media_id` and `business_card_media_id` columns.
- Add model fields for new references.
- No binary transfer yet.

### Phase 2

Web -> phone upload path:
- Implement chunked HTTP upload endpoints.
- Persist uploaded file under app-private storage.
- Create `media_assets` row and update owning row (`logo_media_id`/`business_card_media_id`).

### Phase 3

Phone -> web download path:
- Implement authenticated media GET endpoint.
- Web companion resolves missing media via metadata + fetch.
- Add cache invalidation using `sha256` changes.

### Phase 4

Hardening:
- MIME and size validation.
- Retry/resume for chunk uploads.
- Garbage collection for unreferenced media.

## Security and privacy constraints

1. LAN only, no outbound network calls.
2. Session-auth required for media endpoints.
3. App-private file storage on mobile.
4. Optional file-size caps and MIME allow-list in upload init.

## Migration notes

- Existing rows remain valid due to path fallback columns.
- UI should prefer `*_media_id` when available; fallback to path otherwise.
- Future cleanup migration can backfill `media_assets` from existing local paths.

## Validation checklist (when Phase 2/3 lands)

1. Add logo on web companion -> appears in mobile business profile.
2. Add business card image on web companion -> appears in mobile party profile.
3. Add logo on mobile -> appears in browser after metadata sync + media fetch.
4. Logout/disconnect should stop media fetch/upload immediately.
5. No image transfer outside local LAN.
