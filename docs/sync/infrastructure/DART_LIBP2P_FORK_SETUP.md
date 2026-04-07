# dart_libp2p Fork Setup and Maintenance

**Date**: 7 April 2026  
**Status**: Active fork maintained by KashCube team  
**Upstream**: https://github.com/aetherity/dart_libp2p  
**Fork**: https://github.com/kashcube/dart_libp2p  

---

## 1. Fork Rationale

**Why Fork from Day 1?**

1. **Single Maintainer Risk**: Package is 9 months old with one maintainer (stephanfeb/aetherity)
2. **Privacy Verification**: Need full code audit to ensure zero network calls (KashCube privacy guarantee)
3. **Control**: If maintainer becomes unresponsive, we maintain full control
4. **Custom Features**: May need KashCube-specific optimizations:
   - BLE transport for offline proximity sync (Phase 3+)
   - Relay policy enforcement (conditional hosting)
   - Financial data stream prioritization
5. **License**: MIT/Apache 2.0 (assumed) allows freedom to fork, modify, redistribute

**Fork Strategy**: **Fork insurance** — Fork exists, but using pub.dev for Phase 1 due to packaging issue. Will fix and switch to fork if custom changes needed.

**Packaging Issue Discovered** (7 April 2026):
- dart_libp2p has relative path dependency: `path: ../dart-udx`
- This breaks git dependency usage (cannot resolve paths outside repo)
- **Workaround**: Use pub.dev version (^1.0.3) for Phase 1
- **Fix needed**: If custom changes required, fix pubspec.yaml in fork:
  ```yaml
  # Change from:
  dart_udx:
    path: ../dart-udx
  # To:
  dart_udx: ^2.0.3  # Use pub.dev version
  ```
- **Upstream PR**: Consider contributing this fix upstream

---

## 2. Fork Setup (One-Time)

### Step 1: Create Fork on GitHub

```bash
# On GitHub web UI:
# 1. Navigate to https://github.com/aetherity/dart_libp2p
# 2. Click "Fork" button
# 3. Create fork under "kashcube/dart_libp2p"
```

**Or via GitHub CLI**:
```bash
gh repo fork aetherity/dart_libp2p --org kashcube --clone=false
```

### Step 2: Clone Fork Locally

```bash
cd ~/code/kashcube-deps  # Or wherever you store dependencies
git clone https://github.com/kashcube/dart_libp2p.git
cd dart_libp2p
```

### Step 3: Add Upstream Remote

```bash
# Track upstream for pulling updates
git remote add upstream https://github.com/aetherity/dart_libp2p.git
git fetch upstream

# Verify remotes
git remote -v
# origin    https://github.com/kashcube/dart_libp2p.git (fetch)
# origin    https://github.com/kashcube/dart_libp2p.git (push)
# upstream  https://github.com/aetherity/dart_libp2p.git (fetch)
# upstream  https://github.com/aetherity/dart_libp2p.git (push)
```

### Step 4: Create Branch Strategy

```bash
# main = track upstream (keep in sync)
git checkout main
git merge upstream/main  # Start in sync

# kashcube-custom = KashCube-specific changes
git checkout -b kashcube-custom
git push -u origin kashcube-custom
```

### Step 5: Update KashCube pubspec.yaml

```yaml
dependencies:
  # Use our fork via git dependency
  dart_libp2p:
    git:
      url: https://github.com/kashcube/dart_libp2p.git
      ref: v1.0.3  # Pin to specific tag initially
      # Later: ref: kashcube-custom  # Switch to custom branch when needed
```

### Step 6: Test Fork Integration

```bash
cd /path/to/KashCube
flutter pub get
flutter test test/dart_libp2p_import_test.dart  # Should pass
```

---

## 3. Daily Workflow

### Using Upstream Version (Phase 1)

**For Phase 1**: Use upstream `v1.0.3` as-is (no modifications needed).

```yaml
# pubspec.yaml
dart_libp2p:
  git:
    url: https://github.com/kashcube/dart_libp2p.git
    ref: v1.0.3  # Upstream tag
```

**Rationale**: Start with vanilla upstream, only diverge if issues arise.

### Making Custom Changes (Phase 2+)

