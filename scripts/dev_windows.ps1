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

# Recover dependency sources that older SyncWatch setup versions may have
# modified in the shared PUB_CACHE. Restore only files we touched.
$packageConfig = Join-Path $root ".dart_tool\package_config.json"
if (Test-Path $packageConfig) {
  try {
    $config = Get-Content $packageConfig -Raw | ConvertFrom-Json

    $mvPackage = $config.packages | Where-Object { $_.name -eq "multiview_desktop" } | Select-Object -First 1
    if ($null -ne $mvPackage) {
      $mvUri = [Uri]$mvPackage.rootUri
      $mvRoot = if ($mvUri.IsAbsoluteUri -and $mvUri.Scheme -eq "file") {
        $mvUri.LocalPath
      } else {
        [IO.Path]::GetFullPath((Join-Path (Split-Path $packageConfig -Parent) $mvPackage.rootUri))
      }
      if (Test-Path (Join-Path $mvRoot ".git")) {
        Write-Host "Restoring clean multiview_desktop sources..."
        & git -C $mvRoot checkout -- windows/multi_view_desktop.cpp windows/multi_view_desktop_plugin.cpp
        if ($LASTEXITCODE -ne 0) { throw "Failed to restore multiview_desktop sources." }
      }
    }

    $mkPackage = $config.packages | Where-Object { $_.name -eq "media_kit_video" } | Select-Object -First 1
    if ($null -ne $mkPackage) {
      $mkUri = [Uri]$mkPackage.rootUri
      $mkRoot = if ($mkUri.IsAbsoluteUri -and $mkUri.Scheme -eq "file") {
        $mkUri.LocalPath
      } else {
        [IO.Path]::GetFullPath((Join-Path (Split-Path $packageConfig -Parent) $mkPackage.rootUri))
      }
      $mkVideoOutput = Join-Path $mkRoot "windows\video_output.cc"
      if ((Test-Path $mkVideoOutput) -and
          ((Get-Content $mkVideoOutput -Raw) -match "SyncWatch presentation timing feedback")) {
        Write-Host "Removing stale patched media_kit_video package..."
        $mkPackageDir = Split-Path $mkRoot -Parent
        Remove-Item $mkPackageDir -Recurse -Force
      }
    }
  } catch {
    throw "Dependency recovery failed: $($_.Exception.Message)"
  }
}

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
$client = 'Set-Location "' + $root + '"; flutter run -d windows 2>&1 | Tee-Object -FilePath "' + $clientLog + '"'
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
Write-Host "  Test Peer: $peerLog"
Write-Host "  Server:    $serverLog"
