import Cocoa
import FlutterMacOS
import Foundation

public class V2RayDanPlugin: NSObject, FlutterPlugin {
  private var eventSink: FlutterEventSink?
  private var v2rayProcess: Process?
  private var isConnected: Bool = false
  private var logs: [String] = []
  
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "v2ray_dan", binaryMessenger: registrar.messenger)
    let eventChannel = FlutterEventChannel(name: "v2ray_dan/status", binaryMessenger: registrar.messenger)
    let instance = V2RayDanPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
    eventChannel.setStreamHandler(instance)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    log("Method called: \(call.method)")
    
    switch call.method {
    case "getPlatformVersion":
      result("macOS " + ProcessInfo.processInfo.operatingSystemVersionString)
      
    case "initialize":
      // Return a temp directory for config/log files
      let filesDir = NSTemporaryDirectory()
      log("Initialize: filesDir = \(filesDir)")
      result(filesDir)
      
    case "requestPermission":
      // macOS proxy mode doesn't need VPN permissions
      log("Permission granted (proxy mode)")
      result(true)
      
    case "startV2Ray":
      startV2Ray(call: call, result: result)
      
    case "stopV2Ray":
      stopV2Ray(result: result)
      
    case "getCoreVersion":
      result("v5.x (macOS stub)")
      
    case "getLogs":
      result(logs)
      
    case "getServerDelay":
      getServerDelay(call: call, result: result)
      
    case "getSystemDns":
      getSystemDns(result: result)
      
    default:
      log("Method not implemented: \(call.method)")
      result(FlutterMethodNotImplemented)
    }
  }
  
  // MARK: - V2Ray Control Methods
  
  private func startV2Ray(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any] else {
      result(FlutterError(code: "INVALID_ARGS", message: "Missing arguments", details: nil))
      return
    }
    
    let remark = args["remark"] as? String ?? "Unknown"
    let config = args["config"] as? String ?? "{}"
    let proxyOnly = args["proxyOnly"] as? Bool ?? true
    
    log("========== Starting V2Ray (macOS) ==========")
    log("Server: \(remark)")
    log("Mode: \(proxyOnly ? "Proxy Only" : "Proxy Only (VPN not available on macOS)")")
    log("Config length: \(config.count) bytes")
    
    // Save config to temp file for debugging
    let configPath = NSTemporaryDirectory() + "v2ray_config.json"
    do {
      try config.write(toFile: configPath, atomically: true, encoding: .utf8)
      log("Config saved to: \(configPath)")
    } catch {
      log("Failed to save config: \(error)")
    }
    
    // For now, we simulate a successful connection
    // Real implementation would need v2ray-core binary embedded in the app
    isConnected = true
    log("========== V2Ray Started (Simulated) ==========")
    log("")
    log("⚠️  NOTE: macOS V2Ray core is not yet implemented.")
    log("   This is a stub that simulates connection.")
    log("   For actual V2Ray on macOS, you need to:")
    log("   1. Embed v2ray-core binary")
    log("   2. Or use XRay-core for macOS")
    log("")
    
    // Notify Flutter that we're "connected"
    DispatchQueue.main.async {
      self.eventSink?("connected")
    }
    
    result(nil)
  }
  
  private func stopV2Ray(result: @escaping FlutterResult) {
    log("Stopping V2Ray...")
    
    // Terminate process if running
    if let process = v2rayProcess, process.isRunning {
      process.terminate()
      v2rayProcess = nil
    }
    
    isConnected = false
    log("V2Ray stopped")
    
    // Notify Flutter
    DispatchQueue.main.async {
      self.eventSink?("disconnected")
    }
    
    result(nil)
  }
  
  private func getServerDelay(call: FlutterMethodCall, result: @escaping FlutterResult) {
    // Simulate a ping test
    // Real implementation would make HTTP request through proxy
    DispatchQueue.global().async {
      // Simulate network delay
      Thread.sleep(forTimeInterval: 0.1)
      
      // Return a simulated delay (random between 50-200ms)
      let delay = Int.random(in: 50...200)
      
      DispatchQueue.main.async {
        result(delay)
      }
    }
  }
  
  private func getSystemDns(result: @escaping FlutterResult) {
    // Get DNS servers from system configuration
    var dnsServers: [String] = []
    
    // Try to read from /etc/resolv.conf
    if let resolvConf = try? String(contentsOfFile: "/etc/resolv.conf", encoding: .utf8) {
      let lines = resolvConf.components(separatedBy: "\n")
      for line in lines {
        if line.hasPrefix("nameserver ") {
          let dns = line.replacingOccurrences(of: "nameserver ", with: "").trimmingCharacters(in: .whitespaces)
          if !dns.isEmpty {
            dnsServers.append(dns)
          }
        }
      }
    }
    
    // If no DNS found, return common defaults
    if dnsServers.isEmpty {
      dnsServers = ["8.8.8.8", "1.1.1.1"]
    }
    
    log("System DNS: \(dnsServers)")
    result(dnsServers)
  }
  
  // MARK: - Logging
  
  private func log(_ message: String) {
    let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
    let logMessage = "[\(timestamp)] [macOS] \(message)"
    print(logMessage)
    logs.append(logMessage)
    
    // Keep only last 100 logs
    if logs.count > 100 {
      logs.removeFirst(logs.count - 100)
    }
  }
}

// MARK: - FlutterStreamHandler

extension V2RayDanPlugin: FlutterStreamHandler {
  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    self.eventSink = events
    log("Event channel listener attached")
    return nil
  }
  
  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    self.eventSink = nil
    log("Event channel listener detached")
    return nil
  }
}
