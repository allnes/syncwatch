param(
  [switch]$SkipBuild,
  [switch]$DisableImpeller
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

Write-Host "Renderer: $(if ($DisableImpeller) { 'Skia (Impeller disabled)' } else { 'default Flutter renderer' })"
Write-Host "Runtime logs will be written to:"
Write-Host "  $logDir"

Write-Host "Stopping stale SyncWatch processes..."
Get-Process syncwatch -ErrorAction SilentlyContinue | Stop-Process -Force

Write-Host "Resolving Flutter dependencies..."
flutter pub get
if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed." }
& (Join-Path $PSScriptRoot "prepare_webrtc_plugin.ps1")
flutter pub get
if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed after the native WebRTC patch." }

Write-Host "Configuring Windows multi-view runner..."
$previousDisableImpeller = $env:SYNCWATCH_DISABLE_IMPELLER
$env:SYNCWATCH_DISABLE_IMPELLER = if ($DisableImpeller) { "1" } else { "0" }
& (Join-Path $PSScriptRoot "enable_multiview_windows.ps1")
$env:SYNCWATCH_DISABLE_IMPELLER = $previousDisableImpeller
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

# Preserve the fully patched main runtime before building Test Peer.
$clientRuntime = Join-Path $root "build\windows\client_runtime"
$callHelperRuntime = Join-Path $root "build\windows\call_helper"
foreach ($runtime in @($clientRuntime, $callHelperRuntime)) {
  if (Test-Path $runtime) { Remove-Item $runtime -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $runtime | Out-Null
  Copy-Item (Join-Path $debugRuntime "*") $runtime -Recurse -Force
}
$clientExe = Join-Path $clientRuntime "syncwatch.exe"
$callHelperExe = Join-Path $callHelperRuntime "syncwatch.exe"
if (!(Test-Path $clientExe) -or !(Test-Path $callHelperExe)) {
  throw "Failed to preserve main/call-helper runtimes."
}

# Build Test Peer before any SyncWatch process is running. Flutter uses the
# same Windows output directory for both targets, so compiling it after the
# client starts can fail when INSTALL.vcxproj tries to overwrite loaded DLLs.
Write-Host "Building Windows Test Peer..."
flutter build windows --debug -t lib\livekit_test_peer_app.dart
if ($LASTEXITCODE -ne 0) { throw "Test Peer Windows build failed." }

# The Test Peer must use the same patched WebRTC DLL.
Copy-Item $patchedDll.FullName (Join-Path $debugRuntime "libwebrtc.dll") -Force
$peerRuntime = Join-Path $root "build\windows\test_peer_runtime"
if (Test-Path $peerRuntime) { Remove-Item $peerRuntime -Recurse -Force }
New-Item -ItemType Directory -Force -Path $peerRuntime | Out-Null
Copy-Item (Join-Path $debugRuntime "*") $peerRuntime -Recurse -Force
$peerExe = Join-Path $peerRuntime "syncwatch.exe"
if (!(Test-Path $peerExe)) { throw "Failed to preserve Test Peer runtime." }

Write-Host "Prepared isolated runtimes:"
Write-Host "  Client:    $clientExe"
Write-Host "  Call:      $callHelperExe"
Write-Host "  Test Peer: $peerExe"

$serverLog = Join-Path $logDir "server.log"
$clientLog = Join-Path $logDir "client.log"
$peerLog = Join-Path $logDir "test_peer.log"

$server = 'Set-Location "' + (Join-Path $root "server") + '"; dart run bin\server.dart 2>&1 | Tee-Object -FilePath "' + $serverLog + '"'
$clientErrLog = Join-Path $logDir "client_stderr.log"
$client = 'Set-Location "' + $root + '"; ' +
  '$process = Start-Process -FilePath "' + $clientExe + '" ' +
  '-RedirectStandardOutput "' + $clientLog + '" ' +
  '-RedirectStandardError "' + $clientErrLog + '" -PassThru; ' +
  '$process.WaitForExit()'
$peer = 'Set-Location "' + $root + '"; ' +
  '$process = Start-Process -FilePath "' + $peerExe + '" ' +
  '-RedirectStandardOutput "' + $peerLog + '" -PassThru; ' +
  '$process.WaitForExit()'

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
