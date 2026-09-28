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
    "url": "https://github.com/webrtc-sdk/webrtc.git@m150_release",
    "deps_file": "DEPS",
    "managed": False,
    "custom_deps": {},
    "custom_vars": {},
  },
]
target_os = ["win"]
'@ | Set-Content -Encoding ASCII .gclient
}

# Ensure an old m144 checkout from earlier script revisions is not reused.
if (Test-Path "$WorkDir\\src") {
  $configuredUrl = (Get-Content "$WorkDir\\.gclient" -Raw)
  if ($configuredUrl -notmatch "m150_release") {
    Remove-Item "$WorkDir\\src" -Recurse -Force
  }
}
gclient sync --nohooks --no-history
if ($LASTEXITCODE -ne 0) { throw "gclient sync failed." }
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

$audioSource = "modules\\audio_device\\win\\audio_device_core_win.cc"
if (!(Select-String -Path $audioSource -Pattern "SyncWatch: system ducking disabled" -Quiet)) {
  $source = Get-Content $audioSource -Raw
  $initializePos = $source.IndexOf("_ptrClientOut->Initialize(")
  if ($initializePos -lt 0) {
    throw "Could not find AudioDeviceWindowsCore render Initialize()."
  }
  $needle = "  EXIT_ON_ERROR(hr);"
  $insertPos = $source.IndexOf($needle, $initializePos)
  if ($insertPos -lt 0) {
    throw "Could not find EXIT_ON_ERROR after AudioDeviceWindowsCore render Initialize()."
  }
  $insertPos += $needle.Length
  $duckingCode = @'

  // SyncWatch owns its in-app ducking policy. Do not let this WebRTC
  // render stream attenuate unrelated Windows applications.
  {
    IAudioClientDuckingControl* ducking_control = nullptr;
    const HRESULT ducking_hr = _ptrClientOut->GetService(
        __uuidof(IAudioClientDuckingControl),
        reinterpret_cast<void**>(&ducking_control));
    if (SUCCEEDED(ducking_hr) && ducking_control != nullptr) {
      const HRESULT set_ducking_hr =
          ducking_control->SetDuckingOptionsForCurrentStream(
              AUDIO_DUCKING_OPTIONS_DO_NOT_DUCK_OTHER_STREAMS);
      if (SUCCEEDED(set_ducking_hr)) {
        RTC_LOG(LS_INFO) << "SyncWatch: system ducking disabled";
      } else {
        RTC_LOG(LS_WARNING)
            << "SyncWatch: failed to disable system ducking: "
            << set_ducking_hr;
      }
      ducking_control->Release();
    } else {
      RTC_LOG(LS_WARNING)
          << "SyncWatch: IAudioClientDuckingControl unavailable: "
          << ducking_hr;
    }
  }
'@
  $source = $source.Insert($insertPos, $duckingCode)
  [System.IO.File]::WriteAllText(
    (Resolve-Path $audioSource),
    $source,
    [System.Text.UTF8Encoding]::new($false)
  )
  if (!(Select-String -Path $audioSource -Pattern "SyncWatch: system ducking disabled" -Quiet)) {
    throw "AudioDeviceWindowsCore no-system-ducking patch verification failed."
  }
  Write-Host "Applied and verified SyncWatch no-system-ducking patch to AudioDeviceWindowsCore."
}

if (!(Test-Path "libwebrtc")) {
  git clone https://github.com/webrtc-sdk/libwebrtc.git libwebrtc
}
# Pin the wrapper to the exact binary release used by flutter_webrtc
# 1.6.2+hotfix.3. Do not build arbitrary wrapper main against this checkout.
git -C libwebrtc fetch --tags origin
git -C libwebrtc reset --hard 070aa6d763c16027ba53c0965107658c837a4dae
if ($LASTEXITCODE -ne 0) { throw "Failed to pin libwebrtc wrapper release." }

# Release 7871.03 added enable_sctp_snap to the wrapper and expects the matching
# WebRTC m150 API. The m150_release checkout used here predates that one field,
# so add the matching RTCConfiguration member before compiling the wrapper.
$pcInterface = "api\\peer_connection_interface.h"
if (!(Select-String -Path $pcInterface -Pattern "enable_sctp_snap" -Quiet)) {
  $pcText = Get-Content $pcInterface -Raw
  $pcAnchor = "    int max_sctp_streams = 65536;"
  if (!$pcText.Contains($pcAnchor)) {
    throw "Could not find RTCConfiguration max_sctp_streams insertion point."
  }
  $pcText = $pcText.Replace(
    $pcAnchor,
    $pcAnchor + [Environment]::NewLine +
      [Environment]::NewLine +
      "    // Enable SNAP (SCTP INIT in SDP)." + [Environment]::NewLine +
      "    bool enable_sctp_snap = false;"
  )
  [System.IO.File]::WriteAllText(
    (Resolve-Path $pcInterface),
    $pcText,
    [System.Text.UTF8Encoding]::new($false)
  )
  Write-Host "Applied m150 RTCConfiguration enable_sctp_snap compatibility field."
}

