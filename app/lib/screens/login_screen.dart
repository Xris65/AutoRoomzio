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

  static const String _startUrl = 'https://my.roomz.io';

  // Searches localStorage then sessionStorage for any OIDC user object
  static const String _extractJs = r"""
    (function() {
      var stores = [localStorage, sessionStorage];
      for (var s = 0; s < stores.length; s++) {
        var store = stores[s];
        for (var i = 0; i < store.length; i++) {
          var key = store.key(i);
          if (key && key.startsWith('oidc.user')) {
            return store.getItem(key);
          }
        }
      }
      return null;
    })()
  """;



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

  // ── Initialisation ────────────────────────────────────────────────────────

  void _initAndroid() async {
    // Clear cookies before instantiating controller to prevent auto-login
    await WebViewCookieManager().clearCookies();
    
    _androidController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: _onPageFinishedAndroid,
      ));
      
    await _androidController!.clearCache();
    await _androidController!.clearLocalStorage();
    await _androidController!.loadRequest(Uri.parse(_startUrl));
    
    if (mounted) setState(() {});
  }

  String _currentWindowsUrl = '';

  Future<void> _initWindows() async {
    await _windowsController.initialize();

    // Clear cookies and cache for Windows to prevent auto-login
    try {
      await _windowsController.clearCookies();
      await _windowsController.clearCache();
    } catch (_) {}

    // Track current URL locally so we don't subscribe to the stream multiple times
    _windowsController.url.listen((url) {
      _currentWindowsUrl = url;
    });

    // Trigger extraction when a page finishes loading on my.roomz.io
    _windowsController.loadingState.listen((state) async {
      if (state == LoadingState.navigationCompleted &&
          _currentWindowsUrl.startsWith('https://my.roomz.io')) {
        await _tryExtract(() async {
          final result = await _windowsController.executeScript(_extractJs);
          return result?.toString();
        });
      }
    });

    await _windowsController.loadUrl(_startUrl);
    if (mounted) setState(() => _windowsReady = true);
  }

  // ── Token extraction ──────────────────────────────────────────────────────

  Future<void> _onPageFinishedAndroid(String url) async {
    if (!url.startsWith('https://my.roomz.io') || _androidController == null) return;
    await _tryExtract(() async {
      final result = await _androidController!
          .runJavaScriptReturningResult(_extractJs);
      return result.toString();
    });
  }

  /// Shared extraction logic with retry: waits up to 5 × 1s for the OIDC
  /// library to write the token into localStorage after the redirect.
  Future<void> _tryExtract(Future<String?> Function() readFn) async {
    if (_extracting) return;
    if (mounted) setState(() => _extracting = true);

    for (int attempt = 0; attempt < 5; attempt++) {
      // Give the OIDC library a moment to write to localStorage
      await Future.delayed(const Duration(seconds: 1));

      final raw = await readFn();
      if (raw == null || raw == 'null' || raw.trim().isEmpty || raw == 'undefined') {
        continue; // not ready yet, retry
      }

      try {
        // Result may arrive as a JS-quoted string — unwrap one level if needed
        final cleaned = raw.trim().startsWith('"')
            ? jsonDecode(raw.trim()) as String
            : raw.trim();
        final oidcUser = jsonDecode(cleaned) as Map<String, dynamic>;

        final refreshToken = oidcUser['refresh_token'] as String?;
        final accessToken  = oidcUser['access_token']  as String?;

        if (refreshToken == null || accessToken == null) continue;

        await _storage.saveRefreshToken(refreshToken);

        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => SetupScreen(accessToken: accessToken)),
        );
        return; // success
      } catch (_) {
        continue;
      }
    }

    // All retries exhausted — let user keep browsing
    if (mounted) setState(() => _extracting = false);
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
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (Platform.isAndroid) {
      if (_androidController == null) {
        return const Center(child: CircularProgressIndicator());
      }
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
            Text('Plateforme non supportée.', style: TextStyle(fontSize: 18)),
            SizedBox(height: 8),
            Text('Utilisez Android ou Windows.', style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
