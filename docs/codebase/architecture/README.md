# Architecture Deep-Dive (As-Built)

This folder expands architecture documentation from high-level overview to runtime-accurate implementation detail.

## Documents

1. `BOOT_AND_STARTUP_AS_BUILT.md`
   - `main()` execution timeline
   - platform-conditional startup branches
   - `_LockGate` sequence and lifecycle behavior
2. `APP_SHELL_AND_NAVIGATION_AS_BUILT.md`
   - 5-tab shell architecture
   - per-tab nested navigators and stack behavior
   - adaptive layout (`NavigationRail` vs `NavigationBar`)
   - deep links, SMS overlays, role-aware tab access
3. `STATE_AND_DATAFLOW_ARCHITECTURE_AS_BUILT.md`
   - Riverpod orchestration model
   - provider/repository/service interaction flow
   - sync-event invalidation strategy
4. `RUNTIME_CROSS_CUTTING_AS_BUILT.md`
   - notifications and scheduler wiring
   - sync freshness guarantees
   - backup/cache/runtime reliability mechanisms

## Reading Order

- **New engineer onboarding**: 1 → 2 → 3 → 4
- **Debugging startup issues**: 1
- **Debugging navigation/FAB/deep-link issues**: 2
- **Debugging stale UI after sync**: 3 + 4
