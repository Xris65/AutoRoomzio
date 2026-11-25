import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../api_service.dart';
import '../storage_service.dart';
import '../token_crypto.dart';
import '../utils/error_sanitizer.dart';
import '../utils/html_helper.dart';
import '../utils/windows_webview_helper.dart';
import 'home_screen.dart';
import 'setup_screen.dart';

/// Shows the real MyRoomz login page.
/// - Android / iOS: webview_flutter
/// - Windows: webview_windows (WebView2 / Edge), with graceful fallback to direct PKCE form
/// - Web: Direct Email + Password login via Cloudflare PKCE Worker (or `#token=` / `?token=` QR URL)
class LoginScreen extends StatefulWidget {
  final bool ignoreUrlToken;
  final bool forceWebLayout;
  final StorageService? storageService;
  final RoomzApiService? apiService;

  const LoginScreen({
    super.key,
    this.ignoreUrlToken = false,
    this.forceWebLayout = false,
    this.storageService,
    this.apiService,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final StorageService _storage;
  late final RoomzApiService _api;
  bool _extracting = false;
  bool _windowsReady = false;
  bool _useDirectFormFallback = false;

  // Web / direct login form controllers & state
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _rememberEmail = true;
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

  // Android / iOS controller
  WebViewController? _androidController;

  // Windows controller wrapper (isolated from WebAssembly via conditional import)
  WindowsWebViewHelper? _windowsHelper;
  StreamSubscription<String>? _windowsUrlSub;
  StreamSubscription<void>? _windowsLoadingSub;
  String _currentWindowsUrl = '';

  bool get _isMobileWebViewPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  bool get _isWindowsPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  static bool _isRoomzHost(String url) {
    final Uri? uri = Uri.tryParse(url);
    return uri != null &&
        uri.scheme == 'https' &&
        (uri.host == 'my.roomz.io' || uri.host.endsWith('.roomz.io'));
  }

  @override
  void initState() {
    super.initState();
    _storage = widget.storageService ?? StorageService();
    _api = widget.apiService ?? RoomzApiService();
    if (kIsWeb || widget.forceWebLayout) {
      _initWeb();
    } else if (_isMobileWebViewPlatform) {
      _initAndroid();
    } else if (_isWindowsPlatform) {
      _initWindows();
    }
  }

  Future<void> _initWeb() async {
    if (widget.ignoreUrlToken) {
      // Clear only expired/invalid auth tokens without wiping configured desks/rules/favorites
      await _storage.clearTokens();
    } else {
      await _checkWebToken();
    }
    if (mounted) {
      await _loadRememberedEmail();
    }
  }

  Future<void> _loadRememberedEmail() async {
    final bool remember = await _storage.getRememberEmail();
    if (!mounted) return;
    setState(() => _rememberEmail = remember);
    if (remember) {
      final String? email = await _storage.getSavedEmail();
      if (!mounted) return;
      if (email != null && email.isNotEmpty && _emailController.text.isEmpty) {
        _emailController.text = email;
      }
    }
  }

  // ── Initialisation ────────────────────────────────────────────────────────

  static Map<String, String> _extractWebPairingParams(Uri uri) {
    final String fallbackHash = getWebRawFragment();
    final String rawFragment =
        uri.fragment.isNotEmpty ? uri.fragment : fallbackHash;
    if (rawFragment.isNotEmpty) {
      String normalized = rawFragment;
      if (normalized.startsWith('#')) {
        normalized = normalized.substring(1);
      }
      if (normalized.startsWith('/?')) {
        normalized = normalized.substring(2);
      } else if (normalized.startsWith('/')) {
        normalized = normalized.substring(1);
      } else if (normalized.startsWith('?')) {
        normalized = normalized.substring(1);
      }
      try {
        final Map<String, String> fragmentParams =
            Uri.splitQueryString(normalized);
        final String? fragmentToken = fragmentParams['token'];
        if (fragmentToken != null && fragmentToken.isNotEmpty) {
          return fragmentParams;
        }
      } catch (_) {
        // Fallback to queryParameters if fragment is not query-formatted
      }
    }
    return uri.queryParameters;
  }

  Future<void> _checkWebToken() async {
    final Map<String, String> params = _extractWebPairingParams(Uri.base);
    final String? tokenEncrypted = params['token'];

    if (tokenEncrypted != null && tokenEncrypted.isNotEmpty) {
      // Extract everything BEFORE clearing the URL
      final String? bId = params['b'];
      final String? fId = params['f'];
      final String? wId = params['w'];
      final String? wName = params['wn'];

      // Clean URL in browser address bar immediately before any async processing
      clearWebUrl();

      // 1. Decrypt token
      final String? token = TokenCryptoService.decryptToken(tokenEncrypted);
      if (token == null) {
        await _storage.clearTokens();
        return;
      }

      // 2. Extract workspace context if present
      if (bId != null && bId.isNotEmpty) await _storage.saveBuildingId(bId);
      if (fId != null && fId.isNotEmpty) await _storage.saveFloorId(fId);
      if (wId != null && wId.isNotEmpty) await _storage.saveWorkspaceId(wId);

      // Also restore workspace display name
      if (wName != null && wName.isNotEmpty) {
        String decodedName = wName;
        if (wName.contains('%')) {
          try {
            decodedName = Uri.decodeComponent(wName);
          } catch (_) {
            decodedName = wName;
          }
        }
        await _storage.saveWorkspaceName(decodedName);
      }

      // 3. Save refresh token
      await _storage.saveRefreshToken(token);

      final String? currentWsId = await _storage.getWorkspaceId();
      if (currentWsId != null && currentWsId.isNotEmpty) {
        if (!mounted) return;
        Navigator.of(context).pushReplacement<void, void>(
          MaterialPageRoute<void>(
            builder: (_) => const HomeScreen(),
            settings: const RouteSettings(name: '/'),
          ),
        );
      } else {
        String? accessToken;
        try {
          accessToken = await _api.refreshMyToken(force: true);
        } catch (_) {
          accessToken = null;
        }
        if (!mounted) return;
        if (accessToken != null && accessToken.isNotEmpty) {
          Navigator.of(context).pushReplacement<void, void>(
            MaterialPageRoute<void>(
              builder: (_) => SetupScreen(accessToken: accessToken!),
              settings: const RouteSettings(name: '/'),
            ),
          );
        } else {
          Navigator.of(context).pushReplacement<void, void>(
            MaterialPageRoute<void>(
              builder: (_) => const HomeScreen(),
              settings: const RouteSettings(name: '/'),
            ),
          );
        }
      }
    }
    // Never wipe configured workspaces, automation rules, or favorites when opening LoginScreen without a URL token!
  }

  Future<void> _handleWebLogin() async {
    setState(() => _webError = null);

    if (_formKey.currentState == null || !_formKey.currentState!.validate()) {
      return;
    }

    final String email = _emailController.text.trim();
    final String password = _passwordController.text;

    setState(() {
      _webLoggingIn = true;
    });

    try {
      final String? accessToken = await _api.login(email, password);

      if (!mounted) return;

      if (accessToken == null || accessToken.isEmpty) {
        setState(() {
          _webLoggingIn = false;
          _webError = 'Email ou mot de passe Roomz incorrect.';
        });
        return;
      }

      await _storage.saveRememberEmail(_rememberEmail);
      if (_rememberEmail) {
        await _storage.saveSavedEmail(email);
      } else {
        await _storage.clearSavedEmail();
      }

      final String? currentWsId = await _storage.getWorkspaceId();
      if (!mounted) return;

      if (currentWsId != null && currentWsId.isNotEmpty) {
        Navigator.of(context).pushReplacement<void, void>(
          MaterialPageRoute<void>(
            builder: (_) => const HomeScreen(),
            settings: const RouteSettings(name: '/'),
          ),
        );
      } else {
        Navigator.of(context).pushReplacement<void, void>(
          MaterialPageRoute<void>(
            builder: (_) => SetupScreen(accessToken: accessToken),
            settings: const RouteSettings(name: '/'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _webLoggingIn = false;
          _webError = ErrorSanitizer.sanitize(e);
        });
      }
    }
  }

  Future<void> _initAndroid() async {
    try {
      // Clear cookies before instantiating controller to prevent auto-login
      await WebViewCookieManager().clearCookies();

      final WebViewController controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageFinished: _onPageFinishedAndroid,
          ),
        );

      _androidController = controller;
      await controller.clearCache();
      await controller.clearLocalStorage();
      await controller.loadRequest(Uri.parse(_startUrl));

      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        setState(() {
          _useDirectFormFallback = true;
          _webError = ErrorSanitizer.sanitize(e);
        });
        await _loadRememberedEmail();
      }
    }
  }

