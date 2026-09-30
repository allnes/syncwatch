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

$resourceLog = Join-Path $logDir "resources.log"
$resourceScript = Join-Path $logDir "resource_monitor.ps1"
$resourceMonitor = @'
$ErrorActionPreference = "SilentlyContinue"
$log = "__RESOURCE_LOG__"
$intervalSeconds = 2
$lastCpu = @{}
$lastAt = Get-Date
"timestamp|systemCpuPct|systemMemUsedPct|pid|process|cpuPct|workingSetMB|privateMB|gpuPct" | Set-Content -Path $log -Encoding UTF8
while ($true) {
  $now = Get-Date
  $elapsed = [Math]::Max(0.001, ($now - $lastAt).TotalSeconds)
  $lastAt = $now
  $os = Get-CimInstance Win32_OperatingSystem
  $cpu = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
  $memUsed = if ($os.TotalVisibleMemorySize -gt 0) { 100.0 * ($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize } else { 0.0 }
  $gpuByPid = @{}
  Get-Counter "\GPU Engine(*)\Utilization Percentage" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty CounterSamples | ForEach-Object {
    if ($_.InstanceName -match "pid_(\d+)_") {
      $pidValue = [int]$matches[1]
      if (-not $gpuByPid.ContainsKey($pidValue)) { $gpuByPid[$pidValue] = 0.0 }
      $gpuByPid[$pidValue] += [double]$_.CookedValue
    }
  }
  $processes = Get-Process | Where-Object { $_.ProcessName -in @("syncwatch","dart","flutter","powershell") }
  foreach ($p in $processes) {
    $cpuNow = [double]$p.CPU
    $cpuPct = 0.0
    if ($lastCpu.ContainsKey($p.Id)) { $cpuPct = 100.0 * ($cpuNow - [double]$lastCpu[$p.Id]) / $elapsed }
    $lastCpu[$p.Id] = $cpuNow
    $gpu = if ($gpuByPid.ContainsKey($p.Id)) { [double]$gpuByPid[$p.Id] } else { 0.0 }
    $line = "{0}|{1:N1}|{2:N1}|{3}|{4}|{5:N1}|{6:N1}|{7:N1}|{8:N1}" -f $now.ToString("o"), [double]$cpu, [double]$memUsed, $p.Id, $p.ProcessName, $cpuPct, ($p.WorkingSet64 / 1MB), ($p.PrivateMemorySize64 / 1MB), $gpu
    Add-Content -Path $log -Value $line -Encoding UTF8
  }
  Start-Sleep -Seconds $intervalSeconds
}
'@
$resourceMonitor = $resourceMonitor.Replace("__RESOURCE_LOG__", $resourceLog.Replace("'", "''"))
Set-Content -Path $resourceScript -Value $resourceMonitor -Encoding UTF8
$monitorCommand = '& "' + $resourceScript + '"'
Start-SyncWatchShell -Title "SyncWatch Resource Monitor" -Command $monitorCommand
Start-Sleep -Seconds 1

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
Write-Host "  Resources: $resourceLog"
