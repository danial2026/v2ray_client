# Changelog

All notable changes to this project will be documented in this file.

## [0.0.6] - 2025-12-20
### Fixed
- Fixed critical crash in release builds caused by R8 obfuscation stripping V2Ray native bindings.
- Added Proguard rules for `libv2ray` and `go` packages.
- Added `consumer-rules.pro` to `v2ray_dan` package to automatically apply keep rules.

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

## [0.0.4] - 2025-12-19
### Added
- GPL-3.0 License.
- App documentation and initial README improvements.
