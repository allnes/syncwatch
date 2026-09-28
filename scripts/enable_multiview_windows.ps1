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
Write-Utf8NoBom $main $m

# Patch the pub-cache Windows multi-view host. The upstream frameless secondary
# window currently needs explicit non-client hit testing and a frame refresh on
# Windows for reliable sizing/resizing.
$pluginRoot = Join-Path $env:LOCALAPPDATA "Pub\Cache\hosted\pub.dev\multiview_desktop-1.2.2\windows"
$pluginCpp = Join-Path $pluginRoot "multi_view_desktop.cpp"
if (!(Test-Path $pluginCpp)) {
  throw "Missing multiview_desktop Windows source: $pluginCpp. Run flutter pub get first."
}

$p = Get-Content $pluginCpp -Raw

if ($p -notmatch "SyncWatch frameless resize hit-test") {
  $hitStart = $p.IndexOf('} else if (message == WM_NCHITTEST) {')
  if ($hitStart -lt 0) {
    throw "Could not locate multiview_desktop WM_NCHITTEST region."
  }
  $hitEnd = $p.IndexOf('} else if (message == WM_GETMINMAXINFO) {', $hitStart)
  if ($hitEnd -lt 0) {
    throw "Could not locate multiview_desktop WM_NCHITTEST/WM_GETMINMAXINFO region."
  }

  $newHit = @'
} else if (message == WM_NCHITTEST) {
            if (!window->is_resizable_) {
                return HTCLIENT;
            }

            // SyncWatch frameless resize hit-test: Windows removes the visible
            // non-client frame for hidden title bars, so provide resize borders.
            if (window->title_bar_style_ == "hidden" || window->is_frameless_) {
                POINT cursor = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
                RECT rect{};
                GetWindowRect(hwnd, &rect);
                const int border =
                    std::max(6, GetSystemMetrics(SM_CXSIZEFRAME) +
                                    GetSystemMetrics(SM_CXPADDEDBORDER));
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
  $p = $p.Substring(0, $hitStart) + $newHit + $p.Substring($hitEnd)
}

if ($p -notmatch "SyncWatch refresh native frame") {
  $oldResizable = @'
    ::SetWindowLong(hWnd, GWL_STYLE, gwlStyle);
}
'@
  $newResizable = @'
    ::SetWindowLong(hWnd, GWL_STYLE, gwlStyle);
    // SyncWatch refresh native frame after changing WS_THICKFRAME.
    ::SetWindowPos(hWnd, nullptr, 0, 0, 0, 0,
                   SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER |
                       SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
}
'@
  $setResizablePos = $p.IndexOf("void MultiViewDesktop::SetResizable")
  if ($setResizablePos -lt 0) {
    throw "Could not locate MultiViewDesktop::SetResizable."
  }
  $tail = $p.Substring($setResizablePos)
  if (!$tail.Contains($oldResizable)) {
    throw "Could not locate SetResizable SetWindowLong block."
  }
  $tail = $tail.Replace($oldResizable, $newResizable)
  $p = $p.Substring(0, $setResizablePos) + $tail
}

Write-Utf8NoBom $pluginCpp $p

# Force CMake to rebuild the locally patched plugin instead of reusing a
# previously compiled object from the last Flutter build.
$pluginBuild = Join-Path $root "build\windows\x64\plugins\multiview_desktop"
if (Test-Path $pluginBuild) {
  Remove-Item $pluginBuild -Recurse -Force
}

Write-Host "SyncWatch Windows runner is configured for single-engine multi-view."
