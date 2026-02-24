# UI/UX Design Guidelines
# ExpenseOwl Design System

**Version:** 1.0  
**Date:** February 24, 2026  
**Status:** Design Phase  
**Framework:** Flutter + Material Design 3

---

## 1. Design Principles

### 1.1 Core Principles

| # | Principle | Description |
|---|-----------|-------------|
| 1 | **Privacy First** | UI must never feel surveillance-like. No cloud icons, no sync spinners. Reinforce "your data, your device" at every opportunity |
| 2 | **Instant Clarity** | Financial data must be scannable in < 2 seconds. Use color, size, and hierarchy to communicate status |
| 3 | **Minimal Friction** | Common actions (add expense, check balance) should take ≤ 2 taps |
| 4 | **Indian Context** | ₹ symbol, lakh/crore formatting, UPI-native terminology and patterns |
| 5 | **Forgiving Design** | Undo actions, confirmation dialogs for destructive operations, and auto-save for forms |

### 1.2 Design Personality

- **Tone:** Calm, trustworthy, efficient
- **Feel:** Like a personal finance diary, not a corporate banking app
- **Mascot:** Owl (🦉) — wise, watchful, nocturnal (tracks while you sleep)
- **Visual style:** Clean, minimal, data-dense where needed but never cluttered

---

## 2. Color System

### 2.1 Light Theme (Default)

#### Primary Palette

| Token | Hex | Usage |
|-------|-----|-------|
| `primary` | `#1B5E20` | AppBar, FAB, primary buttons (deep green) |
| `onPrimary` | `#FFFFFF` | Text/icons on primary surfaces |
| `primaryContainer` | `#C8E6C9` | Chips, tags, selected states |
| `onPrimaryContainer` | `#0D3311` | Text on primary container |

#### Semantic Colors

| Token | Hex | Usage |
|-------|-----|-------|
| `income` | `#2E7D32` | Income amounts, positive trends |
| `incomeBackground` | `#E8F5E9` | Income cards background |
| `expense` | `#C62828` | Expense amounts, negative trends |
| `expenseBackground` | `#FFEBEE` | Expense cards background |
| `credit` | `#E65100` | Credit/udhar amounts |
| `creditBackground` | `#FFF3E0` | Credit cards background |
| `overdue` | `#B71C1C` | Overdue credit badges |

#### Surface Colors

| Token | Hex | Usage |
|-------|-----|-------|
| `surface` | `#FAFAFA` | Screen backgrounds |
| `surfaceVariant` | `#F5F5F5` | Card backgrounds |
| `onSurface` | `#1C1B1F` | Primary text |
| `onSurfaceVariant` | `#49454F` | Secondary text |
| `outline` | `#79747E` | Borders, dividers |
| `outlineVariant` | `#CAC4D0` | Subtle dividers |

#### Chart Colors

| Index | Hex | Category Example |
|-------|-----|------------------|
| 0 | `#FF6384` | Food & Dining |
| 1 | `#36A2EB` | Transport |
| 2 | `#FFCE56` | Shopping |
| 3 | `#4BC0C0` | Bills & Utilities |
| 4 | `#9966FF` | Entertainment |
| 5 | `#FF9F40` | Health |
| 6 | `#C9CBCF` | Education |
| 7 | `#7BC67E` | Business |

### 2.2 Dark Theme

| Token | Hex | Usage |
|-------|-----|-------|
| `primary` | `#81C784` | Primary brand color (lighter green) |
| `onPrimary` | `#003909` | Text on primary |
| `surface` | `#1C1B1F` | Screen backgrounds |
| `surfaceVariant` | `#2C2C2C` | Card backgrounds |
| `onSurface` | `#E6E1E5` | Primary text |
| `income` | `#66BB6A` | Income (brighter for dark bg) |
| `expense` | `#EF5350` | Expense (brighter for dark bg) |
| `credit` | `#FFA726` | Credit (brighter for dark bg) |

