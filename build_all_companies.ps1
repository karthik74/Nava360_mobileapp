# Builds the release app for every company flavor and collects the outputs.
#
#   .\build_all_companies.ps1              # Play Store bundles (.aab)
#   .\build_all_companies.ps1 -Apk         # direct-install APKs instead
#
# Outputs land in dist\<flavor>\ with a versioned file name.
param([switch]$Apk)

$flavors = @("livelihoods", "souhardha", "laxmi")
$kind = if ($Apk) { "apk" } else { "appbundle" }

$version = (Select-String -Path pubspec.yaml -Pattern '^version:\s*(\S+)').Matches[0].Groups[1].Value
Write-Host "Building v$version ($kind) for: $($flavors -join ', ')" -ForegroundColor Cyan

New-Item -ItemType Directory -Force dist | Out-Null
$failed = @()

foreach ($flavor in $flavors) {
    Write-Host "`n=== $flavor ===" -ForegroundColor Yellow
    flutter build $kind --release --flavor $flavor
    if ($LASTEXITCODE -ne 0) {
        Write-Host "$flavor build FAILED" -ForegroundColor Red
        $failed += $flavor
        continue
    }
    New-Item -ItemType Directory -Force "dist\$flavor" | Out-Null
    if ($Apk) {
        Copy-Item "build\app\outputs\flutter-apk\app-$flavor-release.apk" `
            "dist\$flavor\$flavor-v$version.apk" -Force
    } else {
        Copy-Item "build\app\outputs\bundle\${flavor}Release\app-$flavor-release.aab" `
            "dist\$flavor\$flavor-v$version.aab" -Force
    }
    Write-Host "$flavor OK -> dist\$flavor\" -ForegroundColor Green
}

Write-Host ""
if ($failed.Count -gt 0) {
    Write-Host "FAILED: $($failed -join ', ')" -ForegroundColor Red
    exit 1
}
Write-Host "All $($flavors.Count) builds complete. Outputs in dist\" -ForegroundColor Green
Get-ChildItem dist -Recurse -File | Select-Object FullName, Length
