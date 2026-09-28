param(
  [string]$WorkDir = "D:\\libwebrtc-syncwatch"
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$patch = Join-Path $repoRoot "patches\\libwebrtc-no-system-ducking.patch"

New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
Set-Location $WorkDir

if (!(Test-Path "depot_tools")) {
  git clone --depth 1 https://chromium.googlesource.com/chromium/tools/depot_tools.git
}
$env:PATH = "$WorkDir\\depot_tools;$env:PATH"
$env:DEPOT_TOOLS_WIN_TOOLCHAIN = "0"
$env:GYP_MSVS_VERSION = "2022"

if (!(Test-Path ".gclient")) {
@'
solutions = [
  {
    "name": "src",
    "url": "https://github.com/webrtc-sdk/webrtc.git@m144_release",
    "deps_file": "DEPS",
    "managed": False,
    "custom_deps": {},
    "custom_vars": {},
  },
]
target_os = ["win"]
'@ | Set-Content -Encoding ASCII .gclient
}

gclient sync --no-history
Set-Location "$WorkDir\\src"

git apply --check $patch
git apply $patch

if (!(Test-Path "libwebrtc")) {
  git clone https://github.com/webrtc-sdk/libwebrtc.git libwebrtc
}

$buildFile = Get-Content BUILD.gn -Raw
if ($buildFile -notmatch '"//libwebrtc"') {
  $buildFile = $buildFile -replace 'deps = \[ ":webrtc" \]', 'deps = [ ":webrtc", "//libwebrtc" ]'
  Set-Content -Encoding UTF8 BUILD.gn $buildFile
}

gn gen out/Windows-x64 --args='target_os="win" target_cpu="x64" is_component_build=false is_clang=true is_debug=false rtc_use_h264=true ffmpeg_branding="Chrome" rtc_include_tests=false rtc_build_examples=false libwebrtc_desktop_capture=true' --ide=vs2022
ninja -C out/Windows-x64 libwebrtc

$out = Join-Path $repoRoot "third_party\\libwebrtc-syncwatch\\lib"
New-Item -ItemType Directory -Force -Path $out | Out-Null
Copy-Item out/Windows-x64/libwebrtc.dll $out -Force
Copy-Item out/Windows-x64/libwebrtc.dll.lib $out -Force

$pubCache = Join-Path $env:LOCALAPPDATA "Pub\\Cache\\hosted\\pub.dev"
$webrtcPackage = Get-ChildItem $pubCache -Directory -Filter "flutter_webrtc-1.6.2+hotfix.3" | Select-Object -First 1
if ($webrtcPackage) {
  $pluginLib = Join-Path $webrtcPackage.FullName "third_party\\libwebrtc\\lib"
  New-Item -ItemType Directory -Force -Path $pluginLib | Out-Null
  Copy-Item (Join-Path $out "libwebrtc.dll") $pluginLib -Force
  Copy-Item (Join-Path $out "libwebrtc.dll.lib") $pluginLib -Force
  $pluginBuildCache = Join-Path $repoRoot "build\\windows\\x64\\plugins\\flutter_webrtc"
  if (Test-Path $pluginBuildCache) {
    Remove-Item $pluginBuildCache -Recurse -Force
  }
  Write-Host "Installed custom libwebrtc into $pluginLib"
} else {
  Write-Warning "flutter_webrtc-1.6.2+hotfix.3 was not found in the Pub cache. Run flutter pub get, then copy the DLL and import library manually from $out."
}

Write-Host "Custom SyncWatch libwebrtc built at $out"
