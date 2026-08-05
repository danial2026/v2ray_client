import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:v2ray_dan/v2ray_dan.dart';
import '../models/v2ray_server.dart';
import '../theme/app_theme.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final _pasteController = TextEditingController();
  final _picker = ImagePicker();
  final V2ray _v2ray = V2ray(onStatusChanged: (_) {});
  bool _isScanning = false;
  String? _parseError;

  Future<void> _scanImage(ImageSource source) async {
    setState(() {
      _isScanning = true;
      _parseError = null;
    });

    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        imageQuality: 100,
      );

      if (image == null) {
        setState(() => _isScanning = false);
        return;
      }

      String? result = await _v2ray.decodeQR(image.path);

      if (result != null && result.isNotEmpty) {
        _tryImportLink(result);
      } else {
        setState(() => _isScanning = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No QR code found. Try again or paste the link.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      setState(() => _isScanning = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.errorColor),
        );
      }
    }
  }

  void _tryImportLink(String link) {
    final trimmed = link.trim();
    if (trimmed.startsWith('vmess://') || trimmed.startsWith('vless://')) {
      try {
        final server = V2RayServer.fromAnyLink(trimmed);
        if (mounted) Navigator.pop(context, server);
      } catch (e) {
        setState(() {
          _isScanning = false;
          _parseError = 'Failed to parse: ${e.toString()}';
        });
      }
      return;
    }

    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      setState(() => _isScanning = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Subscription URL found. Add it in Subscriptions.')),
        );
      }
      return;
    }

    setState(() {
      _isScanning = false;
      _parseError = 'Not a valid VMess/VLESS link';
    });
  }

  void _handlePaste() {
    setState(() => _parseError = null);
    final text = _pasteController.text.trim();
    if (text.isNotEmpty) _tryImportLink(text);
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    if (data != null && data.text != null) {
      _pasteController.text = data.text!;
      _handlePaste();
    }
  }

  @override
  void dispose() {
    _pasteController.dispose();
    _v2ray.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('IMPORT CONFIG'),
      ),
      body: _isScanning
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Scanning...', style: TextStyle(fontSize: 12)),
                ],
              ),
            )
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                child: Column(
                  children: [
                    Icon(Icons.qr_code_2, size: 64, color: Colors.white.withValues(alpha: 0.1)),
                    const SizedBox(height: 24),
                    if (Platform.isAndroid)
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: () => _scanImage(ImageSource.camera),
                          icon: const Icon(Icons.camera_alt, size: 16),
                          label: const Text('Scan with Camera'),
                        ),
                      ),
                    if (Platform.isAndroid) const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: () => _scanImage(ImageSource.gallery),
                        icon: const Icon(Icons.image, size: 16),
                        label: const Text('Pick QR Code Image'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Open an image containing a QR code to import',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.3)),
                    ),
                    const SizedBox(height: 32),
                    Row(
                      children: [
                        Expanded(child: Container(height: 1, color: Colors.white.withValues(alpha: 0.05))),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text('OR', style: TextStyle(fontSize: 10, letterSpacing: 2, color: Colors.white.withValues(alpha: 0.3))),
                        ),
                        Expanded(child: Container(height: 1, color: Colors.white.withValues(alpha: 0.05))),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _pasteController,
                      decoration: const InputDecoration(
                        labelText: 'VMess / VLESS Link',
                        hintText: 'Paste configuration link here',
                      ),
                      maxLines: 4,
                      style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                      onChanged: (_) => setState(() => _parseError = null),
                    ),
                    if (_parseError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(_parseError!, style: const TextStyle(color: AppTheme.errorColor, fontSize: 11)),
                      ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(onPressed: _handlePaste, child: const Text('Import')),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: _pasteFromClipboard,
                        icon: const Icon(Icons.content_paste, size: 16),
                        label: const Text('Paste from Clipboard'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
