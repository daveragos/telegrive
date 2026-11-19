import Cocoa
import FlutterMacOS
import window_manager

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    // Telegrive has one window, so View has no Show Tab Bar for it.
    NSWindow.allowsAutomaticWindowTabbing = false
    self.tabbingMode = .disallowed

    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // The files Finder or another app copied, as paths, for Paste to upload.
    let clipboard = FlutterMethodChannel(
      name: "telegrive/clipboard",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    clipboard.setMethodCallHandler { call, result in
      guard call.method == "files" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let urls = NSPasteboard.general.readObjects(
        forClasses: [NSURL.self],
        options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
      result(urls.map { $0.path })
    }

    super.awakeFromNib()
  }

  // The window stays hidden until the app has put it where it was left,
  // so it doesn't open at one size and jump to another.
  override public func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
    super.order(place, relativeTo: otherWin)
    hiddenWindowAtLaunch()
  }
}
