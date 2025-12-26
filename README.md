# Flaming Cherubim

A fast, modern, and high-performance V2Ray VPN client built with Flutter.
- **Android**: Full system VPN support.
- **macOS**: High-performance Proxy support (SOCKS/HTTP).

Uses a custom native plugin to run the official V2Ray core directly.

### Android

![Screenshot 1](screenshots/android/screenshot-1.png)
![Screenshot 2](screenshots/android/screenshot-2.png)
![Screenshot 3](screenshots/android/screenshot-3.png)

### macOS

![Screenshot 1](screenshots/macos/screenshot-1.png)
![Screenshot 2](screenshots/macos/screenshot-2.png)
![Screenshot 3](screenshots/macos/screenshot-3.png)


## Features

### Protocol Support

Full support for VMess and VLESS protocols, custom TLS settings (SNI, ALPN, fingerprint spoofing), and Reality and XTLS support.

### Connection Modes

VPN Mode provides full system VPN with traffic routing for all apps. Proxy-Only Mode offers local SOCKS5 (10808) and HTTP (10809) proxy without VPN overhead.

### Advanced Features

- Custom ping settings with configurable intervals and methods
- Home screen widgets for connection control and status (Android)
- Real-time traffic monitoring and RAM usage indicators
- Minimal UI with clean, dark-themed interface
- Comprehensive logging and diagnostics
- Kill switch for graceful shutdown protection
- Built-in browser with automatic proxy routing
- DNS leak protection and intelligent server selection
- Privacy censorship mode for server addresses

## Disclaimer

> [!NOTE]
> I coded this over the weekends, it might have bugs and it's not production-ready, and the macos version is fully vibe coded.

## Full Documentation

For complete documentation about the app architecture, features, and technical details, see [DOCUMENTATION.md](DOCUMENTATION.md).

## License

GNU General Public License v3.0 (GPL-3.0)
