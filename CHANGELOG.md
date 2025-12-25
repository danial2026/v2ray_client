# Changelog

All notable changes to this project will be documented in this file.

---

## [0.0.8] - 2025-12-25
### Added
- **Circle Home Screen Widget**: New circular widget variant with connection status.
- **Usage Statistics**: Real-time upload, download, and memory usage monitoring in the AppBar (toggleable in Settings).
- **IP & Country Flag**: Display current connected IP address and country flag in the AppBar.
- **macOS Support**: Initial platform configuration for macOS.
- **Privacy Censoring**: Option to censor server addresses in the list for privacy (hides middle characters).
- **WebView Improvements**: Added URL history, navigation controls, and basic download handling.

### Changed
- Improved Settings screen organization (formerly Ping Engine).
- Enhanced AppBar layout to accommodate new status indicators.

---

## [0.0.7] - 2025-12-20
### Added
- Android home screen widget for quick VPN connect/disconnect control.
- In-app changelog viewer in Settings page (About section).

---

## [0.0.6] - 2025-12-20
### Fixed
- Fixed critical crash in release builds caused by R8 obfuscation stripping V2Ray native bindings.
- Added Proguard rules for `libv2ray` and `go` packages.
- Added `consumer-rules.pro` to `v2ray_dan` package to automatically apply keep rules.

---

## [0.0.5] - 2025-12-19
### Added
- Custom v2ray_dan plugin implementation
- Built-in browser with network diagnostics
- Full logging system (App, Core, tun2socks)
- Kill switch protection
- VPN and Proxy-Only modes
- Intelligent ping system
- Modern minimal UI
- DNS leak protection

### Changed
- Switched to "Proxy Only" mode support.
- Updated WebView to use VPN connection.
- Refined VPN service implementation for better stability.

---

## [0.0.4] - 2025-12-19
### Added
- GPL-3.0 License.
- App documentation and initial README improvements.
