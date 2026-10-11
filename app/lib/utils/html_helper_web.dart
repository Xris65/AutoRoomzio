// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;

void clearWebUrl() {
  final loc = html.window.location;
  final cleanUrl = '${loc.pathname}${loc.hash}';
  html.window.history.replaceState(null, '', cleanUrl);
}
