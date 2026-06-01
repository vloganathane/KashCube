<#
Builds the Windows release and packages it with Inno Setup (ISCC).

Usage:
  # Basic (will run flutter build windows --release)
  .\scripts\build_windows_installer.ps1

  # Provide explicit version for the installer (passed to Inno Setup preprocessor)
  .\scripts\build_windows_installer.ps1 -Version 1.2.3

  # Skip Flutter build (useful if CI already produced artifacts)
  .\scripts\build_windows_installer.ps1 -SkipFlutter

Requirements:
- `flutter` on PATH
- `ISCC.exe` (Inno Setup) on PATH
#>

param(
    [string]$Version = "",
    [string]$ISCC = "ISCC.exe",
    [switch]$SkipFlutter,
    [switch]$Sign,
    [string]$SignTool = "signtool.exe",
    [string]$PfxPath = "",
    [string]$PfxPassword = "",
    [string]$TimestampUrl = "http://timestamp.digicert.com"
)

function Abort($msg) {
    Write-Error $msg
    exit 1
}

Write-Host "Build script starting..." -ForegroundColor Cyan

if (-not $SkipFlutter) {
    if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
        Abort "`nFlutter executable not found in PATH. Install Flutter or add it to PATH.`n"
    }

    Write-Host "Running: flutter build windows --release" -ForegroundColor Yellow
    & flutter build windows --release
    if ($LASTEXITCODE -ne 0) { Abort "Flutter build failed (exit code $LASTEXITCODE)." }
}
else {
    Write-Host "Skipping Flutter build as requested." -ForegroundColor Yellow
}

if (-not (Get-Command $ISCC -ErrorAction SilentlyContinue)) {
    Abort "ISCC.exe (Inno Setup compiler) not found in PATH. Install Inno Setup 6 and ensure ISCC.exe is available." 
}

$scriptDir = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
$issPath = Resolve-Path (Join-Path -Path $scriptDir -ChildPath "..\installer\windows.iss") -ErrorAction Stop

$isccArgs = @()
if ($Version) {
    $isccArgs += ('/DMyAppVersion="{0}"' -f $Version)
    Write-Host "Passing installer version: $Version" -ForegroundColor Yellow
}
$isccArgs += $issPath.Path

Write-Host "Running ISCC: $ISCC $($isccArgs -join ' ')" -ForegroundColor Cyan
& $ISCC @isccArgs
if ($LASTEXITCODE -ne 0) { Abort "ISCC failed (exit code $LASTEXITCODE)." }

Write-Host "Installer build complete. Output is in the 'dist' directory." -ForegroundColor Green

# Optional code signing
if ($Sign) {
    Write-Host "Signing requested." -ForegroundColor Cyan

    if (-not $PfxPath) { Abort "Signing requested but -PfxPath was not provided." }
    if (-not (Test-Path $PfxPath)) { Abort "PFX file not found at path: $PfxPath" }

    $signToolCmd = Get-Command $SignTool -ErrorAction SilentlyContinue
    if (-not $signToolCmd) { Abort "SignTool not found: $SignTool. Ensure Windows SDK SignTool is installed and on PATH." }
    $signToolPath = $signToolCmd.Source

    # Find the most-recent installer exe in dist
    $installerFile = Get-ChildItem -Path (Join-Path -Path (Get-Location) -ChildPath 'dist') -Filter 'KashCube-Setup-*.exe' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $installerFile) { Abort "Couldn't find installer exe in 'dist' to sign." }

    Write-Host "Signing $($installerFile.FullName) with $signToolPath" -ForegroundColor Yellow

    $signArgs = @('sign', '/f', $PfxPath, '/p', $PfxPassword, '/fd', 'SHA256', '/tr', $TimestampUrl, '/td', 'SHA256', $installerFile.FullName)
    & $signToolPath @signArgs
    if ($LASTEXITCODE -ne 0) { Abort "SignTool failed (exit code $LASTEXITCODE)." }

    Write-Host "Signing completed successfully." -ForegroundColor Green
}
