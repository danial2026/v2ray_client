import 'dart:io';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../services/storage_service.dart';

class WebViewScreen extends StatefulWidget {
  final String initialUrl;

  const WebViewScreen({
    super.key,
    this.initialUrl = 'https://danials.org/network', // Default to network diagnostic
  });

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late final WebViewController _controller;
  final TextEditingController _urlController = TextEditingController();
  bool _isLoading = true;
  double _progress = 0;
  String _currentUrl = '';
  List<String> _history = [];

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.initialUrl;
    _urlController.text = _currentUrl;
    _loadHistory();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted);
    
    // setBackgroundColor is not fully supported on macOS WebView
    if (!Platform.isMacOS) {
      _controller.setBackgroundColor(Colors.black);
    }
    
    _controller
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (NavigationRequest request) {
            // Basic download handling for common file types
            final url = request.url.toLowerCase();
            if (url.endsWith('.pdf') ||
                url.endsWith('.zip') ||
                url.endsWith('.apk') ||
                url.endsWith('.dmg') ||
                url.endsWith('.iso')) {
              _launchExternal(request.url);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onProgress: (int progress) {
            setState(() {
              _progress = progress / 100;
            });
          },
          onPageStarted: (String url) {
            setState(() {
              _isLoading = true;
              _currentUrl = url;
              _urlController.text = url;
            });
          },
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
              _currentUrl = url;
            });
            _addToHistory(url);
          },
          onWebResourceError: (WebResourceError error) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text('Error: ${error.description}'),
                    backgroundColor: AppTheme.errorColor),
              );
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.initialUrl));
  }

  void _loadUrl(String url) {
    if (url.isEmpty) return;

    String finalUrl = url;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      finalUrl = 'https://$url';
    }

    _controller.loadRequest(Uri.parse(finalUrl));
  }

  Future<void> _loadHistory() async {
    final storage = await StorageService.init();
    setState(() {
      _history = storage.loadUrlHistory();
    });
  }

  Future<void> _addToHistory(String url) async {
    if (url.isEmpty || url == 'about:blank') return;

    // Avoid duplicates at the top
    if (_history.isNotEmpty && _history.first == url) return;

    setState(() {
      _history.remove(url);
      _history.insert(0, url);
      if (_history.length > 20) _history.removeLast();
    });

    final storage = await StorageService.init();
    await storage.saveUrlHistory(_history);
  }

  Future<void> _launchExternal(String url) async {
    try {
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  void _showHistory() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: const Text('Browsing History',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _history.length,
              itemBuilder: (context, index) {
                final url = _history[index];
                return ListTile(
                  leading: const Icon(Icons.history,
                      color: Colors.white54, size: 20),
                  title: Text(url,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  onTap: () {
                    Navigator.pop(context);
                    _loadUrl(url);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        titleSpacing: 0,
        title: Container(
          height: 40,
          margin: const EdgeInsets.only(right: 16),
          decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20)),
          child: TextField(
            controller: _urlController,
            style: const TextStyle(fontSize: 14, color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Search or enter website name',
              hintStyle:
                  TextStyle(color: Colors.white.withValues(alpha: 0.3)),
              prefixIcon: Icon(Icons.lock_outline,
                  size: 16, color: Colors.white.withValues(alpha: 0.5)),
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              isDense: true,
            ),
            textInputAction: TextInputAction.go,
            onSubmitted: _loadUrl,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history, size: 20),
            onPressed: _showHistory,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: () {
              setState(() {
                _isLoading = true;
                _progress = 0;
              });
              _controller.reload();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isLoading)
            LinearProgressIndicator(
              value: _progress > 0 ? _progress : null,
              backgroundColor: Colors.transparent,
              color: AppTheme.successColor,
              minHeight: 2,
            ),
          Expanded(child: WebViewWidget(controller: _controller)),
          _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios, size: 18),
                  onPressed: () async {
                    if (await _controller.canGoBack()) {
                      await _controller.goBack();
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_forward_ios, size: 18),
                  onPressed: () async {
                    if (await _controller.canGoForward()) {
                      await _controller.goForward();
                    }
                  },
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.successColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                    color: AppTheme.successColor.withValues(alpha: 0.3),
                    width: 0.5),
              ),
              child: const Row(
                children: [
                  Icon(Icons.shield_outlined,
                      size: 10, color: AppTheme.successColor),
                  SizedBox(width: 4),
                  Text(
                    'PROXIED',
                    style: TextStyle(
                        color: AppTheme.successColor,
                        fontSize: 9,
                        fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
