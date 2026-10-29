import 'package:http/http.dart' as http;
import 'dart:convert';

class CardService {
  static const String mtgApiBase = 'https://api.scryfall.com';

  /// Set names are cached per TCGdex language because Japanese/Chinese sets
  /// have localized names that differ from the English set list.
  final Map<String, Map<String, String>> _setNameCaches = {};

  String _apiBase(String language) => 'https://api.tcgdex.net/v2/$language';

  /// Retries transient 5xx errors (TCGdex occasionally answers "no available server").
  Future<http.Response> _getWithRetry(Uri uri, {Map<String, String>? headers}) async {
    http.Response? lastResponse;
    for (var attempt = 0; attempt < 3; attempt++) {
      lastResponse = await http.get(uri, headers: headers);
      if (lastResponse.statusCode < 500) return lastResponse;
      if (attempt < 2) {
        await Future.delayed(const Duration(milliseconds: 700));
      }
    }
    return lastResponse!;
  }

  /// Loads set id -> set name once per language so search results can show
  /// the edition (important for telling printings apart).
  Future<Map<String, String>> _getSetNames(String language) async {
    final cached = _setNameCaches[language];
    if (cached != null) return cached;
    try {
      final response = await _getWithRetry(
        Uri.parse('${_apiBase(language)}/sets'),
      );
      if (response.statusCode == 200) {
        final List<dynamic> sets = jsonDecode(response.body);
        final names = <String, String>{
          for (final set in sets)
            if (set['id'] != null)
              set['id'] as String: set['name'] as String? ?? '',
        };
        _setNameCaches[language] = names;
        return names;
      }
    } catch (e) {
      print("Set list error ($language): $e");
    }
    return <String, String>{};
  }

  String _setIdFromCardId(String cardId) {
    final index = cardId.lastIndexOf('-');
    return index > 0 ? cardId.substring(0, index) : '';
  }

