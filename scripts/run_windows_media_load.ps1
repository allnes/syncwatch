param(
  [Parameter(Mandatory = $true)][string]$Executable,
  [Parameter(Mandatory = $true)][string]$MediaPath,
  [Parameter(Mandatory = $true)][string]$OutputDirectory,
  [string]$BackendUrl = 'http://127.0.0.1:8787',
  [string]$Room = 'syncwatch-synthetic',
  [string]$AudioInput = 'Stereo Mix',
  [ValidateRange(30, 3600)][int]$Seconds = 180,
  [ValidateRange(0, 3500)][int]$RestartCallAfterSeconds = 0
)

# Run in an interactive Windows desktop. Build the separate target first:
# flutter build windows --release -t tool/synthetic_media_load.dart
$ErrorActionPreference = 'Stop'
$Executable = (Resolve-Path $Executable).Path
$MediaPath = (Resolve-Path $MediaPath).Path
New-Item $OutputDirectory -ItemType Directory -Force | Out-Null
$OutputDirectory = (Resolve-Path $OutputDirectory).Path
if ($RestartCallAfterSeconds -ge $Seconds) { throw 'Restart must occur before the run ends' }
$clients = @()
try {
  foreach ($index in 1..2) {
    $identity = "synthetic-$index"
    $configPath = Join-Path $OutputDirectory "$identity.json"
    if (Test-Path $configPath) { throw "Use a fresh output directory: $OutputDirectory" }
    $config = @{
      backendUrl = $BackendUrl; room = $Room; identity = $identity
      mediaPath = $MediaPath; statsPath = (Join-Path $OutputDirectory "$identity.jsonl")
      audioInput = $AudioInput; seconds = $Seconds
      windowX = (20 + ($index - 1) * 720); windowY = 40
    }
    if ($RestartCallAfterSeconds -gt 0) { $config.restartCallAfterSeconds = $RestartCallAfterSeconds }
    $config | ConvertTo-Json | Set-Content -Encoding UTF8 $configPath
    $client = Start-Process $Executable -ArgumentList "`"$configPath`"" -PassThru `
      -WorkingDirectory (Split-Path $Executable) `
      -RedirectStandardOutput (Join-Path $OutputDirectory "$identity.stdout.log") `
      -RedirectStandardError (Join-Path $OutputDirectory "$identity.stderr.log")
    # Keep the native handle open; Windows PowerShell can otherwise return a
    # null ExitCode when a short-lived process exits before WaitForExit.
    $null = $client.Handle
    $clients += $client
  }
  Write-Output "Client PIDs: $($clients.Id -join ', ')"
  $deadline = (Get-Date).AddSeconds($Seconds + 60)
  while (@($clients | Where-Object { !$_.HasExited }).Count -gt 0) {
    if ((Get-Date) -gt $deadline) { throw 'Media load timed out' }
    foreach ($client in $clients) {
      if ($client.HasExited -and $client.ExitCode -ne 0) {
        throw "Client $($client.Id) failed: $($client.ExitCode)"
      }
    }
    Start-Sleep -Seconds 1
  }
  foreach ($client in $clients) {
    $client.WaitForExit()
    if ($client.ExitCode -ne 0) { throw "Client failed: $($client.ExitCode)" }
  }
  Write-Output 'Both clients exited successfully. Validate RTP and playback logs before accepting measurements.'
} finally {
  foreach ($client in $clients) {
    if (!$client.HasExited) { Stop-Process -Id $client.Id }
  }
}
