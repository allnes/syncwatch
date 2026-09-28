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

# This WebRTC branch recognizes Visual Studio through 2022. If a newer Visual
# Studio is installed, provide its path explicitly and request the compatible
# VS 2022/v143 toolchain mode.
$vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\\Installer\\vswhere.exe"
$vsPath = $null
if (Test-Path $vswhere) {
  $vsPath = & $vswhere -latest -products * -property installationPath
}
if ($vsPath) {
  # This Chromium branch detects supported versions before consulting
  # GYP_MSVS_OVERRIDE_PATH. Hint the installed VS 2026 path as the supported
  # VS 2022 candidate; DetectVisualStudioPath() then resolves this exact path.
  $env:vs2022_install = $vsPath
  $env:GYP_MSVS_OVERRIDE_PATH = $vsPath
  Write-Host "Using local Visual Studio toolchain at $vsPath (advertised to WebRTC as VS 2022)."
} else {
  throw "No Visual Studio installation was found by vswhere."
}

# Chromium expects WINDOWSSDKDIR when using a local toolchain. Detect the SDK
# from standard and alternate-drive locations instead of assuming C:.
$sdkCandidates = @(
  "C:\\Program Files (x86)\\Windows Kits\\10",
  "D:\\Windows Kits\\10"
)
$sdkRoot = $sdkCandidates |
  Where-Object { Test-Path (Join-Path $_ "Include") } |
  Select-Object -First 1
if (!$sdkRoot) {
  throw "Windows 10/11 SDK was not found."
}
$sdkVersion = Get-ChildItem (Join-Path $sdkRoot "Include") -Directory |
  Sort-Object { [version]$_.Name } -Descending |
  Select-Object -First 1 -ExpandProperty Name
if (!$sdkVersion) {
  throw "No Windows SDK version was found under $sdkRoot\\Include."
}
$env:WINDOWSSDKDIR = "$sdkRoot\\"
$env:WINDOWSSDKVERSION = "$sdkVersion\\"
Write-Host "Using Windows SDK $sdkVersion at $sdkRoot."

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

# Windows PowerShell 5.1 Set-Content -Encoding UTF8 writes a BOM. An earlier
# revision of this script touched BUILD.gn that way; strip the BOM if present
# so GN can parse the checkout without requiring a fresh gclient sync.
$rootBuild = Join-Path (Get-Location) "BUILD.gn"
$rootBytes = [System.IO.File]::ReadAllBytes($rootBuild)
if ($rootBytes.Length -ge 3 -and
    $rootBytes[0] -eq 0xEF -and
    $rootBytes[1] -eq 0xBB -and
    $rootBytes[2] -eq 0xBF) {
  [System.IO.File]::WriteAllBytes(
    $rootBuild,
    $rootBytes[3..($rootBytes.Length - 1)]
  )
  Write-Host "Removed accidental UTF-8 BOM from BUILD.gn."
}

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
  [System.IO.File]::WriteAllText(
    (Resolve-Path $audioSource),
    $source,
    [System.Text.UTF8Encoding]::new($false)
  )
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

$argsFile = Join-Path (Get-Location) "out\\Windows-x64\\args.gn"
New-Item -ItemType Directory -Force -Path (Split-Path $argsFile) | Out-Null
@'
target_os = "win"
target_cpu = "x64"
is_component_build = false
is_clang = true
is_debug = false
rtc_use_h264 = true
ffmpeg_branding = "Chrome"
rtc_include_tests = false
rtc_build_examples = false
libwebrtc_desktop_capture = true
'@ | Set-Content -Path $argsFile -Encoding ASCII

& gn gen out/Windows-x64 --ide=vs2022
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
