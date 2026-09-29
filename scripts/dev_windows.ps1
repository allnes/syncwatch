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

$logDir = Join-Path $root "logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
Remove-Item (Join-Path $logDir "*.log") -Force -ErrorAction SilentlyContinue

Write-Host "Runtime logs will be written to:"
Write-Host "  $logDir"

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

$serverLog = Join-Path $logDir "server.log"
$clientLog = Join-Path $logDir "client.log"
$peerLog = Join-Path $logDir "test_peer.log"

$server = 'Set-Location "' + (Join-Path $root "server") + '"; dart run bin\server.dart 2>&1 | Tee-Object -FilePath "' + $serverLog + '"'
$clientExe = Join-Path $root "build\windows\x64\runner\Debug\syncwatch.exe"
$clientErrLog = Join-Path $logDir "client_stderr.log"
$client = 'Set-Location "' + $root + '"; ' +
  '$process = Start-Process -FilePath "' + $clientExe + '" ' +
  '-RedirectStandardOutput "' + $clientLog + '" ' +
  '-RedirectStandardError "' + $clientErrLog + '" -PassThru; ' +
  '$process.WaitForExit()'
$peer = 'Set-Location "' + $root + '"; flutter run -d windows -t lib\livekit_test_peer_app.dart 2>&1 | Tee-Object -FilePath "' + $peerLog + '"'

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
Write-Host ""
Write-Host "Logs:"
Write-Host "  Client:    $clientLog"
Write-Host "  Client err:$clientErrLog"
Write-Host "  Test Peer: $peerLog"
Write-Host "  Server:    $serverLog"