### 2.3 Color Usage Rules

```dart
// ✅ DO: Use semantic colors for financial data
Text('₹5,000', style: TextStyle(color: theme.income))
Text('-₹450', style: TextStyle(color: theme.expense))

// ❌ DON'T: Hardcode colors
Text('₹5,000', style: TextStyle(color: Colors.green))

// ✅ DO: Use theme tokens
Container(color: theme.surfaceVariant)

// ❌ DON'T: Use arbitrary hex values
Container(color: Color(0xFFE0E0E0))
```

---

## 3. Typography

### 3.1 Font Stack

| Priority | Font | Usage |
|----------|------|-------|
| Primary | **Roboto** | Default Material 3 font (body text, labels) |
| Monospace | **Roboto Mono** | Amount displays, reference numbers |
| Fallback | System default | System font fallback chain |

### 3.2 Type Scale

| Style | Size | Weight | Line Height | Usage |
|-------|------|--------|-------------|-------|
| `displayLarge` | 57sp | 400 | 64sp | — (reserved) |
| `displayMedium` | 45sp | 400 | 52sp | — (reserved) |
| `displaySmall` | 36sp | 400 | 44sp | Large amount display (detail screen) |
| `headlineLarge` | 32sp | 400 | 40sp | — (reserved) |
| `headlineMedium` | 28sp | 400 | 36sp | Screen titles |
| `headlineSmall` | 24sp | 400 | 32sp | Section headers |
| `titleLarge` | 22sp | 500 | 28sp | Card titles |
| `titleMedium` | 16sp | 500 | 24sp | List item primary text |
| `titleSmall` | 14sp | 500 | 20sp | Chip labels |
| `bodyLarge` | 16sp | 400 | 24sp | Main body text |
| `bodyMedium` | 14sp | 400 | 20sp | Secondary body text |
| `bodySmall` | 12sp | 400 | 16sp | Captions, timestamps |
| `labelLarge` | 14sp | 500 | 20sp | Button text |
| `labelMedium` | 12sp | 500 | 16sp | Navigation labels |
| `labelSmall` | 11sp | 500 | 16sp | Badges, micro labels |

### 3.3 Amount Formatting

```dart
// ₹ symbol always prefix, no space
"₹1,234"      // Amounts < 1 lakh
"₹1.5L"       // Shorthand in cards (1.5 lakh)
"₹1,50,000"   // Full format in detail views (Indian comma style)
"-₹450"       // Expense (with minus prefix)
"+₹25,000"    // Income (with plus prefix)

// Font for amounts: Roboto Mono, medium weight
// Income amounts: income color + no sign OR + prefix
// Expense amounts: expense color + - prefix
```

### 3.4 Typography Rules

- **Never** use more than 3 text sizes on a single screen
- **Always** use theme text styles, never inline `TextStyle` with custom sizes
- Amount text should be **monospace** for alignment in lists
- Use `fontFeatures: [FontFeature.tabularFigures()]` for number alignment

---

## 4. Spacing & Layout

### 4.1 Spacing Scale

| Token | Value | Usage |
|-------|-------|-------|
| `xs` | 4dp | Icon-to-text gap, tight padding |
| `sm` | 8dp | Compact spacing within components |
| `md` | 12dp | Standard internal padding |
| `base` | 16dp | Screen horizontal padding, card padding |
| `lg` | 20dp | Section spacing |
| `xl` | 24dp | Major section gaps |
| `xxl` | 32dp | Screen top/bottom padding |
| `xxxl` | 48dp | Large visual breaks |

### 4.2 Screen Layout Template

