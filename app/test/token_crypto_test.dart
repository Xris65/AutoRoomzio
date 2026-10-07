import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:encrypt/encrypt.dart';
import 'package:auto_roomzio/token_crypto.dart';

void main() {
  group('TokenCryptoService Unit Tests', () {
    const sampleToken = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.'
        'eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.'
        'SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c';

    group('1. Round-Trip Encryption & Decryption', () {
      test('should encrypt and decrypt a standard JWT token correctly', () {
        final encrypted = TokenCryptoService.encryptToken(sampleToken);
        final decrypted = TokenCryptoService.decryptToken(encrypted);
        expect(decrypted, equals(sampleToken));
      });

      test('should round-trip short strings', () {
        const shortInputs = ['a', 'ab', 'abc', '1234567890', 'test_token'];
        for (final input in shortInputs) {
          final encrypted = TokenCryptoService.encryptToken(input);
          final decrypted = TokenCryptoService.decryptToken(encrypted);
          expect(decrypted, equals(input));
        }
      });

      test('should round-trip an empty string', () {
        final encrypted = TokenCryptoService.encryptToken('');
        final decrypted = TokenCryptoService.decryptToken(encrypted);
        expect(decrypted, equals(''));
      });

      test('should round-trip long strings (> 2048 chars)', () {
        final longInput = 'A' * 2500;
        final encrypted = TokenCryptoService.encryptToken(longInput);
        final decrypted = TokenCryptoService.decryptToken(encrypted);
        expect(decrypted, equals(longInput));
      });

      test('should round-trip complex UTF-8 characters and emojis', () {
        const complexInput =
            'Étage 3 • Salle de réunion #42 (Cafétéria) 🏢✨ — €100 & «accents»';
        final encrypted = TokenCryptoService.encryptToken(complexInput);
        final decrypted = TokenCryptoService.decryptToken(encrypted);
        expect(decrypted, equals(complexInput));
      });
    });

    group('2. Random IV & Non-Determinism', () {
      test('should produce distinct ciphertexts for identical plaintexts (non-deterministic)', () {
        final cipher1 = TokenCryptoService.encryptToken(sampleToken);
        final cipher2 = TokenCryptoService.encryptToken(sampleToken);
        final cipher3 = TokenCryptoService.encryptToken(sampleToken);

        expect(cipher1, isNot(equals(cipher2)));
        expect(cipher2, isNot(equals(cipher3)));
        expect(cipher1, isNot(equals(cipher3)));

        expect(TokenCryptoService.decryptToken(cipher1), equals(sampleToken));
        expect(TokenCryptoService.decryptToken(cipher2), equals(sampleToken));
        expect(TokenCryptoService.decryptToken(cipher3), equals(sampleToken));
      });

      test('should prepend a 16-byte random IV in the binary payload', () {
        final cipher = TokenCryptoService.encryptToken(sampleToken);
        final bytes = base64Url.decode(base64Url.normalize(cipher));

        // IV is 16 bytes, ciphertext is a multiple of 16 bytes
        expect(bytes.length, greaterThanOrEqualTo(32));
        expect((bytes.length - 16) % 16, equals(0));
      });
    });

    group('3. URL Safety & RFC 4648 Base64URL Compliance', () {
      test('should only contain RFC 4648 URL-safe characters ([A-Za-z0-9_-])', () {
        final cipher = TokenCryptoService.encryptToken(sampleToken);
        final urlSafeRegex = RegExp(r'^[A-Za-z0-9_-]+$');

        expect(urlSafeRegex.hasMatch(cipher), isTrue);
        expect(cipher.contains('+'), isFalse);
        expect(cipher.contains('/'), isFalse);
        expect(cipher.contains('='), isFalse);
        expect(cipher.contains(' '), isFalse);
      });

      test('should survive Uri query parameter encoding and parsing without corruption', () {
        final cipher = TokenCryptoService.encryptToken(sampleToken);
        final uri = Uri.parse('https://Xris65.github.io/AutoRoomzio/?token=$cipher&buildingId=12');

        final extractedToken = uri.queryParameters['token'];
        expect(extractedToken, equals(cipher));

        final decrypted = TokenCryptoService.decryptToken(extractedToken!);
        expect(decrypted, equals(sampleToken));
      });

      test('should decrypt successfully when padding (=) is present', () {
        final cipher = TokenCryptoService.encryptToken(sampleToken);
        final padded = base64Url.normalize(cipher); // Appends '=' if needed

        final decrypted = TokenCryptoService.decryptToken(padded);
        expect(decrypted, equals(sampleToken));
      });

      test('should decrypt successfully when percent-encoded characters (%3D) are present', () {
        final cipher = TokenCryptoService.encryptToken(sampleToken);
        final padded = base64Url.normalize(cipher);
        final percentEncoded = Uri.encodeComponent(padded);

        final decrypted = TokenCryptoService.decryptToken(percentEncoded);
        expect(decrypted, equals(sampleToken));
      });
    });

    group('4. Malformed, Truncated, & Invalid Inputs (Graceful Null Handling)', () {
      test('should return null for empty string', () {
        expect(TokenCryptoService.decryptToken(''), isNull);
      });

      test('should return null for whitespace-only strings', () {
        expect(TokenCryptoService.decryptToken('   '), isNull);
        expect(TokenCryptoService.decryptToken('\t\n\r'), isNull);
      });

      test('should return null for invalid Base64 characters', () {
        expect(TokenCryptoService.decryptToken('Not@Valid#Base64!'), isNull);
        expect(TokenCryptoService.decryptToken('???===='), isNull);
      });

      test('should return null for payloads shorter than 16-byte IV', () {
        final shortBytes = Uint8List(10);
        final shortBase64 = base64Url.encode(shortBytes);
        expect(TokenCryptoService.decryptToken(shortBase64), isNull);
      });

      test('should return null for payloads with IV only (16 bytes, no ciphertext)', () {
        final ivOnlyBytes = Uint8List(16);
        final ivOnlyBase64 = base64Url.encode(ivOnlyBytes);
        expect(TokenCryptoService.decryptToken(ivOnlyBase64), isNull);
      });

      test('should return null for non-block-aligned payloads (< 32 bytes or partial blocks)', () {
        for (final len in [17, 20, 25, 31, 33, 40]) {
          final badBytes = Uint8List(len);
          final badBase64 = base64Url.encode(badBytes);
          expect(TokenCryptoService.decryptToken(badBase64), isNull);
        }
      });

      test('should never throw uncaught exceptions across pathological inputs', () {
        final pathologicalCases = [
          '',
          ' ',
          'null',
          'undefined',
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
          'A' * 10,
          'A' * 17,
          'A' * 31,
          '==',
          '====',
          '--__--__',
        ];

        for (final input in pathologicalCases) {
          expect(() => TokenCryptoService.decryptToken(input), returnsNormally);
          expect(TokenCryptoService.decryptToken(input), isNull);
        }
      });
    });

    group('5. Tamper Resistance & Integrity', () {
      test('should return null when IV bytes are flipped', () {
        final cipher = TokenCryptoService.encryptToken(sampleToken);
        final bytes = Uint8List.fromList(base64Url.decode(base64Url.normalize(cipher)));

        // Flip bits in the IV (first 16 bytes)
        bytes[0] ^= 0xFF;
        final tampered = base64Url.encode(bytes);

        expect(TokenCryptoService.decryptToken(tampered), isNull);
      });

      test('should return null when ciphertext bytes are flipped', () {
        final cipher = TokenCryptoService.encryptToken(sampleToken);
        final bytes = Uint8List.fromList(base64Url.decode(base64Url.normalize(cipher)));

        // Flip bits in the ciphertext (byte index 16+)
        bytes[16] ^= 0xFF;
        final tampered1 = base64Url.encode(bytes);
        expect(TokenCryptoService.decryptToken(tampered1), isNull);

        // Flip bits in the last block (corrupts PKCS7 padding)
        bytes[bytes.length - 1] ^= 0xFF;
        final tampered2 = base64Url.encode(bytes);
        expect(TokenCryptoService.decryptToken(tampered2), isNull);
      });

      test('should return null when ciphertext is truncated by 1 byte', () {
        final cipher = TokenCryptoService.encryptToken(sampleToken);
        final bytes = Uint8List.fromList(base64Url.decode(base64Url.normalize(cipher)));

        final truncatedBytes = bytes.sublist(0, bytes.length - 1);
        final tampered = base64Url.encode(truncatedBytes);

        expect(TokenCryptoService.decryptToken(tampered), isNull);
      });
    });

    group('6. Key Sensitivity & Mismatched Key Protection', () {
      test('should return null when decrypting with a mismatched 32-byte key', () {
        final foreignKey = Key.fromUtf8('ForeignSecretKey32BytesLong2026!');
        final cipher = TokenCryptoService.encryptToken(sampleToken);

        final decrypted = TokenCryptoService.decryptToken(cipher, key: foreignKey);
        expect(decrypted, isNull);
      });

      test('should successfully decrypt when using matching custom key', () {
        final customKey = Key.fromUtf8('CustomSecretKey32BytesLong2026!!');
        final cipher = TokenCryptoService.encryptToken(sampleToken, key: customKey);

        // Decrypt with wrong key fails
        expect(TokenCryptoService.decryptToken(cipher), isNull);

        // Decrypt with correct custom key succeeds
        final decrypted = TokenCryptoService.decryptToken(cipher, key: customKey);
        expect(decrypted, equals(sampleToken));
      });
    });

    group('7. AutoRoomzio QR Pairing Flow Simulation', () {
      test('should correctly simulate the mobile generation and web extraction flow', () {
        const originalRefreshToken = 'rt_prod_AutoRoomzio_user_session_token_xyz987';
        const buildingId = '10';
        const floorId = '2';
        const roomId = '45';
        const workspaceName = 'Bureau OpenSpace Sud';

        // Mobile side: encrypt token and build pairing URL
        final encryptedToken = TokenCryptoService.encryptToken(originalRefreshToken);
        final pairingUri = Uri.https('Xris65.github.io', '/AutoRoomzio/', {
          'token': encryptedToken,
          'buildingId': buildingId,
          'floorId': floorId,
          'roomId': roomId,
          'workspaceName': workspaceName,
        });

        // Web side: receive URI and extract query parameters
        final incomingToken = pairingUri.queryParameters['token'];
        expect(incomingToken, isNotNull);
        expect(pairingUri.queryParameters['buildingId'], equals(buildingId));
        expect(pairingUri.queryParameters['floorId'], equals(floorId));
        expect(pairingUri.queryParameters['roomId'], equals(roomId));
        expect(pairingUri.queryParameters['workspaceName'], equals(workspaceName));

        // Web side: decrypt token
        final decryptedToken = TokenCryptoService.decryptToken(incomingToken!);
        expect(decryptedToken, equals(originalRefreshToken));
      });
    });
  });
}
