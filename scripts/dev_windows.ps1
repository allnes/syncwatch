param(
  [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

function Start-SyncWatchShell {
  param(
    [string]$Title,
    [string]$Command
  )

  $encoded = [Convert]::ToBase64String(
    [Text.Encoding]::Unicode.GetBytes(
      '$Host.UI.RawUI.WindowTitle = "' + $Title + '"; ' +
      '$ErrorActionPreference = "Stop"; ' +
      $Command +
      '; Write-Host ""; Write-Host "[' + $Title + '] stopped. Press Enter to close."; Read-Host'
    )
  )

  Start-Process powershell.exe -ArgumentList @(
    "-NoExit",
    "-ExecutionPolicy", "Bypass",
    "-EncodedCommand", $encoded
  )
}

Set-Location $root

Write-Host "Stopping stale SyncWatch processes..."
Get-Process syncwatch -ErrorAction SilentlyContinue | Stop-Process -Force

Write-Host "Resolving Flutter dependencies..."
flutter pub get
if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed." }

Write-Host "Configuring Windows multi-view runner..."
& (Join-Path $PSScriptRoot "enable_multiview_windows.ps1")
if ($LASTEXITCODE -ne 0) { throw "enable_multiview_windows.ps1 failed." }

Write-Host "Analyzing client..."
flutter analyze lib
if ($LASTEXITCODE -ne 0) { throw "flutter analyze lib failed." }

if (!$SkipBuild) {
  Write-Host "Building Windows client..."
  flutter build windows --debug
  if ($LASTEXITCODE -ne 0) { throw "flutter build windows --debug failed." }
}

$server = 'Set-Location "' + (Join-Path $root "server") + '"; dart run bin\server.dart'
$client = 'Set-Location "' + $root + '"; .\build\windows\x64\runner\Debug\syncwatch.exe'
$peer = 'Set-Location "' + $root + '"; flutter run -d windows -t lib\livekit_test_peer_app.dart'

Write-Host "Starting server, SyncWatch, and Test Peer in separate PowerShell windows..."
Start-SyncWatchShell -Title "SyncWatch Server" -Command $server
Start-Sleep -Seconds 2
Start-SyncWatchShell -Title "SyncWatch Client" -Command $client
Start-Sleep -Seconds 2
Start-SyncWatchShell -Title "SyncWatch Test Peer" -Command $peer

Write-Host ""
Write-Host "Started:"
Write-Host "  1. SyncWatch Server"
Write-Host "  2. SyncWatch Client"
Write-Host "  3. SyncWatch Test Peer"