  /// Searches Pokemon cards by name, optionally with a card number.
  /// Supports queries like "Gyarados 049/182", "Gyarados 49", "リザードン
  /// 001/165" and "喷火龙GX 002/176".
  Future<List<Map<String, dynamic>>> searchPokemon(
    String query, {
    String language = 'en',
  }) async {
    try {
      String name = query.trim();
      String? number;

      // Match "Name 123/456", "Name 123", "Name TG01/TG30", "Name 001/S-P"
      // or "123/456 Name". The part after the slash may be a total or a promo
      // suffix such as "S-P"/"SV-P".
      final trailingNumber = RegExp(
        r'^(.+?)\s+#?([A-Za-z]*\d+)(?:\s*/\s*[A-Za-z0-9-]+)?$',
      ).firstMatch(name);
      final leadingNumber = RegExp(
        r'^#?([A-Za-z]*\d+)(?:\s*/\s*[A-Za-z0-9-]+)?\s+(.+)$',
      ).firstMatch(name);
      if (trailingNumber != null) {
        name = trailingNumber.group(1)!.trim();
        number = trailingNumber.group(2)!.trim();
      } else if (leadingNumber != null) {
        number = leadingNumber.group(1)!.trim();
        name = leadingNumber.group(2)!.trim();
      } else {
        // A scan sometimes yields only the collector number.
        final numberOnly = RegExp(
          r'^#?([A-Za-z]{0,4}\d{1,4})(?:\s*/\s*[A-Za-z0-9-]+)?$',
        ).firstMatch(name);
        if (numberOnly != null) {
          number = numberOnly.group(1)!.trim();
          name = '';
        }
      }

      if (name.isEmpty && number == null) return [];

      final base = _apiBase(language);
      String cardsUrl({String? cardName, String? localId}) {
        final params = <String>[];
        if (cardName != null && cardName.isNotEmpty) {
          params.add('name=${Uri.encodeComponent(cardName)}');
        }
        if (localId != null && localId.isNotEmpty) {
          params.add('localId=${Uri.encodeComponent(localId)}');
        }
        return '$base/cards?${params.join('&')}';
      }

      final response = await _getWithRetry(
        Uri.parse(cardsUrl(cardName: name, localId: number)),
      );
      if (response.statusCode != 200) return [];

      final List<dynamic> summaries = jsonDecode(response.body);

      // If an exact number was requested but nothing matched (e.g. "49" vs "049"),
      // retry with zero-padded / zero-stripped variants.
      if (summaries.isEmpty && number != null) {
        final variants = <String>{};
        if (RegExp(r'^\d+$').hasMatch(number)) {
          variants.add(number.padLeft(3, '0'));
          variants.add(number.replaceFirst(RegExp(r'^0+'), ''));
        }
        variants.remove(number);
        for (final variant in variants) {
          if (variant.isEmpty) continue;
          final retryResponse = await _getWithRetry(
            Uri.parse(cardsUrl(cardName: name, localId: variant)),
          );
          if (retryResponse.statusCode == 200) {
            final found = jsonDecode(retryResponse.body) as List<dynamic>;
            if (found.isNotEmpty) {
              summaries.addAll(found);
              break;
            }
          }
        }
      }

      // A number-only search can return hundreds of printings. Keep the list
      // manageable and put the most recent sets first.
      if (name.isEmpty) {
        summaries.sort((a, b) {
          final aId = a['id'] as String? ?? '';
          final bId = b['id'] as String? ?? '';
          return bId.compareTo(aId);
        });
        if (summaries.length > 80) {
          summaries.removeRange(80, summaries.length);
        }
      }

      // Return every summary (no detail requests here). Full details are fetched
      // lazily when the user taps a result, so all printings are findable.
      final setNames = await _getSetNames(language);
      return summaries.map((s) {
        final image = s['image'] as String?;
        final id = s['id'] as String? ?? '';
        final setId = _setIdFromCardId(id);
        return <String, dynamic>{
          'id': id,
          'name': s['name'],
          'game': 'pokemon',
          'language': language,
          'set': setNames[setId] ?? setId,
          'setId': setId,
          'imageUri': image != null ? '$image/low.webp' : '',
          'price': 0.0,
          'rarity': '',
          'foil': false,
          'finishes': <String>[],
          'finish': '',
          'priceSource': '',
          'number': s['localId'] ?? '',
          'artist': '',
          'detailsLoaded': false,
        };
      }).toList();
    } catch (e) {
      print("Pokemon search error ($language): $e");
    }
    return [];
  }

  /// Fetches full details for a single Pokemon card in the given language.
  Future<Map<String, dynamic>?> getPokemonDetails(
    String id, {
    String language = 'en',
  }) async {
    try {
      final response = await _getWithRetry(
        Uri.parse('${_apiBase(language)}/cards/$id'),
      );
      if (response.statusCode != 200) return null;

      final card = jsonDecode(response.body);
      final pricing = card['pricing'];
      final cardmarket = _bestCardmarketPricing(card);
      final price = _bestPrice(card);
      var priceSource = _priceSource(pricing);
      if (priceSource.isEmpty && price > 0) priceSource = 'cardmarket';

      final localId = card['localId'] ?? '';
      final setCount = card['set']?['cardCount']?['official'] ??
          card['set']?['cardCount']?['total'];
      final number = (localId.isNotEmpty && setCount != null)
          ? '$localId/$setCount'
          : localId;

      final rawRarity = (card['rarity'] as String? ?? '').trim();
      final rarity = (rawRarity.isEmpty ||
              rawRarity.toLowerCase() == 'none' ||
              rawRarity.toLowerCase() == 'unknown')
          ? 'Neznáma'
          : rawRarity;

      final variants = card['variants'];
      final variantsDetailed = card['variants_detailed'];
      final finishes = _finishesFromVariants(variants, variantsDetailed);
      final imageUri = await _resolveImage(card, language);

      return <String, dynamic>{
        'id': card['id'],
        'name': card['name'],
        'game': 'pokemon',
        'language': language,
        'set': card['set']?['name'] ?? '',
        'setId': card['set']?['id'] ?? '',
        'imageUri': imageUri,
        'price': price,
        'priceSource': priceSource,
        'priceCurrency': priceSource == 'cardmarket' ? 'EUR' : 'USD',
        'rarity': rarity,
        'foil': finishes.any((finish) => finish != 'normal'),
        'finish': _primaryFinish(variants, variantsDetailed),
        'finishes': finishes,
        'number': number,
        'artist': card['illustrator'] ?? '',
        'priceHistory': _priceHistoryFromCardmarket(cardmarket),
        'detailsLoaded': true,
      };
    } catch (e) {
      print("Pokemon detail error ($language): $e");
      return null;
    }
  }

