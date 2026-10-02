param(
  [Parameter(Mandatory = $true)][int[]]$ProcessIds,
  [ValidateRange(5, 3600)][int]$Seconds = 30,
  [Parameter(Mandatory = $true)][string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$samples = [System.Collections.Generic.List[object]]::new()
$clock = [System.Diagnostics.Stopwatch]::StartNew()
while ($clock.Elapsed.TotalSeconds -lt $Seconds) {
  foreach ($processId in $ProcessIds) {
    $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
    if ($null -eq $process) { continue }
    $samples.Add([pscustomobject]@{
      elapsedSeconds = [math]::Round($clock.Elapsed.TotalSeconds, 3)
      processId = $process.Id
      workingSetBytes = $process.WorkingSet64
      privateBytes = $process.PrivateMemorySize64
      cpuSeconds = $process.TotalProcessorTime.TotalSeconds
      handles = $process.HandleCount
      threads = $process.Threads.Count
    })
    $process.Dispose()
  }
  Start-Sleep -Milliseconds 1000
}
$samples | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $OutputPath
foreach ($group in ($samples | Group-Object processId)) {
  $first = $group.Group[0]
  $last = $group.Group[-1]
  $elapsed = $last.elapsedSeconds - $first.elapsedSeconds
  [pscustomobject]@{
    processId = $group.Name
    samples = $group.Count
    meanPrivateMiB = [math]::Round(($group.Group | Measure-Object privateBytes -Average).Average / 1MB, 1)
    meanWorkingSetMiB = [math]::Round(($group.Group | Measure-Object workingSetBytes -Average).Average / 1MB, 1)
    # 100 means one fully utilized logical core; divide by logical cores for
    # Task Manager's whole-machine CPU percentage. Include helper PIDs too.
    cpuOneCorePercent = if ($elapsed -gt 0) {
      [math]::Round(100 * ($last.cpuSeconds - $first.cpuSeconds) / $elapsed, 1)
    } else { 0 }
  }
}