```
┌─────────────────────────────────────┐
│ AppBar (56dp)                       │
├─────────────────────────────────────┤
│ ← 16dp padding →                    │
│                                     │
│ ┌─────────────────────────────────┐ │
│ │ Summary Cards (120dp height)    │ │
│ └─────────────────────────────────┘ │
│                                     │
│ ← 24dp gap →                        │
│                                     │
│ Section Header                      │
│ ← 8dp gap →                         │
│ ┌─────────────────────────────────┐ │
│ │ Content List                    │ │
│ │ Item 1 (72dp min height)       │ │
│ │ ─────────────────────          │ │
│ │ Item 2                         │ │
│ │ ─────────────────────          │ │
│ │ Item 3                         │ │
│ └─────────────────────────────────┘ │
│                                     │
│                          [FAB 56dp] │
├─────────────────────────────────────┤
│ Bottom Nav (80dp)                   │
└─────────────────────────────────────┘
```

### 4.3 Card Elevation

| Surface | Elevation | Usage |
|---------|-----------|-------|
| Background | 0 | Screen background |
| Cards | 1 | Transaction cards, summary cards |
| FAB | 3 | Floating action button |
| AppBar | 0 (scroll: 2) | Top app bar (elevate on scroll) |
| Bottom Nav | 2 | Bottom navigation |
| Dialog | 3 | Confirmation dialogs |
| Bottom Sheet | 4 | Modal bottom sheets |

### 4.4 Grid System

- **Screen padding:** 16dp horizontal
- **Card grid:** 1 column (phone), 2 columns (tablet landscape)
- **Summary cards:** Horizontal scroll or 3-column grid
- **Category grid:** 4 columns (small icons), 2 columns (large icons)
- **Minimum tap target:** 48dp × 48dp (accessibility)

---

## 5. Component Library

### 5.1 Transaction List Item

```
┌──────────────────────────────────────────┐
│ 🍽️  Swiggy                    -₹450.00  │
│     Food & Dining • UPI         6:30 PM  │
└──────────────────────────────────────────┘

Height: 72dp minimum
Left: Category icon (40dp circle, colored)
Center: Merchant name (titleMedium) + Category + Method (bodySmall)
Right: Amount (titleMedium, monospace) + Time (bodySmall)
Divider: outlineVariant, inset 56dp from left
```

```dart
ListTile(
  leading: CircleAvatar(
    backgroundColor: category.color.withOpacity(0.1),
    child: Icon(category.icon, color: category.color),
  ),
  title: Text(transaction.merchant, style: titleMedium),
  subtitle: Text(
    '${transaction.category} • ${transaction.method}',
    style: bodySmall.copyWith(color: onSurfaceVariant),
  ),
  trailing: Column(
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Text(
        transaction.formattedAmount,
        style: titleMedium.copyWith(
          color: transaction.isExpense ? expense : income,
          fontFamily: 'RobotoMono',
        ),
      ),
      Text(transaction.formattedTime, style: bodySmall),
    ],
  ),
);
```

### 5.2 Summary Card

```
┌─────────────────────┐
│  Income        🟢   │
│  ₹75,000            │
│  ▲ 12% vs last      │
└─────────────────────┘

Height: 100-120dp
Width: Flexible (1/3 of screen or scroll)
Background: income/expense/neutral container color
Border radius: 16dp
Padding: 16dp all sides
```

### 5.3 Credit Customer Tile

```
┌──────────────────────────────────────────┐
│ RK  Ramesh Kumar                ₹5,000  │
│     Phone: 9876543210           OVERDUE  │
│     Due: Mar 10, 2026           🔴      │
└──────────────────────────────────────────┘

Left: Avatar initials (40dp circle)
Center: Name (titleMedium) + Details (bodySmall)
Right: Amount (income color) + Status badge
Overdue badge: error/overdue color, labelSmall
```

### 5.4 Category Chip

```
[ 🍽️ Food ]  [ 🚗 Transport ]  [ 🛍️ Shopping ]

Height: 36dp
Padding: 8dp horizontal, 4dp vertical
Border radius: 8dp
Unselected: outline border, transparent background
Selected: primaryContainer background, onPrimaryContainer text
```

### 5.5 Filter Chip Row

