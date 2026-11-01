import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Ximilar (Card Grader) API token.
///
/// The token can be supplied by the release build (`--dart-define`) or saved
/// from the app settings. The free Ximilar plan includes 1,000 credits/month;
/// one full front+back grading costs 100 credits, i.e. ten free gradings.
class GradingTokenService {
  static const String _storageKey = 'ximilar_card_grader_token';
  static const String buildToken = String.fromEnvironment(
    'XIMILAR_API_TOKEN',
    defaultValue: '',
  );

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  bool get hasBuildToken => buildToken.trim().isNotEmpty;

  Future<String> getToken() async {
    try {
      final stored = (await _storage.read(key: _storageKey))?.trim() ?? '';
      if (stored.isNotEmpty) return stored;
    } catch (_) {
      // Secure storage may be unavailable on a freshly reset device.
    }
    return buildToken.trim();
  }

  Future<bool> isConfigured() async {
    return (await getToken()).isNotEmpty;
  }

  Future<void> saveToken(String token) async {
    final value = token.trim();
    if (value.isEmpty) {
      await clearToken();
      return;
    }
    await _storage.write(key: _storageKey, value: value);
  }

  Future<void> clearToken() async {
    try {
      await _storage.delete(key: _storageKey);
    } catch (_) {}
  }
}
