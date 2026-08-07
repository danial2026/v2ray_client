import Cocoa
import FlutterMacOS
import Darwin

@main
class AppDelegate: FlutterAppDelegate {
  private var statsChannel: FlutterMethodChannel?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    guard let controller = mainFlutterWindow?.contentViewController as? FlutterViewController else {
      return
    }
    let messenger = controller.engine.binaryMessenger
    statsChannel = FlutterMethodChannel(
      name: "com.flaming.cherubim/stats",
      binaryMessenger: messenger
    )
    statsChannel?.setMethodCallHandler { [weak self] call, result in
      if call.method == "getUsageStats" {
        self?.handleGetUsageStats(result: result)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func handleGetUsageStats(result: @escaping FlutterResult) {
    var upload: Int = 0
    var download: Int = 0

    var ifap: UnsafeMutablePointer<ifaddrs>?
    if getifaddrs(&ifap) == 0, let first = ifap {
      var ptr: UnsafeMutablePointer<ifaddrs>? = first
      while ptr != nil {
        if let name = ptr?.pointee.ifa_name,
           String(cString: name) == "lo0",
           let addr = ptr?.pointee.ifa_addr,
           addr.pointee.sa_family == UInt8(AF_LINK) {
          let data = ptr!.pointee.ifa_data.assumingMemoryBound(to: if_data.self)
          upload = Int(data.pointee.ifi_obytes)
          download = Int(data.pointee.ifi_ibytes)
        }
        ptr = ptr?.pointee.ifa_next
      }
      freeifaddrs(first)
    }

    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) {
      $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
        task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
      }
    }
    let memMB: Double = (kr == KERN_SUCCESS)
      ? Double(info.resident_size) / (1024 * 1024)
      : 0

    result([
      "upload": upload,
      "download": download,
      "memory": memMB,
    ])
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
