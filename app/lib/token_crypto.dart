import 'dart:convert';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart';

/// Cryptographic service providing AES-256-CBC encryption and decryption
/// for pairing tokens embedded in Web URLs.
///
/// Encrypted payloads prepend a random 16-byte Initialization Vector (IV)
/// to the AES ciphertext and are encoded in RFC 4648 URL-safe Base64
/// without trailing padding for safe embedding in HTTP query parameters.
class TokenCryptoService {
  /// 32-byte (256-bit) shared symmetric key constant.
  static const String _defaultKeyString = 'AutoRoomzioSecretKey2026AES256!!';
  static final Key _defaultKey = Key.fromUtf8(_defaultKeyString);

  /// Exposes the default symmetric key (read-only) for verification.
  static Key get defaultKey => _defaultKey;

  /// Encrypts [plainText] using AES-256-CBC with PKCS7 padding and a cryptographically
  /// secure random 16-byte IV.
  ///
  /// The binary payload is structured as `[ IV (16 bytes) | CipherText (N bytes) ]`.
  /// The result is encoded as an unpadded RFC 4648 URL-safe Base64 string.
  ///
  /// Optional [key] allows overriding the key for testing purposes.
  static String encryptToken(String plainText, {Key? key}) {
    final activeKey = key ?? _defaultKey;

    // 1. Generate cryptographically secure random 16-byte IV
    final iv = IV.fromSecureRandom(16);

    // 2. Initialize AES in CBC mode with PKCS7 padding
    final Encrypted encrypted;
    if (plainText.isEmpty) {
      final encrypter = Encrypter(AES(activeKey, mode: AESMode.cbc, padding: null));
      final pkcs7EmptyBlock = Uint8List(16)..fillRange(0, 16, 16);
      encrypted = encrypter.encryptBytes(pkcs7EmptyBlock, iv: iv);
    } else {
      final encrypter = Encrypter(AES(activeKey, mode: AESMode.cbc));
      encrypted = encrypter.encrypt(plainText, iv: iv);
    }

    // 3. Assemble binary payload: [ IV (16 bytes) | CipherText (N bytes) ]
    final combined = Uint8List(iv.bytes.length + encrypted.bytes.length);
    combined.setRange(0, iv.bytes.length, iv.bytes);
    combined.setRange(iv.bytes.length, combined.length, encrypted.bytes);

    // 4. Encode as URL-safe Base64 (RFC 4648) and strip unneeded '=' padding
    return base64Url.encode(combined).replaceAll('=', '');
  }

  /// Decrypts a URL-safe Base64 [cipherText] containing `[ IV (16 bytes) | CipherText ]`.
  ///
  /// Returns the decrypted plain-text string, or `null` if the ciphertext is
  /// corrupt, truncated, malformed, or fails padding/UTF-8 validation.
  /// Never throws uncaught exceptions.
  ///
  /// Optional [key] allows overriding the key for testing purposes.
  static String? decryptToken(String cipherText, {Key? key}) {
    if (cipherText.trim().isEmpty) {
      return null;
    }

    try {
      final activeKey = key ?? _defaultKey;

      // 1. Clean input and handle URL percent-encoding (e.g. %3D) if present
      var clean = cipherText.trim();
      if (clean.contains('%')) {
        try {
          clean = Uri.decodeQueryComponent(clean);
        } catch (_) {
          // Keep clean string if percent decoding fails
        }
      }

      // 2. Normalize URL-safe Base64 (restores '=' padding if stripped)
      final normalized = base64Url.normalize(clean);
      final combined = base64Url.decode(normalized);

      // 3. Validate minimum payload size:
      // Minimum is 16 bytes IV + at least 16 bytes AES block (PKCS7 padding) = 32 bytes
      if (combined.length < 32) {
        return null;
      }

      // 4. Validate block alignment:
      // Ciphertext length after 16-byte IV must be a multiple of 16 (AES block size)
      if ((combined.length - 16) % 16 != 0) {
        return null;
      }

      // 5. Extract IV (first 16 bytes) and CipherText (subsequent bytes)
      final iv = IV(combined.sublist(0, 16));
      final cipherBytes = combined.sublist(16);

      // 6. Decrypt ciphertext blocks using AES-256-CBC
      final encrypter = Encrypter(AES(activeKey, mode: AESMode.cbc));
      final decryptedBytes = encrypter.decryptBytes(
        Encrypted(cipherBytes),
        iv: iv,
      );

      // 7. Strict UTF-8 decoding (throws FormatException on corrupted bytes)
      final decrypted = utf8.decode(decryptedBytes, allowMalformed: false);

      return decrypted;
    } catch (_) {
      // Catch any FormatException, ArgumentError, or PointyCastle exception cleanly
      return null;
    }
  }
}
