param([Parameter(Mandatory = $true)][string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\artifact_paths.ps1')
$output = Get-SyncWatchExternalArtifactPath $OutputDirectory
if (Test-Path -LiteralPath $output) { throw 'Use a fresh output directory' }
$checkout = Join-Path $output 'source'
New-Item $checkout -ItemType Directory -Force | Out-Null
$alias = Join-Path $output 'alias'
try {
  New-Item $alias -ItemType Junction -Target $checkout | Out-Null
  foreach ($candidate in @($checkout, (Join-Path $checkout 'new\stats.jsonl'),
      (Join-Path $output 'external\..\source\stats.jsonl'),
      (Join-Path $alias 'new\stats.jsonl'), $checkout.ToUpperInvariant())) {
    $rejected = $false
    try { $null = Get-SyncWatchExternalArtifactPath $candidate -RepositoryRoot $checkout }
    catch { $rejected = $_.Exception.Message -like 'Artifacts must be outside*' }
    if (!$rejected) { throw "Failed to reject $candidate" }
  }
  foreach ($name in @('results', 'source-results')) {
    $candidate = Join-Path $output "$name\run\stats.csv"
    $actual = Get-SyncWatchExternalArtifactPath $candidate -RepositoryRoot $checkout
    if ($actual -ne $candidate) { throw "Unexpected path: $actual" }
    if (Test-Path $candidate) { throw 'Validation created an output file' }
  }
  Write-Output 'PASS: nested paths, traversal, junctions, case and external siblings'
} finally {
  # Remove only the junction itself, never recurse into its target.
  if (Test-Path -LiteralPath $alias) { [IO.Directory]::Delete($alias) }
}
