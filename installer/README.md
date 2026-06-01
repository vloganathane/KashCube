# Windows Installer (Inno Setup)

Prerequisites
- Install Inno Setup 6 (ISCC) on your Windows build machine.

Build steps
1. Build the Windows release with Flutter: `flutter build windows --release` (outputs to `build\windows\x64\runner\Release`).
2. From the repository root run the Inno Setup compiler:

```powershell
ISCC.exe installer\windows.iss
```

Update-safety notes
- Keep the `AppId` value in `windows.iss` unchanged between releases so Inno Setup treats new installers as upgrades.
- Application binaries are installed to `Program Files`; user data should live under `%LOCALAPPDATA%\\Kash Cube\\data` (the script creates this directory and marks it with `uninsneveruninstall`).
- Do not add `uninsdelete` flags for user-data directories if you want to preserve them on uninstall.

Recommended release steps
- Increment `MyAppVersion` (or pass it via the preprocessor) for each release.
- Verify the installer by installing over an existing installation and confirming user data remains intact.

If you need help automating Inno Setup compilation, I can add a build script or CI job.