  Future<void> _initWindows() async {
    final WindowsWebViewHelper helper = WindowsWebViewHelper();
    _windowsHelper = helper;
    try {
      await helper.initialize();

      // Clear cookies and cache for Windows to prevent auto-login
      try {
        await helper.clearCookiesAndCache();
      } catch (_) {}

      // Track current URL locally so we don't subscribe to the stream multiple times
      await _windowsUrlSub?.cancel();
      _windowsUrlSub = helper.urlStream.listen((String url) {
        _currentWindowsUrl = url;
      });

      // Trigger extraction when a page finishes loading on a verified Roomz host
      await _windowsLoadingSub?.cancel();
      _windowsLoadingSub = helper.onNavigationCompleted.listen((void _) {
        if (_isRoomzHost(_currentWindowsUrl)) {
          _tryExtract(() => helper.executeScript(_extractJs));
        }
      });

      await helper.loadUrl(_startUrl);
      if (mounted) {
        setState(() => _windowsReady = true);
      }
    } catch (_) {
      // Graceful fallback when Edge WebView2 Runtime is missing or blocked (e.g. enterprise PC)
      await _windowsUrlSub?.cancel();
      await _windowsLoadingSub?.cancel();
      _windowsUrlSub = null;
      _windowsLoadingSub = null;
      helper.dispose();
      _windowsHelper = null;
      if (!mounted) return;
      setState(() {
        _useDirectFormFallback = true;
      });
      await _loadRememberedEmail();
    }
  }

