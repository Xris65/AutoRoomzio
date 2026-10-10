import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_windows/webview_windows.dart';
import '../api_service.dart';
import '../storage_service.dart';
import 'setup_screen.dart';
import 'home_screen.dart';
import '../token_crypto.dart';
import '../utils/html_helper.dart';

/// Shows the real MyRoomz login page.
/// - Android: webview_flutter
/// - Windows:  webview_windows (WebView2 / Edge)
/// - Web: Direct Email + Password login via Cloudflare PKCE Worker (or QR Code URL)
class LoginScreen extends StatefulWidget {
  final bool ignoreUrlToken;
  const LoginScreen({super.key, this.ignoreUrlToken = false});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _storage = StorageService();
  final _api = RoomzApiService();
  bool _extracting = false;
  bool _windowsReady = false;

  // Web login form controllers & state
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _webLoggingIn = false;
  bool _obscurePassword = true;
  String? _webError;

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
    if (kIsWeb) {
      if (widget.ignoreUrlToken) {
        // Prevent infinite loop on invalid tokens
        _storage.clearAllData();
      } else {
        _checkWebToken();
      }
    } else if ((!kIsWeb && Platform.isAndroid)) {
      _initAndroid();
    } else if ((!kIsWeb && Platform.isWindows)) {
      _initWindows();
    }
  }

  // ── Initialisation ────────────────────────────────────────────────────────

  void _checkWebToken() async {
    final params = Uri.base.queryParameters;
    final tokenEncrypted = params['token'];
    
    if (tokenEncrypted != null && tokenEncrypted.isNotEmpty) {
      // Extract everything BEFORE clearing the URL
      final bId = params['b'];
      final fId = params['f'];
      final wId = params['w'];
      final wName = params['wn'];

      // Clean URL in browser address bar instantly
      clearWebUrl();
      
      // 1. Decrypt token
      final token = TokenCryptoService.decryptToken(tokenEncrypted);
      if (token == null) {
        // Invalid or corrupted token, clear everything
        await _storage.clearAllData();
        return;
      }
      
      // 2. Extract workspace context if present
      if (bId != null && bId.isNotEmpty) await _storage.saveBuildingId(bId);
      if (fId != null && fId.isNotEmpty) await _storage.saveFloorId(fId);
      if (wId != null && wId.isNotEmpty) await _storage.saveWorkspaceId(wId);
      
      // Also restore workspace display name
      if (wName != null && wName.isNotEmpty) {
        await _storage.saveWorkspaceName(Uri.decodeComponent(wName));
      }
      
      // 3. Save refresh token
      await _storage.saveRefreshToken(token);

      final currentWsId = await _storage.getWorkspaceId();
      if (currentWsId != null && currentWsId.isNotEmpty) {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => const HomeScreen(),
            settings: const RouteSettings(name: '/'),
          ),
        );
      } else {
        final accessToken = await _api.refreshMyToken(force: true);
        if (!mounted) return;
        if (accessToken != null && accessToken.isNotEmpty) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => SetupScreen(accessToken: accessToken),
              settings: const RouteSettings(name: '/'),
            ),
          );
        } else {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => const HomeScreen(),
              settings: const RouteSettings(name: '/'),
            ),
          );
        }
      }
    } else {
      // No token in URL: Wipe state clean to force fresh session
      await _storage.clearAllData();
    }
  }

  Future<void> _handleWebLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _webError = 'Veuillez renseigner votre email et votre mot de passe.');
      return;
    }

    setState(() {
      _webLoggingIn = true;
      _webError = null;
    });

    try {
      final accessToken = await _api.login(email, password);

      if (!mounted) return;

      if (accessToken == null || accessToken.isEmpty) {
        setState(() {
          _webLoggingIn = false;
          _webError = 'Email ou mot de passe Roomz incorrect.';
        });
        return;
      }

      final currentWsId = await _storage.getWorkspaceId();
      if (!mounted) return;

      if (currentWsId != null && currentWsId.isNotEmpty) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => const HomeScreen(),
            settings: const RouteSettings(name: '/'),
          ),
        );
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => SetupScreen(accessToken: accessToken),
            settings: const RouteSettings(name: '/'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _webLoggingIn = false;
          _webError = 'Erreur réseau : $e';
        });
      }
    }
  }

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
        final currentWsId = await _storage.getWorkspaceId();
        if (!mounted) return;
        if (currentWsId != null && currentWsId.isNotEmpty) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        } else {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => SetupScreen(accessToken: accessToken)),
          );
        }
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
    _emailController.dispose();
    _passwordController.dispose();
    if ((!kIsWeb && Platform.isWindows)) _windowsController.dispose();
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
    if (kIsWeb) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: AutofillGroup(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.lock_person_rounded, size: 56, color: Colors.blue),
                      const SizedBox(height: 12),
                      const Text(
                        'Connexion MyRoomz',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Connectez-vous avec votre email et votre mot de passe Roomz.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.username, AutofillHints.email],
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Email professionnel',
                          prefixIcon: Icon(Icons.email_outlined),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        autofillHints: const [AutofillHints.password],
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _webLoggingIn ? null : _handleWebLogin(),
                        decoration: InputDecoration(
                          labelText: 'Mot de passe Roomz',
                          prefixIcon: const Icon(Icons.key_outlined),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword ? Icons.visibility_off : Icons.visibility,
                            ),
                            onPressed: () {
                              setState(() => _obscurePassword = !_obscurePassword);
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () {
                            launchUrl(
                              Uri.parse('https://login.roomz.io/forgot-password'),
                              mode: LaunchMode.externalApplication,
                            );
                          },
                          child: const Text(
                            'Créer / Réinitialiser mon mot de passe Roomz',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                      if (_webError != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.redAccent),
                          ),
                          child: Text(
                            _webError!,
                            style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _webLoggingIn ? null : _handleWebLogin,
                          child: _webLoggingIn
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text(
                                  'Se connecter',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Divider(),
                      const SizedBox(height: 8),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.qr_code_scanner, size: 16, color: Colors.grey),
                          SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'Vous pouvez aussi scanner le QR Code depuis l\'application PC.',
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    if ((!kIsWeb && Platform.isAndroid)) {
      if (_androidController == null) {
        return const Center(child: CircularProgressIndicator());
      }
      return WebViewWidget(controller: _androidController!);
    }

    if ((!kIsWeb && Platform.isWindows)) {
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