  double _bestPrice(dynamic card) {
    if (card is! Map) return 0;
    final direct = _priceFromPricing(card['pricing']);
    if (direct > 0) return direct;

    // Japanese sets often expose pricing only on the variant entries.
    final variants = card['variants_detailed'];
    if (variants is List) {
      for (final variant in variants) {
        if (variant is! Map) continue;
        final value = _priceFromPricing(variant['pricing']);
        if (value > 0) return value;
      }
    }
    return 0;
  }

  dynamic _bestCardmarketPricing(dynamic card) {
    if (card is! Map) return null;
    final pricing = card['pricing'];
    if (pricing is Map && pricing['cardmarket'] is Map) {
      return pricing['cardmarket'];
    }
    final variants = card['variants_detailed'];
    if (variants is List) {
      for (final variant in variants) {
        if (variant is! Map) continue;
        final variantPricing = variant['pricing'];
        if (variantPricing is Map && variantPricing['cardmarket'] is Map) {
          return variantPricing['cardmarket'];
        }
      }
    }
    return null;
  }

  double _priceFromPricing(dynamic pricing) {
    if (pricing is! Map) return 0;

    final cardmarket = pricing['cardmarket'];
    if (cardmarket is Map) {
      final average = (cardmarket['avg'] as num?)?.toDouble() ?? 0;
      final trend = (cardmarket['trend'] as num?)?.toDouble() ?? 0;
      final low = (cardmarket['low'] as num?)?.toDouble() ?? 0;
      if (average > 0) return average;
      if (trend > 0) return trend;
      if (low > 0) return low;
    }

    final tcgplayer = pricing['tcgplayer'];
    if (tcgplayer is Map) {
      final average = (tcgplayer['avg'] as num?)?.toDouble() ?? 0;
      final market = (tcgplayer['market'] as num?)?.toDouble() ?? 0;
      final low = (tcgplayer['low'] as num?)?.toDouble() ?? 0;
      if (average > 0) return average;
      if (market > 0) return market;
      if (low > 0) return low;
    }
    return 0;
  }

  String _priceSource(dynamic pricing) {
    if (pricing is! Map) return '';
    final cardmarket = pricing['cardmarket'];
    if (cardmarket is Map && _priceFromPricing({'cardmarket': cardmarket}) > 0) {
      return 'cardmarket';
    }
    final tcgplayer = pricing['tcgplayer'];
    if (tcgplayer is Map && _priceFromPricing({'tcgplayer': tcgplayer}) > 0) {
      return 'tcgplayer';
    }
    return '';
  }

