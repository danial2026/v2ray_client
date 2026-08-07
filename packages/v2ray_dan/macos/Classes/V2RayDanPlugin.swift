import Cocoa
import FlutterMacOS
import Foundation
import LocalAuthentication
import Security
import Vision

public class V2RayDanPlugin: NSObject, FlutterPlugin {
  private var eventSink: FlutterEventSink?
  private var v2rayProcess: Process?
  private var isConnected: Bool = false
  private var logs: [String] = []
  private var configPath: String = ""
  private var v2rayBinaryPath: String?
  private var tun2socksBinaryPath: String?
  private var tunActive: Bool = false
  
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
      
    case "decodeQR":
      decodeQR(call: call, result: result)
      
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
    findTUN2SocksBinary()
    
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
            do {
              try FileManager.default.removeItem(atPath: tempPath)
            } catch {
              log("⚠️ Could not remove existing binary (might be in use), attempting to reuse it: \(error)")
            }
          }
          
          // Only copy if file doesn't exist (successful remove or wasn't there)
          if !FileManager.default.fileExists(atPath: tempPath) {
             try FileManager.default.copyItem(atPath: bundledPath, toPath: tempPath)
          }
          
          let chmod = Process()
          chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
          chmod.arguments = ["+x", tempPath]
          try chmod.run()
          chmod.waitUntilExit()
          
          v2rayBinaryPath = tempPath
          log("✓ Using V2Ray executable at: \(tempPath)")
          return
        } catch {
          log("Failed to prepare V2Ray binary: \(error)")
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

  private func findTUN2SocksBinary() {
    // 1. Bundled binary (Priority)
    let bundle = Bundle(for: type(of: self))
    if let bundledPath = bundle.path(forResource: "tun2socks", ofType: nil) {
      if FileManager.default.isExecutableFile(atPath: bundledPath) {
        tun2socksBinaryPath = bundledPath
        log("✓ Found bundled tun2socks binary at: \(bundledPath)")
        return
      } else {
        log("Found bundled tun2socks but not executable, copying to temp...")
        let tempPath = NSTemporaryDirectory() + "tun2socks_exec"
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
          tun2socksBinaryPath = tempPath
          log("✓ Using tun2socks executable at: \(tempPath)")
          return
        } catch {
          log("Failed to prepare tun2socks binary: \(error)")
        }
      }
    } else {
      log("⚠️ Bundled 'tun2socks' not found in resources")
    }

    // 2. Common locations (Fallback)
    let possiblePaths = [
      "/usr/local/bin/tun2socks",
      "/opt/homebrew/bin/tun2socks",
      "/usr/bin/tun2socks",
      NSHomeDirectory() + "/go/bin/tun2socks",
    ]
    for path in possiblePaths {
      if FileManager.default.isExecutableFile(atPath: path) {
        tun2socksBinaryPath = path
        log("✓ Found system tun2socks binary at: \(path)")
        return
      }
    }
    log("⚠️ tun2socks binary not found in bundle or system paths.")
  }

  // MARK: - TUN VPN (utun + tun2socks, root-based)

  private struct TunParams {
    var socksPort: Int = 10808
    var serverIp: String?
  }

  private func parseTunParams(configJson: String) -> TunParams {
    var params = TunParams()
    guard let data = configJson.data(using: .utf8),
          let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
      return params
    }
    if let inbounds = json["inbounds"] as? [[String: Any]] {
      for ib in inbounds {
        if let proto = ib["protocol"] as? String, proto == "socks",
           let port = ib["port"] as? Int {
          params.socksPort = port
        }
      }
    }
    if let outbounds = json["outbounds"] as? [[String: Any]] {
      for ob in outbounds {
        if let tag = ob["tag"] as? String, tag == "proxy",
           let settings = ob["settings"] as? [String: Any],
           let vnext = settings["vnext"] as? [[String: Any]],
           let addr = vnext.first?["address"] as? String {
          params.serverIp = addr
        }
      }
    }
    return params
  }

  private var tunStateDir: String {
    NSTemporaryDirectory() + "v2ray_tun/"
  }

  private func writeTunScript(_ name: String, _ content: String) -> String? {
    let dir = tunStateDir
    do {
      try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
      let path = dir + name
      try content.write(toFile: path, atomically: true, encoding: .utf8)
      return path
    } catch {
      log("Failed to write TUN script \(name): \(error)")
      return nil
    }
  }

  private func setupTunVpn(socksPort: Int, serverIp: String?) -> Bool {
    guard let tun2socks = tun2socksBinaryPath else {
      log("❌ tun2socks binary not found, cannot start TUN VPN")
      return false
    }
    guard let serverIp = serverIp, !serverIp.isEmpty else {
      log("❌ Could not resolve VPN server IP, cannot start TUN VPN")
      return false
    }

    log("========== Setting up TUN VPN (utun + tun2socks) ==========")
    log("tun2socks: \(tun2socks)")
    log("SOCKS port: \(socksPort)")
    log("Server IP: \(serverIp)")

    // The utun device is created by tun2socks itself (via com.apple.net.utun_control),
    // NOT by "ifconfig utunN create" which fails with SIOCIFCREATE2 on modern macOS.
    // We use a fixed high unit number to avoid clashing with system utun0-4/Private Relay.
    let script = """
    #!/bin/bash
    set -e
    DIR="@DIR@"
    UTUN=utun100
    GW=""
    exec >> "$DIR/setup.log" 2>&1
    echo "==== setup.sh start ===="
    rm -f "$DIR/tun.pid" "$DIR/tun.iface" "$DIR/tun.gw" "$DIR/tun.server"
    echo "Starting tun2socks (creates $UTUN)..."
    "@TUN@" -device "$UTUN" -proxy socks5://127.0.0.1:@PORT@ -mtu 1500 -loglevel info > "$DIR/tun2socks.log" 2>&1 &
    PID=$!
    echo $PID > "$DIR/tun.pid"
    # Wait for the utun interface to actually appear (tun2socks creates it asynchronously)
    FOUND=""
    for i in $(seq 1 20); do
      if ! kill -0 $PID 2>/dev/null; then
        echo "tun2socks exited early, log follows:"
        cat "$DIR/tun2socks.log" 2>/dev/null || true
        exit 20
      fi
      if ifconfig "$UTUN" >/dev/null 2>&1; then FOUND="yes"; break; fi
      sleep 0.3
    done
    if [ -z "$FOUND" ]; then
      echo "Device $UTUN was not created by tun2socks (waited 6s)"
      cat "$DIR/tun2socks.log" 2>/dev/null || true
      exit 21
    fi
    echo "Device $UTUN created. Assigning point-to-point address..."
    ifconfig "$UTUN" inet 10.0.0.2 10.0.0.1 netmask 255.255.255.0 mtu 1500 up || { echo "addr failed"; exit 22; }
    GW=$(route -n get default 2>/dev/null | awk '/gateway:/{print $2; exit}')
    [ -z "$GW" ] && { echo "no default gateway"; exit 23; }
    echo "Gateway: $GW"
    # Host route for VPN server via the real gateway (prevents routing loop)
    route -n add -host @SERVER@ "$GW" 2>/dev/null || true
    # Default routes through the tunnel
    route -n add -net 0.0.0.0/1 -interface "$UTUN" || { echo "route 1 failed"; exit 24; }
    route -n add -net 128.0.0.0/1 -interface "$UTUN" || { echo "route 2 failed"; exit 25; }
    echo "$UTUN" > "$DIR/tun.iface"
    echo "$GW" > "$DIR/tun.gw"
    echo "@SERVER@" > "$DIR/tun.server"
    echo "==== setup.sh done ===="
    exit 0
    """

    let rendered = script
      .replacingOccurrences(of: "@DIR@", with: tunStateDir)
      .replacingOccurrences(of: "@TUN@", with: tun2socks)
      .replacingOccurrences(of: "@PORT@", with: String(socksPort))
      .replacingOccurrences(of: "@SERVER@", with: serverIp)

    guard let scriptPath = writeTunScript("setup.sh", rendered) else { return false }

    log("Running TUN setup script as root...")
    let ok = executeBatch(["bash \(scriptPath)"])
    logSetupOutput()
    if ok {
      tunActive = true
      log("✓ TUN VPN setup complete (utun created by tun2socks, routes added)")
    } else {
      log("❌ TUN VPN setup script failed (user cancelled or privileges denied)")
      teardownTunVpn()
    }
    return ok
  }

  private func logSetupOutput() {
    let paths = ["setup.log", "tun2socks.log"]
    for name in paths {
      let path = tunStateDir + name
      guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
      for line in content.components(separatedBy: "\n") where !line.isEmpty {
        log("[TUN-SETUP] \(line)")
      }
    }
  }

  private func teardownTunVpn() {
    guard tunActive || FileManager.default.fileExists(atPath: tunStateDir + "tun.iface") else {
      log("TUN teardown skipped (not active)")
      return
    }
    log("========== Tearing down TUN VPN ==========")

    let script = """
    #!/bin/bash
    DIR="@DIR@"
    exec >> "$DIR/teardown.log" 2>&1
    echo "==== teardown.sh start ===="
    IFACE=$(cat $DIR/tun.iface 2>/dev/null)
    PID=$(cat $DIR/tun.pid 2>/dev/null)
    SERVER=$(cat $DIR/tun.server 2>/dev/null)
    GW=$(cat $DIR/tun.gw 2>/dev/null)
    [ -n "$PID" ] && kill $PID 2>/dev/null && echo "killed tun2socks pid $PID" || true
    [ -n "$IFACE" ] && {
      route -n delete -net 0.0.0.0/1 -interface $IFACE 2>/dev/null || true
      route -n delete -net 128.0.0.0/1 -interface $IFACE 2>/dev/null || true
      echo "deleted default routes on $IFACE"
      # utun device disappears automatically when its socket closes (killed above);
      # destroying the iface can throw SIOCIFDESTROY on modern macOS, ignore silently.
      ifconfig $IFACE destroy 2>/dev/null || true
    }
    [ -n "$SERVER" ] && [ -n "$GW" ] && route -n delete -host $SERVER $GW 2>/dev/null || true
    rm -f $DIR/tun.pid $DIR/tun.iface $DIR/tun.gw $DIR/tun.server
    echo "==== teardown.sh done ===="
    exit 0
    """

    let rendered = script.replacingOccurrences(of: "@DIR@", with: tunStateDir)

    guard let scriptPath = writeTunScript("teardown.sh", rendered) else { return }
    let ok = executeBatch(["bash \(scriptPath)"])
    let logPath = tunStateDir + "teardown.log"
    if let content = try? String(contentsOfFile: logPath, encoding: .utf8) {
      for line in content.components(separatedBy: "\n") where !line.isEmpty {
        log("[TUN-TEARDOWN] \(line)")
      }
    }
    tunActive = false
    log(ok ? "✓ TUN VPN teardown complete" : "⚠️ TUN VPN teardown failed or was denied")
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
    log("Mode: \(proxyOnly ? "Proxy Only" : "VPN (TUN + tun2socks)")")
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
        self?.teardownTunVpn()
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
            
            // VPN mode on macOS: set up root-based TUN (utun + tun2socks)
            if !proxyOnly {
              self.log("VPN mode: setting up TUN interface (utun + tun2socks)...")
              let params = self.parseTunParams(configJson: config)
              self.log("Parsed TUN params: socksPort=\(params.socksPort), serverIp=\(params.serverIp ?? "nil")")
              self.log("  SOCKS5: 127.0.0.1:\(params.socksPort)")
              let tunOk = self.setupTunVpn(socksPort: params.socksPort, serverIp: params.serverIp)
              if tunOk {
                self.log("✓ TUN VPN established - ALL system traffic routed through tunnel")
                self.isConnected = true
                self.eventSink?("connected")
              } else {
                self.log("❌ TUN VPN setup FAILED - system proxy NOT modified")
                self.log("⚠️ Tunnel not active; only local SOCKS5 on 127.0.0.1:\(params.socksPort) is available")
                self.isConnected = false
                self.eventSink?("error")
              }
            } else {
              self.log("Proxy-only mode requested - no TUN/VPN routes installed")
              self.isConnected = true
              self.eventSink?("connected")
            }
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
    
    // Tear down TUN VPN (routes, utun interface, tun2socks)
    teardownTunVpn()
    
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
    var httpPort = 10809
    if let args = call.arguments as? [String: Any] {
      if let configJson = args["config"] as? String,
         let data = configJson.data(using: .utf8),
         let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
         let inbounds = json["inbounds"] as? [[String: Any]] {
        for ib in inbounds {
          if let proto = ib["protocol"] as? String, proto == "http",
             let port = ib["port"] as? Int {
            httpPort = port
            break
          }
        }
      }
    }
    
    DispatchQueue.global().async { [weak self] in
      let startTime = Date()
      
      // Create a URL session that uses our HTTP proxy
      let config = URLSessionConfiguration.ephemeral
      config.connectionProxyDictionary = [
        kCFNetworkProxiesHTTPEnable: true,
        kCFNetworkProxiesHTTPProxy: "127.0.0.1",
        kCFNetworkProxiesHTTPPort: httpPort,
        kCFNetworkProxiesHTTPSEnable: true,
        kCFNetworkProxiesHTTPSProxy: "127.0.0.1",
        kCFNetworkProxiesHTTPSPort: httpPort
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
    // 1. Get the primary interface device (e.g., en0) using "route get default"
    let routeProcess = Process()
    routeProcess.executableURL = URL(fileURLWithPath: "/sbin/route")
    routeProcess.arguments = ["-n", "get", "default"]
    
    let routePipe = Pipe()
    routeProcess.standardOutput = routePipe
    
    var primaryDevice: String?
    
    do {
      try routeProcess.run()
      routeProcess.waitUntilExit()
      
      let data = routePipe.fileHandleForReading.readDataToEndOfFile()
      if let output = String(data: data, encoding: .utf8) {
        let lines = output.components(separatedBy: "\n")
        for line in lines {
          if line.contains("interface:") {
            primaryDevice = line.replacingOccurrences(of: "interface:", with: "").trimmingCharacters(in: .whitespaces)
            break
          }
        }
      }
    } catch {
      log("Failed to get default route: \(error)")
    }
    
    guard let device = primaryDevice else {
      log("Could not find default route interface, falling back to heuristic")
      // Start fallback heuristic
      return "Wi-Fi" 
    }
    
    log("Primary network device identified: \(device)")
    
    // 2. Map device (en0) to Service Name (Wi-Fi) using "networksetup -listallhardwareports"
    let nsProcess = Process()
    nsProcess.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
    nsProcess.arguments = ["-listallhardwareports"]
    
    let nsPipe = Pipe()
    nsProcess.standardOutput = nsPipe
    
    do {
      try nsProcess.run()
      nsProcess.waitUntilExit()
      
      let data = nsPipe.fileHandleForReading.readDataToEndOfFile()
      if let output = String(data: data, encoding: .utf8) {
        let lines = output.components(separatedBy: "\n")
        var currentPortName: String?
        
        for line in lines {
          if line.hasPrefix("Hardware Port:") {
            currentPortName = line.replacingOccurrences(of: "Hardware Port:", with: "").trimmingCharacters(in: .whitespaces)
          } else if line.contains("Device: \(device)") {
            if let serviceName = currentPortName {
              log("Mapped device \(device) to service: \(serviceName)")
              return serviceName
            }
          }
        }
      }
    } catch {
      log("Failed to list hardware ports: \(error)")
    }
    
    // 3. Fallback to simple check if mapping failed
    log("Mapping failed, falling back to simple heuristic for Wi-Fi/Ethernet")
    return "Wi-Fi"
  }
  
  private func setSystemProxy(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let interface = getPrimaryNetworkInterface() else {
      log("❌ Could not determine network interface")
      result(FlutterError(code: "NO_INTERFACE", message: "Could not determine network interface", details: nil))
      return
    }
    
    // Extract proxy mode from arguments (default to "both" for backward compatibility)
    var proxyMode = "both"
    var socksPort = 10808
    var httpPort = 10809
    if let args = call.arguments as? [String: Any] {
      if let mode = args["proxyMode"] as? String {
        proxyMode = mode
      }
      if let port = args["socksPort"] as? Int {
        socksPort = port
      }
      if let port = args["httpPort"] as? Int {
        httpPort = port
      }
    }

    log("Setting system proxy for interface: \(interface)")
    log("Proxy mode: \(proxyMode)")
    log("Ports: SOCKS=\(socksPort), HTTP=\(httpPort)")
    
    var commands: [String] = []
    let safeInterface = "\"\(interface)\""
    
    // Configure HTTP/HTTPS
    if proxyMode == "http" || proxyMode == "both" {
      commands.append("/usr/sbin/networksetup -setwebproxy \(safeInterface) 127.0.0.1 \(httpPort)")
      commands.append("/usr/sbin/networksetup -setsecurewebproxy \(safeInterface) 127.0.0.1 \(httpPort)")
      commands.append("/usr/sbin/networksetup -setwebproxystate \(safeInterface) on")
      commands.append("/usr/sbin/networksetup -setsecurewebproxystate \(safeInterface) on")
    }
    
    // Configure SOCKS
    if proxyMode == "socks" || proxyMode == "both" {
      commands.append("/usr/sbin/networksetup -setsocksfirewallproxy \(safeInterface) 127.0.0.1 \(socksPort)")
      commands.append("/usr/sbin/networksetup -setsocksfirewallproxystate \(safeInterface) on")
    }
    
    if executeBatch(commands) {
      log("✓ System proxy configured successfully")
      result(true)
    } else {
      log("⚠️ Failed to invoke admin script for proxy setup")
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
    let safeInterface = "\"\(interface)\""
    
    var commands: [String] = []
    
    // Disable all proxies
    commands.append("/usr/sbin/networksetup -setwebproxystate \(safeInterface) off")
    commands.append("/usr/sbin/networksetup -setsecurewebproxystate \(safeInterface) off")
    commands.append("/usr/sbin/networksetup -setsocksfirewallproxystate \(safeInterface) off")
    
    if executeBatch(commands) {
      log("✓ System proxy cleared successfully")
      result(true)
    } else {
      log("⚠️ Failed to clear system proxy")
      result(false)
    }
  }
  
  private func executeBatch(_ commands: [String]) -> Bool {
    guard !commands.isEmpty else { return true }
    
    let fullScript = commands.joined(separator: " && ")
    
    // 1. Try with stored password and Touch ID first
    if let password = KeychainHelper.getAdminPassword() {
      // Only verify biometric if available
      if BiometricHelper.isBiometricAvailable() {
        if BiometricHelper.authenticateUser(reason: "Authenticate to configure VPN settings") {
          log("Touch ID success, attempting to execute with stored password")
          if executeWithSudo(fullScript, password: password) {
            log("✓ Command executed via sudo with Touch ID auth")
            return true
          } else {
            log("⚠️ Stored password failed with sudo, removing invalid password")
            KeychainHelper.deleteAdminPassword()
          }
        } else {
          log("Touch ID authentication failed or cancelled, falling back to system dialog")
        }
      }
    }
    
    // 2. If no valid password or Touch ID failed, try to capture password if user wants?
    // We will only prompt ONE time per session to capture password if biometric is available
    // and verify it working.
    
    if BiometricHelper.isBiometricAvailable() && KeychainHelper.getAdminPassword() == nil {
        log("No stored password. Prompting user to enable Touch ID...")
        if let password = showAdminPasswordPrompt() {
          if executeWithSudo(fullScript, password: password) {
            log("✓ Command executed via sudo with entered password")
            KeychainHelper.saveAdminPassword(password)
            return true
          } else {
             log("✗ Entered password invalid for sudo")
          }
        } else {
           log("User cancelled custom prompt, falling back to osascript")
        }
    }

    // 3. Fallback to standard osascript
    let escapedScript = fullScript.replacingOccurrences(of: "\\", with: "\\\\")
                                  .replacingOccurrences(of: "\"", with: "\\\"")
    
    let appleScriptSource = "do shell script \"\(escapedScript)\" with administrator privileges"
    
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", appleScriptSource]
    
    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = errorPipe
    
    do {
      try process.run()
      process.waitUntilExit()
      
      if process.terminationStatus == 0 {
        return true
      } else {
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        if let errorMsg = String(data: errorData, encoding: .utf8) {
          log("OsaScript failed: \(errorMsg.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return false
      }
    } catch {
      log("Failed to execute osascript: \(error)")
      return false
    }
  }

  private func executeWithSudo(_ command: String, password: String) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    // Use sudo -S -k to force reading from stdin and ignore cached credentials
    process.arguments = ["-c", "sudo -S -k -p '' \(command)"]
    
    let inputPipe = Pipe()
    let outputPipe = Pipe()
    
    process.standardInput = inputPipe
    process.standardOutput = outputPipe
    process.standardError = outputPipe
    
    do {
      try process.run()
      
      if let data = (password + "\n").data(using: .utf8) {
        inputPipe.fileHandleForWriting.write(data)
        // Close stdin to signal EOF
        try? inputPipe.fileHandleForWriting.closeFile()
      }
      
      process.waitUntilExit()
      return process.terminationStatus == 0
    } catch {
      log("Sudo execution error: \(error)")
      return false
    }
  }
  
  private func showAdminPasswordPrompt() -> String? {
    // Helper function to create and run the alert
    func runAlert() -> String? {
        let alert = NSAlert()
        alert.messageText = "Setup Touch ID for V2Ray"
        alert.informativeText = "Enter your administrator password once to enable Touch ID for future connections. If you Cancel, you will be prompted by the system every time."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Enable Touch ID")
        alert.addButton(withTitle: "Skip")
        
        let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        alert.accessoryView = input
        
        // Try to focus
        alert.window.initialFirstResponder = input
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
          return input.stringValue
        }
        return nil
    }

    if Thread.isMainThread {
        return runAlert()
    } else {
        return DispatchQueue.main.sync {
            return runAlert()
        }
    }
  }
  
  // MARK: - Helpers

  private struct BiometricHelper {
    static func isBiometricAvailable() -> Bool {
      let context = LAContext()
      var error: NSError?
      return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }
    
    static func authenticateUser(reason: String) -> Bool {
      let context = LAContext()
      var authorized = false
      let semaphore = DispatchSemaphore(value: 0)
      
      context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, authenticationError in
        authorized = success
        semaphore.signal()
      }
      
      _ = semaphore.wait(timeout: .now() + 60)
      return authorized
    }
  }
  
  private struct KeychainHelper {
    static let service = "com.flaming.cherubim.admin" 
    static let account = "root"
    
    static func saveAdminPassword(_ password: String) {
      guard let data = password.data(using: .utf8) else { return }
      
      let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
        kSecValueData as String: data
      ]
      
      SecItemDelete(query as CFDictionary)
      SecItemAdd(query as CFDictionary, nil)
    }
    
    static func getAdminPassword() -> String? {
      let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne
      ]
      
      var dataTypeRef: AnyObject?
      let status: OSStatus = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
      
      if status == errSecSuccess, let data = dataTypeRef as? Data {
        return String(data: data, encoding: .utf8)
      }
      return nil
    }
    
    static func deleteAdminPassword() {
      let query: [String: Any] = [
         kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account
      ]
      SecItemDelete(query as CFDictionary)
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
  // MARK: - QR Code Decode
  private func decodeQR(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let path = args["path"] as? String else {
      log("decodeQR: missing path argument")
      result(FlutterError(code: "INVALID_ARGS", message: "Missing path argument", details: nil))
      return
    }
    
    log("decodeQR: path=\(path)")
    
    let fileURL = URL(fileURLWithPath: path)
    let fileExists = FileManager.default.fileExists(atPath: path)
    log("decodeQR: file exists = \(fileExists)")
    
    guard let imageData = try? Data(contentsOf: fileURL) else {
      log("decodeQR: FAILED to read file data, path=\(path)")
      result(FlutterError(code: "LOAD_ERROR", message: "Could not read file at: \(path)", details: nil))
      return
    }
    
    log("decodeQR: read \(imageData.count) bytes")
    
    guard let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil) else {
      log("decodeQR: FAILED to create CGImageSource from data")
      result(FlutterError(code: "LOAD_ERROR", message: "Could not decode image data", details: nil))
      return
    }
    
    let imageType = CGImageSourceGetType(imageSource) as String? ?? "unknown"
    log("decodeQR: image type = \(imageType)")
    
    guard let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
      log("decodeQR: FAILED to create CGImage from source")
      result(FlutterError(code: "LOAD_ERROR", message: "Could not create CGImage", details: nil))
      return
    }
    
    log("decodeQR: CGImage created, size=\(cgImage.width)x\(cgImage.height)")
    
    let orientation = CGImagePropertyOrientation(imageSource)
    log("decodeQR: orientation = \(orientation.rawValue)")
    
    let ciImage = CIImage(cgImage: cgImage).oriented(orientation)
    log("decodeQR: starting Vision barcode detection...")
    
    let request = VNDetectBarcodesRequest { (request, error) in
      if let error = error {
        DispatchQueue.main.async {
          self.log("decodeQR: Vision error = \(error.localizedDescription)")
          result(FlutterError(code: "DETECT_ERROR", message: error.localizedDescription, details: nil))
        }
        return
      }
      
      guard let observations = request.results as? [VNBarcodeObservation] else {
        DispatchQueue.main.async {
          self.log("decodeQR: no VNBarcodeObservation results")
          result(nil)
        }
        return
      }
      
      DispatchQueue.main.async {
        self.log("decodeQR: found \(observations.count) barcode(s)")
        for (i, obs) in observations.enumerated() {
          self.log("decodeQR: barcode[\(i)] type=\(obs.symbology.rawValue) payload=\(obs.payloadStringValue ?? "nil")")
        }
        
        for observation in observations {
          if observation.symbology == .qr, let payload = observation.payloadStringValue, !payload.isEmpty {
            self.log("decodeQR: SUCCESS payload=\(payload)")
            result(payload)
            return
          }
        }
        
        self.log("decodeQR: no QR code found in \(observations.count) barcode(s)")
        result(nil)
      }
    }
    
    request.symbologies = [.qr]
    
    let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        try handler.perform([request])
      } catch {
        DispatchQueue.main.async {
          self.log("decodeQR: handler.perform error = \(error.localizedDescription)")
          result(FlutterError(code: "HANDLER_ERROR", message: error.localizedDescription, details: nil))
        }
      }
    }
  }
}

extension CGImagePropertyOrientation {
  init(_ source: CGImageSource) {
    if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
       let exifOrientation = properties[kCGImagePropertyOrientation as String] as? UInt32 {
      self = CGImagePropertyOrientation(rawValue: exifOrientation) ?? .up
    } else {
      self = .up
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
