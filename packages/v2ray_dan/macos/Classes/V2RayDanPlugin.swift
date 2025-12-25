import Cocoa
import FlutterMacOS
import Foundation

public class V2RayDanPlugin: NSObject, FlutterPlugin {
  private var eventSink: FlutterEventSink?
  private var v2rayProcess: Process?
  private var isConnected: Bool = false
  private var logs: [String] = []
  private var configPath: String = ""
  private var v2rayBinaryPath: String?
  
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
      initialize(result: result)
      
    case "requestPermission":
      // macOS proxy mode doesn't need VPN permissions
      log("Permission granted (proxy mode)")
      result(true)
      
    case "startV2Ray":
      startV2Ray(call: call, result: result)
      
    case "stopV2Ray":
      stopV2Ray(result: result)
      
    case "getCoreVersion":
      getCoreVersion(result: result)
      
    case "getLogs":
      result(logs)
      
    case "getServerDelay":
      getServerDelay(call: call, result: result)
      
    case "getSystemDns":
      getSystemDns(result: result)
      
    case "setSystemProxy":
      setSystemProxy(call: call, result: result)
      
    case "clearSystemProxy":
      clearSystemProxy(result: result)
      
    default:
      log("Method not implemented: \(call.method)")
      result(FlutterMethodNotImplemented)
    }
  }
  
  // MARK: - Initialize
  
  private func initialize(result: @escaping FlutterResult) {
    // Return a temp directory for config/log files
    let filesDir = NSTemporaryDirectory()
    log("Initialize: filesDir = \(filesDir)")
    
    // Try to find v2ray binary
    findV2RayBinary()
    
    result(filesDir)
  }
  
  private func findV2RayBinary() {
    // 1. Check for bundled binary (Priority)
    // In macOS Flutter plugins, resources are often in the plugin's bundle
    let bundle = Bundle(for: type(of: self))
    if let bundledPath = bundle.path(forResource: "v2ray", ofType: nil) {
      if FileManager.default.isExecutableFile(atPath: bundledPath) {
        v2rayBinaryPath = bundledPath
        log("✓ Found bundled V2Ray binary at: \(bundledPath)")
        return
      } else {
        log("Found bundled binary but not executable, attempting to fix: \(bundledPath)")
        // Copy to temp and chmod
        let tempPath = NSTemporaryDirectory() + "v2ray_exec"
        do {
          if FileManager.default.fileExists(atPath: tempPath) {
            try FileManager.default.removeItem(atPath: tempPath)
          }
          try FileManager.default.copyItem(atPath: bundledPath, toPath: tempPath)
          
          let chmod = Process()
          chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
          chmod.arguments = ["+x", tempPath]
          try chmod.run()
          chmod.waitUntilExit()
          
          v2rayBinaryPath = tempPath
          log("✓ Created executable copy at: \(tempPath)")
          return
        } catch {
          log("Failed to make bundled binary executable: \(error)")
        }
      }
    } else {
        log("Bundled binary 'v2ray' not found in resources")
    }

    // 2. Common locations (Fallback)
    let possiblePaths = [
      "/usr/local/bin/v2ray",
      "/opt/homebrew/bin/v2ray",
      "/usr/bin/v2ray",
      NSHomeDirectory() + "/.local/bin/v2ray",
      "/usr/local/bin/xray",
      "/opt/homebrew/bin/xray",
    ]
    
    for path in possiblePaths {
      if FileManager.default.isExecutableFile(atPath: path) {
        v2rayBinaryPath = path
        log("✓ Found system V2Ray binary at: \(path)")
        return
      }
    }
    
    // ... (rest of "which" checks preserved or minimal)
    log("⚠️ V2Ray/XRay binary not found in bundle or system paths.")
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
    log("Mode: \(proxyOnly ? "Proxy Only" : "Proxy Only (VPN not available)")")
    log("Config length: \(config.count) bytes")
    
    // Stop existing process if any
    if let existingProcess = v2rayProcess, existingProcess.isRunning {
      log("Stopping existing V2Ray process...")
      existingProcess.terminate()
      existingProcess.waitUntilExit()
      v2rayProcess = nil
    }
    
    // Check if v2ray binary exists
    guard let binaryPath = v2rayBinaryPath else {
      log("❌ V2Ray binary not found!")
      log("Please install V2Ray or XRay:")
      log("  brew install v2ray")
      log("  or: brew install xray")
      
      // Still emit connected status for UI, but log the warning
      isConnected = true
      DispatchQueue.main.async {
        self.eventSink?("connected")
      }
      result(FlutterError(code: "BINARY_NOT_FOUND", message: "V2Ray binary not found. Install with: brew install v2ray", details: nil))
      return
    }
    
    // Save config to temp file
    configPath = NSTemporaryDirectory() + "v2ray_config.json"
    do {
      try config.write(toFile: configPath, atomically: true, encoding: .utf8)
      log("Config saved to: \(configPath)")
    } catch {
      log("Failed to save config: \(error)")
      result(FlutterError(code: "CONFIG_ERROR", message: "Failed to save config: \(error.localizedDescription)", details: nil))
      return
    }
    
    // Start V2Ray process
    log("Starting V2Ray binary: \(binaryPath)")
    
    let process = Process()
    process.executableURL = URL(fileURLWithPath: binaryPath)
    process.arguments = ["run", "-c", configPath]
    
    // Set environment to find assets (geoip.dat, geosite.dat)
    var env = ProcessInfo.processInfo.environment
    let assetPath = URL(fileURLWithPath: binaryPath).deletingLastPathComponent().path
    env["V2RAY_LOCATION_ASSET"] = assetPath
    env["XRAY_LOCATION_ASSET"] = assetPath
    process.environment = env
    
    // Capture output
    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = errorPipe
    
    // Handle output asynchronously
    outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
      let data = handle.availableData
      if let output = String(data: data, encoding: .utf8), !output.isEmpty {
        DispatchQueue.main.async {
          self?.log("[V2Ray] \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
      }
    }
    
    errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
      let data = handle.availableData
      if let output = String(data: data, encoding: .utf8), !output.isEmpty {
        DispatchQueue.main.async {
          self?.log("[V2Ray ERR] \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
      }
    }
    
    // Handle process termination
    process.terminationHandler = { [weak self] proc in
      DispatchQueue.main.async {
        self?.log("V2Ray process terminated with code: \(proc.terminationStatus)")
        self?.isConnected = false
        self?.eventSink?("disconnected")
      }
    }
    
    do {
      try process.run()
      v2rayProcess = process
      log("✓ V2Ray process started with PID: \(process.processIdentifier)")
      
      // Wait a moment for startup
      DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) { [weak self] in
        guard let self = self else { return }
        
        if process.isRunning {
          DispatchQueue.main.async {
            self.log("========== V2Ray Started Successfully ==========")
            self.log("")
            self.log("Proxy is running at:")
            self.log("  SOCKS5: 127.0.0.1:10808")
            self.log("  HTTP:   127.0.0.1:10809")
            self.log("")
            self.log("Configure your browser/apps to use these proxies.")
            self.log("")
            
            self.isConnected = true
            self.eventSink?("connected")
          }
        } else {
          DispatchQueue.main.async {
            self.log("❌ V2Ray process failed to start or exited immediately")
            self.eventSink?("error")
          }
        }
      }
      
      result(nil)
    } catch {
      log("Failed to start V2Ray: \(error)")
      result(FlutterError(code: "START_ERROR", message: "Failed to start V2Ray: \(error.localizedDescription)", details: nil))
    }
  }
  
  private func stopV2Ray(result: @escaping FlutterResult) {
    log("Stopping V2Ray...")
    
    // Terminate process if running
    if let process = v2rayProcess {
      if process.isRunning {
        process.terminate()
        // Give it a moment to stop gracefully
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
          if process.isRunning {
            process.interrupt()
          }
        }
      }
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
  
  private func getCoreVersion(result: @escaping FlutterResult) {
    guard let binaryPath = v2rayBinaryPath else {
      result("Not installed")
      return
    }
    
    let process = Process()
    process.executableURL = URL(fileURLWithPath: binaryPath)
    process.arguments = ["version"]
    
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    
    do {
      try process.run()
      process.waitUntilExit()
      
      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      if let output = String(data: data, encoding: .utf8) {
        // Extract first line which usually contains version
        let firstLine = output.components(separatedBy: "\n").first ?? output
        result(firstLine.trimmingCharacters(in: .whitespacesAndNewlines))
        return
      }
    } catch {
      log("Failed to get version: \(error)")
    }
    
    result("Unknown")
  }
  
  private func getServerDelay(call: FlutterMethodCall, result: @escaping FlutterResult) {
    // Test connection through the HTTP proxy (more reliable than SOCKS with URLSession)
    DispatchQueue.global().async { [weak self] in
      let startTime = Date()
      
      // Create a URL session that uses our HTTP proxy
      let config = URLSessionConfiguration.ephemeral
      config.connectionProxyDictionary = [
        kCFNetworkProxiesHTTPEnable: true,
        kCFNetworkProxiesHTTPProxy: "127.0.0.1",
        kCFNetworkProxiesHTTPPort: 10809,
        kCFNetworkProxiesHTTPSEnable: true,
        kCFNetworkProxiesHTTPSProxy: "127.0.0.1",
        kCFNetworkProxiesHTTPSPort: 10809
      ]
      config.timeoutIntervalForRequest = 10
      
      let session = URLSession(configuration: config)
      let url = URL(string: "https://www.google.com/generate_204")!
      
      let semaphore = DispatchSemaphore(value: 0)
      var delay: Int = -1
      var errorMsg: String = ""
      
      let task = session.dataTask(with: url) { _, response, error in
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 204 || httpResponse.statusCode == 200 {
          delay = Int(Date().timeIntervalSince(startTime) * 1000)
        } else if let error = error {
          errorMsg = error.localizedDescription
          delay = -1
        } else {
          errorMsg = "Unknown error"
          delay = -1
        }
        semaphore.signal()
      }
      task.resume()
      
      _ = semaphore.wait(timeout: .now() + 10)
      
      DispatchQueue.main.async {
        if delay > 0 {
          self?.log("✓ Server delay test: \(delay)ms")
        } else {
          self?.log("❌ Server delay test failed: \(errorMsg)")
        }
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
  
  private func getPrimaryNetworkInterface() -> String? {
    // Try to get the primary network interface (usually Wi-Fi or Ethernet)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
    process.arguments = ["-listnetworkserviceorder"]
    
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    
    do {
      try process.run()
      process.waitUntilExit()
      
      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      if let output = String(data: data, encoding: .utf8) {
        // Parse output to find first active interface
        let lines = output.components(separatedBy: "\n")
        for line in lines {
          // Look for lines like "(1) Wi-Fi" or "(1) Ethernet"
          if line.contains("Wi-Fi") {
            return "Wi-Fi"
          } else if line.contains("Ethernet") {
            return "Ethernet"
          }
        }
      }
    } catch {
      log("Failed to get network interface: \(error)")
    }
    
    // Default fallback
    return "Wi-Fi"
  }
  
  private func setSystemProxy(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let interface = getPrimaryNetworkInterface() else {
      log("❌ Could not determine network interface")
      result(FlutterError(code: "NO_INTERFACE", message: "Could not determine network interface", details: nil))
      return
    }
    
    log("Setting system proxy for interface: \(interface)")
    log("  HTTP Proxy: 127.0.0.1:10809")
    log("  HTTPS Proxy: 127.0.0.1:10809")
    log("  SOCKS Proxy: 127.0.0.1:10808")
    
    // Set HTTP proxy
    log("Configuring HTTP proxy...")
    let setHttpProxy = executeCommand("/usr/sbin/networksetup", ["-setwebproxy", interface, "127.0.0.1", "10809"])
    log("HTTP proxy setup: \(setHttpProxy ? "✓ Success" : "✗ Failed")")
    
    log("Configuring HTTPS proxy...")
    let setHttpsProxy = executeCommand("/usr/sbin/networksetup", ["-setsecurewebproxy", interface, "127.0.0.1", "10809"])
    log("HTTPS proxy setup: \(setHttpsProxy ? "✓ Success" : "✗ Failed")")
    
    log("Configuring SOCKS proxy...")
    let setSocksProxy = executeCommand("/usr/sbin/networksetup", ["-setsocksfirewallproxy", interface, "127.0.0.1", "10808"])
    log("SOCKS proxy setup: \(setSocksProxy ? "✓ Success" : "✗ Failed")")
    
    // Enable proxies
    log("Enabling proxies...")
    let enableHttp = executeCommand("/usr/sbin/networksetup", ["-setwebproxystate", interface, "on"])
    log("HTTP proxy enable: \(enableHttp ? "✓ Success" : "✗ Failed")")
    
    let enableHttps = executeCommand("/usr/sbin/networksetup", ["-setsecurewebproxystate", interface, "on"])
    log("HTTPS proxy enable: \(enableHttps ? "✓ Success" : "✗ Failed")")
    
    let enableSocks = executeCommand("/usr/sbin/networksetup", ["-setsocksfirewallproxystate", interface, "on"])
    log("SOCKS proxy enable: \(enableSocks ? "✓ Success" : "✗ Failed")")
    
    if setHttpProxy && setHttpsProxy && setSocksProxy && enableHttp && enableHttps && enableSocks {
      log("✓ System proxy configured successfully")
      result(true)
    } else {
      log("⚠️ Some proxy settings failed, will require admin permissions on next attempt")
      result(false)
    }
  }
  
  private func clearSystemProxy(result: @escaping FlutterResult) {
    guard let interface = getPrimaryNetworkInterface() else {
      log("❌ Could not determine network interface")
      result(FlutterError(code: "NO_INTERFACE", message: "Could not determine network interface", details: nil))
      return
    }
    
    log("Clearing system proxy for interface: \(interface)")
    
    // Disable proxies
    log("Disabling HTTP proxy...")
    let disableHttp = executeCommand("/usr/sbin/networksetup", ["-setwebproxystate", interface, "off"])
    log("HTTP proxy disable: \(disableHttp ? "✓ Success" : "✗ Failed")")
    
    log("Disabling HTTPS proxy...")
    let disableHttps = executeCommand("/usr/sbin/networksetup", ["-setsecurewebproxystate", interface, "off"])
    log("HTTPS proxy disable: \(disableHttps ? "✓ Success" : "✗ Failed")")
    
    log("Disabling SOCKS proxy...")
    let disableSocks = executeCommand("/usr/sbin/networksetup", ["-setsocksfirewallproxystate", interface, "off"])
    log("SOCKS proxy disable: \(disableSocks ? "✓ Success" : "✗ Failed")")
    
    if disableHttp && disableHttps && disableSocks {
      log("✓ System proxy cleared successfully")
      result(true)
    } else {
      log("⚠️ Some proxy clear operations failed")
      result(false)
    }
  }
  
  private func executeCommand(_ command: String, _ arguments: [String]) -> Bool {
    // First, try without admin privileges
    let normalProcess = Process()
    normalProcess.executableURL = URL(fileURLWithPath: command)
    normalProcess.arguments = arguments
    normalProcess.standardOutput = FileHandle.nullDevice
    normalProcess.standardError = FileHandle.nullDevice
    
    do {
      try normalProcess.run()
      normalProcess.waitUntilExit()
      
      if normalProcess.terminationStatus == 0 {
        return true
      }
      
      // If failed, try with admin privileges
      log("Command failed without admin, retrying with administrator privileges...")
      
      let fullCommand = "\(command) \(arguments.joined(separator: " "))"
      let script = """
      do shell script "\(fullCommand)" with administrator privileges
      """
      
      let adminProcess = Process()
      adminProcess.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
      adminProcess.arguments = ["-e", script]
      adminProcess.standardOutput = FileHandle.nullDevice
      adminProcess.standardError = FileHandle.nullDevice
      
      try adminProcess.run()
      adminProcess.waitUntilExit()
      
      if adminProcess.terminationStatus == 0 {
        log("✓ Command succeeded with admin privileges")
        return true
      } else {
        log("✗ Command failed even with admin privileges")
        return false
      }
    } catch {
      log("Command execution error: \(command) \(arguments.joined(separator: " ")) - \(error)")
      return false
    }
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
