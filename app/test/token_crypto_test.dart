import 'dart:convert';
import 'dart:typed_data';
import 'package:auto_roomzio/token_crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TokenCryptoService Unit Tests', () {
    const String sampleToken = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.'
        'eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.'
        'SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c';

    group('1. v2 AES-GCM Round-Trip Encryption & Decryption', () {
      test('should encrypt and decrypt a standard JWT token with v2_ prefix',
          () async {
        final String encrypted =
            await TokenCryptoService.encryptToken(sampleToken);
        expect(encrypted, startsWith('v2_'));
        final String? decrypted =
            await TokenCryptoService.decryptToken(encrypted);
        expect(decrypted, equals(sampleToken));
      });

      test('should round-trip short strings', () async {
        const List<String> shortInputs = <String>[
          'a',
          'ab',
          'abc',
          '1234567890',
          'test_token',
        ];
        for (final String input in shortInputs) {
          final String encrypted = await TokenCryptoService.encryptToken(input);
          final String? decrypted =
              await TokenCryptoService.decryptToken(encrypted);
          expect(decrypted, equals(input));
        }
      });

      test('should round-trip an empty string', () async {
        final String encrypted = await TokenCryptoService.encryptToken('');
        expect(encrypted, startsWith('v2_'));
        final String? decrypted =
            await TokenCryptoService.decryptToken(encrypted);
        expect(decrypted, equals(''));
      });

      test('should round-trip long strings (> 2048 chars)', () async {
        final String longInput = 'A' * 2500;
        final String encrypted =
            await TokenCryptoService.encryptToken(longInput);
        final String? decrypted =
            await TokenCryptoService.decryptToken(encrypted);
        expect(decrypted, equals(longInput));
      });

      test('should round-trip complex UTF-8 characters and emojis', () async {
        const String complexInput =
            'Étage 3 • Salle de réunion #42 (Cafétéria) 🏢✨ — €100 & «accents»';
        final String encrypted =
            await TokenCryptoService.encryptToken(complexInput);
        final String? decrypted =
            await TokenCryptoService.decryptToken(encrypted);
        expect(decrypted, equals(complexInput));
      });

      test('defaultKeyBytes exposes 32 bytes', () {
        expect(TokenCryptoService.defaultKeyBytes.length, equals(32));
      });
    });

    group('2. Random Nonce & Binary Layout', () {
      test(
          'should produce distinct ciphertexts for identical plaintexts (non-deterministic)',
          () async {
        final String cipher1 =
            await TokenCryptoService.encryptToken(sampleToken);
        final String cipher2 =
            await TokenCryptoService.encryptToken(sampleToken);
        final String cipher3 =
            await TokenCryptoService.encryptToken(sampleToken);

        expect(cipher1, isNot(equals(cipher2)));
        expect(cipher2, isNot(equals(cipher3)));
        expect(cipher1, isNot(equals(cipher3)));

        expect(
          await TokenCryptoService.decryptToken(cipher1),
          equals(sampleToken),
        );
        expect(
          await TokenCryptoService.decryptToken(cipher2),
          equals(sampleToken),
        );
        expect(
          await TokenCryptoService.decryptToken(cipher3),
          equals(sampleToken),
        );
      });

      test('should format v2 payload as [ 12B Nonce | CipherText | 16B MAC ]',
          () async {
        final String cipher =
            await TokenCryptoService.encryptToken(sampleToken);
        expect(cipher, startsWith('v2_'));
        final Uint8List bytes =
            base64Url.decode(base64Url.normalize(cipher.substring(3)));

        // 12B nonce + utf8(sampleToken) + 16B GCM tag
        expect(bytes.length, equals(12 + utf8.encode(sampleToken).length + 16));
      });
    });

    group('3. URL Safety & RFC 4648 Base64URL Compliance', () {
      test('should only contain RFC 4648 URL-safe characters ([A-Za-z0-9_-])',
          () async {
        final String cipher =
            await TokenCryptoService.encryptToken(sampleToken);
        final RegExp urlSafeRegex = RegExp(r'^[A-Za-z0-9_-]+$');

        expect(urlSafeRegex.hasMatch(cipher), isTrue);
        expect(cipher.contains('+'), isFalse);
        expect(cipher.contains('/'), isFalse);
        expect(cipher.contains('='), isFalse);
        expect(cipher.contains(' '), isFalse);
      });

      test(
          'should survive Uri query/fragment encoding and parsing without corruption',
          () async {
        final String cipher =
            await TokenCryptoService.encryptToken(sampleToken);
        final Uri uri = Uri.parse(
          'https://Xris65.github.io/AutoRoomzio/#token=$cipher&buildingId=12',
        );

        final Map<String, String> params = Uri.splitQueryString(uri.fragment);
        final String? extractedToken = params['token'];
        expect(extractedToken, equals(cipher));

        final String? decrypted =
            await TokenCryptoService.decryptToken(extractedToken!);
        expect(decrypted, equals(sampleToken));
      });

      test('should decrypt successfully when padding (=) is present', () async {
        final String cipher =
            await TokenCryptoService.encryptToken(sampleToken);
        final String padded =
            'v2_${base64Url.normalize(cipher.substring(3))}';

        final String? decrypted = await TokenCryptoService.decryptToken(padded);
        expect(decrypted, equals(sampleToken));
      });

      test(
          'should decrypt successfully when percent-encoded characters (%3D) are present',
          () async {
        final String cipher =
            await TokenCryptoService.encryptToken(sampleToken);
        final String padded =
            'v2_${base64Url.normalize(cipher.substring(3))}';
        final String percentEncoded = Uri.encodeComponent(padded);

        final String? decrypted =
            await TokenCryptoService.decryptToken(percentEncoded);
        expect(decrypted, equals(sampleToken));
      });
    });

    group('4. Malformed, Truncated, & Invalid Inputs (Graceful Null Handling)',
        () {
      test('should return null for empty and whitespace-only strings',
          () async {
        expect(await TokenCryptoService.decryptToken(''), isNull);
        expect(await TokenCryptoService.decryptToken('   '), isNull);
        expect(await TokenCryptoService.decryptToken('\t\n\r'), isNull);
      });

      test('should return null for invalid Base64 characters', () async {
        expect(
          await TokenCryptoService.decryptToken('Not@Valid#Base64!'),
          isNull,
        );
        expect(await TokenCryptoService.decryptToken('v2_Not@Valid!'), isNull);
        expect(await TokenCryptoService.decryptToken('???===='), isNull);
      });

      test('should return null for v2 payloads shorter than 28 bytes',
          () async {
        expect(await TokenCryptoService.decryptToken('v2_'), isNull);
        for (final int len in <int>[0, 11, 12, 20, 27]) {
          final String shortB64 =
              base64Url.encode(Uint8List(len)).replaceAll('=', '');
          expect(await TokenCryptoService.decryptToken('v2_$shortB64'), isNull);
        }
      });

      test('should return null for v1 payloads shorter than 32B or unaligned',
          () async {
        for (final int len in <int>[10, 16, 17, 20, 25, 31, 33, 40]) {
          final String badBase64 = base64Url.encode(Uint8List(len));
          expect(await TokenCryptoService.decryptToken(badBase64), isNull);
        }
      });

      test('should never throw uncaught exceptions across pathological inputs',
          () async {
        const List<String> pathologicalCases = <String>[
          '',
          ' ',
          'null',
          'undefined',
          'v2_',
          'v2_null',
          '{}',
          '[]',
          '0',
          'true',
          'false',
          'NaN',
          'eyJhbGciOi...',
          '%%%%',
          '%00%00%00',
          '\x00\x01\x02\x03',
          'AAAAAAAAAA',
          '==',
          '====',
          '--__--__',
        ];

        for (final String input in pathologicalCases) {
          expect(await TokenCryptoService.decryptToken(input), isNull);
        }
      });
    });

    group('5. v2 AES-GCM Tamper Resistance & Authentication', () {
      test('should return null when nonce, ciphertext, or MAC bytes are flipped',
          () async {
        final String cipher =
            await TokenCryptoService.encryptToken(sampleToken);
        final Uint8List original = base64Url.decode(
          base64Url.normalize(cipher.substring(3)),
        );

        // Flip nonce byte (0..11)
        final Uint8List badNonce = Uint8List.fromList(original)..[0] ^= 0xFF;
        expect(
          await TokenCryptoService.decryptToken(
            'v2_${base64Url.encode(badNonce).replaceAll('=', '')}',
          ),
          isNull,
        );

        // Flip ciphertext byte
        final Uint8List badCipher = Uint8List.fromList(original)..[12] ^= 0xFF;
        expect(
          await TokenCryptoService.decryptToken(
            'v2_${base64Url.encode(badCipher).replaceAll('=', '')}',
          ),
          isNull,
        );

        // Flip MAC tag byte (last 16 bytes)
        final Uint8List badMac = Uint8List.fromList(original)
          ..[original.length - 1] ^= 0xFF;
        expect(
          await TokenCryptoService.decryptToken(
            'v2_${base64Url.encode(badMac).replaceAll('=', '')}',
          ),
          isNull,
        );
      });

      test('should return null when v2 ciphertext is truncated by 1 byte',
          () async {
        final String cipher =
            await TokenCryptoService.encryptToken(sampleToken);
        final Uint8List bytes = base64Url.decode(
          base64Url.normalize(cipher.substring(3)),
        );
        final Uint8List truncated = bytes.sublist(0, bytes.length - 1);
        expect(
          await TokenCryptoService.decryptToken(
            'v2_${base64Url.encode(truncated).replaceAll('=', '')}',
          ),
          isNull,
        );
      });
    });

    group('6. Key Sensitivity & Mismatched Key Protection', () {
      test('should return null when decrypting with a mismatched 32-byte key',
          () async {
        final List<int> foreignKey =
            utf8.encode('ForeignSecretKey32BytesLong2026!');
        final String cipher =
            await TokenCryptoService.encryptToken(sampleToken);

        final String? decrypted = await TokenCryptoService.decryptToken(
          cipher,
          keyBytes: foreignKey,
        );
        expect(decrypted, isNull);
      });

      test('should successfully decrypt when using matching custom key',
          () async {
        final List<int> customKey =
            utf8.encode('CustomSecretKey32BytesLong2026!!');
        final String cipher = await TokenCryptoService.encryptToken(
          sampleToken,
          keyBytes: customKey,
        );

        expect(await TokenCryptoService.decryptToken(cipher), isNull);
        expect(
          await TokenCryptoService.decryptToken(cipher, keyBytes: customKey),
          equals(sampleToken),
        );
      });
    });

    group('7. Legacy v1 AES-256-CBC Compatibility (Cloudflare Worker & Old QR)',
        () {
      test('encryptLegacyCbc produces v1 CBC format decrypted by decryptToken',
          () async {
        final String legacyCipher =
            await TokenCryptoService.encryptLegacyCbc(sampleToken);
        expect(legacyCipher.startsWith('v2_'), isFalse);

        final Uint8List bytes =
            base64Url.decode(base64Url.normalize(legacyCipher));
        expect(bytes.length, greaterThanOrEqualTo(32));
        expect((bytes.length - 16) % 16, equals(0));

        final String? decrypted =
            await TokenCryptoService.decryptToken(legacyCipher);
        expect(decrypted, equals(sampleToken));
      });

      test('encryptLegacyCbc supports empty string and UTF-8', () async {
        final String emptyLegacy = await TokenCryptoService.encryptLegacyCbc('');
        expect(await TokenCryptoService.decryptToken(emptyLegacy), equals(''));

        const String utf8Text = 'Étage 2 • café 🔐';
        final String utf8Legacy =
            await TokenCryptoService.encryptLegacyCbc(utf8Text);
        expect(
          await TokenCryptoService.decryptToken(utf8Legacy),
          equals(utf8Text),
        );
      });

      test('v1 CBC returns null on tampered or wrong-key payloads', () async {
        final String legacyCipher =
            await TokenCryptoService.encryptLegacyCbc(sampleToken);
        final Uint8List bytes = Uint8List.fromList(
          base64Url.decode(base64Url.normalize(legacyCipher)),
        );

        // Tamper IV
        final Uint8List badIv = Uint8List.fromList(bytes)..[0] ^= 0xFF;
        expect(
          await TokenCryptoService.decryptToken(base64Url.encode(badIv)),
          isNull,
        );

        // Wrong key
        final List<int> foreignKey =
            utf8.encode('ForeignSecretKey32BytesLong2026!');
        expect(
          await TokenCryptoService.decryptToken(
            legacyCipher,
            keyBytes: foreignKey,
          ),
          isNull,
        );
      });
    });
  });
}
