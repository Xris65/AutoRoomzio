import 'package:web/web.dart' as web;

void clearWebUrl() {
  final loc = web.window.location;
  final cleanUrl = '${loc.pathname}${loc.hash}';
  web.window.history.replaceState(null, '', cleanUrl);
}
