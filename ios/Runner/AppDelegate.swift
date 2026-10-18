import Flutter
import StoreKit
import UIKit
import UserNotifications
import WidgetKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let launched = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    // Set before launch finishes so the tap that opened the app is delivered.
    UNUserNotificationCenter.current().delegate = DailyReminders.shared
    DailyWidgetRefresh.observe()
    return launched
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "DailyReminders") {
      DailyReminders.shared.attach(messenger: registrar.messenger())
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AppReview") {
      AppReview.attach(messenger: registrar.messenger())
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "GiftPush") {
      GiftPush.shared.attach(messenger: registrar.messenger())
    }
  }

  override func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    GiftPush.shared.registered(token: deviceToken)
  }

  override func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
    GiftPush.shared.failed(error)
  }
}

/// Asks the Home Screen widget (ios/DailyWidget) for today's picture again when the game comes to the
/// front, at most once an hour, so a widget that could not load it (offline at midnight, or a build
/// before 127 whose picture was too large to show) shows it as soon as the player opens the game.
/// Reloads asked while the app is in front do not use the widget's daily budget; with no widget on
/// the Home Screen nothing runs.
enum DailyWidgetRefresh {
  private static let key = "dailyWidgetReloadedAt"

  static func observe() {
    NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
      reloadIfDue()
    }
  }

  static func reloadIfDue(now: Date = Date()) {
    let defaults = UserDefaults.standard
    guard now.timeIntervalSince1970 - defaults.double(forKey: key) >= 3600 else { return }
    defaults.set(now.timeIntervalSince1970, forKey: key)
    WidgetCenter.shared.reloadTimelines(ofKind: "DailyWidget")
  }
}

/// Gift notifications from friends (Dart side: lib/core/push.dart; docs/friend-gifts.md). Apple's
/// own push service, no third-party SDK: iOS gives the app a device token, Dart registers it as an
/// Appwrite push target, and Appwrite Messaging sends to it. Permission is the one the daily
/// reminders ask for.
///
/// Channel `cjw/push`: `environment` (the APNs environment of this build's profile: `development`
/// or `production`), `register` (asks iOS for the token; it comes back as `token`, or
/// `tokenError`), `ready` (Dart is listening; returns the link of a notification tap that launched
/// the app). A tap while Dart listens is sent as `open` with the notification's link, and a
/// notification that arrives while the game is open as `received` ({title, body, link}).
final class GiftPush {
  static let shared = GiftPush()

  private var channel: FlutterMethodChannel?
  private var dartReady = false
  private var pendingLink: String?
  private var token: String?

  func attach(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "cjw/push", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return result(nil) }
      switch call.method {
      case "environment":
        result(Self.environment)
      case "register":
        UIApplication.shared.registerForRemoteNotifications()
        // iOS calls back with the token (on every launch too); a token from earlier goes now.
        if let token = self.token { self.channel?.invokeMethod("token", arguments: token) }
        result(nil)
      case "ready":
        self.dartReady = true
        result(self.pendingLink)
        self.pendingLink = nil
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.channel = channel
  }

  func registered(token data: Data) {
    let hex = data.map { String(format: "%02x", $0) }.joined()
    token = hex
    channel?.invokeMethod("token", arguments: hex)
  }

  func failed(_ error: Error) {
    channel?.invokeMethod("tokenError", arguments: error.localizedDescription)
  }

  /// A tapped notification: its link goes to Dart now, or when Dart is ready (a cold start).
  func opened(_ notification: UNNotification) {
    guard let link = Self.link(of: notification.request.content.userInfo) else { return }
    if dartReady, let channel {
      channel.invokeMethod("open", arguments: link)
    } else {
      pendingLink = link
    }
  }

  /// A notification while the game is open: Dart refreshes the inbox and shows a toast.
  func received(_ notification: UNNotification) {
    let content = notification.request.content
    channel?.invokeMethod("received", arguments: [
      "title": content.title,
      "body": content.body,
      "link": Self.link(of: content.userInfo) ?? "",
    ])
  }

  static func isRemote(_ notification: UNNotification) -> Bool {
    notification.request.trigger is UNPushNotificationTrigger
  }

