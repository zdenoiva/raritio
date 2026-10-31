import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Small cached USD -> EUR rate used only for display totals.
///
/// The last successful rate stays available offline. Prices themselves remain
/// in their source currency in local state, so a new rate can be applied
/// without rewriting the collection.
class ExchangeRateService {
  static const String _rateKey = 'usd_eur_rate';
  static const String _dateKey = 'usd_eur_rate_date';
  static const Duration _maxAge = Duration(hours: 12);

  Future<double> getUsdEur({bool force = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getDouble(_rateKey) ?? 0;
    final cachedAt = DateTime.tryParse(prefs.getString(_dateKey) ?? '');

    if (!force &&
        cached > 0.5 &&
        cached < 2 &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _maxAge) {
      return cached;
    }

    try {
      final response = await http
          .get(
            Uri.parse('https://api.frankfurter.app/latest?from=USD&to=EUR'),
            headers: const {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final rates = data is Map ? data['rates'] : null;
        final rate = rates is Map ? rates['EUR'] : null;
        final value = double.tryParse(rate?.toString() ?? '') ?? 0;
        if (value > 0.5 && value < 2) {
          await prefs.setDouble(_rateKey, value);
          await prefs.setString(
            _dateKey,
            DateTime.now().toUtc().toIso8601String(),
          );
          return value;
        }
      }
    } catch (_) {
      // Offline or provider unavailable: use the last known rate.
    }

    return cached > 0.5 && cached < 2 ? cached : 0.92;
  }
}
