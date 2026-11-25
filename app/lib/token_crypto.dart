import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

/// Cryptographic service providing authenticated AES-256-GCM (v2) encryption
/// with HKDF-SHA256 key derivation, plus legacy AES-256-CBC (v1) compatibility
/// for pairing tokens, profile bundles, and Cloudflare Worker auth payloads.
class TokenCryptoService {
  /// 32-byte (256-bit) shared symmetric key constant.
  static const String _defaultKeyString = 'AutoRoomzioSecretKey2026AES256!!';
  static final List<int> _defaultKeyBytes = utf8.encode(_defaultKeyString);

  static final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  static final List<int> _hkdfSalt = utf8.encode('autoroomzio-hkdf-salt-v2');
  static final List<int> _hkdfInfo = utf8.encode('autoroomzio-pairing-v2');

  static final AesGcm _aesGcm = AesGcm.with256bits();
  static final AesCbc _aesCbc = AesCbc.with256bits(
    macAlgorithm: MacAlgorithm.empty,
    paddingAlgorithm: PaddingAlgorithm.pkcs7,
  );

  /// Exposes the default 32-byte symmetric key (read-only) for verification.
  static List<int> get defaultKeyBytes =>
      List<int>.unmodifiable(_defaultKeyBytes);

  static Future<SecretKeyData> _deriveGcmKey(List<int> masterKeyBytes) {
    return _hkdf.deriveKey(
      secretKey: SecretKey(masterKeyBytes),
      nonce: _hkdfSalt,
      info: _hkdfInfo,
    );
  }

  /// Encrypts [plainText] using HKDF-SHA256 derived AES-256-GCM with a
  /// cryptographically secure random 12-byte nonce.
  ///
  /// The binary payload is structured as `[ Nonce (12B) | CipherText | MAC (16B) ]`
  /// and returned as `'v2_'` followed by unpadded RFC 4648 URL-safe Base64.
  static Future<String> encryptToken(
    String plainText, {
    List<int>? keyBytes,
  }) async {
    final List<int> activeKey = keyBytes ?? _defaultKeyBytes;
    final SecretKeyData derivedKey = await _deriveGcmKey(activeKey);
    final SecretBox secretBox = await _aesGcm.encrypt(
      utf8.encode(plainText),
      secretKey: derivedKey,
    );
    final Uint8List combined = secretBox.concatenation(nonce: true, mac: true);
    return 'v2_${base64Url.encode(combined).replaceAll('=', '')}';
  }

  /// Encrypts [plainText] using legacy AES-256-CBC (PKCS7 padding, raw 32-byte key)
  /// with a random 16-byte IV, structured as `[ IV (16B) | CipherText ]` in
  /// unpadded URL-safe Base64.
  ///
  /// Used by `RoomzApiService.login()` for the Cloudflare PKCE Worker.
  static Future<String> encryptLegacyCbc(
    String plainText, {
    List<int>? keyBytes,
  }) async {
    final List<int> activeKey = keyBytes ?? _defaultKeyBytes;
    final SecretBox secretBox = await _aesCbc.encrypt(
      utf8.encode(plainText),
      secretKey: SecretKey(activeKey),
    );
    final Uint8List combined = secretBox.concatenation(nonce: true, mac: false);
    return base64Url.encode(combined).replaceAll('=', '');
  }

  /// Decrypts a `v2_` (AES-256-GCM) or legacy `v1` (AES-256-CBC) URL-safe
  /// Base64 [cipherText].
  ///
  /// Returns the decrypted UTF-8 string, or `null` if the payload is corrupt,
  /// truncated, malformed, or fails authentication/padding/UTF-8 validation.
  /// Never throws uncaught exceptions.
  static Future<String?> decryptToken(
    String cipherText, {
    List<int>? keyBytes,
  }) async {
    if (cipherText.trim().isEmpty) {
      return null;
    }

    try {
      final List<int> activeKey = keyBytes ?? _defaultKeyBytes;

      var clean = cipherText.trim();
      if (clean.contains('%')) {
        try {
          clean = Uri.decodeQueryComponent(clean).trim();
        } catch (_) {
          // Keep original trimmed string if percent-decoding fails
        }
      }

      if (clean.startsWith('v2_')) {
        final String encoded = clean.substring(3);
        if (encoded.isEmpty) {
          return null;
        }
        final Uint8List combined = base64Url.decode(base64Url.normalize(encoded));
        // Minimum is 12-byte nonce + 16-byte GCM authentication tag = 28 bytes
        if (combined.length < 12 + 16) {
          return null;
        }
        final SecretBox secretBox = SecretBox(
          combined.sublist(12, combined.length - 16),
          nonce: combined.sublist(0, 12),
          mac: Mac(combined.sublist(combined.length - 16)),
        );
        final SecretKeyData derivedKey = await _deriveGcmKey(activeKey);
        final List<int> decryptedBytes = await _aesGcm.decrypt(
          secretBox,
          secretKey: derivedKey,
        );
        return utf8.decode(decryptedBytes, allowMalformed: false);
      }

      // Legacy v1 AES-256-CBC decryption
      final Uint8List combined = base64Url.decode(base64Url.normalize(clean));
      if (combined.length < 32 || (combined.length - 16) % 16 != 0) {
        return null;
      }
      final SecretBox secretBox = SecretBox(
        combined.sublist(16),
        nonce: combined.sublist(0, 16),
        mac: Mac.empty,
      );
      final List<int> decryptedBytes = await _aesCbc.decrypt(
        secretBox,
        secretKey: SecretKey(activeKey),
      );
      return utf8.decode(decryptedBytes, allowMalformed: false);
    } catch (_) {
      return null;
    }
  }
}
