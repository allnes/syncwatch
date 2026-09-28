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

  $onCreatePattern = '(?s)bool FlutterWindow::OnCreate\(\) \{.*?\n\}'
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
  $c = [regex]::Replace($c, $onCreatePattern, $onCreate, 1)

  $destroyPattern = '(?s)void FlutterWindow::OnDestroy\(\) \{.*?\n\}'
  $destroy = @'
void FlutterWindow::OnDestroy() {
  Win32Window::OnDestroy();
}
'@
  $c = [regex]::Replace($c, $destroyPattern, $destroy, 1)

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

Write-Host "SyncWatch Windows runner is configured for single-engine multi-view."
