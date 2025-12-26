# Flaming Cherubim — Complete Documentation

A modern, high-performance V2Ray VPN client for Android and macOS

Flaming Cherubim is a powerful V2Ray client built from the ground up with Flutter and Kotlin, designed to provide a fast, reliable, and user-friendly VPN experience. Unlike other V2Ray clients that rely on third-party plugins, this app uses a custom-built native plugin that integrates directly with the official V2Ray core, offering maximum control, transparency, and performance.

---

## Overview

Flaming Cherubim brings enterprise-grade proxy capabilities to your devices with an emphasis on speed, reliability, and simplicity. Whether you need system-wide VPN protection or just a local proxy for specific applications, this app delivers both with a clean, minimal interface that stays out of your way.

---

## Features

### Protocol Support

The app supports VMess, the industry-standard obfuscation protocol with full configuration support, and VLESS, a lightweight protocol with Reality and XTLS support. You can fine-tune custom TLS settings including SNI, ALPN, and fingerprint spoofing for maximum stealth.

### Connection Modes

#### VPN Mode (System-Wide)

Full system VPN tunnel that routes all device traffic through V2Ray. Perfect for complete privacy and circumventing network restrictions.

- Creates a TUN interface managed by Android's VPN service
- Routes all network traffic through the V2Ray core
- Works with all apps automatically, no per-app configuration needed
- Includes DNS leak protection to prevent exposure

#### Proxy-Only Mode

Lightweight local proxy server without the VPN overhead. Ideal for development, testing, or when you only need specific apps to use the proxy.

- SOCKS5 Proxy on port 10808
- HTTP Proxy on port 10809
- Configure individual apps to use the proxy manually
- Lower resource usage than VPN mode
- No VPN permission required

### Advanced Features

#### Intelligent Ping System

The app can automatically ping servers at configurable intervals (30 seconds, 1 minute, 5 minutes, 15 minutes, or never). You can choose between TCP ping, HTTP ping, or both for latency monitoring. Real-time latency is displayed for all configured servers, and you can optionally auto-select the server with the lowest ping.

#### Built-In Network Diagnostic Browser

A fully-featured in-app browser that opens directly to a custom speed and latency test at https://danials.org/network. This diagnostic page shows your current public IP address, country flag and location, real-time latency tests, and speed test capabilities.

The browser includes URL input with auto-https, forward and back navigation, refresh button, and a progress indicator. All traffic is automatically routed through the active VPN or proxy connection, with a "PROXIED" indicator showing the connection is encrypted.

#### Comprehensive Logging

Real-time visibility into everything happening under the hood. The app logs Flutter-level events, state changes, and user actions. V2Ray Core logs show direct output from V2Ray core including connection attempts, protocol negotiation, and traffic details. In VPN mode, tun2socks logs provide low-level TUN interface information.

You can easily filter between different log sources, export logs for debugging or analysis, and clear all logs when needed.

#### Kill Switch Protection

If the app crashes or is force-stopped while connected, the VPN connection is gracefully terminated to prevent traffic leaks. Your device won't continue sending unencrypted traffic if the VPN goes down unexpectedly.

#### Home Screen Widgets (Android)

Two Android widgets are available for quick access:
1. **Connect Widget**: Quick-toggle connection without opening the app.
2. **Circle Status Widget**: Minimal circular status indicator.

#### Usage Statistics & Indicators

The AppBar provides real-time monitoring:
- **Speeds & RAM**: Live upload/download monitoring and app memory usage.
- **IP & Location**: Current connected IP and country flag.

#### Modern, Minimal UI

The app features a dark-themed interface with smooth animations and intuitive navigation. A large color-coded button handles connection status, and the server list supports easy management with swipe-to-delete and privacy censoring options.

---

## Architecture & Technical Details

### The Custom v2ray_dan Plugin

Unlike most Flutter V2Ray clients that use pre-built plugins like flutter_v2ray, Flaming Cherubim implements its own native plugin (v2ray_dan) from scratch. This provides full control with direct access to all V2Ray configuration options, native performance with zero overhead between Flutter and V2Ray core, complete transparency into what's happening at the native layer, easy extensibility for specific use cases, and no third-party dependencies for core VPN functionality.

### What Runs Where?

#### Dart (Flutter Layer)

The Flutter layer handles all UI, state management, and user interactions. This includes all visual components like home_screen.dart, logs_page.dart, and webview_screen.dart. Provider-based state management tracks app state, connection status, and the server list.

