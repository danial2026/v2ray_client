#!/usr/bin/swift

import Foundation
import LocalAuthentication
import Security

// Mock Logging
func log(_ message: String) {
    print("[StandaloneProxyTest] \(message)")
}

// --- Helper Structures ---

struct VLessConfigModel {
    let uuid: String
    let server: String
    let port: Int
}

class VLessParser {
    static func parse(_ link: String) -> VLessConfigModel? {
        guard link.hasPrefix("vless://") else { return nil }
        let cleanLink = String(link.dropFirst("vless://".count))
        
        // Remove fragment #
        let withoutFragment = cleanLink.components(separatedBy: "#").first ?? cleanLink
        // Remove query ?
        let withoutQuery = withoutFragment.components(separatedBy: "?").first ?? withoutFragment
        
        // Format: uuid@server:port
        let parts = withoutQuery.components(separatedBy: "@")
        guard parts.count == 2 else { return nil }
        let uuid = parts[0]
        let serverPort = parts[1]
        
        // Handle last colon for port
        let hostPortParts = serverPort.components(separatedBy: ":")
        guard hostPortParts.count >= 2,
              let portString = hostPortParts.last,
              let port = Int(portString) else { return nil }
              
        // Host is everything before the last colon
        let host = hostPortParts.dropLast().joined(separator: ":")
              
        return VLessConfigModel(uuid: uuid, server: host, port: port)
    }
}

class V2RayProxyConfigurator {
    
    // Simulating the setSystemProxy logic
    func setSystemProxy(interface: String, mode: String) -> Bool {
        log("Setting system proxy for interface: \(interface)")
        
        var commands: [String] = []
        let safeInterface = "\"\(interface)\""
        
        if mode == "http" || mode == "both" {
            commands.append("/usr/sbin/networksetup -setwebproxy \(safeInterface) 127.0.0.1 10809")
            commands.append("/usr/sbin/networksetup -setsecurewebproxy \(safeInterface) 127.0.0.1 10809")
            commands.append("/usr/sbin/networksetup -setwebproxystate \(safeInterface) on")
            commands.append("/usr/sbin/networksetup -setsecurewebproxystate \(safeInterface) on")
        }
        
        if mode == "socks" || mode == "both" {
             commands.append("/usr/sbin/networksetup -setsocksfirewallproxy \(safeInterface) 127.0.0.1 10808")
             commands.append("/usr/sbin/networksetup -setsocksfirewallproxystate \(safeInterface) on")
        }
        
        return executeBatch(commands)
    }
    
    private func executeBatch(_ commands: [String]) -> Bool {
        guard !commands.isEmpty else { return true }
        
        let fullScript = commands.joined(separator: " && ")
        log("Commands to execute: \(fullScript)")
        
        // 1. Try with stored password and Touch ID first
        if let password = KeychainHelper.getAdminPassword() {
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
              log("Touch ID authentication failed or cancelled")
            }
          }
        }
        
        // 2. If no valid password, prompt (CLI version)
        if BiometricHelper.isBiometricAvailable() && KeychainHelper.getAdminPassword() == nil {
            log("No stored password. Prompting user to enable Touch ID...")
            // CLI Prompt
            print("Enter Admin Password to enable Touch ID (will be saved to Keychain): ", terminator: "")
            if let password = readLine(strippingNewline: true), !password.isEmpty {
                if executeWithSudo(fullScript, password: password) {
                    log("✓ Command executed via sudo with entered password")
                    KeychainHelper.saveAdminPassword(password)
                    return true
                } else {
                    log("✗ Entered password invalid for sudo")
                }
            } else {
                log("Skipped password entry")
            }
        }

        // 3. Fallback to standard osascript
        log("Falling back to osascript...")
        let escapedScript = fullScript.replacingOccurrences(of: "\\", with: "\\\\")
                                      .replacingOccurrences(of: "\"", with: "\\\"")
        
        let appleScriptSource = "do shell script \"\(escapedScript)\" with administrator privileges"
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", appleScriptSource]
        
        process.waitUntilExit()
        
        return process.terminationStatus == 0
    }

      private func executeWithSudo(_ command: String, password: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sudo -S -k -p '' \(command)"]
        
        let inputPipe = Pipe()
        let outputPipe = Pipe() // Redirect stdout/stderr to suppress noise
        
        process.standardInput = inputPipe
        // process.standardOutput = outputPipe // Keep stdout for debug if needed, but usually noisy
        process.standardError = outputPipe
        
        do {
          try process.run()
          
          if let data = (password + "\n").data(using: .utf8) {
            inputPipe.fileHandleForWriting.write(data)
            inputPipe.fileHandleForWriting.closeFile()
          }
          
          process.waitUntilExit()
          return process.terminationStatus == 0
        } catch {
          log("Sudo execution error: \(error)")
          return false
        }
      }
      
      // Helpers
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
}