  /// Appwrite Messaging puts a push's data under `data` (the APNs adapter of utopia-php/messaging).
  private static func link(of userInfo: [AnyHashable: Any]) -> String? {
    let link = (userInfo["data"] as? [String: Any])?["link"] as? String ?? userInfo["link"] as? String
    return link?.isEmpty == false ? link : nil
  }

  /// The APNs environment this build's tokens belong to, from the `aps-environment` of the
  /// embedded provisioning profile. Simulators use the development service; App Store and
  /// TestFlight builds carry no embedded profile and use the production one.
  static var environment: String {
    #if targetEnvironment(simulator)
    return "development"
    #else
    guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
          let data = try? Data(contentsOf: url),
          let start = data.range(of: Data("<?xml".utf8)),
          let end = data.range(of: Data("</plist>".utf8)),
          start.lowerBound < end.upperBound,
          let plist = try? PropertyListSerialization.propertyList(from: data.subdata(in: start.lowerBound..<end.upperBound), format: nil) as? [String: Any],
          let entitlements = plist["Entitlements"] as? [String: Any],
          let value = entitlements["aps-environment"] as? String
    else { return "production" }
    return value
    #endif
  }
}

/// App Store rating prompt (Dart side: lib/core/app_review.dart). StoreKit decides whether the
/// prompt really appears (at most three times a year per person) and talks only to Apple.
///
/// Channel `cjw/review`: `request` asks StoreKit in the active window scene; answers whether a
/// scene was there to ask in (not whether the prompt showed: StoreKit never says).
enum AppReview {
  private static var channel: FlutterMethodChannel?

  static func attach(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "cjw/review", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "request" else { return result(FlutterMethodNotImplemented) }
      let scene = UIApplication.shared.connectedScenes
        .first { $0.activationState == .foregroundActive } as? UIWindowScene
      guard let scene else { return result(false) }
      if #available(iOS 16.0, *) {
        AppStore.requestReview(in: scene)
      } else {
        SKStoreReviewController.requestReview(in: scene)
      }
      result(true)
    }
    self.channel = channel
  }
}

/// Daily reminders (Dart side: lib/core/reminders.dart). Local notifications
/// only: they are scheduled on the device and nothing leaves it.
///
/// Channel `cjw/reminders`: `status`, `request`, `schedule` (replaces every
/// pending reminder), `cancel`, `pending` and `delivered` (read back, for
/// QA), `openSettings`, `ready` (Dart is listening; returns the route of a
/// tap that launched the app). A tap while Dart is listening is sent back
/// as `open` with the reminder's route.
final class DailyReminders: NSObject, UNUserNotificationCenterDelegate {
  static let shared = DailyReminders()
  private static let prefix = "cjw.reminder."

  private var channel: FlutterMethodChannel?
  private var dartReady = false
  private var pendingRoute: String?

