import Cocoa
import FlutterMacOS
import multiview_desktop

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    if !MainFlutterWindow.usesMultiView { return true }
    return MultiviewDesktopPlugin.applicationShouldTerminateAfterLastWindowClosed()
  }

  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !MainFlutterWindow.usesMultiView {
      return super.applicationShouldHandleReopen(sender, hasVisibleWindows: flag)
    }
    if MultiviewDesktopPlugin.applicationShouldHandleReopen(sender, hasVisibleWindows: flag) {
      return false
    }
    return super.applicationShouldHandleReopen(sender, hasVisibleWindows: flag)
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if !MainFlutterWindow.usesMultiView { return .terminateNow }
    return MultiviewDesktopPlugin.applicationShouldTerminate(sender)
  }

  override func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
    if !MainFlutterWindow.usesMultiView { return super.applicationDockMenu(sender) }
    return MultiviewDesktopPlugin.applicationDockMenu(sender)
  }
}