// --- Verified Classes for Core Management ---

class ConfigGenerator {
    static func generateBasicVLessConfig(uuid: String, server: String, port: Int) -> String {
        return """
        {
          "log": { "loglevel": "warning" },
          "dns": {
            "servers": [
              "8.8.8.8",
              "1.1.1.1",
              "localhost"
            ]
          },
          "inbounds": [
            {
              "tag": "socks-in",
              "port": 10808,
              "listen": "127.0.0.1",
              "protocol": "socks",
              "settings": { "auth": "noauth", "udp": true }
            },
            {
              "tag": "http-in",
              "port": 10809,
              "listen": "127.0.0.1",
              "protocol": "http"
            }
          ],
          "outbounds": [
            {
              "tag": "proxy",
              "protocol": "vless",
              "settings": {
                "vnext": [
                  {
                    "address": "\(server)",
                    "port": \(port),
                    "users": [ { "id": "\(uuid)", "encryption": "none" } ]
                  }
                ]
              },
              "streamSettings": { "network": "tcp", "security": "none" }
            },
            { "tag": "direct", "protocol": "freedom" }
          ],
          "routing": {
            "domainStrategy": "IPIfNonMatch",
            "rules": [
              { "type": "field", "outboundTag": "proxy", "network": "tcp,udp" },
              { "type": "field", "port": 53, "outboundTag": "direct" }
            ]
          }
        }
        """
    }
}

class V2RayRunner {
    var process: Process?
    
    func findBinary() -> String? {
        let paths = [
            FileManager.default.currentDirectoryPath + "/packages/v2ray_dan/macos/Resources/v2ray",
            "/usr/local/bin/v2ray",
            "/opt/homebrew/bin/v2ray"
        ]
        
        for path in paths {
            if FileManager.default.isExecutableFile(atPath: path) {
                log("Found V2Ray binary at: \(path)")
                return path
            }
        }
        log("❌ V2Ray binary not found in common locations.")
        return nil
    }
    
    func start(binaryPath: String, configContent: String) {
        let configPath = NSTemporaryDirectory() + "test_config.json"
        
        do {
            try configContent.write(toFile: configPath, atomically: true, encoding: .utf8)
            
            process = Process()
            process?.executableURL = URL(fileURLWithPath: binaryPath)
            process?.arguments = ["run", "-c", configPath]
            
            // PIPE OUTPUT TO CONSOLE FOR DEBUGGING
            process?.standardOutput = FileHandle.standardOutput
            process?.standardError = FileHandle.standardError
            
            try process?.run()
            log("✓ V2Ray core started (PID: \(process?.processIdentifier ?? 0))")
        } catch {
            log("Failed to start V2Ray: \(error)")
        }
    }
    
    func stop() {
        if let p = process, p.isRunning {
            p.terminate()
            log("V2Ray core stopped")
        }
    }
}

class IPChecker {
    static func checkIP(proxyPort: Int, completion: @escaping (String?) -> Void) {
        let url = URL(string: "http://ip-api.com/line/?fields=query")! 
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [
            kCFNetworkProxiesHTTPEnable: true,
            kCFNetworkProxiesHTTPProxy: "127.0.0.1",
            kCFNetworkProxiesHTTPPort: proxyPort,
            kCFNetworkProxiesHTTPSEnable: true,
            kCFNetworkProxiesHTTPSProxy: "127.0.0.1",
            kCFNetworkProxiesHTTPSPort: proxyPort
        ]
        
        config.timeoutIntervalForRequest = 5
        
        let session = URLSession(configuration: config)
        log("Checking IP via 127.0.0.1:\(proxyPort)...")
        
        let task = session.dataTask(with: url) { data, response, error in
            if let error = error {
                log("IP Check failed: \(error.localizedDescription)")
                completion(nil)
                return
            }
            if let data = data, let ip = String(data: data, encoding: .utf8) {
                completion(ip.trimmingCharacters(in: .whitespacesAndNewlines))
            } else {
                completion(nil)
            }
        }
        task.resume()
    }
}