**If custom changes needed**:

1. **Create Feature Branch**:
   ```bash
   cd ~/code/kashcube-deps/dart_libp2p
   git checkout kashcube-custom
   git checkout -b feature/ble-transport
   
   # Make changes
   # Test thoroughly
   
   git commit -m "Add BLE transport for offline proximity sync"
   git push origin feature/ble-transport
   ```

2. **Merge to kashcube-custom**:
   ```bash
   git checkout kashcube-custom
   git merge feature/ble-transport
   git push origin kashcube-custom
   ```

3. **Update KashCube Dependency**:
   ```yaml
   # pubspec.yaml
   dart_libp2p:
     git:
       url: https://github.com/kashcube/dart_libp2p.git
       ref: kashcube-custom  # Now use custom branch
   ```

4. **Consider Upstream Contribution**:
   ```bash
   # If feature benefits wider community:
   git checkout -b upstream-pr/ble-transport
   git cherry-pick <commit-hash>  # Pick feature commits
   git push origin upstream-pr/ble-transport
   
   # Create PR to aetherity/dart_libp2p from GitHub UI
   ```

---

## 4. Syncing with Upstream

**Frequency**: Monthly (or when upstream releases new version)

### Check for Upstream Updates

```bash
cd ~/code/kashcube-deps/dart_libp2p
git fetch upstream

# Check what changed
git log main..upstream/main --oneline

# Review changes
git diff main upstream/main
```

### Merge Upstream Changes

```bash
# Update our main branch
git checkout main
git merge upstream/main
git push origin main

# Merge into kashcube-custom (resolve conflicts if any)
git checkout kashcube-custom
git merge main

# Resolve conflicts if any
# git mergetool
# git commit

git push origin kashcube-custom
```

### Handle Conflicts

**If merge conflicts**:
1. Review upstream changes carefully (privacy implications?)
2. Resolve conflicts favoring KashCube requirements
3. Add conflict resolution notes to `KASHCUBE_CHANGES.md`
4. Test thoroughly after merge

---

## 5. Documentation

### KASHCUBE_CHANGES.md (In Fork Repo)

Create in fork root:

```markdown
# KashCube-Specific Changes to dart_libp2p

This fork is maintained by the KashCube team. We track upstream and contribute back when possible.

## Divergences from Upstream

### Features Added

- **None yet** (Phase 1 uses vanilla upstream v1.0.3)

### Future Planned Features

- **BLE Transport** (Phase 3+): Bluetooth Low Energy transport for offline proximity sync
- **Relay Policy Hooks** (Phase 2): Conditional hosting enforcement
- **Stream Prioritization** (Phase 2+): Prioritize financial data streams over discovery/keepalive

### Bugs Fixed

- **None yet**

### Upstream Contributions

- **None yet**

## Version Mapping

| KashCube Version | dart_libp2p Fork Version | Upstream Version | Notes |
|------------------|--------------------------|------------------|-------|
| v1.0.0+1         | v1.0.3                   | v1.0.3           | Vanilla upstream |

## Sync Status

- **Last Sync**: 7 April 2026 (initial fork)
- **Upstream Commits Behind**: 0 (in sync)
- **Custom Commits Ahead**: 0 (no custom changes yet)

## Contact

- **Maintainer**: KashCube Core Team
- **Fork**: https://github.com/kashcube/dart_libp2p
- **Upstream**: https://github.com/aetherity/dart_libp2p
- **Issues**: Report KashCube-specific issues at kashcube/dart_libp2p
- **Upstream Issues**: Report general issues at aetherity/dart_libp2p

## License

MIT License (inherited from upstream)
```

---

## 6. Testing Strategy

### Before Merging Upstream Changes

**Test Suite** (run in KashCube app):
```bash
# Unit tests
flutter test test/data/repositories/libp2p_sync_repository_impl_test.dart

# Integration tests (2-device sync)
flutter drive --driver=test_driver/integration_test.dart \
              --target=integration_test/sync_test.dart

# Smoke tests
flutter test test/dart_libp2p_import_test.dart
```

### Performance Regression Tests

