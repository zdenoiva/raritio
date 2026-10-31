import 'package:flutter/services.dart';

/// Verifies the signing certificate of a downloaded APK. The SHA256 from
/// latest.json protects transport, while this pin protects against a
/// compromised latest.json or GitHub release.
class SecurityService {
  static const MethodChannel _channel = MethodChannel(
    'sk.zdenoiva.raritio/security',
  );

  /// SHA-256 of the Raritio release signing certificate.
  static const String releaseSignerSha256 =
      'f47dbf93d8c27679f462ea6d96d3866e479f5d8446ccde9d34c73b9ca367e443';

  Future<void> verifyApkSignature(String path) async {
    final result = await _channel.invokeMethod<String>('getApkSignerSha256', {
      'path': path,
    });
    final actual = (result ?? '').trim().toLowerCase();
    if (actual != releaseSignerSha256) {
      throw const FormatException('APK nemá podpis Raritio.');
    }
  }
}