The services layer includes v2ray_service.dart for high-level VPN/proxy operations coordination, storage_service.dart for persistent storage using SharedPreferences, and ping_service.dart for server latency testing and monitoring. Models define server configurations, DNS presets, and ping settings. Method channel communication bridges Flutter to native Kotlin code.

#### Kotlin (Native Android Layer)

The Kotlin layer manages the V2Ray core and Android VPN APIs.

1. **V2RayDanPlugin.kt**: Main bridge handling `initialize`, `startV2Ray`, `stopV2Ray`, and permission requests.
2. **V2RayCoreManager.kt**: Managed via `libv2ray` (Mobile bind). Handles core lifecycle, JSON config loading, and Go-level protection hooks.
3. **V2RayVPNService.kt**: Android `VpnService` that establishes a TUN interface (172.19.0.1) and manages a `tun2socks` supervisor thread.
4. **V2RayProxyOnlyService.kt**: Starts core with local inbounds only; runs as a foreground service with notification.
5. **FD Passing**: Uses `LocalSocket` to pass the TUN file descriptor from Kotlin to the `tun2socks` binary.

#### Swift (Native macOS Layer)

The Swift layer provides desktop-integrated proxy management.

1. **V2RayDanPlugin.swift**:
   - Executes bundled or system `v2ray`/`xray` binaries directly via `Process()`.
   - Manages system-wide SOCKS (10808) and HTTP/HTTPS (10809) proxies.
2. **Proxy Management**:
   - Uses `networksetup` via `osascript` (with admin privileges) or `sudo` (authenticated via Touch ID).
   - Primary interface detection via `/sbin/route` and hardware port mapping.
3. **Latency Verification**: Implements native `getServerDelay` using `URLSession` proxied through the local core.

#### Native Components

- **V2Ray Core**: Official binary for Android (ARM64/ARMv7) and macOS (Intel/Apple Silicon).
- **tun2socks**: Bridges TUN-to-SOCKS (Android VPN mode).

### Communication Flow

```
┌──────────────────────────────────────────────┐
│                Flutter (Dart)                │
│  ┌────────────┐   ┌──────────────┐           │
│  │ HomeScreen │──▶│ V2RayService │           │
│  └────────────┘   └───────┬──────┘           │
└───────────────────────────┼──────────────────┘
              MethodChannel │ ▲ EventChannel (Status)
              Channel(logs) │ │ Channel(logs)
                            ▼ │
┌─────────────────────────────┴──────────────────────────────────┐
│                      Native Layer (Swift/Kotlin)               │
│  ┌────────────────────┐   Managed    ┌──────────────────────┐  │
│  │  V2RayDanPlugin    │─────────────▶│   V2Ray Core / Bin   │  │
│  └────────┬───────────┘   Process    └──────────┬───────────┘  │
│           │                                     │              │
│    ┌──────┴──────────┐                          │              │
│    ▼                 ▼                          │              │
│  ┌─────────────┐   ┌─────────────┐              │              │
│  │ VPN/Proxy   │   │ Sys Proxy   │              │              │
│  │ (Android)   │   │ (macOS)     │              │              │
│  └─────────────┘   └─────────────┘              │              │
└─────────────────────────────────────────────────┼──────────────┘
                                                  ▼
                                          Network Traffic
```

### How it Works: Android (VPN Mode)

1. **Initiation**: User taps connect; Flutter calls `startV2Ray()` via MethodChannel.
2. **VpnService**: `V2RayVPNService` starts; Android creates a TUN interface (172.19.0.1).
3. **Supervisor**: A supervisor thread launches the `tun2socks` binary and monitors its lifecycle.
4. **FD Passing**: Kotlin establishes a `LocalSocket` to send the TUN file descriptor to `tun2socks`.
5. **Core**: `V2RayCoreManager` (via `libv2ray`) starts the V2Ray process with the JSON config.
6. **Routing**: Traffic: TUN (172.19.0.1) -> `tun2socks` -> V2Ray SOCKS (10808) -> Remote.

### How it Works: macOS (System Proxy)

