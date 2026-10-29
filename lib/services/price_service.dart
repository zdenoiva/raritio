import 'package:http/http.dart' as http;

import 'dart:convert';

class PriceService {
  static const String ptcgApiBase = 'https://api.pokemontcg.io/v2';
  static const String mtgApiBase = 'https://api.scryfall.com/cards';

  String _tcgdexBase(String language) => 'https://api.tcgdex.net/v2/$language';

  /// Get price for a Pokémon card by ID.
  /// [source] is either 'tcgdex' (default) or 'ptcg' (pokemontcg.io).
  /// [language] selects the TCGdex language endpoint (en/ja/zh-cn).
  Future<double> getPokemonPrice(
    String cardId, {
    String source = 'tcgdex',
    String language = 'en',
  }) async {
    // pokemontcg.io only indexes English cards.
    if (source == 'ptcg' && language == 'en') {
      return _getPtcgPrice(cardId);
    }

    try {
      final response = await _getWithRetry(
        '${_tcgdexBase(language)}/cards/$cardId',
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final best = _bestMarketPrice(data);
        if (best > 0) return best;
      }
    } catch (e) {
      print("Error fetching Pokemon price ($language): $e");
    }
    return 0.0;
  }

  double _bestMarketPrice(dynamic card) {
    if (card is! Map) return 0;

    var bestCardmarket = 0.0;
    var bestTcgplayer = 0.0;

    void consider(dynamic pricing) {
      if (pricing is! Map) return;
      final cardmarket = _priceFromCardmarket(pricing);
      if (cardmarket > bestCardmarket) bestCardmarket = cardmarket;
      final tcgplayer = _priceFromTcgplayer(pricing);
      if (tcgplayer > bestTcgplayer) bestTcgplayer = tcgplayer;
    }

    consider(card['pricing']);
    // Japanese/Chinese cards sometimes carry the market price only on a
    // variant (normal/holo/reverse), not on the top-level pricing object.
    final variants = card['variants_detailed'];
    if (variants is List) {
      for (final variant in variants) {
        if (variant is! Map) continue;
        consider(variant['pricing']);
      }
    }

    // Cardmarket is always preferred, even when another variant only has a
    // TCGplayer price.
    return bestCardmarket > 0 ? bestCardmarket : bestTcgplayer;
  }

  double _priceFromCardmarket(dynamic pricing) {
    if (pricing is! Map) return 0;
    final cardmarket = pricing['cardmarket'];
    if (cardmarket is! Map) return 0;
    final average = (cardmarket['avg'] as num?)?.toDouble() ?? 0;
    final trend = (cardmarket['trend'] as num?)?.toDouble() ?? 0;
    final low = (cardmarket['low'] as num?)?.toDouble() ?? 0;
    if (average > 0) return average;
    if (trend > 0) return trend;
    if (low > 0) return low;
    return 0;
  }

  double _priceFromTcgplayer(dynamic pricing) {
    if (pricing is! Map) return 0;
    final tcgplayer = pricing['tcgplayer'];
    if (tcgplayer is! Map) return 0;
    final average = (tcgplayer['avg'] as num?)?.toDouble() ?? 0;
    final market = (tcgplayer['market'] as num?)?.toDouble() ?? 0;
    final low = (tcgplayer['low'] as num?)?.toDouble() ?? 0;
    if (average > 0) return average;
    if (market > 0) return market;
    if (low > 0) return low;
    return 0;
  }

  Future<double> _getPtcgPrice(String cardId) async {
    try {
      final response = await http.get(Uri.parse('$ptcgApiBase/cards/$cardId'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'];
        final tcgPrices = data['tcgplayer']?['prices'];
        if (tcgPrices != null) {
          for (final key in [
            'holofoil',
            'normal',
            'reverseHolofoil',
            '1stEditionHolofoil',
          ]) {
            final market = tcgPrices[key]?['market'];
            if (market != null) return (market as num).toDouble();
          }
        }
        final cmPrice = data['cardmarket']?['prices']?['averageSellPrice'];
        if (cmPrice != null) return (cmPrice as num).toDouble();
      }
    } catch (e) {
      print("Error fetching Pokemon price (ptcg): $e");
    }
    return 0.0;
  }

  /// Get price for an MTG card by name using Scryfall
  Future<double> getMtgPrice(String cardName) async {
    try {
      final encodedName = Uri.encodeComponent(cardName);
      final response = await http.get(
        Uri.parse('$mtgApiBase/named?fuzzy=$encodedName'),
        headers: {'User-Agent': 'RaritioTCG/1.0', 'Accept': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final prices = data['prices'];

        if (prices != null) {
          if (prices['usd'] != null)
            return double.parse(prices['usd'].toString());
          if (prices['eur'] != null)
            return double.parse(prices['eur'].toString());
          if (prices['tix'] != null)
            return double.parse(prices['tix'].toString());
        }
      }
    } catch (e) {
      print("Error fetching MTG price: $e");
    }
    return 0.0;
  }

  /// Retries transient 5xx errors (TCGdex occasionally answers "no available server").
  Future<http.Response> _getWithRetry(String url) async {
    http.Response? lastResponse;
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        lastResponse = await http.get(Uri.parse(url));
        lastError = null;
        if (lastResponse.statusCode < 500) return lastResponse;
      } catch (error) {
        lastError = error;
      }
      if (attempt < 2) {
        await Future.delayed(const Duration(milliseconds: 700));
      }
    }
    if (lastResponse != null) return lastResponse;
    throw lastError ?? Exception('Price request failed');
  }
}
