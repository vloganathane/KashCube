# ExpenseOwl 🦉

**Privacy-First Expense Tracker for Indian Small Businesses & Freelancers**

ExpenseOwl is a Flutter mobile app that automatically captures UPI transactions from SMS, manages customer credits (udhar/khata), and provides comprehensive financial tracking—all while keeping your data 100% local and private.

## 🎯 Vision

A smart expense tracker designed specifically for the Indian market that:
- 📱 **Auto-captures** transactions from UPI SMS (PhonePe, GPay, Paytm, BHIM)
- 💰 **Manages credits** given to customers with auto-linking of repayments
- 🔒 **Privacy-first** - All data stays on your device, no cloud required
- 📊 **Smart reports** - Daily, monthly, and yearly analytics
- 🇮🇳 **Built for India** - UPI-focused, supports top banks and payment apps

## ✨ Key Features

### MVP (6 Weeks)
- ✅ **SMS Auto-Capture** - Parse UPI/bank transactions automatically
- ✅ **Credit Management** - Track udhar (credits given) and auto-link repayments  
- ✅ **Manual Entry** - Quick transaction input with smart categorization
- ✅ **Reports** - Daily summary, monthly charts, yearly trends
- ✅ **PIN Lock** - Secure with 4-digit PIN + biometric unlock
- ✅ **Local Backup** - Export/restore database with full control

### Beyond MVP
- 📅 Budget tracking with overspend alerts
- 🧾 Invoice generation (GST-compliant)
- 🔄 Recurring transaction management
- 🌐 Multi-language support (Hindi, Tamil, Telugu)
- 📸 Receipt scanning (OCR)

## 🛠️ Tech Stack

- **Framework:** Flutter 3.16+ / Dart 3.2+
- **Database:** SQLite (sqflite) - Local-only storage
- **State Management:** Riverpod 2.4+
- **SMS Parsing:** telephony 0.2.0 (Android)
- **Charts:** fl_chart 0.66+
- **Security:** local_auth (PIN + biometric)

## 🚀 Quick Start

### Prerequisites
- Flutter SDK 3.16+
- Dart SDK 3.2+
- Android Studio / Xcode (for emulators)

### Installation

```bash
# Clone repository
cd ExpenseOwl

# Install dependencies
flutter pub get

# Run app
flutter run
```

For detailed setup instructions, see [Setup Guide](./docs/SETUP_GUIDE.md).

## 📚 Documentation

Complete documentation is available in the [`/docs`](./docs) folder:

### Product & Planning
- 📋 [**Product Requirements (PRD)**](./docs/PRD.md) - Complete product vision, features, and requirements
- 🎯 [**MVP Scope**](./docs/MVP_SCOPE.md) - 6-week minimum viable product definition
- 🗺️ [**Implementation Roadmap**](./docs/IMPLEMENTATION_ROADMAP.md) - 26-week phased development plan
- 📊 [**User Personas**](./docs/PRD.md#4-user-personas) - Target users and use cases

### Technical
- 🏗️ [**Technical Architecture**](./docs/TECHNICAL_ARCHITECTURE.md) - System design and component architecture
- 🗄️ [**Database Schema**](./docs/DATABASE_SCHEMA.md) - Complete SQLite schema with relationships
- 📱 [**SMS Parsing Specification**](./docs/SMS_PARSING_SPEC.md) - Detailed SMS parsing patterns and logic

### Privacy & Security
- 🔒 [**Privacy Architecture**](./docs/PRIVACY_ARCHITECTURE.md) - Privacy-first design and commitments
- 📜 [**Privacy Policy**](./docs/PRIVACY_POLICY.md) - User-facing privacy policy

### Getting Started
- 📖 [**Documentation Index**](./docs/README.md) - Complete documentation overview
- ⚡ [**Setup Guide**](./docs/SETUP_GUIDE.md) - Development environment setup

## 🎨 Architecture Overview

```
┌─────────────────────────────────────────┐
│          UI Layer (Flutter)             │
│  Screens • Widgets • Material Design 3  │
└──────────────┬──────────────────────────┘
               │
┌──────────────▼──────────────────────────┐
│     Business Logic (Riverpod)           │
│  Providers • State • Services           │
└──────────────┬──────────────────────────┘
               │
┌──────────────▼──────────────────────────┐
│       Data Layer (SQLite)               │
│  Repository • Database • SMS Parser     │
└─────────────────────────────────────────┘
```

## 🔐 Privacy Commitment

- ✅ **100% Local** - All data stored on your device only
- ✅ **No Cloud** - No data uploaded to any server
- ✅ **No Analytics** - Zero tracking or telemetry
- ✅ **No Login** - No account creation required
- ✅ **Open Permissions** - Only READ_SMS (optional, explained clearly)

Read our complete [Privacy Architecture](./docs/PRIVACY_ARCHITECTURE.md).

## 🗺️ Roadmap

### Phase 1: Core MVP (Weeks 1-6) - Current
- SMS parsing for top 5 banks + 4 UPI apps
- Credit (udhar) management with auto-linking
- Transaction tracking & categorization
- Daily/Monthly/Yearly reports
- PIN lock & local backup

### Phase 2: Scale (Weeks 7-10)
- Budget management
- Recurring transactions
- Enhanced notifications

### Phase 3: Beta (Weeks 11-14)
- Testing with 10+ users
- Bug fixes & UX polish
- Dark mode improvements

### Phase 4: Launch (Weeks 15-18)
- Google Play listing
- Public beta release
- Marketing materials

See the complete [Implementation Roadmap](./docs/IMPLEMENTATION_ROADMAP.md).

## 🇮🇳 Made for India

### Supported UPI Apps (MVP)
- PhonePe
- Google Pay  
- Paytm
- BHIM

### Supported Banks (MVP)
- HDFC Bank
- ICICI Bank
- SBI
- Axis Bank
- Kotak Mahindra

More banks and UPI apps will be added based on community contributions. See [SMS Parsing Spec](./docs/SMS_PARSING_SPEC.md) for details.

## 💎 Monetization

**Freemium Model:**
- **Free Tier** - Unlimited transactions, all core features
- **Pro** (₹199/year) - Advanced reports, export options, priority support
- **Business Pro** (₹699/year) - Invoice generation, GST reports, multi-user

## 🤝 Contributing

We welcome contributions! Key areas:
- 🏦 SMS parsing patterns for more banks
- 🌐 Language translations
- 🐛 Bug reports and fixes
- 💡 Feature suggestions

## 📄 License

MIT License - Feel free to use this project for personal or commercial purposes.

## 🙏 Credits

Built with ❤️ for India's small businesses and freelancers.

---

**⭐ Star this repo if you find it useful!**

**🔒 Privacy-first. 🇮🇳 Made for India. 💰 Built for small businesses.**