1. **Binary Detection**: Swift searches for bundled `v2ray` or system `v2ray/xray` (Homebrew/local).
2. **Execution**: Swift spawns the V2Ray process directly using `Process()` with `--run -c [config]`.
3. **Device Mapping**: Identifies primary interface (e.g., "Wi-Fi") using `route get default` and `networksetup`.
4. **Proxy Setup**: Direct calls to `networksetup` (via `osascript` or `sudo` + Touch ID) set system-wide SOCKS/HTTP/HTTPS proxies.
5. **Bidirectional Logs**: Both platforms pipe process stdout/stderr back to Dart via dedicated MethodChannels.

---

## User Interface

### Main Screen (Home)

Large connect button lets you tap to connect or disconnect with color-coded status. The scrollable server list shows server name/alias, country flag (based on remarks), latency indicator (green/yellow/red based on ping), and supports swipe-to-delete gestures. Bottom navigation provides quick access to Logs, Settings, Add Server, and Browser.

### Add/Edit Server Screen

Choose protocol (VMess or VLESS), enter server details like address, port, ID, and alterId (for VMess). Configure TLS settings including enable TLS, SNI, ALPN, and fingerprint. Set transport settings for TCP, WebSocket, gRPC, and more. Add an alias or remarks for custom naming, and test the connection with a built-in connectivity test before saving.

### Logs Screen

Real-time feed with auto-scrolling log viewer. Toggle source filters between App, V2Ray Core, and tun2socks logs. Search to filter logs by keyword. Export to save logs to file for debugging, or clear to wipe all logs.

### Settings Screen

Connection mode toggle switches between VPN and Proxy-Only modes. Configure ping settings for auto-ping interval and method. Choose DNS settings from presets (Google, Cloudflare, Quad9, or custom). Enable or disable kill switch for crash protection. View app info including version number and developer website. Use the reset VPN button as an emergency reset to clear stuck states.

### Browser Screen

URL bar lets you enter any website or use the default diagnostic page. Navigation controls include back, forward, and refresh. Progress indicator provides visual feedback during page loads. A proxied badge shows traffic is routed through VPN/proxy. All browser traffic automatically uses the active connection through auto-proxy.

---

## Security & Privacy

### DNS Leak Protection

When VPN mode is active, all DNS queries are routed through the VPN tunnel using configured DNS servers. This prevents your ISP from seeing which websites you're visiting, even if they can't see the encrypted traffic.

### Kill Switch

If the app crashes or is terminated unexpectedly, the VPN service is designed to shut down gracefully. This prevents your device from continuing to send traffic in the clear after the VPN disconnects.

### TLS Fingerprinting

Support for custom TLS fingerprints (Chrome, Firefox, Safari, iOS, Edge, and others) helps bypass deep packet inspection and makes your traffic look like standard browser traffic.

### No Data Collection

This app doesn't collect, store, or transmit any usage data, logs, or personal information. Everything stays on your device.

### Open Source

The entire codebase is available for review. You can verify exactly what the app does and doesn't do.

---

## Performance

### Lightweight Design

The minimal UI provides fast rendering with efficient Flutter widgets. Typical RAM usage is 60-100MB. Optimized background services ensure battery efficiency. Cold start completes in under 2 seconds.

### Fast Connections

Direct core integration means no unnecessary middleware or wrappers. tun2socks is highly optimized for packet forwarding. Latency monitoring helps you always know which server is fastest.

### Resource Usage

VPN mode uses roughly 70-120MB RAM with minimal CPU when idle. Proxy mode uses roughly 50-80MB RAM with even lower overhead. Background services suspend when disconnected.

---

### Android
- Android 5.0 (Lollipop) or higher
- ARM (v7) or ARM64 (v8) architecture
- Permissions: VPN, Internet, Foreground Service, Wake Lock

### macOS
- macOS 11.0 (Big Sur) or higher
- Intel or Apple Silicon (M1/M2/M3)
- Permissions: System Proxy configuration, Local Network, Internet

---

## Development

### Technology Stack

- Flutter 3.0+
- Dart SDK 3.10+
- Kotlin for Android native plugin
- V2Ray Core official release (embedded)
- tun2socks for TUN-to-SOCKS bridging

### Project Structure

