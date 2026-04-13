# Screenshot Capture Guide — Kash Cube Play Store

**Emulator:** playart_arm64  
**Target Resolution:** 1080x1920 or higher  
**Format:** PNG (24-bit, no alpha)  
**Count:** 2-8 screenshots required

---

## 📱 Play Store Screenshot Requirements

- **Min dimension:** 320px
- **Max dimension:** 3840px  
- **Aspect ratio:** Max dimension ≤ 2x min dimension
- **Format:** JPEG or 24-bit PNG (no alpha channel)
- **Recommended sizes:** 
  - Phone: 1080x1920 (portrait) or 1920x1080 (landscape)
  - Tablet: 1600x2560 or 2560x1600

---

## 🎯 Screenshot Checklist (2-8 images)

### Must-Have Screenshots (Priority Order):

1. **Home Dashboard** ⭐ REQUIRED
   - Transaction feed with real-looking data
   - Show income (green) and expense (red)
   - Indian ₹ formatting (₹1,234 NOT $1,234)
   - Date ranges visible
   - FAB (+) button prominent

2. **Reports Screen** ⭐ REQUIRED  
   - Pie chart or bar graph
   - Category breakdown
   - Colorful visualization
   - Date filter shown
   - Indian amounts (₹1,00,000 style)

3. **Add Transaction Form** (Recommended)
   - Clean form UI
   - Category picker expanded
   - Amount field with ₹ symbol
   - Date picker
   - Party autocomplete

4. **SMS Auto-Capture** (Recommended)
   - List of detected transactions
   - Confidence badges (HIGH/MEDIUM)
   - Bank logos/icons
   - UPI references
   - One-tap import UI

5. **Settings → Privacy** (Recommended)
   - Analytics toggle (OFF by default)
   - PIN lock option
   - App lock settings
   - Highlights privacy-first features

6. **Invoice Preview** (Optional)
   - GST invoice example
   - Professional layout
   - Indian business details
   - Party info, items, totals
   - GST breakdown

7. **Credits/Udhar Screen** (Optional)
   - Customer credit list
   - Outstanding amounts
   - Due dates
   - Payment history

8. **Dark Mode** (Optional)
   - Any screen in dark theme
   - Shows theme support

---

## 🚀 Quick Setup Commands

### 1. Wait for Emulator to Boot

```bash
# Check if emulator is ready
adb devices

# Wait for boot complete (run until you see "1")
adb shell getprop sys.boot_completed
```

### 2. Build and Install Release APK

```bash
cd /Users/loganathanev/Documents/vloganathane/daily-apps/2026/02/24/KashCube

# Build release APK
flutter build apk --release

# Install on emulator
adb install -r build/app/outputs/apk/release/app-release.apk
```

### 3. Prepare Sample Data

**Important:** Use realistic-looking data, not test/dummy entries!

**Sample Transactions:**
- ₹5,000 - Salary (Income, 1 Apr)
- -₹450 - Grocery (Expense, 3 Apr)
- -₹1,200 - Electricity Bill (Expense, 5 Apr)
- ₹25,000 - Freelance Project (Income, 7 Apr)
- -₹800 - Fuel (Expense, 10 Apr)
- -₹15,000 - Rent (Expense, 12 Apr)

**Categories to use:**
- Income: Salary, Freelance, Business
- Expense: Grocery, Bills, Fuel, Rent, Food, Shopping

**Party names:**
- Generic: "Swiggy", "Big Bazaar", "Shell Petrol"
- NOT: "Test Party", "ABC", "Demo Vendor"

### 4. Capture Screenshots

```bash
# Create screenshots directory
mkdir -p /Users/loganathanev/Documents/vloganathane/daily-apps/2026/02/24/KashCube/playstore_assets/screenshots

# Capture screenshot (run after navigating to each screen)
adb exec-out screencap -p > /Users/loganathanev/Documents/vloganathane/daily-apps/2026/02/24/KashCube/playstore_assets/screenshots/01_home.png

# OR use shorter path
cd /Users/loganathanev/Documents/vloganathane/daily-apps/2026/02/24/KashCube/playstore_assets/screenshots

adb exec-out screencap -p > 01_home.png
adb exec-out screencap -p > 02_reports.png
adb exec-out screencap -p > 03_add_transaction.png
adb exec-out screencap -p > 04_sms_detect.png
adb exec-out screencap -p > 05_settings_privacy.png
adb exec-out screencap -p > 06_invoice.png
adb exec-out screencap -p > 07_dark_mode.png
```

---

## 📸 Detailed Screenshot Steps

### Screenshot 1: Home Dashboard

1. Open app
2. Ensure 5-10 transactions visible
3. Mix of income (green) and expense (red)
4. Scroll to show date headers
5. Capture: `adb exec-out screencap -p > 01_home.png`

