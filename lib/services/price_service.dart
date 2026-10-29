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
    String? variantId,
    String? finish,
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
        final selected = _findVariant(data, variantId, finish);
        if (selected != null) {
          final price = _variantPrice(selected);
          if (price > 0) return price;
        }
        final topLevel = _priceFromPricingForFinish(data['pricing'], finish);
        if (topLevel > 0) return topLevel;
      }
    } catch (e) {
      print("Error fetching Pokemon price ($language): $e");
    }
    return 0.0;
  }

  dynamic _findVariant(dynamic card, String? variantId, String? finish) {
    if (card is! Map) return null;
    final variants = card['variants_detailed'];
    if (variants is! List) return null;

    if (variantId != null && variantId.trim().isNotEmpty) {
      for (final variant in variants) {
        if (variant is Map &&
            variant['variantId']?.toString() == variantId.trim()) {
          return variant;
        }
      }
    }

    if (finish == null || finish.trim().isEmpty) return null;
    final wanted = finish.trim().toLowerCase();
    final matching = variants.whereType<Map>().where((variant) {
      return _finishForVariant(variant) == wanted;
    }).toList();
    if (matching.isEmpty) return null;
    final plain = matching.where((variant) {
      final stamp = variant['stamp'];
      final foil = variant['foil']?.toString().trim() ?? '';
      return (stamp is! List || stamp.isEmpty) && foil.isEmpty;
    }).toList();
    if (plain.isNotEmpty) return plain.first;
    final unstamped = matching.where((variant) {
      final stamp = variant['stamp'];
      return stamp is! List || stamp.isEmpty;
    }).toList();
    return unstamped.isNotEmpty ? unstamped.first : matching.first;
  }

  String _finishForVariant(Map variant) {
    final foil = variant['foil']?.toString().trim().toLowerCase() ?? '';
    if (foil == 'rainbow') return 'rainbow';
    if (foil == 'gold') return 'gold';
    if (foil == 'cosmos') return 'cosmos';
    if (foil == 'textured' || foil == 'texture') return 'textured';
    if (foil == 'etched') return 'etched';
    final type = variant['type']?.toString().trim().toLowerCase() ?? '';
    if (type == 'reverse') return 'reverse';
    if (type == 'holo') return 'holo';
    if (type == 'normal') return 'normal';
    return type;
  }

  double _variantPrice(Map variant) {
    final type = variant['type']?.toString().trim().toLowerCase() ?? '';
    final pricing = variant['pricing'];
    if (pricing is! Map) return 0;

    final cardmarket = pricing['cardmarket'];
    if (cardmarket is Map) {
      final useHolo = type != 'normal';
      final average = _number(cardmarket[useHolo ? 'avg-holo' : 'avg']);
      final trend = _number(cardmarket[useHolo ? 'trend-holo' : 'trend']);
      final low = _number(cardmarket[useHolo ? 'low-holo' : 'low']);
      final fallbackAverage = _number(cardmarket[useHolo ? 'avg' : 'avg-holo']);
      final fallbackTrend = _number(
        cardmarket[useHolo ? 'trend' : 'trend-holo'],
      );
      final fallbackLow = _number(cardmarket[useHolo ? 'low' : 'low-holo']);
      if (average > 0) return average;
      if (trend > 0) return trend;
      if (low > 0) return low;
      if (fallbackAverage > 0) return fallbackAverage;
      if (fallbackTrend > 0) return fallbackTrend;
      if (fallbackLow > 0) return fallbackLow;
    }
    return _priceFromTcgplayer(pricing);
  }

  double _priceFromPricingForFinish(dynamic pricing, String? finish) {
    if (pricing is! Map) return 0;
    final cardmarket = pricing['cardmarket'];
    if (cardmarket is Map) {
      final useHolo =
          finish != null &&
          finish.isNotEmpty &&
          finish != 'normal' &&
          finish != 'firstEdition';
      final average = _number(cardmarket[useHolo ? 'avg-holo' : 'avg']);
      final trend = _number(cardmarket[useHolo ? 'trend-holo' : 'trend']);
      final low = _number(cardmarket[useHolo ? 'low-holo' : 'low']);
      if (average > 0) return average;
      if (trend > 0) return trend;
      if (low > 0) return low;
    }
    return _priceFromTcgplayer(pricing);
  }

  double _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
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
