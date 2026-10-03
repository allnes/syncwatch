import FlutterMacOS
import Foundation

public final class LibraryAccessPlugin: NSObject, FlutterPlugin {
  // Only startup restoration starts a scope. Picker selections already carry
  // a process-lifetime grant. Keep the restored scope through app teardown so
  // changing the library in player settings cannot revoke the playing movie.
  private var restoredURL: URL?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "dev.syncwatch/library_access", binaryMessenger: registrar.messenger)
    registrar.addMethodCallDelegate(LibraryAccessPlugin(), channel: channel)
  }

  deinit {
    restoredURL?.stopAccessingSecurityScopedResource()
  }

  private func bookmark(for url: URL) throws -> Data {
    try url.bookmarkData(
      options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
      includingResourceValuesForKeys: nil, relativeTo: nil)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let argument = call.arguments as? String else {
      result(FlutterError(code: "invalid_argument", message: "Expected a string", details: nil))
      return
    }
    do {
      switch call.method {
      case "create":
        let url = URL(fileURLWithPath: argument, isDirectory: true)
        result(try bookmark(for: url).base64EncodedString())
      case "restore":
        guard let data = Data(base64Encoded: argument) else {
          throw CocoaError(.coderReadCorrupt)
        }
        var stale = false
        let url = try URL(
          resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI],
          relativeTo: nil, bookmarkDataIsStale: &stale)
        guard url.startAccessingSecurityScopedResource() else {
          throw CocoaError(.fileReadNoPermission)
        }
        do {
          let renewed = stale ? try bookmark(for: url) : data
          let previous = restoredURL
          restoredURL = url
          previous?.stopAccessingSecurityScopedResource()
          result(["path": url.path, "data": renewed.base64EncodedString()])
        } catch {
          url.stopAccessingSecurityScopedResource()
          throw error
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    } catch {
      result(FlutterError(code: "library_access", message: error.localizedDescription, details: nil))
    }
  }
}
