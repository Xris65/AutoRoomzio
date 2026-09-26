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

  // Dumps all keys from localStorage + sessionStorage for diagnostics
  static const String _debugDumpJs = r"""
    (function() {
      var out = { localStorage: {}, sessionStorage: {} };
      for (var i = 0; i < localStorage.length; i++) {
        var k = localStorage.key(i);
        out.localStorage[k] = localStorage.getItem(k);
      }
      for (var i = 0; i < sessionStorage.length; i++) {
        var k = sessionStorage.key(i);
        out.sessionStorage[k] = sessionStorage.getItem(k);
      }
      return JSON.stringify(out);
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

  Future<void> _manualSync() async {
    setState(() => _extracting = true);
    
    // First try normal extraction
    Future<String?> readFn() async {
      if (Platform.isAndroid) {
        final r = await _androidController!.runJavaScriptReturningResult(_extractJs);
        return r.toString();
      } else {
        final r = await _windowsController.executeScript(_extractJs);
        return r?.toString();
      }
    }

    final raw = await readFn();
    
    // Parse result
    try {
      if (raw != null && raw != 'null' && raw.trim().isNotEmpty && raw != 'undefined') {
        final cleaned = raw.trim().startsWith('"') ? jsonDecode(raw.trim()) as String : raw.trim();
        final oidcUser = jsonDecode(cleaned) as Map<String, dynamic>;
        
        final refreshToken = oidcUser['refresh_token'] as String?;
        final accessToken  = oidcUser['access_token']  as String?;

        if (refreshToken != null && accessToken != null) {
          await _storage.saveRefreshToken(refreshToken);
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => SetupScreen(accessToken: accessToken)),
          );
          return;
        }
      }
    } catch (_) {}

    // Failed -> Show debug dump
    if (!mounted) return;
    setState(() => _extracting = false);
    
    String debugDump = '';
    if (Platform.isAndroid) {
      final d = await _androidController!.runJavaScriptReturningResult(_debugDumpJs);
      debugDump = d.toString();
    } else {
      final d = await _windowsController.executeScript(_debugDumpJs);
      debugDump = d?.toString() ?? 'null';
    }

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Aucun token trouvé'),
        content: SingleChildScrollView(child: Text(debugDump)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))
        ],
      ),
    );
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
            )
          else
            TextButton.icon(
              onPressed: _manualSync,
              icon: const Icon(Icons.sync),
              label: const Text('Récupérer Token'),
              style: TextButton.styleFrom(foregroundColor: Colors.white),
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
            Text('Plateforme non supportée.', style: TextStyle(fontSize: 18)),
            SizedBox(height: 8),
            Text('Utilisez Android ou Windows.', style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