```
v2ray_flutter_app/
├── lib/                          # Flutter/Dart code
│   ├── main.dart                 # App entry point
│   ├── models/                   # Data models (Server, PingResult, etc.)
│   ├── screens/                  # UI screens (Home, Logs, Settings, etc.)
│   ├── services/                 # Business logic (V2Ray, Storage, Ping)
│   ├── widgets/                  # Reusable UI components
│   └── theme/                    # App theme and colors
│
├── packages/
│   └── v2ray_dan/                # Custom V2Ray plugin
│       ├── lib/                  # Dart plugin interface
│       └── android/
│           └── src/main/kotlin/
│               └── com/v2ray/dan/
│                   ├── V2RayDanPlugin.kt
│                   ├── V2RayCoreManager.kt
│                   ├── V2RayVPNService.kt
│                   ├── V2RayProxyOnlyService.kt
│                   ├── Utilities.kt
│                   └── AppConfigs.kt
│
├── android/                      # Android-specific configuration
│   ├── app/
│   │   ├── src/main/
│   │   │   ├── AndroidManifest.xml
│   │   │   ├── kotlin/           # MainActivity
│   │   │   └── assets/           # V2Ray core binaries
│   │   └── build.gradle
│   └── build.gradle
│
├── macos/                        # macOS-specific configuration
│   ├── Runner/
│   │   ├── MainFlutterWindow.swift
│   │   ├── AppDelegate.swift
│   │   └── V2RayDanPlugin.swift   # macOS Native Plugin Implementation
│   └── build.gradle
│
├── assets/                       # App assets (logo, etc.)
├── pubspec.yaml                  # Flutter dependencies
└── README.md
```

### Building from Source

```bash
# Clone the repository
git clone https://github.com/danial2026/v2ray_client.git
cd v2ray_client

# Install dependencies
flutter pub get

# Run in debug mode
flutter run

# Build release APK
flutter build apk --release
```

---

## Use Cases

### Personal Privacy

Browse without ISP tracking, prevent DNS leaks, hide your real IP address, and avoid location-based content restrictions.

### Development & Testing

Test apps behind proxies, simulate different geographic locations, debug network issues, and inspect proxied traffic.

### Bypassing Restrictions

Access blocked websites and services, circumvent firewalls and censorship, use services restricted by region, and maintain access during network disruptions.

### App-Specific Proxying

Use proxy mode to only route specific apps while leaving other apps using direct connection. This is better for battery life with selective proxying and useful for development on emulators.

---

## Configuration Tips

### Best Ping Settings

For general use, set auto-ping to every 5 minutes with HTTP ping. For battery saving, use auto-ping every 15 minutes or disable it. For maximum performance, set auto-ping to every 30 seconds with TCP ping.

### DNS Recommendations

For privacy, use Cloudflare (1.1.1.1) or Quad9 (9.9.9.9). For speed, use Google Public DNS (8.8.8.8). You can also set your own custom trusted DNS servers.

### When to Use Each Mode

Use VPN mode when you want all apps and system traffic proxied. Use proxy mode when you want manual control or lower resource usage.

---

## Troubleshooting

### Connection Stuck on "Connecting..."

Check the logs for errors. Try using a different server. Switch between VPN and Proxy modes. Use the "Reset VPN & Relaunch App" button in settings.

### High Ping or Slow Speeds

Try a different server (use auto-ping to find the fastest). Check if your server is overloaded. Verify your internet connection is stable. Try different protocols (VMess vs VLESS).

### App Crashes or Force Closes

Check logs before restarting. Try clearing app cache. Reinstall if the problem persists. Report the issue with log files.

### Browser Not Working Through VPN

Ensure VPN mode is active (not proxy-only). Check for DNS configuration issues in logs. Try a different website to isolate the issue. Verify kill switch isn't blocking traffic.

---

## Contributing

This is a weekend project and not production-ready, but contributions are welcome. Whether it's bug reports, feature requests, or pull requests, feel free to open an issue or PR on GitHub.

---

## License

This project is licensed under the GNU General Public License v3.0 (GPL-3.0).

You are free to use this software for any purpose, study and modify the source code, distribute copies, and distribute modified versions.

Under the conditions that you must disclose the source code, license derivative works under GPL-3.0, state significant changes made, and not use this software for proprietary or closed-source projects.

See the LICENSE file for full details.

---

## Disclaimer

> [!NOTE]
> I coded this over the weekends, it might have bugs and it's not production-ready.

This app is provided as-is with no warranties or guarantees. Use at your own risk. The developer is not responsible for any misuse, data loss, or legal issues arising from the use of this software.

---

## Links

- Developer: Danial
- Website: https://danials.org
- Repository: https://github.com/danial2026/v2ray_client
- License: [GPL-3.0](https://www.gnu.org/licenses/gpl-3.0.en.html)
