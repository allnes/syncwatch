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

$audioSource = "modules\\audio_device\\win\\core_audio_base_win.cc"
if (!(Select-String -Path $audioSource -Pattern "SyncWatch owns its in-app ducking policy" -Quiet)) {
  $source = Get-Content $audioSource -Raw
  $anchor = @'
  // Check device period and the preferred buffer size and log a warning if
'@
  $duckingCode = @'
  // SyncWatch owns its in-app ducking policy. A WebRTC communications render
  // stream must never cause Windows to attenuate unrelated applications.
  // Keep AudioCategory_Communications (AEC/communications processing) and opt
  // only this render stream out of causing system ducking.
  if (IsOutput()) {
    ComPtr<IAudioClientDuckingControl> ducking_control;
    const HRESULT ducking_hr = audio_client->GetService(
        __uuidof(IAudioClientDuckingControl),
        reinterpret_cast<void**>(ducking_control.GetAddressOf()));
    if (SUCCEEDED(ducking_hr) && ducking_control) {
      const HRESULT set_ducking_hr =
          ducking_control->SetDuckingOptionsForCurrentStream(
              AUDIO_DUCKING_OPTIONS_DO_NOT_DUCK_OTHER_STREAMS);
      if (FAILED(set_ducking_hr)) {
        RTC_LOG(LS_WARNING)
            << "SyncWatch: failed to disable system ducking: "
            << set_ducking_hr;
      }
    } else {
      RTC_LOG(LS_WARNING)
          << "SyncWatch: IAudioClientDuckingControl unavailable: "
          << ducking_hr;
    }
  }

'@
  if (!$source.Contains($anchor)) {
    throw "Could not find the Core Audio insertion point in $audioSource."
  }
  $source = $source.Replace($anchor, $duckingCode + $anchor)
  Set-Content -Path $audioSource -Value $source -Encoding UTF8
  Write-Host "Applied SyncWatch no-system-ducking source patch."
}

if (!(Test-Path "libwebrtc")) {
  git clone https://github.com/webrtc-sdk/libwebrtc.git libwebrtc
}

$buildFile = Get-Content BUILD.gn -Raw
if ($buildFile -notmatch '"//libwebrtc"') {
  $buildFile = $buildFile -replace 'deps = \[ ":webrtc" \]', 'deps = [ ":webrtc", "//libwebrtc" ]'
  Set-Content -Encoding UTF8 BUILD.gn $buildFile
}

$gnArgs = 'target_os="win" target_cpu="x64" is_component_build=false is_clang=true is_debug=false rtc_use_h264=true ffmpeg_branding="Chrome" rtc_include_tests=false rtc_build_examples=false libwebrtc_desktop_capture=true'
& gn gen out/Windows-x64 "--args=$gnArgs" --ide=vs2022
if ($LASTEXITCODE -ne 0) { throw "gn gen failed." }
& ninja -C out/Windows-x64 libwebrtc
if ($LASTEXITCODE -ne 0) { throw "libwebrtc build failed." }

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
