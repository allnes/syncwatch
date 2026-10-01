$ErrorActionPreference = "Stop"
$path = Join-Path $PSScriptRoot "build\src\libwebrtc\src\win\wmf_h265_encoder.cc"
if (!(Test-Path $path)) { throw "WMF encoder source not found: $path" }
$text = Get-Content $path -Raw
$old = @'
  // Activate the first (highest priority) encoder
  hr = activate[0]->ActivateObject(IID_PPV_ARGS(&encoder_));
'@
$new = @'
  // SyncWatch: do not give up when the highest-priority hardware MFT cannot
  // be activated. Some hybrid Intel/NVIDIA systems enumerate NVIDIA first
  // even when only the Intel HEVC MFT is usable by this process.
  hr = E_FAIL;
  for (UINT32 i = 0; i < count; ++i) {
    LPWSTR friendly_name = nullptr;
    UINT32 name_len = 0;
    activate[i]->GetAllocatedString(MFT_FRIENDLY_NAME_Attribute,
                                    &friendly_name, &name_len);
    const std::string name =
        friendly_name ? webrtc::ToUtf8(friendly_name, name_len) : "<unknown>";
    if (friendly_name) {
      CoTaskMemFree(friendly_name);
    }

    encoder_.Reset();
    hr = activate[i]->ActivateObject(IID_PPV_ARGS(&encoder_));
    if (SUCCEEDED(hr)) {
      RTC_LOG(LS_INFO) << "SYNCWATCH_WMF_FALLBACK activated HEVC MFT "
                       << name << " index=" << i;
      break;
    }
    RTC_LOG(LS_WARNING) << "SYNCWATCH_WMF_FALLBACK failed HEVC MFT "
                        << name << " index=" << i << " hr=" << HrStr(hr);
  }
'@
if (!$text.Contains($old)) { throw "Expected activation block not found in compiled WMF source." }
$text = $text.Replace($old, $new)
Set-Content $path $text -Encoding utf8
if (!(Select-String -Path $path -SimpleMatch "SYNCWATCH_WMF_FALLBACK" -Quiet)) {
  throw "SyncWatch WMF fallback marker missing after patch."
}
Write-Host "Patched compiled WMF H265 encoder source: $path"
