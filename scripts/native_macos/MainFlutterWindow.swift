import Cocoa
import FlutterMacOS
import multiview_desktop

class MainFlutterWindow: NSWindow {
  private var pluginRegistry: MainWindowPluginRegistry?

  override func awakeFromNib() {
    let engine = FlutterEngine(name: "main_flutter_engine", project: nil, allowHeadlessExecution: true)
    MultiviewDesktopPlugin.prepareEngine(engine, window: self)
    let controller = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
    let windowFrame = frame
    contentViewController = controller
    setFrame(windowFrame, display: false)

    // Legacy plugins (notably window_manager) request the implicit view, which
    // is absent in a multi-view engine. Bind their registrar to this main view.
    let registry = MainWindowPluginRegistry(controller)
    pluginRegistry = registry
    RegisterGeneratedPlugins(registry: registry)
    super.awakeFromNib()
  }
}

private class MainWindowPluginRegistry: NSObject, FlutterPluginRegistry {
  private weak var controller: FlutterViewController?

  init(_ controller: FlutterViewController) {
    self.controller = controller
  }

  func registrar(forPlugin pluginKey: String) -> FlutterPluginRegistrar {
    return MainWindowPluginRegistrar(controller!.registrar(forPlugin: pluginKey), controller!)
  }

  func valuePublished(byPlugin pluginKey: String) -> NSObject? {
    return controller?.valuePublished(byPlugin: pluginKey)
  }
}

private class MainWindowPluginRegistrar: NSObject, FlutterPluginRegistrar {
  private let base: FlutterPluginRegistrar
  private weak var controller: FlutterViewController?

  init(_ base: FlutterPluginRegistrar, _ controller: FlutterViewController) {
    self.base = base
    self.controller = controller
  }

  var messenger: FlutterBinaryMessenger { base.messenger }
  var textures: FlutterTextureRegistry { base.textures }
  var view: NSView? { controller?.view }
  var viewController: NSViewController? { controller }

  func addMethodCallDelegate(_ delegate: FlutterPlugin, channel: FlutterMethodChannel) {
    base.addMethodCallDelegate(delegate, channel: channel)
  }

  func addApplicationDelegate(_ delegate: FlutterAppLifecycleDelegate) {
    base.addApplicationDelegate(delegate)
  }

  func register(_ factory: FlutterPlatformViewFactory, withId factoryId: String) {
    base.register(factory, withId: factoryId)
  }

  func publish(_ value: NSObject) { base.publish(value) }
  func lookupKey(forAsset asset: String) -> String { base.lookupKey(forAsset: asset) }
  func lookupKey(forAsset asset: String, fromPackage package: String) -> String {
    base.lookupKey(forAsset: asset, fromPackage: package)
  }
}
