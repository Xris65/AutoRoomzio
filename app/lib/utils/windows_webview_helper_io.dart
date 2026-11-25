import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:webview_windows/webview_windows.dart';

/// Native `dart:io` wrapper around `package:webview_windows`.
class WindowsWebViewHelper {
  final WebviewController _controller = WebviewController();

  bool get isInitialized => _controller.value.isInitialized;

  Stream<String> get urlStream => _controller.url;

  Stream<void> get onNavigationCompleted => _controller.loadingState
      .where((LoadingState state) => state == LoadingState.navigationCompleted)
      .map<void>((LoadingState _) {});

  Future<void> initialize() async {
    await _controller.initialize();
  }

  Future<void> clearCookiesAndCache() async {
    await _controller.clearCookies();
    await _controller.clearCache();
  }

  Future<String?> executeScript(String script) async {
    final Object? result = await _controller.executeScript(script);
    return result?.toString();
  }

  Future<void> loadUrl(String url) async {
    await _controller.loadUrl(url);
  }

  Widget buildWebView() {
    return Webview(_controller);
  }

  void dispose() {
    if (_controller.value.isInitialized) {
      _controller.dispose();
    }
  }
}
