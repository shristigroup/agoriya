import Flutter
import UIKit
import Firebase
import FirebaseAuth

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    FirebaseApp.configure()
    GeneratedPluginRegistrant.register(with: self)

    // Read-only iOS background diagnostics for DeviceInfoService (Dart).
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "com.agoriya.app/ios_diag",
        binaryMessenger: controller.binaryMessenger)
      channel.setMethodCallHandler { call, result in
        guard call.method == "state" else {
          result(FlutterMethodNotImplemented)
          return
        }
        let refresh: String
        switch UIApplication.shared.backgroundRefreshStatus {
        case .available: refresh = "available"
        case .denied: refresh = "denied"
        case .restricted: refresh = "restricted"
        @unknown default: refresh = "unknown"
        }
        result([
          "backgroundRefresh": refresh,
          "lowPowerMode": ProcessInfo.processInfo.isLowPowerModeEnabled,
        ])
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Forward APNs device token to Firebase — required for Phone Auth.
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    Auth.auth().setAPNSToken(deviceToken, type: .unknown)
  }

  // Forward silent APNs notifications to Firebase — used for phone number verification.
  override func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    if Auth.auth().canHandleNotification(userInfo) {
      completionHandler(.noData)
      return
    }
    // Not a Firebase notification — let Flutter handle it.
    super.application(application, didReceiveRemoteNotification: userInfo, fetchCompletionHandler: completionHandler)
  }

  // Handle reCAPTCHA redirect URL (fallback when APNs is not configured).
  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if Auth.auth().canHandle(url) {
      return true
    }
    return super.application(app, open: url, options: options)
  }
}
