#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

echo "[Phase4] Web Companion QA - scripted checks"
echo "Repo: $ROOT_DIR"
echo

check_file() {
  local f="$1"
  if [[ ! -f "$f" ]]; then
    echo "[FAIL] Missing file: $f"
    exit 1
  fi
  echo "[OK]   Found file: $f"
}

echo "1) Verify required files exist"
check_file "lib/data/services/p2p/p2p_server.dart"
check_file "lib/data/services/web/web_ui_extractor.dart"
check_file "lib/presentation/screens/settings/open_on_laptop_screen.dart"
check_file "lib/core/constants/app_constants.dart"
check_file "docs/sync/infrastructure/WEB_COMPANION_SPEC.md"
echo

echo "2) Static checks for Phase 1-3 hardening hooks"
grep -q "extractNow()" lib/data/services/web/web_ui_extractor.dart
echo "[OK]   extractor prewarm API present"

grep -q "..get('/health'" lib/data/services/p2p/p2p_server.dart
echo "[OK]   /health route present"

grep -q "isHealthy()" lib/data/services/p2p/p2p_server.dart
echo "[OK]   server readiness probe present"

grep -q "SocketException" lib/data/services/p2p/p2p_server.dart
grep -q "AppConstants.p2pPort" lib/data/services/p2p/p2p_server.dart
echo "[OK]   preferred-port then fallback logic present"

grep -q "serverPort" lib/presentation/screens/settings/open_on_laptop_screen.dart
echo "[OK]   QR uses runtime bound server port"
echo

echo "3) Flutter analyze (targeted files)"
flutter analyze \
  lib/data/services/p2p/p2p_server.dart \
  lib/data/services/p2p/p2p_coordinator.dart \
  lib/data/services/web/web_ui_extractor.dart \
  lib/data/services/web/web_companion_service.dart \
  lib/presentation/providers/p2p_provider.dart \
  lib/presentation/screens/settings/open_on_laptop_screen.dart \
  lib/core/constants/app_constants.dart

echo
echo "[PASS] Scripted Phase 4 checks completed successfully"
echo
echo "Manual validation still required:"
echo "  - hotspot OEM matrix (Pixel/Samsung/Xiaomi/Redmi)"
echo "  - 5+ minute background stability"
echo "  - port-50505 conflict fallback behavior"
