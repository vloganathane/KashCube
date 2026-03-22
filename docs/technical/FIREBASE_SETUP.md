# Firebase Analytics Setup

This document covers the one-time setup steps needed to connect KashCube to Firebase Analytics.

## Prerequisites

- Firebase CLI installed: `npm install -g firebase-tools`
- FlutterFire CLI installed: `dart pub global activate flutterfire_cli`
- A Firebase project created at [console.firebase.google.com](https://console.firebase.google.com)

---

## Step 1 — Create a Firebase project

1. Go to [console.firebase.google.com](https://console.firebase.google.com).
2. Click **Add project** → enter a name (e.g., `kashcube-prod`).
3. Disable Google Analytics on the first run if you prefer to configure it separately, or keep it enabled.

---

## Step 2 — Run FlutterFire configure

From the project root:

```bash
flutterfire configure
```

This command:
- Registers the Android app (`com.kashcube.kash_cube`) in the Firebase project.
- Downloads **`google-services.json`** → `android/app/google-services.json`.
- Downloads **`GoogleService-Info.plist`** → `ios/Runner/GoogleService-Info.plist`.
- Applies the `google-services` Gradle plugin to `android/app/build.gradle.kts`.

> **Important**: `google-services.json` is gitignored. Each developer must run this step.

---

## Step 3 — Apply the Gradle plugin (if not auto-applied by FlutterFire)

In `android/app/build.gradle.kts`, ensure the plugins block contains:

```kotlin
plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")   // ← add this
}
```

In `android/build.gradle.kts` (root), ensure the buildscript has the classpath:

```kotlin
buildscript {
    dependencies {
        classpath("com.google.gms:google-services:4.4.2")
    }
}
```

---

## Step 4 — Verify

Run the debug build and check LogCat for:

```
I/FirebaseApp: Firebase SDK initialized successfully
```

Or use the Firebase DebugView in the console to see live events during development.

---

## What analytics collects (when user opts in)

| Event | Trigger |
|-------|---------|
| `screen_*` | Each screen navigation |
| `transaction_added` | User saves a transaction |
| `invoice_created` | User creates an invoice |
| `backup_created` | User exports a backup |
| `analytics_consent_given` | User enables analytics toggle |
| `analytics_consent_revoked` | User disables analytics toggle |

**Never logged**: transaction amounts, party names, account balances, SMS content, or any PII.

---

## Disabling analytics in debug builds

In `lib/presentation/providers/analytics_provider.dart`, change the backend:

```dart
AnalyticsService _buildBackend() {
  // return FirebaseAnalyticsService();
  return const NoOpAnalyticsService(); // ← use in debug / unit tests
}
```

---

## Privacy notes

- Analytics is **off by default**. The user must opt in via Settings → Privacy.
- `SettingsKeys.analyticsConsent` stores the consent: `'true'` | `'false'` | `null`.
- `AnalyticsService.setEnabled(false)` is called on startup when consent is not given.
- See `docs/legal/PRIVACY_POLICY.md` v1.1 for the full data-handling policy.
