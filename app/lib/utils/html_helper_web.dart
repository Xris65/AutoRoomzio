import 'package:web/web.dart' as web;

void clearWebUrl() {
  final web.Location loc = web.window.location;
  final String hash = loc.hash;
  final String cleanUrl = hash.contains('token=')
      ? loc.pathname
      : '${loc.pathname}${hash.split('?').first}';
  web.window.history.replaceState(null, '', cleanUrl);
}

String getWebRawFragment() => web.window.location.hash;
