import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_windows/webview_windows.dart';
import '../storage_service.dart';
import 'setup_screen.dart';

/// Shows the real MyRoomz login page.
/// - Android: webview_flutter
/// - Windows:  webview_windows (WebView2 / Edge)
/// After login, extracts the OIDC tokens from localStorage automatically.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _storage = StorageService();
  bool _extracting = false;
  bool _windowsReady = false;

  // Key used by the OIDC client library in the web app's localStorage
  static const String _oidcKey = 'oidc.user:https://login.roomz.io:my-roomz';
  static const String _startUrl = 'https://my.roomz.io';

  // Android controller
  WebViewController? _androidController;

  // Windows controller
  final WebviewController _windowsController = WebviewController();

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) {
      _initAndroid();
    } else if (Platform.isWindows) {
      _initWindows();
    }
  }

  void _initAndroid() {
    _androidController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: _tryExtractTokenAndroid,
      ))
      ..loadRequest(Uri.parse(_startUrl));
  }

  Future<void> _initWindows() async {
    await _windowsController.initialize();
    _windowsController.url.listen((url) {
      if (url.startsWith('https://my.roomz.io')) {
        _tryExtractTokenWindows();
      }
    });
    await _windowsController.loadUrl(_startUrl);
    if (mounted) setState(() => _windowsReady = true);
  }

  // ── Token extraction ──────────────────────────────────────────────────────

  Future<void> _tryExtractTokenAndroid(String url) async {
    if (!url.startsWith('https://my.roomz.io') || _extracting || _androidController == null) return;
    setState(() => _extracting = true);

    final result = await _androidController!.runJavaScriptReturningResult(
      "window.localStorage.getItem('$_oidcKey')",
    );
    await _processOidcResult(result.toString());
  }

  Future<void> _tryExtractTokenWindows() async {
    if (_extracting) return;
    setState(() => _extracting = true);

    final result = await _windowsController.executeScript(
      "window.localStorage.getItem('$_oidcKey')",
    );
    await _processOidcResult(result?.toString() ?? 'null');
  }

  Future<void> _processOidcResult(String raw) async {
    if (raw == 'null' || raw.isEmpty || raw == 'undefined' || raw == 'null\n') {
      if (mounted) setState(() => _extracting = false);
      return;
    }

    try {
      // Result may be a JS-stringified JSON — unwrap one level if needed
      final cleaned = raw.startsWith('"') ? jsonDecode(raw) as String : raw;
      final oidcUser = jsonDecode(cleaned) as Map<String, dynamic>;

      final refreshToken = oidcUser['refresh_token'] as String?;
      final accessToken = oidcUser['access_token'] as String?;

      if (refreshToken == null || accessToken == null) {
        if (mounted) setState(() => _extracting = false);
        return;
      }

      await _storage.saveRefreshToken(refreshToken);

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => SetupScreen(accessToken: accessToken)),
      );
    } catch (_) {
      if (mounted) setState(() => _extracting = false);
    }
  }

  @override
  void dispose() {
    if (Platform.isWindows) _windowsController.dispose();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

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
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (Platform.isAndroid) {
      return WebViewWidget(controller: _androidController!);
    }

    if (Platform.isWindows) {
      return _windowsReady
          ? Webview(_windowsController)
          : const Center(child: CircularProgressIndicator());
    }

    // Unsupported platform fallback
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.warning_amber_rounded, size: 64, color: Colors.orange),
            SizedBox(height: 16),
            Text(
              'Plateforme non supportée.',
              style: TextStyle(fontSize: 18),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 8),
            Text(
              'Utilisez Android ou Windows.',
              style: TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