  func attach(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "cjw/reminders", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    self.channel = channel
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let center = UNUserNotificationCenter.current()
    switch call.method {
    case "status":
      center.getNotificationSettings { settings in
        let status: String
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: status = "granted"
        case .denied: status = "denied"
        default: status = "notDetermined"
        }
        DispatchQueue.main.async { result(status) }
      }
    case "request":
      // QA runs ask quietly (provisional: no prompt, delivered to Notification Center).
      let quiet = (call.arguments as? [String: Any])?["quiet"] as? Bool ?? false
      let options: UNAuthorizationOptions = quiet ? [.alert, .sound, .provisional] : [.alert, .sound]
      center.requestAuthorization(options: options) { granted, _ in
        DispatchQueue.main.async { result(granted) }
      }
    case "pending":
      center.getPendingNotificationRequests { pending in
        let items: [[String: Any]] = pending.filter { $0.identifier.hasPrefix(Self.prefix) }.map { request in
          let next = (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
          return Self.describe(request, at: next)
        }
        DispatchQueue.main.async { result(items) }
      }
    case "delivered":
      center.getDeliveredNotifications { delivered in
        let items: [[String: Any]] = delivered.filter { $0.request.identifier.hasPrefix(Self.prefix) }.map {
          Self.describe($0.request, at: $0.date)
        }
        DispatchQueue.main.async { result(items) }
      }
    case "schedule":
      let items = call.arguments as? [[String: Any]] ?? []
      schedule(items, center: center) { result(nil) }
    case "cancel":
      schedule([], center: center) { result(nil) }
    case "openSettings":
      let page: String
      if #available(iOS 16.0, *) {
        page = UIApplication.openNotificationSettingsURLString
      } else {
        page = UIApplication.openSettingsURLString
      }
      if let url = URL(string: page) { UIApplication.shared.open(url) }
      result(nil)
    case "ready":
      dartReady = true
      result(pendingRoute)
      pendingRoute = nil
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// A reminder as Dart reads it back (QA checks what is scheduled and delivered).
  private static func describe(_ request: UNNotificationRequest, at date: Date?) -> [String: Any] {
    [
      "id": String(request.identifier.dropFirst(prefix.count)),
      "title": request.content.title,
      "body": request.content.body,
      "route": request.content.userInfo["route"] as? String ?? "",
      "at": (date?.timeIntervalSince1970 ?? 0) * 1000,
    ]
  }

  /// Replaces the pending reminders with [items] ({id, at (ms since epoch),
  /// title, body, route}); ids are days, so a day keeps one reminder.
  private func schedule(_ items: [[String: Any]], center: UNUserNotificationCenter, done: @escaping () -> Void) {
    let ids = Set(items.compactMap { $0["id"] as? String }.map { Self.prefix + $0 })
    center.getPendingNotificationRequests { pending in
      let stale = pending.map(\.identifier).filter { $0.hasPrefix(Self.prefix) && !ids.contains($0) }
      center.removePendingNotificationRequests(withIdentifiers: stale)
      for item in items {
        guard let id = item["id"] as? String, let at = item["at"] as? NSNumber,
              let title = item["title"] as? String, let body = item["body"] as? String else { continue }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = "daily"
        content.userInfo = ["route": item["route"] as? String ?? ""]
        let date = Date(timeIntervalSince1970: at.doubleValue / 1000)
        let when = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: false)
        center.add(UNNotificationRequest(identifier: Self.prefix + id, content: content, trigger: trigger))
      }
      DispatchQueue.main.async { done() }
    }
  }

  // The player is already in the game: no banner while it is open (a gift notification shows as
  // a toast instead, see GiftPush).
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if GiftPush.isRemote(notification) { GiftPush.shared.received(notification) }
    completionHandler([])
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    // Gift notifications come from the server and carry a link instead of a route.
    if GiftPush.isRemote(response.notification) {
      GiftPush.shared.opened(response.notification)
      completionHandler()
      return
    }
    let route = response.notification.request.content.userInfo["route"] as? String ?? ""
    if !route.isEmpty {
      if dartReady, let channel {
        channel.invokeMethod("open", arguments: route)
      } else {
        pendingRoute = route
      }
    }
    completionHandler()
  }
}

// MARK: - Shake to send feedback

/// A shake of the iPhone opens the game's feedback form (Dart side: lib/core/shake.dart and
/// lib/features/profile/shake_feedback.dart; Settings > Help > Shake to send feedback turns it off).
/// UIKit sends a shake to the key window's first responder (the Flutter view, or the text field being
/// typed in) and on up the responder chain to the window, where it arrives with or without a first
/// responder. Not on this delegate: UIApplication, further up, keeps shakes for shake-to-undo and
/// never passes them on (checked on the simulator, 2026-10-18).
extension UIWindow {
  override open func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
    if motion == .motionShake, isKeyWindow { ShakeToFeedback.shaken(in: self) }
    super.motionEnded(motion, with: event)
  }
}

/// Channel `cjw/shake`: `shake` (no arguments) to Dart. Sent only while the game itself is on top:
/// not under a system alert, the share sheet or any other screen iOS presents over Flutter.
enum ShakeToFeedback {
  static func shaken(in window: UIWindow) {
    guard let flutter = window.rootViewController as? FlutterViewController,
          flutter.presentedViewController == nil
    else { return }
    FlutterMethodChannel(name: "cjw/shake", binaryMessenger: flutter.binaryMessenger).invokeMethod("shake", arguments: nil)
  }
}