# Apply the wrapper's m150 custom-audio API patch. The published patch has
# stale context in exactly audio_receive_stream.cc/.h on the current m150
# checkout, so apply with rejects, repair only those two known rejects, and
# fail on anything else.
$wrapperAudioPatch = "libwebrtc\\patches\\custom_audio_source_m150.patch"
$audioDefines = "api\\audio\\audio_device_defines.h"
if (!(Select-String -Path $audioDefines -Pattern "UpdateAudioSenders" -Quiet)) {
  Get-ChildItem -Recurse -Filter "*.rej" | Remove-Item -Force
  git apply --reject --ignore-space-change --ignore-whitespace --whitespace=nowarn $wrapperAudioPatch

  $rejects = @(Get-ChildItem -Recurse -Filter "*.rej")
  $allowedRejectNames = @("audio_receive_stream.cc.rej", "audio_receive_stream.h.rej")
  $unexpectedRejects = @($rejects | Where-Object { $_.Name -notin $allowedRejectNames })
  if ($unexpectedRejects.Count -gt 0) {
    throw "Unexpected m150 patch rejects: $($unexpectedRejects.FullName -join ', ')"
  }

  $receiveCc = "audio\\audio_receive_stream.cc"
  $receiveCcText = Get-Content $receiveCc -Raw
  $receiveCcText = $receiveCcText -replace 'internal::AudioState\* AudioReceiveStreamImpl::audio_state\(\) const \{', 'webrtc::AudioState* AudioReceiveStreamImpl::audio_state() const {'
  $receiveCcText = $receiveCcText -replace 'static_cast<internal::AudioState\*>\(audio_state_\.get\(\)\)', 'static_cast<webrtc::AudioState*>(audio_state_.get())'
  [System.IO.File]::WriteAllText((Resolve-Path $receiveCc), $receiveCcText, [System.Text.UTF8Encoding]::new($false))

  $receiveH = "audio\\audio_receive_stream.h"
  $receiveHText = Get-Content $receiveH -Raw
  $receiveHText = $receiveHText -replace 'internal::AudioState\* audio_state\(\) const;', 'webrtc::AudioState* audio_state() const;'
  [System.IO.File]::WriteAllText((Resolve-Path $receiveH), $receiveHText, [System.Text.UTF8Encoding]::new($false))

  $rejects | Remove-Item -Force
}

$requiredChecks = @(
  @{ Path = "api\\audio\\audio_device_defines.h"; Pattern = "UpdateAudioSenders" },
  @{ Path = "audio\\audio_transport_impl.h"; Pattern = "class AudioTransportFactory" },
  @{ Path = "api\\peer_connection_interface.h"; Pattern = "audio_transport_factory" },
  @{ Path = "audio\\audio_receive_stream.cc"; Pattern = "static_cast<webrtc::AudioState" },
  @{ Path = "audio\\audio_receive_stream.h"; Pattern = "webrtc::AudioState* audio_state" }
)
foreach ($check in $requiredChecks) {
  if (!(Select-String -Path $check.Path -Pattern $check.Pattern -SimpleMatch -Quiet)) {
    throw "m150 compatibility verification failed: $($check.Path) / $($check.Pattern)"
  }
}
Write-Host "Verified libwebrtc m150 custom-audio compatibility patch."

# The wrapper repository defines a test target unconditionally. With
# rtc_include_tests=false, //test:test_main is intentionally absent, so remove
# only that wrapper test target; the production :libwebrtc target is unchanged.
$wrapperBuild = "libwebrtc\\BUILD.gn"
$wrapperText = Get-Content $wrapperBuild -Raw
$testMarker = 'rtc_test("libwebrtc_cpp_api_unittests")'
$testStart = $wrapperText.IndexOf($testMarker)
if ($testStart -ge 0) {
  $braceStart = $wrapperText.IndexOf('{', $testStart)
  $depth = 0
  $testEnd = -1
  for ($i = $braceStart; $i -lt $wrapperText.Length; $i++) {
    if ($wrapperText[$i] -eq '{') { $depth++ }
    elseif ($wrapperText[$i] -eq '}') {
      $depth--
      if ($depth -eq 0) {
        $testEnd = $i + 1
        break
      }
    }
  }
  if ($testEnd -lt 0) { throw "Could not parse libwebrtc wrapper test target." }
  $wrapperText = $wrapperText.Remove($testStart, $testEnd - $testStart)
  [System.IO.File]::WriteAllText(
    (Resolve-Path $wrapperBuild),
    $wrapperText,
    [System.Text.UTF8Encoding]::new($false)
  )
  Write-Host "Disabled libwebrtc wrapper unit-test target for production build."
}

$buildFile = Get-Content BUILD.gn -Raw
if ($buildFile -notmatch '"//libwebrtc"') {
  $buildFile = $buildFile -replace 'deps = \[ ":webrtc" \]', 'deps = [ ":webrtc", "//libwebrtc" ]'
  [System.IO.File]::WriteAllText(
    (Resolve-Path "BUILD.gn"),
    $buildFile,
    [System.Text.UTF8Encoding]::new($false)
  )
}

# The checkout's synthetic LASTCHANGE can still feed an invalid negative PE
# timestamp into Chromium's linker flags. Override Chromium's documented
# compute_build_timestamp GN arg with a tiny deterministic local script.
$timestampScript = Join-Path (Get-Location) "build\\syncwatch_build_timestamp.py"
[System.IO.File]::WriteAllText(
  $timestampScript,
  "print(1704067200)" + [Environment]::NewLine,
  [System.Text.Encoding]::ASCII
)

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
compute_build_timestamp = "//build/syncwatch_build_timestamp.py"
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
