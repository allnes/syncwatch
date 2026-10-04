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
$configPath = Join-Path $root '.dart_tool\package_config.json'
$dependency = (Get-Content $configPath -Raw | ConvertFrom-Json).packages |
  Where-Object name -eq 'media_kit_video'
if (!$dependency) { throw 'Run flutter pub get first.' }
$plugin = ([Uri]::new([Uri]::new($configPath), $dependency.rootUri)).LocalPath
$angle = Join-Path (Split-Path (Split-Path $build -Parent) -Parent) 'ANGLE'
if (!(Test-Path "$angle\include\EGL\egl.h")) { throw 'Build ANGLE headers are missing.' }
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (!$vs) { throw 'Visual Studio C++ tools are required.' }
$patch = Join-Path $root 'patches\media-kit-video-surface-lifetime.patch'
$source = Join-Path $root 'tools\video\check_surface_lifetime.cpp'
$variants = @('fixed')
if ($VerifyBaselineFailure) { $variants += 'baseline' }
foreach ($variant in $variants) {
  $out = Join-Path $output $variant
  $native = Join-Path $out 'windows'
  New-Item -ItemType Directory -Force $native | Out-Null
  Copy-Item "$plugin\windows\angle_surface_manager.*", "$plugin\windows\utils.*" $native -Force
  Copy-Item "$build\libEGL.dll", "$build\libGLESv2.dll" $out -Force
  Push-Location $out
  try {
    & git apply --reverse --check $patch
    if ($LASTEXITCODE -ne 0) { throw 'Expected the prepared surface-lifetime patch.' }
    if ($variant -eq 'baseline') {
      & git apply --reverse $patch
      if ($LASTEXITCODE -ne 0) { throw 'Cannot construct the original-source control.' }
    }
  } finally { Pop-Location }
  @"
@echo off
call "$vs\VC\Auxiliary\Build\vcvars64.bat" >nul
cd /d "$out"
cl /nologo /O2 /std:c++17 /EHsc /DUNICODE /D_UNICODE /D_DISABLE_CONSTEXPR_MUTEX_CONSTRUCTOR /I"$native" /I"$angle\include" "$source" "$native\angle_surface_manager.cc" "$native\utils.cc" /link "$angle\lib\libEGL.dll.lib" "$angle\lib\libGLESv2.dll.lib" d3d11.lib dxgi.lib psapi.lib user32.lib /OUT:"$out\check_surface_lifetime.exe"
"@ | Set-Content "$out\compile.cmd"
  & cmd /c "$out\compile.cmd" *> "$out\compile.log"
  if ($LASTEXITCODE -ne 0) { throw "Native test compilation failed; see $out\compile.log" }
  $previousPreference = $ErrorActionPreference
  try {
    # PowerShell 5.1 wraps a native stderr line in NativeCommandError. The
    # original-source control intentionally reports the retained resources.
    $ErrorActionPreference = 'Continue'
    & "$out\check_surface_lifetime.exe" 60 *> "$out\check.log"
    $code = $LASTEXITCODE
  } finally { $ErrorActionPreference = $previousPreference }
  $expected = if ($variant -eq 'baseline') { 7 } else { 0 }
  if ($code -ne $expected) { throw "Unexpected $variant exit code $code; see $out\check.log" }
  Write-Host "PASS: $variant, 60 resizes, independent D3D readback and two rendering contexts"
}
