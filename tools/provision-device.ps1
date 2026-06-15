# Provisions a company device for Nava360 by installing the release APK with all
# runtime permissions GRANTED at install time — including the hard-restricted
# SMS permissions. Installing via adb uses the trusted "shell" installer, which
# is allowed to grant restricted permissions, so this bypasses the Android
# "restricted settings / denied access" wall and Play Protect does not block it.
#
# Use this at device handover (USB debugging must be ON on the phone).
#
# Usage:
#   .\tools\provision-device.ps1
#   .\tools\provision-device.ps1 -Apk "build\app\outputs\flutter-apk\app-release.apk"

param(
    [string]$Apk = "build\app\outputs\flutter-apk\app-release.apk",
    [string]$Package = "com.hrms.nava_360"
)

$ErrorActionPreference = "Stop"

function Require-Adb {
    $adb = (Get-Command adb -ErrorAction SilentlyContinue)
    if ($null -eq $adb) {
        throw "adb not found on PATH. Install Android platform-tools and retry."
    }
}

Require-Adb

if (-not (Test-Path $Apk)) {
    throw "APK not found: $Apk`nBuild it first:  flutter build apk --release"
}

Write-Host "== Connected devices ==" -ForegroundColor Cyan
adb devices

# -r reinstall keeping data, -g grant ALL runtime permissions (incl. restricted),
# -t allow test builds. The shell installer may grant SMS directly here.
Write-Host "`n== Installing $Apk ==" -ForegroundColor Cyan
adb install -r -g -t $Apk

# Belt-and-suspenders: explicitly grant the SMS permissions in case the device's
# Android version didn't grant them via -g. Wrapped so a failure isn't fatal.
$perms = @(
    "android.permission.READ_SMS",
    "android.permission.RECEIVE_SMS"
)
Write-Host "`n== Granting SMS permissions ==" -ForegroundColor Cyan
foreach ($p in $perms) {
    try {
        adb shell pm grant $Package $p
        Write-Host "  granted $p" -ForegroundColor Green
    } catch {
        Write-Host "  could not grant $p ($_)" -ForegroundColor Yellow
    }
}

# Some OEM builds also gate SMS via appops; force-allow as well.
try { adb shell appops set $Package READ_SMS allow } catch {}

Write-Host "`n== Current SMS permission state ==" -ForegroundColor Cyan
adb shell dumpsys package $Package | Select-String "READ_SMS|RECEIVE_SMS"

Write-Host "`nDone. If the phone still shows a Play Protect prompt on first launch," -ForegroundColor Cyan
Write-Host "tap 'More details' > 'Install anyway' (one-time, per device)." -ForegroundColor Cyan
