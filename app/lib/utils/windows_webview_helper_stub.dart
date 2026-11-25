import 'dart:async';
import 'package:flutter/widgets.dart';

/// Web/Wasm-safe stub for Windows WebView2 so `package:webview_windows`
/// (pre-Dart 3) is never transitively imported by `dart2js` or `dart2wasm`.
class WindowsWebViewHelper {
  bool get isInitialized => false;

  Stream<String> get urlStream => const Stream<String>.empty();

  Stream<void> get onNavigationCompleted => const Stream<void>.empty();

  Future<void> initialize() async {
    throw UnsupportedError('Windows WebView is not supported on Web.');
  }

  Future<void> clearCookiesAndCache() async {}

  Future<String?> executeScript(String script) async => null;

  Future<void> loadUrl(String url) async {}

  Widget buildWebView() {
    return const SizedBox.shrink();
  }

  void dispose() {}
}
