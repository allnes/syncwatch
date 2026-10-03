$ErrorActionPreference = "Stop"

# Always run from repository root, even when launched by Visual Studio from System32.
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  Write-Host ""
  Write-Host "Flutter was not found in PATH." -ForegroundColor Red
  Write-Host "Install Flutter, add flutter\bin to PATH, then run this script again."
  exit 1
}

if (-not (Test-Path "windows\CMakeLists.txt")) {
  Write-Host "Generating Flutter Windows/macOS host files..." -ForegroundColor Cyan

  $backup = Join-Path $env:TEMP "syncwatch-bootstrap"
  if (Test-Path $backup) { Remove-Item $backup -Recurse -Force }
  New-Item -ItemType Directory -Path $backup | Out-Null

  Copy-Item "lib" $backup -Recurse
  Copy-Item "pubspec.yaml" $backup
  Copy-Item "analysis_options.yaml" $backup
  Copy-Item "README.md" $backup

  flutter create --platforms=windows,macos --project-name syncwatch --org dev.syncwatch --no-pub .

  Remove-Item "lib" -Recurse -Force
  Copy-Item (Join-Path $backup "lib") "." -Recurse
  Copy-Item (Join-Path $backup "pubspec.yaml") "." -Force
  Copy-Item (Join-Path $backup "analysis_options.yaml") "." -Force
  Copy-Item (Join-Path $backup "README.md") "." -Force

  Remove-Item $backup -Recurse -Force
}

flutter pub get
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

& (Join-Path $PSScriptRoot "prepare_native_plugins.ps1")
flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& (Join-Path $PSScriptRoot "enable_multiview_windows.ps1")
flutter run -d windows
exit $LASTEXITCODE
