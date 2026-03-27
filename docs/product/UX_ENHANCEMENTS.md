# UX Enhancements — Post-MVP Polish

**Status:** Backlog  
**Priority:** After tutorials complete (Item 16)  
**Last updated:** 24 March 2026

This document tracks polish and UX improvements to consider after core features are stable.

---

## Navigation & Chrome

### Animated Notch Bottom Bar
**Package:** [`animated_notch_bottom_bar`](https://pub.dev/packages/animated_notch_bottom_bar)  
**Status:** Proposed  
**Priority:** Medium  
**Estimated effort:** 2-4 hours + testing

**Benefits:**
- Premium, polished look with smooth animations
- Better visual feedback for active tab
- Modern Material 3 aesthetic
- Notch animation for FAB integration

**Considerations:**
- **Test with per-tab Navigators:** Verify `NotchBottomBarController` works with `IndexedStack` + 5 independent Navigator widgets
- **FAB positioning strategy:** Current FABs are bottom-right and context-dependent (SpeedDialFab on some tabs). Notch bars typically center the FAB. Decision needed:
  - Option A: Keep context FABs bottom-right (loses notch visual benefit)
  - Option B: Move to single centered FAB (requires UX rethink of per-tab actions)
- **Tutorial spotlight compatibility:** Verify GlobalKeys for bottom nav items still work with new widget tree
- **Tab reset logic:** Just stabilized in commits `050241b`, `4b99a0e`, `396eff0` — ensure new package doesn't break it

**Implementation notes:**
- Refactor `AppShell` bottom bar (currently `BottomNavigationBar` at lines 377-432)
- Update `handleTabSelected` to use `NotchBottomBarController`
- Test all 5 tabs, navigation flows, tutorial spotlights

**Alternative:** Material 3's built-in `NavigationBar` (smaller migration, less third-party risk)

**Privacy:** ✅ Pure UI package, no network calls, aligns with privacy-first architecture

**Decision:** Defer until after Item 16 (Reset all tutorials) is complete. Nice-to-have, not must-have.

---

## Future Categories

### Animations & Transitions
_TBD_

### Accessibility
_TBD_

### Gestures & Interactions
_TBD_

### Visual Polish
_TBD_
