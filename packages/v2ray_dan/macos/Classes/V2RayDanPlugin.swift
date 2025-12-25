import Cocoa
import FlutterMacOS
import NetworkExtension

public class V2RayDanPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "v2ray_dan", binaryMessenger: registrar.messenger)
    let instance = V2RayDanPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      result("macOS " + ProcessInfo.processInfo.operatingSystemVersionString)
    case "requestPermission":
      requestPermission(result: result)
    case "initialize":
      // On macOS, initialization might differ (filesDir, etc)
      result("/tmp") 
    case "stopV2Ray":
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func requestPermission(result: @escaping FlutterResult) {
    // On macOS, we check if the VPN configuration is present and enabled
    if #available(OSX 10.11, *) {
        NETunnelProviderManager.loadAllFromPreferences { (managers: [NETunnelProviderManager]?, error: Error?) in
            if let error = error {
                result(FlutterError(code: "PERMISSION_ERROR", message: error.localizedDescription, details: nil))
                return
            }
            
            if let managers = managers, !managers.isEmpty {
                // If we have at least one manager, we consider it "permission granted" for now
                // Technically we should check if it's enabled and matches our bundle ID
                result(true)
            } else {
                // No configuration found. We should probably create one to "request" permission
                self.createConfig(result: result)
            }
        }
    } else {
        result(FlutterError(code: "UNSUPPORTED", message: "macOS version not supported", details: nil))
    }
  }

  private func createConfig(result: @escaping FlutterResult) {
      let manager = NETunnelProviderManager()
      manager.localizedDescription = "Flaming Cherubim"
      
      let protocolConfiguration = NETunnelProviderProtocol()
      protocolConfiguration.providerBundleIdentifier = "com.flaming.cherubim.PacketTunnel"
      protocolConfiguration.serverAddress = "127.0.0.1"
      
      manager.protocolConfiguration = protocolConfiguration
      manager.isEnabled = true
      
      manager.saveToPreferences { error in
          if let error = error {
              result(FlutterError(code: "PERMISSION_DENIED", message: "Failed to save VPN configuration: \(error.localizedDescription)", details: nil))
          } else {
              // Successfully saved (requested)
              result(true)
          }
      }
  }
}
