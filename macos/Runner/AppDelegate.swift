import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  // Closing the window is the app's to decide: it hides the window while
  // Telegrive keeps running in the menu bar, and otherwise quits from Dart,
  // closing TDLib on the way out.
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  // Opening Telegrive while it runs with its window hidden in the menu bar
  // brings the window back, with the app in the Dock again.
  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag {
      NSApp.setActivationPolicy(.regular)
      for window in sender.windows {
        window.makeKeyAndOrderFront(self)
      }
      NSApp.activate(ignoringOtherApps: true)
    }
    return true
  }
}
