param(
  [Parameter(Mandatory=$true)][string]$BuildDirectory,
  [Parameter(Mandatory=$true)][string]$OutputDirectory,
  [switch]$VerifyBaselineFailure
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$build = (Resolve-Path $BuildDirectory).Path
$output = [IO.Path]::GetFullPath($OutputDirectory)
if ($output.Equals($root, [StringComparison]::OrdinalIgnoreCase) -or
    $output.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) {
  throw 'OutputDirectory must be outside the source checkout.'
}
New-Item -ItemType Directory -Force $output | Out-Null
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$installation = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (!$installation) {throw 'Visual Studio C++ tools are required.'}
$vcvars = Join-Path $installation 'VC\Auxiliary\Build\vcvars64.bat'
$source = Join-Path $root 'tools\mpv\check_lifecycle.cpp'
$include = Join-Path (Split-Path (Split-Path $build -Parent) -Parent) 'libmpv\include'
if (!(Test-Path (Join-Path $include 'client.h'))) {throw 'Build libmpv headers are missing.'}
$exports = Join-Path $root 'packages\syncwatch_mpv\windows\mpv_exports.def'
$executable = Join-Path $output 'check_mpv_lifecycle.exe'
$compile = Join-Path $output 'compile.cmd'
@"
@echo off
call "$vcvars" >nul
cd /d "$output"
cl /nologo /std:c++17 /EHsc /I"$include" "$source" /link ole32.lib uuid.lib /OUT:"$executable"
"@ | Set-Content $compile
& cmd /c $compile
if ($LASTEXITCODE -ne 0) {throw 'Native regression test compilation failed.'}
foreach ($apartment in @('sta', 'mta', 'none')) {
  & $executable $build fixed $apartment $exports *> (Join-Path $output "$apartment.log")
  if ($LASTEXITCODE -ne 0) {throw "mpv lifecycle regression failed for $apartment (exit=$LASTEXITCODE)."}
  Write-Host "PASS: $apartment, 12 cycles, shared handles and original API forwarding"
}
if ($VerifyBaselineFailure) {
  & $executable $build baseline sta $exports *> (Join-Path $output 'baseline.log')
  if ($LASTEXITCODE -ne 7) {throw "Expected baseline COM corruption (exit=7), got $LASTEXITCODE."}
  Write-Host 'PASS: original DLL reproduces COM corruption in a separate process'
}