**After merging upstream**:
1. Run Phase 1.6 comparative tests (WebRTC vs libp2p)
2. Check for battery drain regression (should be < 5%/hour)
3. Verify sync latency (should be < 2 seconds for 1000 rows)
4. Memory usage (should be < 50 MB during active sync)

---

## 7. Contribution Guidelines

### When to Contribute Upstream

| Change Type | Action | Reasoning |
|-------------|--------|-----------|
| **Bug fix** | ✅ Contribute upstream | Benefits everyone |
| **Security fix** | ✅ Contribute ASAP | Critical for ecosystem |
| **Performance optimization** | ✅ Try upstream first | Reduces maintenance burden |
| **New transport (BLE)** | ✅ Contribute upstream | General use case |
| **KashCube-specific** | ❌ Keep in fork | Relay policy, business logic |
| **Breaking API change** | ⚠️ Discuss first | May diverge permanently |

### Contribution Workflow

1. **Create Upstream-PR Branch**:
   ```bash
   git checkout -b upstream-pr/fix-memory-leak
   git cherry-pick <commit-hash>  # Pick specific commits
   ```

2. **Clean Up Commits**:
   ```bash
   git rebase -i HEAD~3  # Squash, reword for clean history
   ```

3. **Push to Fork**:
   ```bash
   git push origin upstream-pr/fix-memory-leak
   ```

4. **Create PR on GitHub**:
   - Navigate to https://github.com/aetherity/dart_libp2p
   - Click "New Pull Request"
   - Select: `aetherity/dart_libp2p:main` ← `kashcube/dart_libp2p:upstream-pr/fix-memory-leak`
   - Write clear description with test results
   - Reference any upstream issues

5. **Follow Up**:
   - Respond to maintainer feedback promptly
   - Update PR if requested
   - If PR merged: Delete feature branch
   - If PR rejected: Document reasoning in `KASHCUBE_CHANGES.md`

---

## 8. Versioning Strategy

### Fork Version Tags

**Format**: `v<upstream>-kashcube.<patch>`

**Examples**:
- `v1.0.3` = Vanilla upstream (initial)
- `v1.0.3-kashcube.1` = First KashCube custom change
- `v1.0.3-kashcube.2` = Second custom change
- `v1.0.4` = Upstream v1.0.4 (when released)
- `v1.0.4-kashcube.1` = Upstream v1.0.4 + custom changes

### Tagging Releases

```bash
cd ~/code/kashcube-deps/dart_libp2p
git checkout kashcube-custom

# Tag release
git tag -a v1.0.3-kashcube.1 -m "KashCube custom release 1: Add BLE transport"
git push origin v1.0.3-kashcube.1

# Update KashCube pubspec.yaml
# dart_libp2p:
#   git:
#     url: https://github.com/kashcube/dart_libp2p.git
#     ref: v1.0.3-kashcube.1  # Pin to tagged release
```

---

## 9. Emergency Rollback

**If fork breaks production**:

### Quick Rollback to Upstream

```yaml
# pubspec.yaml - Emergency rollback
dependencies:
  dart_libp2p: ^1.0.3  # Use pub.dev upstream directly
```

```bash
flutter pub get
flutter test  # Verify tests pass
git commit -am "Emergency rollback: Use upstream dart_libp2p from pub.dev"
```

### Rollback to Previous Fork Version

```yaml
# pubspec.yaml
dart_libp2p:
  git:
    url: https://github.com/kashcube/dart_libp2p.git
    ref: v1.0.3-kashcube.0  # Previous known-good version
```

---

## 10. Monitoring Fork Health

### Monthly Checklist

- [ ] Check upstream for new releases
- [ ] Review upstream CHANGELOG for relevant changes
- [ ] Merge upstream changes to `main` branch
- [ ] Test merge in KashCube app
- [ ] Update `KASHCUBE_CHANGES.md` with sync status
- [ ] Tag new fork version if custom changes added
- [ ] Update KashCube pubspec.yaml ref if needed

### Metrics to Track

| Metric | Target | Red Flag |
|--------|--------|----------|
| **Upstream Commits Behind** | < 10 | > 20 |
| **Custom Commits Ahead** | < 5 | > 15 |
| **Last Sync Age** | < 30 days | > 90 days |
| **Open Upstream PRs** | N/A | Any stuck > 60 days |
| **Fork Build Status** | ✅ Passing | ❌ Failing |

