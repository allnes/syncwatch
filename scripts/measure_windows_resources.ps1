param(
  [Parameter(Mandatory = $true)][int[]]$ProcessIds,
  [ValidateRange(5, 3600)][int]$Seconds = 30,
  [Parameter(Mandatory = $true)][string]$OutputPath,
  [switch]$IncludeGpu
)

$ErrorActionPreference = 'Stop'
$samples = [System.Collections.Generic.List[object]]::new()
$gpuSamples = [System.Collections.Generic.List[object]]::new()
$clock = [System.Diagnostics.Stopwatch]::StartNew()

function Get-Maximum($Values) {
  if ($null -eq $Values -or @($Values).Count -eq 0) { return $null }
  return [math]::Round(($Values | Measure-Object -Maximum).Maximum, 4)
}

function Get-Average($Values) {
  $present = @($Values | Where-Object { $null -ne $_ })
  if ($present.Count -eq 0) { return $null }
  return ($present | Measure-Object -Average).Average
}

function Add-ResourceSample($Counters = @()) {
  foreach ($processId in $ProcessIds) {
    $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
    if ($null -eq $process) { continue }
    $elapsed = [math]::Round($clock.Elapsed.TotalSeconds, 3)
    $gpu = @($Counters | Where-Object {
      $_.InstanceName -like "pid_${processId}_*" -and $_.Status -in @(0, 1)
    })
    $engines = @($gpu | Where-Object { $_.Path -like '*\utilization percentage' })
    foreach ($counter in $gpu) {
      $gpuSamples.Add([pscustomobject]@{
        elapsedSeconds = $elapsed
        processId = $processId
        instance = $counter.InstanceName
        counter = ($counter.Path -split '\\')[-1]
        value = $counter.CookedValue
      })
    }
    $samples.Add([pscustomobject]@{
      elapsedSeconds = $elapsed
      processId = $process.Id
      workingSetBytes = $process.WorkingSet64
      privateBytes = $process.PrivateMemorySize64
      cpuSeconds = $process.TotalProcessorTime.TotalSeconds
      handles = $process.HandleCount
      threads = $process.Threads.Count
      # Use the busiest engine, not a sum of independently running engines.
      # Preserve individual adapter/engine instances in the companion GPU CSV.
      gpuBusyPercent = Get-Maximum $engines.CookedValue
      gpu3DPercent = Get-Maximum @($engines | Where-Object { $_.InstanceName -like '*_engtype_3d' } | ForEach-Object CookedValue)
      gpuVideoDecodePercent = Get-Maximum @($engines | Where-Object { $_.InstanceName -like '*_engtype_videodecode' } | ForEach-Object CookedValue)
      gpuVideoEncodePercent = Get-Maximum @($engines | Where-Object { $_.InstanceName -like '*_engtype_videoencode' } | ForEach-Object CookedValue)
      gpuVideoProcessingPercent = Get-Maximum @($engines | Where-Object { $_.InstanceName -like '*_engtype_videoprocessing' } | ForEach-Object CookedValue)
      gpuCopyPercent = Get-Maximum @($engines | Where-Object { $_.InstanceName -like '*_engtype_copy' } | ForEach-Object CookedValue)
      gpuDedicatedBytes = if ($gpu.Count) { ($gpu | Where-Object { $_.Path -like '*\dedicated usage' } | Measure-Object CookedValue -Sum).Sum } else { $null }
      gpuSharedBytes = if ($gpu.Count) { ($gpu | Where-Object { $_.Path -like '*\shared usage' } | Measure-Object CookedValue -Sum).Sum } else { $null }
    })
    $process.Dispose()
  }
}

if ($IncludeGpu) {
  # Keep one PDH sampling session so rate counters have a previous sample.
  # These names require English performance counters; fail if unavailable.
  Get-Counter -Counter '\GPU Engine(*)\Utilization Percentage',
    '\GPU Process Memory(*)\Dedicated Usage',
    '\GPU Process Memory(*)\Shared Usage' -SampleInterval 1 -MaxSamples $Seconds `
    -ErrorAction SilentlyContinue -ErrorVariable counterErrors |
    ForEach-Object { Add-ResourceSample $_.CounterSamples }
} else {
  while ($clock.Elapsed.TotalSeconds -lt $Seconds) {
    Add-ResourceSample
    Start-Sleep -Milliseconds 1000
  }
}
$samples | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $OutputPath
if ($IncludeGpu) {
  $gpuPath = Join-Path ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($OutputPath))) ([IO.Path]::GetFileNameWithoutExtension($OutputPath) + '-gpu.csv')
  $gpuSamples | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $gpuPath
  # Processes/engines may disappear during capture. Keep valid samples instead
  # of losing the entire recording when PDH reports one invalid instance.
  if ($counterErrors) { Write-Warning "PDH reported $($counterErrors.Count) counter errors; invalid instances were excluded." }
  if (-not ($samples | Where-Object { $null -ne $_.gpuBusyPercent })) {
    throw 'No valid GPU samples were collected; CPU/RAM samples were saved.'
  }
}
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
    gpuValidSamples = @($group.Group | Where-Object { $null -ne $_.gpuBusyPercent }).Count
    meanGpuBusyPercent = Get-Average $group.Group.gpuBusyPercent
    meanGpu3DPercent = Get-Average $group.Group.gpu3DPercent
    meanGpuVideoDecodePercent = Get-Average $group.Group.gpuVideoDecodePercent
    meanGpuCopyPercent = Get-Average $group.Group.gpuCopyPercent
    meanGpuDedicatedMiB = if ($IncludeGpu -and $null -ne (Get-Average $group.Group.gpuDedicatedBytes)) { (Get-Average $group.Group.gpuDedicatedBytes) / 1MB } else { $null }
    meanGpuSharedMiB = if ($IncludeGpu -and $null -ne (Get-Average $group.Group.gpuSharedBytes)) { (Get-Average $group.Group.gpuSharedBytes) / 1MB } else { $null }
  }
}