  List<String> _finishesFromVariants(dynamic variants, [dynamic variantsDetailed]) {
    final finishes = <String>[];

    // TCGdex exposes the actual foil style in variants_detailed. This is where
    // gold, rainbow, cosmos and textured cards differ from a plain holo card.
    if (variantsDetailed is List) {
      for (final variant in variantsDetailed) {
        if (variant is! Map) continue;
        final foil = _finishFromFoil(variant['foil']);
        if (foil.isNotEmpty) finishes.add(foil);
        final type = _finishFromFoil(variant['type']);
        if (type.isNotEmpty) finishes.add(type);
      }
    }

    if (variants is Map) {
      if (variants['rainbow'] == true || variants['rainbowRare'] == true) {
        finishes.add('rainbow');
      }
      if (variants['gold'] == true || variants['goldCard'] == true) {
        finishes.add('gold');
      }
      if (variants['cosmos'] == true) finishes.add('cosmos');
      if (variants['textured'] == true || variants['texture'] == true) {
        finishes.add('textured');
      }
      if (variants['holo'] == true || variants['holofoil'] == true) {
        finishes.add('holo');
      }
      if (variants['reverse'] == true) finishes.add('reverse');
      if (variants['firstEdition'] == true) finishes.add('firstEdition');
      if (variants['normal'] == true) finishes.add('normal');
    }

    return finishes.toSet().toList();
  }

  String _finishFromFoil(dynamic value) {
    final foil = (value ?? '').toString().toLowerCase().trim();
    if (foil.isEmpty) return '';
    if (foil == 'rainbow' || foil == 'rainbow rare') return 'rainbow';
    if (foil == 'gold' || foil == 'gold card') return 'gold';
    if (foil == 'cosmos') return 'cosmos';
    if (foil == 'textured' || foil == 'texture') return 'textured';
    if (foil == 'etched') return 'etched';
    if (foil == 'reverse' || foil == 'reverse holo') return 'reverse';
    if (foil == 'holo' || foil == 'holofoil') return 'holo';
    if (foil == 'foil') return 'foil';
    if (foil == 'normal' || foil == 'nonfoil') return 'normal';
    if (foil == 'firstedition' || foil == 'first edition') return 'firstEdition';
    return '';
  }

  String _primaryFinish(dynamic variants, [dynamic variantsDetailed]) {
    final finishes = _finishesFromVariants(variants, variantsDetailed);
    for (final preferred in const [
      'rainbow',
      'gold',
      'cosmos',
      'textured',
      'etched',
      'reverse',
      'holo',
      'foil',
      'firstEdition',
      'normal',
    ]) {
      if (finishes.contains(preferred)) return preferred;
    }
    return '';
  }

  /// Chinese TCGdex entries sometimes have no image. Try the same card name and
  /// local number in the other CJK endpoints before falling back to a placeholder.
  Future<String> _resolveImage(dynamic card, String language) async {
    final image = card['image']?.toString() ?? '';
    if (image.isNotEmpty) return '$image/high.webp';

    final name = card['name']?.toString() ?? '';
    final localId = card['localId']?.toString() ?? '';
    if (name.isEmpty || localId.isEmpty) return '';

    for (final alternate in const ['zh-tw', 'ja', 'zh-cn']) {
      if (alternate == language) continue;
      try {
        final response = await _getWithRetry(
          Uri.parse(
            '${_apiBase(alternate)}/cards?name=${Uri.encodeComponent(name)}',
          ),
        );
        if (response.statusCode != 200) continue;
        final cards = jsonDecode(response.body);
        if (cards is! List) continue;
        for (final candidate in cards) {
          if (candidate is! Map) continue;
          if (candidate['localId']?.toString() != localId) continue;
          final candidateImage = candidate['image']?.toString() ?? '';
          if (candidateImage.isNotEmpty) return '$candidateImage/high.webp';
        }
      } catch (_) {
        // A missing alternate image must never prevent the card from loading.
      }
    }
    return '';
  }