  // ── Token extraction ──────────────────────────────────────────────────────

  Future<void> _onPageFinishedAndroid(String url) async {
    final WebViewController? controller = _androidController;
    if (!_isRoomzHost(url) || controller == null) return;
    await _tryExtract(() async {
      final Object result =
          await controller.runJavaScriptReturningResult(_extractJs);
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
      await Future<void>.delayed(const Duration(seconds: 1));

      final String? raw = await readFn();
      if (raw == null ||
          raw == 'null' ||
          raw.trim().isEmpty ||
          raw == 'undefined') {
        continue; // not ready yet, retry
      }

      try {
        final String trimmed = raw.trim();
        // Result may arrive as a JS-quoted string — unwrap one level if needed
        final Object? outerDecoded =
            trimmed.startsWith('"') ? jsonDecode(trimmed) : trimmed;
        final String cleaned =
            outerDecoded is String ? outerDecoded : trimmed;
        final Object? decodedObj = jsonDecode(cleaned);
        if (decodedObj is! Map<dynamic, dynamic>) continue;
        final Map<String, dynamic> oidcUser =
            Map<String, dynamic>.from(decodedObj);

        final String? refreshToken = oidcUser['refresh_token']?.toString();
        final String? accessToken = oidcUser['access_token']?.toString();

        if (refreshToken == null ||
            refreshToken.isEmpty ||
            accessToken == null ||
            accessToken.isEmpty) {
          continue;
        }

        await _storage.saveRefreshToken(refreshToken);

        if (!mounted) return;
        final String? currentWsId = await _storage.getWorkspaceId();
        if (!mounted) return;
        if (currentWsId != null && currentWsId.isNotEmpty) {
          Navigator.of(context).pushReplacement<void, void>(
            MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
          );
        } else {
          Navigator.of(context).pushReplacement<void, void>(
            MaterialPageRoute<void>(
              builder: (_) => SetupScreen(accessToken: accessToken),
            ),
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
    _windowsUrlSub?.cancel();
    _windowsLoadingSub?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    _windowsHelper?.dispose();
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
    if (kIsWeb || widget.forceWebLayout || _useDirectFormFallback) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: AutofillGroup(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        const Icon(
                          Icons.lock_person_rounded,
                          size: 56,
                          color: Colors.blue,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Connexion MyRoomz',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Connectez-vous avec votre email et votre mot de passe Roomz.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                        const SizedBox(height: 24),
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const <String>[
                            AutofillHints.username,
                            AutofillHints.email,
                          ],
                          textInputAction: TextInputAction.next,
                          validator: (String? value) {
                            final String val = (value ?? '').trim();
                            if (val.isEmpty ||
                                !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                    .hasMatch(val)) {
                              return 'Veuillez saisir une adresse email valide.';
                            }
                            return null;
                          },
                          decoration: const InputDecoration(
                            labelText: 'Email professionnel',
                            prefixIcon: Icon(Icons.email_outlined),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          autofillHints: const <String>[AutofillHints.password],
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (String _) {
                            if (!_webLoggingIn) {
                              _handleWebLogin();
                            }
                          },
                          validator: (String? value) {
                            final String val = (value ?? '').trim();
                            if (val.isEmpty) {
                              return 'Veuillez saisir votre mot de passe.';
                            }
                            if (val.length < 6) {
                              return 'Le mot de passe doit contenir au moins 6 caractères.';
                            }
                            return null;
                          },
                          decoration: InputDecoration(
                            labelText: 'Mot de passe Roomz',
                            prefixIcon: const Icon(Icons.key_outlined),
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                              onPressed: () {
                                setState(
                                  () => _obscurePassword = !_obscurePassword,
                                );
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        CheckboxListTile(
                          value: _rememberEmail,
                          onChanged: (bool? val) {
                            setState(() => _rememberEmail = val ?? false);
                          },
                          title: const Text(
                            'Se souvenir de mon email',
                            style: TextStyle(fontSize: 14),
                          ),
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          dense: true,
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () {
                              launchUrl(
                                Uri.parse(
                                  'https://login.roomz.io/forgot-password',
                                ),
                                mode: LaunchMode.externalApplication,
                              );
                            },
                            child: const Text(
                              'Créer / Réinitialiser mon mot de passe Roomz',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                        if (_webError != null) ...<Widget>[
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
                              style: const TextStyle(
                                color: Colors.redAccent,
                                fontSize: 13,
                              ),
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
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text(
                                    'Se connecter',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Divider(),
                        const SizedBox(height: 8),
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Icon(
                              Icons.qr_code_scanner,
                              size: 16,
                              color: Colors.grey,
                            ),
                            SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'Vous pouvez aussi scanner le QR Code depuis l\'application PC.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
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
        ),
      );
    }

    if (_isMobileWebViewPlatform) {
      if (_androidController == null) {
        return const Center(child: CircularProgressIndicator());
      }
      return WebViewWidget(controller: _androidController!);
    }

    if (_isWindowsPlatform) {
      return _windowsReady && _windowsHelper != null
          ? _windowsHelper!.buildWebView()
          : const Center(child: CircularProgressIndicator());
    }

    // Unsupported platform fallback
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(Icons.warning_amber_rounded, size: 64, color: Colors.orange),
            SizedBox(height: 16),
            Text('Plateforme non supportée.', style: TextStyle(fontSize: 18)),
            SizedBox(height: 8),
            Text(
              'Utilisez Android ou Windows.',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