### Automated Health Check

```bash
#!/bin/bash
# scripts/check_fork_health.sh

cd ~/code/kashcube-deps/dart_libp2p
git fetch upstream

BEHIND=$(git rev-list --count main..upstream/main)
AHEAD=$(git rev-list --count upstream/main..kashcube-custom)
LAST_SYNC=$(git log -1 --format=%cr origin/main)

echo "Fork Health:"
echo "  Commits behind upstream: $BEHIND"
echo "  Commits ahead of upstream: $AHEAD"
echo "  Last sync: $LAST_SYNC"

if [ $BEHIND -gt 20 ]; then
  echo "⚠️  WARNING: Fork is $BEHIND commits behind upstream!"
  echo "   Action: Merge upstream changes"
fi

if [ $AHEAD -gt 15 ]; then
  echo "⚠️  WARNING: Fork has $AHEAD custom commits!"
  echo "   Action: Consider contributing some upstream"
fi
```

---

## 11. Phase 1 Fork Status

**Current State** (7 April 2026):

- **Fork Created**: ✅ https://github.com/vloganathane/dart_libp2p
- **Branch Strategy**: ✅ `main` (tracks upstream)
- **KashCube Dependency**: ⚠️ Using pub.dev ^1.0.3 (not fork) — See packaging issue below
- **Upstream Sync**: ✅ In sync with v1.0.3
- **Custom Changes**: ❌ None (using vanilla upstream from pub.dev)
- **Documentation**: ✅ DART_LIBP2P_FORK_SETUP.md created
- **License Verified**: ✅ MIT (https://github.com/stephanfeb/dart_libp2p/blob/main/LICENSE)

**Packaging Issue Discovered**:
- ❌ dart_libp2p cannot be used as git dependency yet
- **Root Cause**: `pubspec.yaml` has `dart_udx: path: ../dart-udx` (relative path)
- **Impact**: Flutter pub cannot resolve paths outside git repo
- **Workaround**: Use pub.dev version for Phase 1 (fork exists as insurance)
- **Fix Required**: If custom changes needed, fix pubspec.yaml in fork:
  ```yaml
  # In fork's pubspec.yaml, change:
  dart_udx:
    path: ../dart-udx
  # To:
  dart_udx: ^2.0.3  # Use pub.dev version like other deps
  ```
- **Upstream Contribution**: Consider PR to fix this (benefits ecosystem)

**Fork Insurance Status**:
- ✅ Fork exists and ready
- ✅ Can fix packaging and switch to fork anytime
- ✅ Phase 1 proceeds with pub.dev (no blocker)
- ⏳ Switch to fork only if custom changes needed (Phase 2+)

**Phase 1 Fork Plan**:
1. ✅ Fork created and configured
2. ✅ Use vanilla upstream v1.0.3 (no custom changes)
3. ⏳ Implement Phase 1.3-1.6 using fork
4. ⏳ Monitor for issues (no custom changes expected)
5. ⏳ Phase 1.6 comparative testing (verify fork works identically to pub.dev)

**Custom Changes Expected**: **None for Phase 1** — only fork if Phase 1 reveals issues.

---

## 12. References

- **Gap Analysis**: `DART_LIBP2P_GAP_ANALYSIS.md` (fork rationale, risk mitigation)
- **Implementation Plan**: `LIBP2P_FLUTTER_IMPLEMENTATION_PLAN.md` (Phase 1 details)
- **Protocol Spec**: `LIBP2P_KASH_SYNC_PROTOCOL.md` (protocol design)
- **Upstream Repo**: https://github.com/aetherity/dart_libp2p
- **Fork Repo**: https://github.com/kashcube/dart_libp2p
- **pub.dev**: https://pub.dev/packages/dart_libp2p

---

**Next Steps**:
1. Create GitHub fork (5 minutes)
2. Update pubspec.yaml to use fork (2 minutes)
3. Run tests to verify fork works (5 minutes)
4. Proceed with Phase 1.3 implementation (3-4 days)

**Owner**: KashCube Core Team  
**Maintainer**: Primary assigned after Phase 1 completion
