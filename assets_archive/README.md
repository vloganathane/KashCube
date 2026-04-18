# Archived Assets

These files were moved from assets/ to reduce APK size.
They are not declared in pubspec.yaml and are not used in the codebase.
Kept for historical reference only.

Date archived: 2026-04-18


## Archived Directories

### web_ui/ (44MB)
Flutter web build output for the Web Companion feature. To re-enable:
1. Move `assets_archive/web_ui/` back to `assets/web_ui/`
2. Follow steps in `docs/WEB_COMPANION_REENABLE.md`

Or rebuild fresh web UI:
```bash
bash scripts/build_web_ui.sh
```