```
[ Today ] [ This Week ] [ This Month ] [ Custom ]

Scrollable horizontal
Spacing: 8dp between chips
Single select behavior
Active chip: filled style
Inactive chip: outlined style
```

### 5.6 Date Section Header

```
─── Today, Feb 24, 2026 ────────────

Style: bodySmall, onSurfaceVariant color
Padding: 16dp vertical, 16dp horizontal
Sticky (pins to top while scrolling)
```

### 5.7 FAB (Floating Action Button)

```
    ┌─────┐
    │  +  │
    └─────┘

Size: 56dp (standard)
Color: primary
Icon: add (24dp)
Position: Bottom-right, 16dp margin
Show: Home and Transactions tabs only
Animation: Scale in/out on tab change
```

### 5.8 Buttons

| Type | Usage | Style |
|------|-------|-------|
| Filled | Primary actions (Save, Confirm) | `FilledButton` primary color |
| Outlined | Secondary actions (Cancel, Export) | `OutlinedButton` outline color |
| Text | Tertiary actions (Skip, Learn More) | `TextButton` primary color |
| Icon | Toolbar actions (Search, Settings) | `IconButton` 48dp tap target |
| FAB | Add new item | `FloatingActionButton` primary |

---

## 6. Iconography

### 6.1 Icon Set

**Source:** Material Icons (built into Flutter)  
**Size:** 24dp default, 20dp in compact spaces  
**Style:** Outlined (default), Filled (selected/active state)

### 6.2 Category Icons

| Category | Icon | Color |
|----------|------|-------|
| Food & Dining | `restaurant` | `#FF6384` |
| Transport | `directions_car` | `#36A2EB` |
| Shopping | `shopping_bag` | `#FFCE56` |
| Bills & Utilities | `receipt_long` | `#4BC0C0` |
| Entertainment | `movie` | `#9966FF` |
| Health | `local_hospital` | `#FF9F40` |
| Education | `school` | `#C9CBCF` |
| Business | `business_center` | `#7BC67E` |
| Salary / Income | `account_balance_wallet` | `#2E7D32` |
| Rent | `home` | `#8D6E63` |
| Other | `more_horiz` | `#9E9E9E` |

### 6.3 Navigation Icons

| Tab | Inactive | Active |
|-----|----------|--------|
| Home | `home_outlined` | `home` |
| Transactions | `receipt_long_outlined` | `receipt_long` |
| Credits | `account_balance_wallet_outlined` | `account_balance_wallet` |
| Reports | `bar_chart_outlined` | `bar_chart` |

### 6.4 Action Icons

| Action | Icon |
|--------|------|
| Search | `search` |
| Settings | `settings` |
| Add | `add` |
| Edit | `edit` |
| Delete | `delete` |
| Back | `arrow_back` |
| Filter | `filter_list` |
| Sort | `sort` |
| Backup | `backup` |
| Restore | `restore` |
| Export | `file_download` |
| Share | `share` |
| Calendar | `calendar_today` |
| Lock | `lock` |
| Fingerprint | `fingerprint` |

---

## 7. Motion & Animation

### 7.1 Transition Durations

| Type | Duration | Curve |
|------|----------|-------|
| Page transition | 300ms | `Curves.easeInOut` |
| Tab switch | 200ms | `Curves.easeIn` |
| Card appear | 200ms | `Curves.easeOut` |
| FAB scale | 150ms | `Curves.easeInOut` |
| Snackbar slide | 250ms | `Curves.decelerate` |
| Dialog appear | 200ms | `Curves.easeOut` |
| List item stagger | 50ms per item | `Curves.easeOut` |
| Chart draw | 600ms | `Curves.easeInOutCubic` |

### 7.2 Animation Patterns

**Page Transitions:**
```dart
// Forward navigation: Slide right
MaterialPageRoute(builder: (context) => DetailScreen())

// Modal forms: Slide up
showModalBottomSheet() // or
MaterialPageRoute(fullscreenDialog: true)

// Tab switches: Fade
AnimatedSwitcher(duration: Duration(milliseconds: 200))
```

