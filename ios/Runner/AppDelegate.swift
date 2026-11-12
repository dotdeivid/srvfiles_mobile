import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SrvFilesDiskSpace") {
      registerDiskSpaceChannel(messenger: registrar.messenger())
    }
  }

  /// Canal com.srvfiles/disk_space: espacio libre y total en MB (igual que
  /// MainActivity.kt en Android).
  private func registerDiskSpaceChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "com.srvfiles/disk_space", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      let url = URL(fileURLWithPath: NSHomeDirectory())
      do {
        let values = try url.resourceValues(forKeys: [
          .volumeAvailableCapacityForImportantUsageKey,
          .volumeTotalCapacityKey,
        ])
        let mb = 1024.0 * 1024.0
        switch call.method {
        case "getFreeDiskSpace":
          result(Double(values.volumeAvailableCapacityForImportantUsage ?? 0) / mb)
        case "getTotalDiskSpace":
          result(Double(values.volumeTotalCapacity ?? 0) / mb)
        default:
          result(FlutterMethodNotImplemented)
        }
      } catch {
        result(FlutterError(code: "UNAVAILABLE", message: error.localizedDescription, details: nil))
      }
    }
  }
}
