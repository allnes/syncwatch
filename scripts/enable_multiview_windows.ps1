$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$runner = Join-Path $root "windows\runner"
$cpp = Join-Path $runner "flutter_window.cpp"
$header = Join-Path $runner "flutter_window.h"
$main = Join-Path $runner "main.cpp"

foreach ($file in @($cpp, $header, $main)) {
  if (!(Test-Path $file)) {
    throw "Missing Windows runner file: $file. Run 'flutter create --platforms=windows .' once, then rerun this script."
  }
}

function Write-Utf8NoBom([string]$path, [string]$text) {
  [System.IO.File]::WriteAllText(
    $path,
    $text,
    [System.Text.UTF8Encoding]::new($false)
  )
}

$h = Get-Content $header -Raw
if ($h -notmatch "multiview_desktop") {
  $h = $h.Replace('#include <flutter/flutter_view_controller.h>' + [Environment]::NewLine, '')
  $h = $h -replace '\s*std::unique_ptr<flutter::FlutterViewController> flutter_controller_;\s*', [Environment]::NewLine
  Write-Utf8NoBom $header $h
}

$c = Get-Content $cpp -Raw
if ($c -notmatch "MultiViewDesktopCreateMainView") {
  $c = $c.Replace(
    '#include "flutter/generated_plugin_registrant.h"',
    '#include "flutter/generated_plugin_registrant.h"' + [Environment]::NewLine +
    '#include <multiview_desktop/multi_view_desktop_plugin.h>'
  )

  $onCreateStart = $c.IndexOf('bool FlutterWindow::OnCreate()')
  $destroyStart = $c.IndexOf('void FlutterWindow::OnDestroy()', $onCreateStart)
  if ($onCreateStart -lt 0 -or $destroyStart -lt 0) {
    throw "Could not locate FlutterWindow::OnCreate/OnDestroy in $cpp"
  }
  $onCreate = @'
bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();
  const int width = frame.right - frame.left;
  const int height = frame.bottom - frame.top;

  MultiViewDesktopPrepareEngine(project_, GetHandle());
  MultiViewDesktopCreateMainView(GetHandle(), width, height, RegisterPlugins);
  const HWND flutter_hwnd =
      MultiViewDesktopGetFlutterHwnd(MultiViewDesktopGetMainViewId());
  if (flutter_hwnd == nullptr) {
    return false;
  }
  SetChildContent(flutter_hwnd);
  return true;
}

'@
  $c = $c.Substring(0, $onCreateStart) + $onCreate + $c.Substring($destroyStart)

  $destroyStart = $c.IndexOf('void FlutterWindow::OnDestroy()')
  $messageStart = $c.IndexOf('LRESULT', $destroyStart)
  if ($destroyStart -lt 0 -or $messageStart -lt 0) {
    throw "Could not locate FlutterWindow::OnDestroy/MessageHandler in $cpp"
  }
  $destroy = @'
void FlutterWindow::OnDestroy() {
  Win32Window::OnDestroy();
}

'@
  $c = $c.Substring(0, $destroyStart) + $destroy + $c.Substring($messageStart)

  $messageStart = $c.IndexOf('LRESULT' + [Environment]::NewLine + 'FlutterWindow::MessageHandler')
  if ($messageStart -lt 0) {
    $messageStart = $c.IndexOf('LRESULT FlutterWindow::MessageHandler')
  }
  if ($messageStart -lt 0) {
    throw "Could not find FlutterWindow::MessageHandler in $cpp"
  }
  $prefix = $c.Substring(0, $messageStart)
  $message = @'
LRESULT FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  LRESULT result = 0;
  static const UINT syncwatch_bring_to_front =
      RegisterWindowMessage(L"SyncWatch.BringToFront");
  if (message == syncwatch_bring_to_front) {
    if (IsIconic(hwnd)) {
      ShowWindow(hwnd, SW_RESTORE);
    } else {
      ShowWindow(hwnd, SW_SHOW);
    }
    BringWindowToTop(hwnd);
    SetForegroundWindow(hwnd);
    SetActiveWindow(hwnd);
    SetFocus(hwnd);
    return 0;
  }
  if (message == WM_FONTCHANGE) {
    FlutterDesktopEngineReloadSystemFonts(MultiViewDesktopGetEngineRef());
  }
  if (MultiViewDesktopHandleWindowProc(
          hwnd, message, wparam, lparam, &result)) {
    return result;
  }
  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
