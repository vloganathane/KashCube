# Contributing to ExpenseOwl

Thank you for considering contributing to ExpenseOwl! 🦉

## How Can You Help?

### 🏦 Add SMS Parsing Patterns

The most valuable contribution is adding SMS parsing patterns for more banks and UPI apps.

**What we need:**
- Sample SMS text (remove sensitive info like amounts, names)
- Bank/UPI app name
- Sender ID (e.g., "HDFCBK", "PHONEPE")
- Expected parsed fields (amount, merchant, date, etc.)

**How to contribute:**
1. Open an issue with title: "SMS Pattern: [Bank Name]"
2. Provide sanitized SMS samples
3. We'll add the pattern to [SMS_PARSING_SPEC.md](./docs/SMS_PARSING_SPEC.md)

### 🐛 Report Bugs

Found a bug? Please open an issue with:
- **Title:** Clear, descriptive title
- **Description:** What happened vs what you expected
- **Steps to reproduce:** How can we see the bug?
- **Device info:** Android version, device model
- **Screenshots:** If applicable

### 💡 Suggest Features

Have an idea? We'd love to hear it!
- Check existing issues first to avoid duplicates
- Explain the use case and why it's valuable
- Consider if it fits our privacy-first philosophy

### 🌐 Translations

Want to add support for your language?
- Check [PRD.md](./docs/PRD.md) for multi-language roadmap
- Translations will be needed for: UI text, categories, reports
- We'll create a translation guide when ready (Phase 2)

## Development Guidelines

### Code Style
- Follow [Effective Dart](https://dart.dev/guides/language/effective-dart) guidelines
- Use `flutter analyze` before committing
- Format code with `flutter format .`

### State Management
- Use **Riverpod** (not Provider or BLoC)
- Follow patterns in [TECHNICAL_ARCHITECTURE.md](./docs/TECHNICAL_ARCHITECTURE.md)

### Database
- All changes must include migration scripts
- Update [DATABASE_SCHEMA.md](./docs/DATABASE_SCHEMA.md)
- Test migrations both forward and rollback

### Privacy First
- No network calls (we explicitly remove INTERNET permission)
- No telemetry or analytics
- No third-party SDKs that track users
- All data stays local

### Testing
- Write unit tests for business logic
- Widget tests for UI components
- Integration tests for critical flows
- Aim for 80%+ coverage

## Pull Request Process

1. **Fork** the repository
2. **Create a branch**: `git checkout -b feature/your-feature-name`
3. **Make changes** following our guidelines
4. **Test thoroughly**: Run all tests and manual testing
5. **Commit**: Write clear commit messages
6. **Push**: `git push origin feature/your-feature-name`
7. **Open PR**: Fill out the PR template (coming soon)

### PR Checklist
- [ ] Code builds without errors
- [ ] All tests pass (`flutter test`)
- [ ] Code is formatted (`flutter format .`)
- [ ] No new analysis issues (`flutter analyze`)
- [ ] Documentation updated if needed
- [ ] Privacy principles maintained (no data leaks)

## Code Review

We'll review PRs within 1-2 weeks. We may:
- Request changes for code quality
- Suggest improvements
- Ask questions about implementation

Please be patient and responsive to feedback.

## Community Guidelines

- Be respectful and inclusive
- Welcome newcomers
- Assume good intentions
- Give constructive feedback
- Focus on the code, not the person

## Development Setup

See [SETUP_GUIDE.md](./docs/SETUP_GUIDE.md) for detailed setup instructions.

**Quick start:**
```bash
flutter pub get
flutter run
```

## Questions?

- **General questions:** Open a GitHub Discussion (coming soon)
- **Bug reports:** Open an issue
- **Security concerns:** Email security@expenseowl.app (if serious)

## Recognition

Contributors will be:
- Listed in the app's About section
- Credited in release notes
- Mentioned in README.md

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

---

**Thank you for helping make ExpenseOwl better! 🙏**