### Screenshot 2: Reports Screen

1. Tap bottom nav → Reports
2. Select "This Month" or custom date range
3. Ensure pie chart is colorful (multiple categories)
4. Show totals (Income: ₹30,000, Expense: ₹17,450)
5. Capture: `adb exec-out screencap -p > 02_reports.png`

### Screenshot 3: Add Transaction

1. Tap FAB (+) button
2. Fill amount: ₹1,234
3. Select category (dropdown open)
4. Type party name
5. Capture: `adb exec-out screencap -p > 03_add_transaction.png`

### Screenshot 4: SMS Auto-Capture (if you have SMS permission)

1. Go to Settings → SMS Auto-Capture
2. Show detected transactions list
3. Highlight confidence scores
4. Show "Import" buttons
5. Capture: `adb exec-out screencap -p > 04_sms_detect.png`

**Alternative:** Show Settings → Features → "Auto-capture UPI/Bank SMS"

### Screenshot 5: Settings → Privacy

1. Navigate to Settings
2. Scroll to Privacy section
3. Show "Anonymous Analytics" toggle (OFF)
4. Show PIN Lock option
5. Show App Lock timeout
6. Capture: `adb exec-out screencap -p > 05_settings_privacy.png`

### Screenshot 6: Invoice (Optional)

1. Create sample invoice
2. Show preview screen
3. Indian GST format
4. Professional layout
5. Capture: `adb exec-out screencap -p > 06_invoice.png`

### Screenshot 7: Dark Mode (Optional)

1. Enable dark mode: Settings → Theme → Dark
2. Navigate to Home or Reports
3. Show dark theme UI
4. Capture: `adb exec-out screencap -p > 07_dark_mode.png`

---

## ✅ Post-Capture Validation

### 1. Check Screenshot Sizes

```bash
cd /Users/loganathanev/Documents/vloganathane/daily-apps/2026/02/24/KashCube/playstore_assets/screenshots

# Check dimensions of all screenshots
file *.png
sips -g pixelWidth -g pixelHeight *.png
```

**Expected:** 1080x1920 or similar portrait resolution

### 2. Remove Status Bar (Optional)

Play Store screenshots look cleaner without status bar. You can crop:

```bash
# Crop 60px from top (status bar) using ImageMagick/sips
sips -c 1860 1080 --cropOffset 60 0 01_home.png
```

### 3. Convert to 24-bit PNG (if needed)

```bash
# Remove alpha channel if present
sips -s format png --setProperty formatOptions 24 01_home.png
```

### 4. Visual Inspection

- ✅ No test/dummy data visible
- ✅ Indian ₹ formatting (₹1,00,000 NOT ₹100,000)
- ✅ No personal information (if using real data)
- ✅ No debug overlays
- ✅ Clean UI (no half-loaded states)
- ✅ Proper colors (income green, expense red)
- ✅ Dark mode shows correctly (if captured)

---

## 🎨 Optional: Add Device Frames

Make screenshots more attractive by adding device frames:

**Tools:**
- https://mockuphone.com/ (free, web-based)
- https://shotsnapp.com/ (free, with backgrounds)
- Figma (manual framing)

**Steps:**
1. Upload PNG screenshots
2. Select device (Pixel 6, Samsung Galaxy S22)
3. Download framed versions
4. Upload to Play Console

---

## 📊 Play Store Upload

After capturing all screenshots:

1. **Navigate to Play Console:**
   - Store presence → Main store listing → Graphics

2. **Upload Phone Screenshots:**
   - Drag and drop PNG files (2-8 images)
   - Order: 01 → 02 → 03 → ...
   - Most important first (Home, Reports)

3. **Add Captions (Optional):**
   - "Track income & expenses with Indian ₹ formatting"
   - "Visual reports and category breakdowns"
   - "Privacy-first: Your data never leaves your device"

4. **Preview:**
   - Check how they appear in Play Store listing
   - Rearrange if needed

---

## 🚨 Common Issues

### Screenshot too large
```bash
# Resize to 1080x1920 (if emulator captured at higher res)
sips -Z 1920 01_home.png
```

### Wrong orientation
```bash
# Rotate 90 degrees
sips -r 90 01_home.png
```

### File size too big
```bash
# Optimize PNG (reduce file size)
pngquant --quality=80-90 01_home.png
```

---

## ⏱️ Time Estimate

- Emulator setup: 2 minutes
- Sample data entry: 10 minutes
- Screenshot capture: 15 minutes
- Post-processing: 10 minutes
- **Total:** ~30-40 minutes

---

**Next:** After screenshots, prepare:
- Feature graphic (1024x500)
- App icon (512x512)
- Store description