'@
  $c = $prefix + $message
  Write-Utf8NoBom $cpp $c
}

$m = Get-Content $main -Raw
$m = $m.Replace('window.SetQuitOnClose(true);', 'window.SetQuitOnClose(false);')

# Diagnostic A/B switch for Flutter's Windows renderer. Flutter 3.47+ enables
# Impeller by default on Windows. Keep the normal build untouched unless the
# dev launcher explicitly requests the Skia comparison path.
$impellerLine = '  project.set_impeller_switch(flutter::ImpellerSwitch::Disabled);  // SyncWatch diagnostic'
$m = $m.Replace($impellerLine + [Environment]::NewLine, '')
if ($env:SYNCWATCH_DISABLE_IMPELLER -eq "1") {
  $projectLine = '  flutter::DartProject project(L"data");'
  if (!$m.Contains($projectLine)) {
    throw "Could not locate DartProject construction in $main"
  }
  $m = $m.Replace(
    $projectLine,
    $projectLine + [Environment]::NewLine + $impellerLine
  )
  Write-Host "SyncWatch diagnostic renderer: Impeller DISABLED (Skia)."
} else {
  Write-Host "SyncWatch renderer: Flutter default (Impeller)."
}
Write-Utf8NoBom $main $m

# window_manager's setAsFrameless removes the native non-client frame. Patch
# the actual 0.5.2 top-level WindowProc branch used by the isolated helper.
$wmProc = Join-Path $env:LOCALAPPDATA "Pub\\Cache\\hosted\\pub.dev\\window_manager-0.5.2\\windows\\window_manager_plugin.cpp"
if (!(Test-Path $wmProc)) {
  throw "window_manager 0.5.2 Windows source not found: $wmProc"
}
$wm = Get-Content $wmProc -Raw