func killPortConflict() {
    print("🧹 Checking for port conflicts on 10808/10809...")
    // Kill whatever is on port 10808 (SOCKS) and 10809 (HTTP)
    let ports = [10808, 10809]
    for port in ports {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "lsof -t -i:\(port) | xargs kill -9"]
        // Suppress output, we don't care if it fails (no process found)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }
    // Also explicitly kill v2ray just in case
    let killall = Process()
    killall.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
    killall.arguments = ["v2ray"]
    killall.standardOutput = FileHandle.nullDevice
    killall.standardError = FileHandle.nullDevice
    try? killall.run()
    killall.waitUntilExit()
}

// MAIN EXECUTION
func main() {
    print("\n🔎 --- V2Ray Independent Test Runner --- 🔍\n")
    
    // 0. Cleanup Previous Instances
    killPortConflict()
    
    // 1. Get Link
    var vlessLink = ""
    if CommandLine.arguments.count > 1 {
        vlessLink = CommandLine.arguments[1]
    } else {
        print("📝 Enter VLESS URL:")
        if let input = readLine() {
            vlessLink = input.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    
    if vlessLink.isEmpty {
        print("❌ No link provided. Exiting.")
        exit(1)
    }
    
    // 1. Parse Link
    guard let config = VLessParser.parse(vlessLink) else {
        print("❌ Failed to parse VLESS link. Ensure it starts with vless:// and format is correct.")
        exit(1)
    }
    
    print("✅ Parsed: UUID=\(config.uuid) Server=\(config.server) Port=\(config.port)\n")
    
    // 2. Setup V2Ray Logic
    let v2ray = V2RayRunner()
    guard let binary = v2ray.findBinary() else {
        print("Please run this script from the project root or ensure v2ray is installed.")
        exit(1)
    }
    
    // 3. Generate Config
    let configJson = ConfigGenerator.generateBasicVLessConfig(uuid: config.uuid, server: config.server, port: config.port)
    
    // 4. Start Core
    v2ray.start(binaryPath: binary, configContent: configJson)
    
    print("\n⏳ Waiting for V2Ray to establish connection (checking via 10809)...")
    var coreReady = false
    
    for i in 1...10 {
        print("   Attempt \(i)/10 to verify connection...") 
        var currentIp: String?
        let checkSem = DispatchSemaphore(value: 0)
        
        IPChecker.checkIP(proxyPort: 10809) { ip in
            currentIp = ip
            checkSem.signal()
        }
        _ = checkSem.wait(timeout: .now() + 6) 
        
        if let ip = currentIp {
            print("   ✓ V2Ray is Alive! Route Verification Successful. IP: \(ip)")
            coreReady = true
            break
        } else {
            Thread.sleep(forTimeInterval: 2.0)
        }
    }
    
    if !coreReady {
        print("\n❌ V2Ray failed to connect to the server/internet via the proxy port.")
        print("   Check your internet connection or the server status. Aborting.")
        v2ray.stop()
        exit(1)
    }

    // 5. Configure System Proxy
    print("\n⚙️  Configuring System Proxy...")
    let configurator = V2RayProxyConfigurator()
    
    if configurator.setSystemProxy(interface: "Wi-Fi", mode: "socks") {
        print("✅ System Proxy ENABLED (SOCKS)")
    } else {
        print("❌ Failed to enable proxy")
        v2ray.stop()
        exit(1)
    }
    
    // 6. Final Confirmation
    print("\n🌍 Connection is fully established and system-wide!")
    
    // 7. Cleanup
    print("\n🧹 Cleaning up...")
    print("Press Enter to Stop Proxy and Exit...")
    _ = readLine()
    
    let disableScript = "do shell script \"networksetup -setwebproxystate \\\"Wi-Fi\\\" off && networksetup -setsecurewebproxystate \\\"Wi-Fi\\\" off && networksetup -setsocksfirewallproxystate \\\"Wi-Fi\\\" off\" with administrator privileges"
    
    let cleanup = Process()
    cleanup.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    cleanup.arguments = ["-e", disableScript]
    
    do { 
        try cleanup.run() 
        cleanup.waitUntilExit()
    } catch { }

    v2ray.stop()
    print("Done.")
}

main()