  /// Cardmarket exposes 30/7/1-day averages, not a daily series. They give the
  /// price chart a useful starting trend until local snapshots accumulate.
  List<Map<String, dynamic>> _priceHistoryFromCardmarket(dynamic pricing) {
    if (pricing is! Map) return <Map<String, dynamic>>[];

    final now = DateTime.now().toUtc();
    final byDate = <String, Map<String, dynamic>>{};

    void addPoint(int daysAgo, dynamic value) {
      final price = (value as num?)?.toDouble() ?? 0.0;
      if (price <= 0) return;
      final date = now.subtract(Duration(days: daysAgo));
      final key = date.toIso8601String().substring(0, 10);
      byDate[key] = <String, dynamic>{
        'date': key,
        'price': price,
        'source': 'cardmarket',
      };
    }

    addPoint(30, pricing['avg30']);
    addPoint(7, pricing['avg7']);
    addPoint(1, pricing['avg1']);

    final average = (pricing['avg'] as num?)?.toDouble() ?? 0.0;
    final trend = (pricing['trend'] as num?)?.toDouble() ?? 0.0;
    addPoint(0, average > 0 ? average : trend);

    final points = byDate.values.toList()
      ..sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));
    return points;
  }

  Future<List<Map<String, dynamic>>> searchMtg(String query) async {
    try {
      final encodedQuery = Uri.encodeComponent(query);
      final response = await _getWithRetry(
        Uri.parse('$mtgApiBase/cards/search?q=$encodedQuery'),
        headers: {
          'User-Agent': 'RaritioTCG/1.0',
          'Accept': 'application/json',
        },
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['data'].map((card) => {
          'id': card['id'],
          'name': card['name'],
          'game': 'mtg',
          'language': 'en',
          'set': card['set_name'] ?? '',
          'imageUri': _mtgImage(card),
          'price': double.tryParse(card['prices']?['usd'] ?? '0') ?? 0.0,
          'priceSource': 'scryfall',
          'priceCurrency': 'USD',
          'rarity': card['rarity'] ?? 'Unknown',
          'foil': _mtgFinishes(card).any((finish) => finish != 'normal'),
          'finish': _mtgPrimaryFinish(card),
          'finishes': _mtgFinishes(card),
          'number': card['collector_number'] ?? '',
          'artist': card['artist'] ?? '',
          'detailsLoaded': true,
        }));
      }
    } catch (e) {
      print("MTG search error: $e");
    }
    return [];
  }

  /// Reloads the Scryfall image for a stored MTG card id.
  Future<String?> getMtgImage(String id) async {
    if (id.trim().isEmpty) return null;
    try {
      final response = await _getWithRetry(
        Uri.parse('$mtgApiBase/$id'),
        headers: {
          'User-Agent': 'RaritioTCG/1.0',
          'Accept': 'application/json',
        },
      );
      if (response.statusCode != 200) return null;
      final card = jsonDecode(response.body);
      final image = _mtgImage(card);
      return image.isEmpty ? null : image;
    } catch (e) {
      print("MTG image error: $e");
      return null;
    }
  }

  String _mtgImage(dynamic card) {
    if (card is! Map) return '';
    final images = card['image_uris'];
    if (images is Map) {
      final large = images['large']?.toString() ?? '';
      if (large.isNotEmpty) return large;
      final normal = images['normal']?.toString() ?? '';
      if (normal.isNotEmpty) return normal;
    }
    final faces = card['card_faces'];
    if (faces is List) {
      for (final face in faces) {
        if (face is! Map) continue;
        final faceImages = face['image_uris'];
        if (faceImages is! Map) continue;
        final large = faceImages['large']?.toString() ?? '';
        if (large.isNotEmpty) return large;
        final normal = faceImages['normal']?.toString() ?? '';
        if (normal.isNotEmpty) return normal;
      }
    }
    return '';
  }

  List<String> _mtgFinishes(dynamic card) {
    final raw = card is Map ? card['finishes'] : null;
    if (raw is! List) return <String>[];
    return raw
        .map((finish) => finish.toString().toLowerCase())
        .where((finish) => finish.isNotEmpty)
        .toList();
  }

  String _mtgPrimaryFinish(dynamic card) {
    final finishes = _mtgFinishes(card);
    for (final preferred in const ['foil', 'etched', 'glossy', 'normal']) {
      if (finishes.contains(preferred)) return preferred;
    }
    return finishes.isNotEmpty ? finishes.first : '';
  }
}

