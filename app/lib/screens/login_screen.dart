import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../storage_service.dart';
import 'setup_screen.dart';

/// Shows the real MyRoomz login page in a WebView.
/// Once the user is authenticated, we extract the OIDC tokens from
/// the browser's localStorage (where the web app stores them) and
/// navigate to the workspace setup screen.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final WebViewController _controller;
  final _storage = StorageService();
  bool _extracting = false;

  // Key used by the OIDC client library in the web app's localStorage
  static const String _oidcKey = 'oidc.user:https://login.roomz.io:my-roomz';

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) => _tryExtractToken(url),
        ),
      )
      ..loadRequest(Uri.parse('https://my.roomz.io'));
  }

  Future<void> _tryExtractToken(String url) async {
    // Only attempt extraction once we're back on the main app (post-login)
    if (!url.startsWith('https://my.roomz.io') || _extracting) return;

    setState(() => _extracting = true);

    // Inject JS to read the OIDC user object from localStorage
    final result = await _controller.runJavaScriptReturningResult(
      "window.localStorage.getItem('$_oidcKey')",
    );

    final raw = result.toString();

    // result is a JSON string wrapped in JS string quotes — strip them
    if (raw == 'null' || raw.isEmpty || raw == 'undefined') {
      setState(() => _extracting = false);
      return;
    }

    try {
      final cleaned = raw.startsWith('"') ? jsonDecode(raw) as String : raw;
      final oidcUser = jsonDecode(cleaned) as Map<String, dynamic>;

      final refreshToken = oidcUser['refresh_token'] as String?;
      final accessToken = oidcUser['access_token'] as String?;

      if (refreshToken == null || accessToken == null) {
        setState(() => _extracting = false);
        return;
      }

      await _storage.saveRefreshToken(refreshToken);

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => SetupScreen(accessToken: accessToken),
        ),
      );
    } catch (e) {
      // Not yet logged in or unexpected format — silently wait
      setState(() => _extracting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connexion MyRoomz'),
        actions: [
          if (_extracting)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}
