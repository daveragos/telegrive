import Flutter
import UIKit
import UserNotifications
import BackgroundTasks

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // FlutterAppDelegate passes notification callbacks on to plugins, so
    // flutter_local_notifications can show alerts while the app is open and
    // hear when one is tapped.
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "DeviceStorage") {
      DeviceStorage.register(with: registrar.messenger())
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BackgroundTransfers") {
      BackgroundTransfers.register(with: registrar.messenger())
    }
  }
}

/// Keeps the transfers the person started going when Telegrive leaves the
/// screen. iOS suspends an app soon after, and TDLib's uploads stop with
/// it. From iOS 26 a continued processing task carries a task the person
/// started on in the background, as long as it says how far along it is;
/// iOS shows that progress itself, on the Lock Screen and in the Dynamic
/// Island, and the person can stop it there. Before iOS 26 there is only
/// the half minute or so iOS gives any app that asks.
///
/// Dart says begin, update and end, as transfers start, move and finish;
/// iOS ending the task early is told back as stopped.
enum BackgroundTransfers {
  private static var channel: FlutterMethodChannel?

  /// Whether Dart wants a task: a request iOS starts late finds out.
  private static var wanted = false
  private static var title = "Telegrive"
  private static var subtitle = ""
  private static var done: Int64 = 0
  private static var total: Int64 = 1000

  /// The running task, as an `Any` since its class is iOS 26's alone.
  private static var task: Any?
  private static var legacyTask: UIBackgroundTaskIdentifier = .invalid

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "telegrive/background_transfers", binaryMessenger: messenger)
    self.channel = channel
    channel.setMethodCallHandler { call, result in
      let args = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "begin":
        take(args)
        result(begin())
      case "update":
        take(args)
        update()
        result(nil)
      case "end":
        end(success: args["success"] as? Bool ?? true)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func take(_ args: [String: Any]) {
    if let value = args["title"] as? String { title = value }
    if let value = args["subtitle"] as? String { subtitle = value }
    if let value = args["done"] as? NSNumber { done = value.int64Value }
    if let value = args["total"] as? NSNumber { total = max(1, value.int64Value) }
  }

  private static func begin() -> Bool {
    wanted = true
    if #available(iOS 26.0, *) {
      if task != nil { return true }
      let identifier = "\(Bundle.main.bundleIdentifier ?? "dev.ragoose.telegrive").transfers.\(UUID().uuidString)"
      let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { started in
        DispatchQueue.main.async { run(started) }
      }
      guard registered else { return beginLegacy() }
      let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: title, subtitle: subtitle)
      request.strategy = .fail
      do {
        try BGTaskScheduler.shared.submit(request)
        return true
      } catch {
        NSLog("[BackgroundTransfers] Could not ask to carry on: \(error)")
        return beginLegacy()
      }
    }
    return beginLegacy()
  }

  @available(iOS 26.0, *)
  private static func run(_ started: BGTask) {
    guard let continued = started as? BGContinuedProcessingTask else {
      started.setTaskCompleted(success: false)
      return
    }
    // Ended before iOS got to it.
    guard wanted else {
      continued.setTaskCompleted(success: true)
      return
    }
    task = continued
    continued.expirationHandler = {
      DispatchQueue.main.async {
        guard let current = task as? BGContinuedProcessingTask, current === continued else { return }
        task = nil
        continued.setTaskCompleted(success: false)
        channel?.invokeMethod("stopped", arguments: nil)
      }
    }
    update()
  }

  private static func update() {
    if #available(iOS 26.0, *), let continued = task as? BGContinuedProcessingTask {
      continued.progress.totalUnitCount = total
      continued.progress.completedUnitCount = min(done, total)
      continued.updateTitle(title, subtitle: subtitle)
    }
  }

  private static func end(success: Bool) {
    wanted = false
    if #available(iOS 26.0, *), let continued = task as? BGContinuedProcessingTask {
      continued.progress.completedUnitCount = continued.progress.totalUnitCount
      continued.setTaskCompleted(success: success)
    }
    task = nil
    endLegacy()
  }

  /// The few seconds any app gets, for iOS before 26 or a request it turns
  /// down: enough for a small file under way to finish.
  private static func beginLegacy() -> Bool {
    if legacyTask != .invalid { return true }
    legacyTask = UIApplication.shared.beginBackgroundTask(withName: "Transfers") {
      endLegacy()
      channel?.invokeMethod("stopped", arguments: nil)
    }
    return legacyTask != .invalid
  }

  private static func endLegacy() {
    guard legacyTask != .invalid else { return }
    UIApplication.shared.endBackgroundTask(legacyTask)
    legacyTask = .invalid
  }
}

/// Space left on the phone, checked before a big download to it. Saving
/// itself is plain file copying into Documents, done from Dart.
enum DeviceStorage {
  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "telegrive/device_storage", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "freeBytes":
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let bytes = values?.volumeAvailableCapacityForImportantUsage {
          result(NSNumber(value: bytes))
        } else {
          result(nil)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
