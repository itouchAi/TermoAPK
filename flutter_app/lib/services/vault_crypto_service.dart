import 'dart:convert';
import 'dart:math' as math;
import 'package:cryptography/cryptography.dart';
import '../models/thermostat_state.dart';

class VaultBackupPayload {
  final String exportedAt;
  final String locationName;
  final SystemSettingsState settings;

  const VaultBackupPayload({
    required this.exportedAt,
    required this.locationName,
    required this.settings,
  });
}

class VaultCryptoService {
  VaultCryptoService._();

  static final _pbkdf2 = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 10000,
    bits: 256,
  );
  static final _aesGcm = AesGcm.with256bits();

  static List<int> _randomBytes(int length) {
    final rng = math.Random.secure();
    return List<int>.generate(length, (_) => rng.nextInt(256));
  }

  /// Encrypts [settings] and [locationName] using PBKDF2-HMAC-SHA256 + AES-256-GCM.
  static Future<String> encryptBackupJson({
    required SystemSettingsState settings,
    required String locationName,
    required String pin,
  }) async {
    final salt = _randomBytes(16);
    final nonce = _aesGcm.newNonce();
    final secretKey = await _pbkdf2.deriveKeyFromPassword(
      password: pin,
      nonce: salt,
    );

    final plainJson = jsonEncode({
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'locationName': locationName,
      'settings': settings.toJson(),
    });

    final box = await _aesGcm.encrypt(
      utf8.encode(plainJson),
      secretKey: secretKey,
      nonce: nonce,
    );

    return const JsonEncoder.withIndent('  ').convert({
      'format': 'termostat-vault-aes256-v2',
      'kdf': 'PBKDF2-HMAC-SHA256',
      'iterations': 10000,
      'cipher': 'AES-256-GCM',
      'salt': base64Encode(salt),
      'nonce': base64Encode(box.nonce),
      'mac': base64Encode(box.mac.bytes),
      'cipherText': base64Encode(box.cipherText),
    });
  }

  /// Decrypts a vault JSON backup created by [encryptBackupJson].
  /// Throws [SecretBoxAuthenticationError] if [pin] is wrong or payload was tampered with.
  static Future<VaultBackupPayload> decryptBackupJson({
    required String rawJson,
    required String pin,
  }) async {
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid backup JSON format');
    }
    if (decoded['format'] != 'termostat-vault-aes256-v2') {
      throw const FormatException('Unsupported backup format');
    }

    final salt = base64Decode(decoded['salt'] as String);
    final nonce = base64Decode(decoded['nonce'] as String);
    final macBytes = base64Decode(decoded['mac'] as String);
    final cipherText = base64Decode(decoded['cipherText'] as String);

    final secretKey = await _pbkdf2.deriveKeyFromPassword(
      password: pin,
      nonce: salt,
    );
    final clearBytes = await _aesGcm.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes)),
      secretKey: secretKey,
    );

    final inner = jsonDecode(utf8.decode(clearBytes)) as Map<String, dynamic>;
    final settingsMap = inner['settings'] as Map<String, dynamic>;
    return VaultBackupPayload(
      exportedAt: (inner['exportedAt'] as String?) ?? '',
      locationName: (inner['locationName'] as String?) ?? 'Ev · İstanbul',
      settings: SystemSettingsState.fromJson(settingsMap),
    );
  }
}