**List Animations:**
```dart
// Items appear with stagger effect on first load
// 50ms delay per item, max 10 items animated
// Rest appear instantly
AnimatedList with SlideTransition + FadeTransition
```

**Amount Counter:**
```dart
// When summary amounts change, animate the number
// Use TweenAnimationBuilder for smooth counting effect
TweenAnimationBuilder<double>(
  tween: Tween(begin: oldAmount, end: newAmount),
  duration: Duration(milliseconds: 400),
  builder: (context, value, child) => Text(formatCurrency(value)),
)
```

### 7.3 Animation Rules

- **Do** animate: Page transitions, list items, charts, FAB, snackbars
- **Don't** animate: Text changes, color changes (unless meaningful), trivial state changes
- **Reduce motion:** Respect `MediaQuery.of(context).disableAnimations` — use instant transitions
- **Performance:** Keep animations at 60fps; use `RepaintBoundary` for complex animations

---

## 8. Responsive Design

### 8.1 Breakpoints

| Device | Width | Layout |
|--------|-------|--------|
| Small phone | < 360dp | Compact (smaller text, tighter spacing) |
| Standard phone | 360-412dp | Default layout |
| Large phone | 412-600dp | Default with more breathing room |
| Tablet portrait | 600-840dp | 2-column layout |
| Tablet landscape | > 840dp | Navigation rail + 2-column |

### 8.2 Phone Layout (Primary)

```
┌──────────┐
│  AppBar   │
│           │
│  Content  │
│  (full    │
│   width)  │
│           │
│     [FAB] │
│           │
│  BottomNav│
└──────────┘
```

### 8.3 Tablet Layout (Future)

```
┌────┬───────────────────────┐
│Nav │                       │
│Rail│   Primary Content     │
│    │                       │
│🏠 │   ┌────────┬────────┐ │
│📋 │   │ List   │ Detail │ │
│💰 │   │        │        │ │
│📊 │   │        │        │ │
│    │   └────────┴────────┘ │
│    │                       │
│⚙️  │                       │
└────┴───────────────────────┘
```

### 8.4 Responsive Text

```dart
// Scale amounts based on screen width
double amountFontSize(BuildContext context) {
  final width = MediaQuery.of(context).size.width;
  if (width < 360) return 20; // Compact
  if (width < 412) return 24; // Standard
  return 28; // Large
}
```

---

## 9. Accessibility

### 9.1 WCAG 2.1 AA Compliance

| Requirement | Implementation |
|-------------|----------------|
| Color contrast | Minimum 4.5:1 for text, 3:1 for large text |
| Touch targets | Minimum 48dp × 48dp |
| Text scaling | Support up to 200% system text size |
| Screen readers | All elements have semantic labels |
| Motion | Respect reduced motion settings |
| Focus indicators | Visible focus ring on interactive elements |

### 9.2 Semantic Labels

```dart
// ✅ DO: Provide meaningful semantics
Semantics(
  label: 'Income amount: Rupees 75,000',
  child: Text('₹75,000'),
)

// ✅ DO: Label icons
IconButton(
  icon: Icon(Icons.delete),
  tooltip: 'Delete transaction',
  onPressed: () {},
)

// ✅ DO: Announce state changes
Semantics(
  label: 'Credit status: Overdue by 5 days',
  child: Badge(text: 'OVERDUE'),
)

// ❌ DON'T: Leave decorative elements unlabeled
// Use Semantics(excludeSemantics: true) for purely decorative items
```

### 9.3 Color Accessibility

- Never use color alone to convey information
- Pair colors with icons, text labels, or patterns
- Income: Green + upward arrow (▲) + text "Income"
- Expense: Red + downward arrow (▼) + text "Expense"
- Overdue: Red badge + clock icon + text "OVERDUE"

### 9.4 Text Scaling

