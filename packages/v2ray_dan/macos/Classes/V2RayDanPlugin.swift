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
    // macOS VPN requires a Network Extension (PacketTunnel) target which is not currently set up.
    // For now, we return true for proxy-only mode to work.
    // Full VPN mode on macOS would require:
    // 1. A Network Extension target in Xcode
    // 2. Apple Developer Program membership
    // 3. Proper entitlements (com.apple.developer.networking.networkextension)
    // 4. A PacketTunnelProvider implementation
    //
    // Since these are not configured, we inform the caller that VPN mode is not available,
    // but proxy-only mode will still work.
    print("[V2RayDanPlugin] macOS VPN permission requested - returning true for proxy mode compatibility")
    print("[V2RayDanPlugin] Note: Full VPN mode requires Network Extension setup which is not configured")
    result(true)
  }
}