# Normalize our previous version if this shared pub-cache was already patched.
$patchedHit = @'
  } else if (message == WM_NCHITTEST) {
    if (!window_manager->is_resizable_) {
      return HTNOWHERE;
    }
    if (window_manager->is_frameless_) {
      POINT cursor = {
          static_cast<LONG>(static_cast<short>(LOWORD(lParam))),
          static_cast<LONG>(static_cast<short>(HIWORD(lParam)))};
      RECT rect{};
      GetWindowRect(hWnd, &rect);
      const int border = 8;
      const bool left = cursor.x < rect.left + border;
      const bool right = cursor.x >= rect.right - border;
      const bool top = cursor.y < rect.top + border;
      const bool bottom = cursor.y >= rect.bottom - border;
      if (top && left) return HTTOPLEFT;
      if (top && right) return HTTOPRIGHT;
      if (bottom && left) return HTBOTTOMLEFT;
      if (bottom && right) return HTBOTTOMRIGHT;
      if (left) return HTLEFT;
      if (right) return HTRIGHT;
      if (top) return HTTOP;
      if (bottom) return HTBOTTOM;
      return HTCLIENT;
    }
    // SyncWatch helper frameless resize
'@
$upstreamHit = @'
  } else if (message == WM_NCHITTEST) {
    if (!window_manager->is_resizable_) {
      return HTNOWHERE;
    }
'@
if ($wm.Contains($patchedHit)) {
  # already correct
} elseif ($wm.Contains($upstreamHit)) {
  $wm = $wm.Replace($upstreamHit, $patchedHit)
} else {
  throw "window_manager WM_NCHITTEST block changed unexpectedly; refusing blind patch."
}
Write-Utf8NoBom $wmProc $wm

# Generate a tiny native helper used by the main SyncWatch process to activate
# the isolated call window. SetForegroundWindow from the background helper
# itself is rejected by Windows; the foreground client performs the activation.
$focusCpp = Join-Path $runner "syncwatch_focus_window.cpp"
$focusExe = Join-Path $runner "syncwatch_focus_window.exe"
$focusSource = @'
#include <windows.h>
#include <cwchar>

int wmain(int argc, wchar_t** argv) {
  if (argc < 2) return 2;
  const wchar_t* title = argv[1];
  HWND hwnd = FindWindowW(nullptr, title);
  if (hwnd == nullptr) return 3;
  if (IsIconic(hwnd)) ShowWindow(hwnd, SW_RESTORE);
  else ShowWindow(hwnd, SW_SHOW);
  BringWindowToTop(hwnd);
  SetForegroundWindow(hwnd);
  SetActiveWindow(hwnd);
  SetFocus(hwnd);
  return GetForegroundWindow() == hwnd ? 0 : 4;
}
'@
Write-Utf8NoBom $focusCpp $focusSource
$cl = Get-Command cl.exe -ErrorAction SilentlyContinue
if ($null -ne $cl) {
  & $cl.Source /nologo /EHsc /utf-8 $focusCpp /Fe:$focusExe user32.lib | Out-Null
}

# multiview_desktop is pinned to a known Git revision in pubspec.yaml.
# Patch the exact package source selected by Flutter rather than assuming a
# pub.dev cache path/version.
$packageConfig = Join-Path $root ".dart_tool\package_config.json"
if (!(Test-Path $packageConfig)) {
  throw "Missing $packageConfig. Run flutter pub get first."
}
$config = Get-Content $packageConfig -Raw | ConvertFrom-Json
$mvPackage = $config.packages | Where-Object { $_.name -eq "multiview_desktop" } | Select-Object -First 1
if ($null -eq $mvPackage) {
  throw "multiview_desktop is missing from package_config.json."
}
$mvRootUri = [Uri]$mvPackage.rootUri
if ($mvRootUri.IsAbsoluteUri -and $mvRootUri.Scheme -eq "file") {
  $mvRoot = $mvRootUri.LocalPath
} else {
  $mvRoot = [IO.Path]::GetFullPath((Join-Path (Split-Path $packageConfig -Parent) $mvPackage.rootUri))
}
$pluginCpp = Join-Path $mvRoot "windows\multi_view_desktop.cpp"
$pluginProcCpp = Join-Path $mvRoot "windows\multi_view_desktop_plugin.cpp"
if (!(Test-Path $pluginCpp)) {
  throw "Missing pinned multiview_desktop Windows source: $pluginCpp"
}
if (!(Test-Path $pluginProcCpp)) {
  throw "Missing pinned multiview_desktop Windows proc source: $pluginProcCpp"
}

$p = Get-Content $pluginCpp -Raw

# A previous local run may already have patched the Git dependency cache with
# an older SyncWatch block. Because git dependencies are shared in PUB_CACHE,
# flutter pub get does not necessarily restore that file. Normalize stale
# variants before applying the current patch.
if ($p -match "SyncWatch frameless resize hit-test") {
  $staleStart = $p.IndexOf("case WM_NCHITTEST: {")
  $staleEnd = $p.IndexOf("case WM_SIZE: {", $staleStart)
  if ($staleStart -ge 0 -and $staleEnd -gt $staleStart) {
    $p = $p.Remove($staleStart, $staleEnd - $staleStart)
  }
}
$p = $p.Replace(
  "    // SyncWatch refresh native frame after changing WS_THICKFRAME." + [Environment]::NewLine +
  "    ::SetWindowPos(hWnd, nullptr, 0, 0, 0, 0," + [Environment]::NewLine +
  "                   SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER |" + [Environment]::NewLine +
  "                       SWP_NOOWNERZORDER | SWP_FRAMECHANGED);" + [Environment]::NewLine,
  ""
)

if ($p -notmatch "SyncWatch frameless resize hit-test") {
  # The pinned revision routes host messages through HostWndProc and does not
  # contain WM_NCHITTEST/WM_GETMINMAXINFO yet. Add both directly to the host
  # switch instead of searching for handlers that do not exist.
  $sizeCase = "case WM_SIZE: {"
  $casePos = $p.IndexOf($sizeCase)
  if ($casePos -lt 0) {
    throw "Pinned multiview_desktop HostWndProc lacks WM_SIZE."
  }
  $nativeCases = @'
case WM_NCHITTEST: {
MultiViewDesktop *window =
        MultiViewDesktop::Instance().FindByHwnd(hwnd);
if (window != nullptr && window->is_resizable_ &&
    (window->title_bar_style_ == "hidden" || window->is_frameless_)) {
POINT cursor = {
        static_cast<LONG>(static_cast<short>(LOWORD(lparam))),
        static_cast<LONG>(static_cast<short>(HIWORD(lparam)))};
RECT rect{};
GetWindowRect(hwnd, &rect);
const int native_border =
        GetSystemMetrics(SM_CXSIZEFRAME) +
        GetSystemMetrics(SM_CXPADDEDBORDER);
const int border = native_border > 6 ? native_border : 6;
const bool left = cursor.x < rect.left + border;
const bool right = cursor.x >= rect.right - border;
const bool top = cursor.y < rect.top + border;
const bool bottom = cursor.y >= rect.bottom - border;
if (top && left) return HTTOPLEFT;
if (top && right) return HTTOPRIGHT;
if (bottom && left) return HTBOTTOMLEFT;
if (bottom && right) return HTBOTTOMRIGHT;
if (left) return HTLEFT;
if (right) return HTRIGHT;
if (top) return HTTOP;
if (bottom) return HTBOTTOM;
}
break;
}
case WM_GETMINMAXINFO: {
MultiViewDesktop *window =
        MultiViewDesktop::Instance().FindByHwnd(hwnd);
if (window != nullptr) {
MINMAXINFO *info = reinterpret_cast<MINMAXINFO *>(lparam);
if (window->minimum_size_.x != 0) {
info->ptMinTrackSize.x = static_cast<LONG>(
        window->minimum_size_.x * window->pixel_ratio_);
}
if (window->minimum_size_.y != 0) {
info->ptMinTrackSize.y = static_cast<LONG>(
        window->minimum_size_.y * window->pixel_ratio_);
}
if (window->maximum_size_.x != -1) {
info->ptMaxTrackSize.x = static_cast<LONG>(
        window->maximum_size_.x * window->pixel_ratio_);
}
if (window->maximum_size_.y != -1) {
info->ptMaxTrackSize.y = static_cast<LONG>(
        window->maximum_size_.y * window->pixel_ratio_);
}
return 0;
}
break;
}
// SyncWatch frameless resize hit-test
'@
  $p = $p.Insert($casePos, $nativeCases + [Environment]::NewLine)
}

if ($p -notmatch "SyncWatch refresh native frame") {
  $setResizablePos = $p.IndexOf("void MultiViewDesktop::SetResizable")
  if ($setResizablePos -lt 0) {
    throw "Pinned multiview_desktop source lacks SetResizable."
  }
  $setResizableEnd = $p.IndexOf("bool MultiViewDesktop::IsMinimizable", $setResizablePos)
  if ($setResizableEnd -lt 0) {
    throw "Pinned multiview_desktop source lacks IsMinimizable after SetResizable."
  }
  $section = $p.Substring($setResizablePos, $setResizableEnd - $setResizablePos)
  $needle = "    ::SetWindowLong(hWnd, GWL_STYLE, gwlStyle);"
  if (!$section.Contains($needle)) {
    throw "Pinned multiview_desktop SetResizable lacks SetWindowLong."
  }
  $replacement = @'
    ::SetWindowLong(hWnd, GWL_STYLE, gwlStyle);
    // SyncWatch refresh native frame after changing WS_THICKFRAME.
    ::SetWindowPos(hWnd, nullptr, 0, 0, 0, 0,
                   SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER |
                       SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
'@
  $section = $section.Replace($needle, $replacement)
  $p = $p.Substring(0, $setResizablePos) + $section + $p.Substring($setResizableEnd)
}

# MSVC on Russian Windows compiles this generated plugin source under CP1251.
# Strip accidental non-ASCII bytes that can survive in ephemeral patched source
# and turn into invalid multibyte characters inside C++ string literals.
$p = [regex]::Replace($p, '[^\x00-\x7F]', '')
Write-Utf8NoBom $pluginCpp $p

$proc = Get-Content $pluginProcCpp -Raw

# A previous failed patch may have left a stale SyncWatch WM_NCHITTEST body in
# the shared Git package cache. Restore that whole branch to the pinned
# upstream shape before applying the current patch below.
$procHitStart = $proc.IndexOf('        } else if (message == WM_NCHITTEST) {')
if ($procHitStart -ge 0) {
  $procHitEnd = $proc.IndexOf('        } else if (message == WM_GETMINMAXINFO) {', $procHitStart)
  if ($procHitEnd -gt $procHitStart) {
    $upstreamProcHit = @'
        } else if (message == WM_NCHITTEST) {
            if (!window->is_resizable_) {
                return HTNOWHERE;
            }
'@
    $proc = $proc.Substring(0, $procHitStart) + $upstreamProcHit +
            [Environment]::NewLine + $proc.Substring($procHitEnd)
  }
}
$oldProcHit = @'
        } else if (message == WM_NCHITTEST) {
            if (!window->is_resizable_) {
                return HTNOWHERE;
            }
'@
$newProcHit = @'
        } else if (message == WM_NCHITTEST) {
            if (!window->is_resizable_) {
                return HTCLIENT;
            }
            if (window->title_bar_style_ == "hidden" || window->is_frameless_) {
                POINT cursor{};
                GetCursorPos(&cursor);
                RECT rect{};
                GetWindowRect(hwnd, &rect);
                const int native_border =
                        GetSystemMetrics(SM_CXSIZEFRAME) +
                        GetSystemMetrics(SM_CXPADDEDBORDER);
                const int border = native_border > 8 ? native_border : 8;
                const bool left = cursor.x < rect.left + border;
                const bool right = cursor.x >= rect.right - border;
                const bool top = cursor.y < rect.top + border;
                const bool bottom = cursor.y >= rect.bottom - border;
                if (top && left) return HTTOPLEFT;
                if (top && right) return HTTOPRIGHT;
                if (bottom && left) return HTBOTTOMLEFT;
                if (bottom && right) return HTBOTTOMRIGHT;
                if (left) return HTLEFT;
                if (right) return HTRIGHT;
                if (top) return HTTOP;
                if (bottom) return HTBOTTOM;
                return HTCLIENT;
            }
'@
if ($proc.Contains($oldProcHit)) {
  $proc = $proc.Replace($oldProcHit, $newProcHit)
} elseif ($proc -notmatch 'const int border = native_border > 8') {
  throw "Pinned multiview_desktop plugin WM_NCHITTEST block changed unexpectedly."
}
# Enforce min/max constraints in the first native message hook as well.
# HandleWindowProc runs before the host WndProc, so returning here guarantees
# Windows receives the constraints for frameless secondary windows.
$oldProcMinMax = @'
        } else if (message == WM_GETMINMAXINFO) {
            MINMAXINFO *info = reinterpret_cast<MINMAXINFO *>(lparam);
            if (window->minimum_size_.x != 0) {
                info->ptMinTrackSize.x = static_cast<LONG>(
                        window->minimum_size_.x * window->pixel_ratio_);
            }
            if (window->minimum_size_.y != 0) {
                info->ptMinTrackSize.y = static_cast<LONG>(
                        window->minimum_size_.y * window->pixel_ratio_);
            }
            if (window->maximum_size_.x != -1) {
                info->ptMaxTrackSize.x = static_cast<LONG>(
                        window->maximum_size_.x * window->pixel_ratio_);
            }
            if (window->maximum_size_.y != -1) {
                info->ptMaxTrackSize.y = static_cast<LONG>(
                        window->maximum_size_.y * window->pixel_ratio_);
            }
            result = 0;
'@
$newProcMinMax = @'
        } else if (message == WM_GETMINMAXINFO) {
            MINMAXINFO *info = reinterpret_cast<MINMAXINFO *>(lparam);
            if (window->minimum_size_.x != 0) {
                info->ptMinTrackSize.x = static_cast<LONG>(
                        window->minimum_size_.x * window->pixel_ratio_);
            }
            if (window->minimum_size_.y != 0) {
                info->ptMinTrackSize.y = static_cast<LONG>(
                        window->minimum_size_.y * window->pixel_ratio_);
            }
            if (window->maximum_size_.x != -1) {
                info->ptMaxTrackSize.x = static_cast<LONG>(
                        window->maximum_size_.x * window->pixel_ratio_);
            }
            if (window->maximum_size_.y != -1) {
                info->ptMaxTrackSize.y = static_cast<LONG>(
                        window->maximum_size_.y * window->pixel_ratio_);
            }
            return 0;
'@
if ($proc.Contains($oldProcMinMax)) {
  $proc = $proc.Replace($oldProcMinMax, $newProcMinMax)
}

# multi_view_desktop_plugin.cpp is compiled by MSVC under the active Windows
# code page. Keep our generated/patched source strictly ASCII so stale UTF-8
# bytes in the shared PUB_CACHE cannot become invalid C++ string literals.
$proc = [regex]::Replace($proc, '[^\x00-\x7F]', '')
if ([regex]::IsMatch($proc, '[^\x00-\x7F]')) {
  throw "multiview_desktop_plugin.cpp still contains non-ASCII characters after normalization."
}
Write-Utf8NoBom $pluginProcCpp $proc

$pluginBuild = Join-Path $root "build\windows\x64\plugins\multiview_desktop"
if (Test-Path $pluginBuild) {
  Remove-Item $pluginBuild -Recurse -Force
}

Write-Host "SyncWatch Windows runner is configured for single-engine multi-view."
