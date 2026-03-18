#!/usr/bin/env bash
# build_web_ui.sh
# Builds the KashCube Flutter web UI and copies it into the app's asset bundle
# so the phone can serve it to browsers over the LAN.
#
# Run this before cutting a release APK that includes the web companion:
#   bash scripts/build_web_ui.sh
#
# The output lands in assets/web_ui/ and is registered in pubspec.yaml.
# The phone extracts these files at runtime into a temp directory and serves
# them via shelf_static on the same port as the P2P sync server.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

echo "▶ Building Flutter web UI (release)…"
flutter build web --release --dart-define=KASHCUBE_PLATFORM=web

echo "▶ Copying to assets/web_ui/…"
rm -rf assets/web_ui
cp -r build/web assets/web_ui

# The Flutter web build bundles assets/web_ui/ itself (because it's registered
# in pubspec.yaml), creating a nested assets/assets/web_ui/ copy inside the
# output. Remove it to break the recursion and keep the bundle lean.
rm -rf assets/web_ui/assets/assets/web_ui

echo "▶ Generating file manifest…"
find assets/web_ui -type f \
  | sed "s|assets/web_ui/||" \
  | sort \
  > assets/web_ui/manifest.txt

FILE_COUNT=$(wc -l < assets/web_ui/manifest.txt | tr -d ' ')
TOTAL_SIZE=$(du -sh assets/web_ui | cut -f1)

echo "✓ Web UI ready: $FILE_COUNT files, $TOTAL_SIZE total"
echo "  Run 'flutter build apk --release' to bundle it into the APK."
