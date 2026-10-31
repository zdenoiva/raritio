import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Backups are encrypted with AES-256-GCM.
///
/// Manual backups use a user password so they can be restored on another
/// device. Automatic daily backups use a random key stored in Android's
/// encrypted secure storage and are intended for the same installation.
class BackupCryptoService {
  BackupCryptoService({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const int _iterations = 120000;
  static const String _deviceKeyName = 'raritio_backup_device_key';

  final FlutterSecureStorage _storage;
  final Random _random = Random.secure();

  Future<String> encryptWithPassword(String plaintext, String password) async {
    final salt = _randomBytes(16);
    final nonce = _randomBytes(12);
    final key = await _deriveKey(password, salt);
    final box = await AesGcm.with256bits().encrypt(
      utf8.encode(plaintext),
      secretKey: key,
      nonce: nonce,
    );
    return jsonEncode({
      'format': 'raritio-backup',
      'version': 2,
      'encryption': 'aes-256-gcm',
      'kdf': 'pbkdf2-sha256',
      'iterations': _iterations,
      'salt': base64Encode(salt),
      'nonce': base64Encode(box.nonce),
      'mac': base64Encode(box.mac.bytes),
      'ciphertext': base64Encode(box.cipherText),
    });
  }

  Future<String> decryptWithPassword(String payload, String password) async {
    final map = _parse(payload);
    if (map['kdf'] != 'pbkdf2-sha256') {
      throw const FormatException('Záloha nie je chránená heslom.');
    }
    final salt = base64Decode(map['salt'] as String);
    final key = await _deriveKey(password, salt);
    return _decryptBox(map, key);
  }

  Future<String> encryptWithDeviceKey(String plaintext) async {
    final key = await _deviceKey();
    final box = await AesGcm.with256bits().encrypt(
      utf8.encode(plaintext),
      secretKey: key,
    );
    return jsonEncode({
      'format': 'raritio-backup',
      'version': 2,
      'encryption': 'aes-256-gcm',
      'kdf': 'device',
      'nonce': base64Encode(box.nonce),
      'mac': base64Encode(box.mac.bytes),
      'ciphertext': base64Encode(box.cipherText),
    });
  }

  Future<String> decryptWithDeviceKey(String payload) async {
    final map = _parse(payload);
    if (map['kdf'] != 'device') {
      throw const FormatException('Záloha nie je viazaná na toto zariadenie.');
    }
    return _decryptBox(map, await _deviceKey());
  }

  bool isEncrypted(String payload) {
    try {
      return _parse(payload)['format'] == 'raritio-backup';
    } catch (_) {
      return false;
    }
  }

  String? encryptionKind(String payload) {
    try {
      return _parse(payload)['kdf']?.toString();
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _parse(String payload) {
    final decoded = jsonDecode(payload);
    if (decoded is! Map) throw const FormatException('Neplatná záloha.');
    final map = Map<String, dynamic>.from(decoded);
    if (map['format'] != 'raritio-backup' ||
        map['encryption'] != 'aes-256-gcm') {
      throw const FormatException('Neznámy formát zálohy.');
    }
    return map;
  }

  Future<SecretKey> _deriveKey(String password, List<int> salt) {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: _iterations,
      bits: 256,
    );
    return pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
  }

  Future<String> _decryptBox(Map<String, dynamic> map, SecretKey key) async {
    final box = SecretBox(
      base64Decode(map['ciphertext'] as String),
      nonce: base64Decode(map['nonce'] as String),
      mac: Mac(base64Decode(map['mac'] as String)),
    );
    final clear = await AesGcm.with256bits().decrypt(box, secretKey: key);
    return utf8.decode(clear);
  }

  Future<SecretKey> _deviceKey() async {
    final existing = await _storage.read(key: _deviceKeyName);
    if (existing != null && existing.isNotEmpty) {
      return SecretKey(base64Decode(existing));
    }
    final key = _randomBytes(32);
    await _storage.write(key: _deviceKeyName, value: base64Encode(key));
    return SecretKey(key);
  }

  List<int> _randomBytes(int length) {
    return List<int>.generate(length, (_) => _random.nextInt(256));
  }
}
