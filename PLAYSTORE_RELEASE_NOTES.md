# Play Store Release Notes

## Version 1.0.1 (Build 2) - 18 April 2026

### For Play Store Console (500 character limit)

```
Bug fixes and improvements:
• Fixed biometric unlock crash in Settings
• Fixed PIN lock triggering during normal usage (transactions, keyboard input)
• Improved payment method selection - now interactive with smart filtering
• Reduced app size by 45MB

Better stability and smoother experience!
```

### Detailed Release Notes (Internal/Website)

**What's Fixed**

🔒 **Biometric Authentication**
- Resolved crash when enabling fingerprint/face unlock in Settings
- Added proper error messages for unsupported devices

🔐 **PIN Lock Improvements**
- Fixed spurious PIN lock screen appearing during transaction saves
- No more interruptions when using keyboard or viewing dialogs
- Smarter detection of actual app backgrounding vs. temporary UI events

💳 **Payment Method UX**
- Payment method dropdown now stays enabled when account is selected
- Shows only valid methods for your account type
- Example: Bank accounts display UPI, Net Banking, Debit Card, Cheque
- Smart preservation of your selection when switching accounts

📦 **App Size Optimization**
- Reduced installation size by ~45MB
- Removed unused Web Companion assets (feature disabled for this release)
- Faster downloads and less storage usage

**Technical Details**

- Version: 1.0.1 (Build 2)
- Minimum Android: 8.0 (API 26)
- Target Android: 14 (API 34)
- Size: ~15MB (down from ~60MB)

**Privacy Commitment**

✅ 100% local data storage
✅ Zero network calls for financial data
✅ No third-party trackers
✅ Optional anonymous usage analytics (can be disabled in Settings)

---

## Version 1.0.0 (Build 1) - 3 April 2026

Initial Play Store release - Privacy-first financial tracker for India.

**Core Features**
- Automatic SMS transaction capture (UPI, banks)
- Credit/Udhar (khata) management
- Transaction categorization and budgeting
- Charts and spending insights
- PIN lock with biometric authentication
- 100% offline, local-first operation

---

## Release Checklist

- [x] Version bumped: 1.0.0+1 → 1.0.1+2
- [x] All fixes tested on emulator
- [x] Release AAB built: `flutter build appbundle --release`
- [ ] AAB signed and verified
- [ ] Tested on physical device
- [ ] Play Store screenshots updated (if needed)
- [ ] Privacy Policy reviewed (no changes needed)
- [ ] Play Store listing updated with release notes
- [ ] Uploaded to Play Console for review
