# Makefile: helper targets for building the Windows installer

SHELL := powershell.exe

# Variables (override on command line: `make installer-windows VERSION=1.2.3 SIGN=1 PFX=path PFXPASS=secret`)
VERSION ?=
SIGN ?=0
PFX ?=
PFXPASS ?=
TIMESTAMP ?=http://timestamp.digicert.com

.PHONY: installer-windows
installer-windows:
	@echo Building Windows installer...
	@if ($$env:OS -ne "Windows_NT") { Write-Host "This target is intended to run on Windows."; exit 1 }
	@powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build_windows_installer.ps1 \
		$(if $(VERSION),-Version $(VERSION)) \
		$(if $(filter 1,$(SIGN)),-Sign) \
		$(if $(PFX),-PfxPath "$(PFX)") \
		$(if $(PFXPASS),-PfxPassword "$(PFXPASS)") \
		-TimestampUrl "$(TIMESTAMP)"
.PHONY: apk apk-universal apk-install apk-aab db-inventory db-inventory-check

# ── Android release builds ───────────────────────────────────────────────────

## apk  — arm64-only release APK (fastest; covers all modern Android phones).
##        Output: build/app/outputs/flutter-apk/app-release.apk
apk:
	flutter build apk --release \
		--target-platform android-arm64 \
		--split-debug-info=build/debug-info \
		--no-tree-shake-icons
	@echo "✓ APK → build/app/outputs/flutter-apk/app-release.apk"

## apk-universal  — fat APK for all ABIs (arm, arm64, x86_64), split per ABI.
##                  Use for Play Store or distribution to unknown devices.
##        Output: build/app/outputs/flutter-apk/app-*-release.apk
apk-universal:
	flutter build apk --release \
		--split-per-abi \
		--split-debug-info=build/debug-info
	@echo "✓ APKs → build/app/outputs/flutter-apk/"

## apk-install  — build arm64 APK and push it straight to a connected device.
apk-install: apk
	adb install -r build/app/outputs/flutter-apk/app-release.apk
	@echo "✓ Installed on connected device"

## apk-aab  — release App Bundle for Play Store submission.
##        Output: build/app/outputs/bundle/release/app-release.aab
apk-aab:
	flutter build appbundle --release \
		--split-debug-info=build/debug-info
	@echo "✓ AAB → build/app/outputs/bundle/release/app-release.aab"

db-inventory:
	python3 scripts/generate_db_inventory.py --output docs/codebase/DATABASE_INVENTORY_AUTO.md
	@echo "Generated docs/codebase/DATABASE_INVENTORY_AUTO.md"

db-inventory-check:
	python3 scripts/generate_db_inventory.py --output /tmp/kashcube_db_inventory_check.md --expect-table-count 61
	@echo "Table count check passed (61)"
