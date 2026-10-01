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

# For the WMF hardware-encoder experiment, install the patched libwebrtc
# artifact produced by our GitHub Actions workflow. The GitHub artifact is a
# zip containing another zip; accept either the outer artifact or inner zip.
$debugRuntime = Join-Path $root "build\windows\x64\runner\Debug"
$downloads = Join-Path $HOME "Downloads"
$artifactCandidates = @(
  (Join-Path $downloads "libwebrtc-win-x64-release-patched.zip"),
  (Join-Path $root "libwebrtc-win-x64-release-patched.zip")
)
$artifact = $artifactCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($null -eq $artifact) {
  $artifact = Join-Path $root "libwebrtc-win-x64-release-patched.zip"
  $artifactUrl = "https://github.com/nestolen/syncwatch/actions/runs/36880639008/artifacts/11174518375"
  Write-Host "Patched libwebrtc artifact is not cached locally."
  Write-Host "Download it once from:"
  Write-Host "  $artifactUrl"
  Write-Host "and save it as:"
  Write-Host "  $artifact"
  throw "Patched libwebrtc artifact needs one-time download from GitHub Actions."
}
$patchedTemp = Join-Path $env:TEMP "syncwatch-patched-libwebrtc"
if (Test-Path $patchedTemp) { Remove-Item $patchedTemp -Recurse -Force }
New-Item -ItemType Directory -Force -Path $patchedTemp | Out-Null
Expand-Archive -Path $artifact -DestinationPath $patchedTemp -Force
$innerZip = Get-ChildItem $patchedTemp -Filter "*.zip" -File | Select-Object -First 1
if ($null -ne $innerZip) {
  $innerDir = Join-Path $patchedTemp "inner"
  Expand-Archive -Path $innerZip.FullName -DestinationPath $innerDir -Force
  $patchedDll = Get-ChildItem $innerDir -Filter "libwebrtc.dll" -File -Recurse | Select-Object -First 1
} else {
  $patchedDll = Get-ChildItem $patchedTemp -Filter "libwebrtc.dll" -File -Recurse | Select-Object -First 1
}
if ($null -eq $patchedDll) { throw "Patched artifact does not contain libwebrtc.dll." }
$runtimeDll = Join-Path $debugRuntime "libwebrtc.dll"
if (!(Test-Path $runtimeDll)) { throw "Built runtime libwebrtc.dll not found: $runtimeDll" }
Copy-Item $patchedDll.FullName $runtimeDll -Force
Write-Host "Installed patched libwebrtc.dll:"
Write-Host "  $($patchedDll.FullName) -> $runtimeDll"

# The test-peer flutter run uses the same Windows output directory and can
# overwrite syncwatch.exe. Preserve a complete client runtime for isolated
# call-process launches before starting the test peer.
$callHelperRuntime = Join-Path $root "build\windows\call_helper"
if (Test-Path $callHelperRuntime) {
  Remove-Item $callHelperRuntime -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $callHelperRuntime | Out-Null
Copy-Item (Join-Path $debugRuntime "*") $callHelperRuntime -Recurse -Force
$callHelperExe = Join-Path $callHelperRuntime "syncwatch.exe"
if (!(Test-Path $callHelperExe)) {
  throw "Failed to preserve isolated call helper executable."
}
Write-Host "Preserved isolated call helper runtime:"
Write-Host "  $callHelperExe"

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
