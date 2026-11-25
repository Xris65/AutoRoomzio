import 'package:auto_roomzio/token_crypto.dart';
import 'package:auto_roomzio/widgets/web_pairing_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WebPairingDialog.buildPairingUrl', () {
    test('places the encrypted token in the URL fragment, never the query', () {
      final String url = WebPairingDialog.buildPairingUrl(
        refreshToken: 'refresh-secret',
        buildingId: 'b1',
        floorId: 'f 2',
        workspaceId: 'w3',
        workspaceName: 'Open Space - 04',
      );

      final Uri uri = Uri.parse(url);
      expect(uri.query, isEmpty);
      expect(url, isNot(contains('?token=')));
      expect(uri.fragment, startsWith('token='));
      expect(url, isNot(contains('refresh-secret')));

      final Map<String, String> params = Uri.splitQueryString(uri.fragment);
      expect(TokenCryptoService.decryptToken(params['token']!), 'refresh-secret');
      expect(params['b'], 'b1');
      expect(params['f'], 'f 2');
      expect(params['w'], 'w3');
      expect(params['wn'], 'Open Space - 04');
    });
  });
}
