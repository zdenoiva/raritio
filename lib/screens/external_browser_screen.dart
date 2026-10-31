import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// External web pages are intentionally isolated from the main app WebView.
/// This keeps the app bridge and local assets out of third-party pages and
/// gives Android back a route to pop instead of closing Raritio.
class ExternalBrowserScreen extends StatefulWidget {
  const ExternalBrowserScreen({super.key, required this.url});

  final String url;

  @override
  State<ExternalBrowserScreen> createState() => _ExternalBrowserScreenState();
}

class _ExternalBrowserScreenState extends State<ExternalBrowserScreen> {
  late final WebViewController _controller;
  int _progress = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0A0A0C))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (value) {
            if (mounted) setState(() => _progress = value);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _progress = 100);
          },
          onWebResourceError: (error) {
            if (!mounted || error.isForMainFrame == false) return;
            setState(() => _error = error.description);
          },
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri == null) return NavigationDecision.prevent;
            if (uri.scheme == 'http' || uri.scheme == 'https') {
              return NavigationDecision.navigate;
            }
            return NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    final title = Uri.tryParse(widget.url)?.host ?? 'Odkaz';
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0C),
        foregroundColor: Colors.white,
        title: Text(title, overflow: TextOverflow.ellipsis),
      ),
      body: Column(
        children: [
          if (_progress < 100)
            LinearProgressIndicator(
              value: _progress <= 0 ? null : _progress / 100,
              minHeight: 2,
              backgroundColor: const Color(0xFF16161A),
            ),
          Expanded(
            child: _error == null
                ? WebViewWidget(controller: _controller)
                : _ExternalError(
                    message: _error!,
                    onRetry: () {
                      setState(() {
                        _error = null;
                        _progress = 0;
                      });
                      _controller.reload();
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ExternalError extends StatelessWidget {
  const _ExternalError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.public_off_rounded,
              color: Color(0xFFFCA5A5),
              size: 42,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF94A3B8), height: 1.4),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Skúsiť znova')),
          ],
        ),
      ),
    );
  }
}
