# GitHub Pages Setup for Privacy Policy

## 🎯 Quick Setup (5 minutes)

### Option 1: Enable GitHub Pages (Recommended)

1. **Commit the docs folder**
   ```bash
   git add docs/
   git commit -m "Add privacy policy and terms for Play Store"
   git push origin main
   ```

2. **Enable GitHub Pages**
   - Go to your GitHub repo: `https://github.com/YOUR_USERNAME/KashCube`
   - Click **Settings** (top right)
   - Scroll down to **Pages** (left sidebar)
   - Under **Source**, select:
     - Branch: `main`
     - Folder: `/docs`
   - Click **Save**

3. **Wait 1-2 minutes** for GitHub to build
   - Your privacy policy will be live at:
     ```
     https://YOUR_USERNAME.github.io/KashCube/privacy.html
     ```

4. **Test the URL** in your browser

5. **Add to Play Console**
   - Copy the full URL: `https://YOUR_USERNAME.github.io/KashCube/privacy.html`
   - Paste in Play Console → Store settings → Privacy Policy URL

---

### Option 2: Custom Domain (Optional)

If you have `kashcube.com`:

1. Follow Option 1 first
2. In GitHub Pages settings, add custom domain: `kashcube.com`
3. Update DNS records (CNAME pointing to `YOUR_USERNAME.github.io`)
4. Your privacy policy will be at: `https://kashcube.com/privacy.html`

---

## 📂 Files Created

```
docs/
├── index.html       # Landing page
├── privacy.html     ← Privacy Policy (required for Play Store)
└── terms.html       # Terms of Use
```

---

## ✅ Verification Checklist

- [ ] Commit & push `docs/` folder to GitHub
- [ ] Enable GitHub Pages in repo settings
- [ ] Wait 1-2 minutes for deployment
- [ ] Open `https://YOUR_USERNAME.github.io/KashCube/privacy.html`
- [ ] Verify content displays correctly
- [ ] Copy URL and test in incognito window
- [ ] Add URL to Play Console

---

## 🔗 URLs You'll Use

| Document | GitHub Pages URL |
|----------|------------------|
| **Privacy Policy** | `https://YOUR_USERNAME.github.io/KashCube/privacy.html` |
| Terms of Use | `https://YOUR_USERNAME.github.io/KashCube/terms.html` |
| Landing Page | `https://YOUR_USERNAME.github.io/KashCube/` |

**Replace `YOUR_USERNAME`** with your actual GitHub username.

---

## 🎨 Customization (Optional)

The HTML files are standalone and ready to use. To customize:

1. **Change colors**: Edit the `<style>` section in each HTML file
2. **Update contact info**: Replace "GitHub repository" with your actual repo link
3. **Add logo**: Add `<img>` tag in the header section

---

## 🚨 Troubleshooting

**Q: GitHub Pages not working?**
- Check Settings → Pages shows "Your site is live at..."
- Ensure branch is `main` and folder is `/docs`
- Wait 2-3 minutes after enabling
- Try hard refresh (Ctrl+Shift+R or Cmd+Shift+R)

**Q: 404 error?**
- Ensure files are in `/docs` folder, not `/docs/docs`
- Check file names are exactly: `privacy.html`, `terms.html`, `index.html`
- Verify files are pushed to GitHub (check repo on github.com)

**Q: Need to update content?**
- Edit the HTML files in `/docs`
- Commit and push
- GitHub Pages updates automatically in 1-2 minutes

---

## 📱 Play Store Data Safety Form

When filling out the Play Store Data Safety form, use this guidance:

**Data Collection:**
- [x] Analytics (optional, off by default)
  - Type: App interactions
  - Purpose: Analytics
  - Collected: Only if user opts in
  - Shared: No

- [ ] Financial info: NO
- [ ] Location: NO
- [ ] Personal info: NO
- [ ] Device ID: Only for LAN sync (not shared externally)

**Privacy Policy URL:**
```
https://YOUR_USERNAME.github.io/KashCube/privacy.html
```

---

## ✅ Done!

Once GitHub Pages is live, you can:
1. ✅ Add the privacy policy URL to Play Console
2. ✅ Submit your app for review
3. ✅ Update the privacy policy anytime by editing HTML and pushing to GitHub

**No server maintenance, no hosting costs — GitHub Pages is free forever.**