```dart
// Support dynamic type by using theme text styles
// Never set fixed pixel sizes

// ✅ DO:
Text('Amount', style: Theme.of(context).textTheme.titleMedium)

// ❌ DON'T:
Text('Amount', style: TextStyle(fontSize: 16))

// Handle overflow for scaled text
Text(
  merchant,
  overflow: TextOverflow.ellipsis,
  maxLines: 1,
)
```

---

## 10. Dark Mode

### 10.1 Design Principles for Dark Mode

1. **Surface hierarchy** over elevation shadows (shadows don't work on dark)
2. **Desaturate colors** slightly for comfort on dark backgrounds
3. **Light text on dark** — avoid pure white (#FFFFFF); use #E6E1E5
4. **Avoid pure black** (#000000) for backgrounds; use #1C1B1F

### 10.2 Component Adjustments

| Component | Light | Dark |
|-----------|-------|------|
| Cards | White + shadow | Dark surface + subtle border |
| Charts | Vibrant colors | Slightly muted, higher opacity |
| Icons | Dark tint | Light tint |
| Dividers | Light gray | Subtle dark gray |
| Status badges | Filled | Filled with reduced opacity bg |

### 10.3 Implementation

```dart
// ThemeData setup
MaterialApp(
  theme: ExpenseOwlTheme.light(),
  darkTheme: ExpenseOwlTheme.dark(),
  themeMode: ThemeMode.system, // Follow system preference
)

// Manual toggle in Settings
// Store preference in settings database table
// Key: 'theme_mode', Values: 'system', 'light', 'dark'
```

---

## 11. Indian Locale Specifics

### 11.1 Number Formatting

```dart
// Indian numbering system
// 1,00,000 (not 100,000)
// 10,00,000 (not 1,000,000)

String formatIndianCurrency(double amount) {
  final formatter = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );
  return formatter.format(amount);
}

// Examples:
// 1,234
// 12,345
// 1,23,456
// 12,34,567
```

### 11.2 Shorthand Amounts

| Full Amount | Shorthand | Context |
|-------------|-----------|---------|
| ₹1,00,000 | ₹1L | Summary cards |
| ₹10,00,000 | ₹10L | Summary cards |
| ₹1,00,00,000 | ₹1Cr | Summary cards |
| ₹50,000 | ₹50K | Summary cards |
| ₹1,234 | ₹1,234 | No shorthand |

### 11.3 Date & Time

```dart
// Date format: Day Month Year
// "24 Feb 2026" (primary)
// "24/02/2026" (compact)
// "Today", "Yesterday" (relative for recent)

// Time format: 12-hour with AM/PM
// "6:30 PM"
// "11:45 AM"
```

### 11.4 Language / Copy Conventions

- Use "Credit" not "Loan" for udhar
- Use "Party" not "Vendor" for transaction counterparty
- Use "UPI" prominently (most Indian users understand)
- Payment methods: Cash, UPI, Card, Net Banking, Wallet
- Avoid jargon: "savings" not "fund allocation"

---

## 12. Form Design

### 12.1 Input Fields

```
┌─────────────────────────────────────┐
│ ₹ Amount                            │
│ ┌─────────────────────────────────┐ │
│ │ 450                             │ │
│ └─────────────────────────────────┘ │
│                                     │
│ Category                            │
│ ┌─────────────────────────────────┐ │
│ │ Food & Dining              ▼   │ │
│ └─────────────────────────────────┘ │
│                                     │
│ Notes (optional)                    │
│ ┌─────────────────────────────────┐ │
│ │ Dinner with friends            │ │
│ └─────────────────────────────────┘ │
└─────────────────────────────────────┘

Field height: 56dp
Label: Above field, bodySmall
Hint text: Inside field, bodyLarge, onSurfaceVariant
Error text: Below field, bodySmall, error color
Border: OutlineInputBorder, 8dp radius
Focus border: primary color, 2dp width
```

### 12.2 Validation Patterns

| Field | Validation | Error Message |
|-------|-----------|---------------|
| Amount | Required, > 0 | "Please enter an amount" |
| Category | Required | "Please select a category" |
| Date | Required, not future | "Date cannot be in the future" |
| Customer Name | Required for credits | "Please enter a name" |
| PIN | Exactly 4 digits | "PIN must be 4 digits" |
| PIN Confirm | Must match | "PINs don't match" |

### 12.3 Form Behavior

- **Auto-focus** on first empty required field
- **Keyboard type** matches field (number pad for amounts)
- **Save button** disabled until required fields valid
- **Unsaved changes** → Show discard confirmation on back
- **Amount field** → Large, prominent, auto-selected on focus

---

## 13. Notification Design

### 13.1 In-App Notifications

```
┌──────────────────────────────────────────┐
│  ✓ Transaction saved                     │  ← Snackbar (non-blocking)
│                              [UNDO]      │
└──────────────────────────────────────────┘

Duration: 4 seconds (with undo), 2 seconds (without)
Position: Bottom, above bottom nav
Max width: min(screen_width - 32, 400)
```

### 13.2 System Notifications (SMS Auto-Capture)

```
┌──────────────────────────┐
│ 🦉 ExpenseOwl            │
│ ₹450 spent at Swiggy     │
│ Category: Food & Dining   │
│ [View]  [Edit Category]  │
└──────────────────────────┘

Priority: Low (no sound/vibration)
Channel: "Transaction Alerts"
Tap: Opens Transaction Detail
```

---

## 14. Implementation Notes

### 14.1 Theme File Structure

```
lib/
├── core/
│   └── theme/
│       ├── app_theme.dart          // ThemeData definitions
│       ├── color_tokens.dart       // Color constants
│       ├── text_styles.dart        // Custom text style extensions
│       └── spacing.dart            // Spacing constants
```

### 14.2 Theme Extension Pattern

```dart
// Custom semantic colors via ThemeExtension
class ExpenseOwlColors extends ThemeExtension<ExpenseOwlColors> {
  final Color income;
  final Color expense;
  final Color credit;
  final Color overdue;
  final Color incomeBackground;
  final Color expenseBackground;
  final Color creditBackground;

  // ... constructors, copyWith, lerp
}

// Usage:
final colors = Theme.of(context).extension<ExpenseOwlColors>()!;
Text('₹5,000', style: TextStyle(color: colors.income));
```

### 14.3 Spacing Constants

```dart
class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double base = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
}
```

### 14.4 Platform Conventions

| Platform | Guideline |
|----------|-----------|
| Android | Material 3, system back gesture, edge-to-edge display |
| iOS (Future) | Cupertino-style navigation transitions, but Material components |
| Both | Respect safe areas (notch, bottom bar), system font scaling |

---

## 15. Design Checklist

Before implementing any screen, verify:

- [ ] Uses `Theme.of(context)` for all colors and text styles
- [ ] All touch targets are ≥ 48dp
- [ ] Income/Expense colors used correctly (green/red)
- [ ] Amounts formatted in Indian currency style
- [ ] Empty state designed and implemented
- [ ] Error state designed and implemented
- [ ] Loading state handled (shimmer or progress indicator)
- [ ] Dark mode tested
- [ ] Screen reader labels on all interactive elements
- [ ] Text scales properly (test at 200%)
- [ ] Back navigation works correctly
- [ ] Keyboard dismissal handled
- [ ] Form validation messages shown
- [ ] Destructive actions have confirmation dialogs

---

**References:**
- [Material Design 3 Guidelines](https://m3.material.io/)
- [Flutter Widget Catalog](https://docs.flutter.dev/ui/widgets)
- [Technical Architecture](./TECHNICAL_ARCHITECTURE.md)
- [Screen Flows](./SCREEN_FLOWS.md)
- [MVP Scope](./MVP_SCOPE.md)
