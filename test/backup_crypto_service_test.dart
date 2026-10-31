import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:raritio/services/backup_crypto_service.dart';

void main() {
  final service = BackupCryptoService();

  test('encrypts and decrypts a backup with a password', () async {
    final plain = jsonEncode({
      'app': 'raritio',
      'state': {'binders': []},
    });
    final encrypted = await service.encryptWithPassword(
      plain,
      'test-heslo-123',
    );
    expect(encrypted, isNot(contains('binders')));
    expect(service.isEncrypted(encrypted), isTrue);
    expect(service.encryptionKind(encrypted), 'pbkdf2-sha256');
    expect(
      await service.decryptWithPassword(encrypted, 'test-heslo-123'),
      plain,
    );
  });

  test('rejects a wrong password', () async {
    final encrypted = await service.encryptWithPassword('secret', 'right-pass');
    expect(
      () => service.decryptWithPassword(encrypted, 'wrong-pass'),
      throwsA(anything),
    );
  });
}
