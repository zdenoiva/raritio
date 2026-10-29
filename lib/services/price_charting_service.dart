import 'dart:convert';

import 'package:http/http.dart' as http;

/// Reads public PriceCharting pages through Jina's text reader.
///
/// PriceCharting itself answers direct requests with a Cloudflare challenge on
/// Android. The reader endpoint returns the same page as Markdown, including
/// the complete "Full Price Guide" with every grading company and the recent
/// sold listings.
class PriceChartingService {
  static const String _readerBase = 'https://r.jina.ai/';

  final http.Client _client;

  PriceChartingService({http.Client? client}) : _client = client ?? http.Client();

  Future<Map<String, dynamic>?> fetchForCard({
    required String name,
    required String set,
    required String number,
    String game = 'pokemon',
    String? language,
    String? existingUrl,
  }) async {
    if (name.trim().isEmpty) return null;

    final candidates = <String>[];
    final saved = (existingUrl ?? '').trim();
    if (saved.isNotEmpty) candidates.add(saved);

    final direct = buildUrl(name: name, set: set, number: number, game: game);
    if (direct != null && !candidates.contains(direct)) candidates.add(direct);

    for (final url in candidates) {
      final markdown = await _read(url);
      if (markdown == null) continue;
      final parsed = parsePage(markdown, url: url);
      if (parsed != null) return parsed;
    }

    // Fallback: search PriceCharting by name and collector number. This also
    // handles set names that use a different slug on the site.
    final query = [name, number, set]
        .where((part) => part.trim().isNotEmpty)
        .join(' ')
        .trim();
    if (query.isEmpty) return null;

    final searchUrl =
        'https://www.pricecharting.com/search-products?q=${Uri.encodeQueryComponent(query)}&type=prices';
    final searchMarkdown = await _read(searchUrl);
    if (searchMarkdown == null) return null;

    final productUrl = findProductUrl(
      searchMarkdown,
      name: name,
      number: number,
      set: set,
    );
    if (productUrl == null || candidates.contains(productUrl)) return null;

    final markdown = await _read(productUrl);
    if (markdown == null) return null;
    return parsePage(markdown, url: productUrl);
  }

  Future<String?> _read(String targetUrl) async {
    try {
      // The reader only includes the hidden "Full Price Guide" section (all
      // grading companies) when it renders the complete page. The query option
      // is understood by the reader and is not sent to PriceCharting.
      final separator = targetUrl.contains('?') ? '&' : '?';
      final readerUrl =
          '$_readerBase$targetUrl${separator}x-return-format=html';
      final response = await _client
          .get(
            Uri.parse(readerUrl),
            headers: const {
              'Accept': 'text/plain',
              'User-Agent': 'RaritioTCG/1.0 (Android)',
            },
          )
          .timeout(const Duration(seconds: 35));
      if (response.statusCode != 200) return null;
      return utf8.decode(response.bodyBytes, allowMalformed: true);
    } catch (_) {
      return null;
    }
  }

  static String? buildUrl({
    required String name,
    required String set,
    required String number,
    String game = 'pokemon',
  }) {
    final setSlug = slugify(set);
    final nameSlug = slugify(name);
    final numberSlug = _numberSlug(number);
    if (setSlug.isEmpty || nameSlug.isEmpty || numberSlug.isEmpty) return null;

    final category = game == 'mtg' ? 'magic-the-gathering' : 'pokemon';
    final prefix = setSlug.startsWith('pokemon') ? '' : '$category-';
    return 'https://www.pricecharting.com/game/$prefix$setSlug/$nameSlug-$numberSlug';
  }

  static String? findProductUrl(
    String markdown, {
    required String name,
    required String number,
    String? set,
  }) {
    final wantedName = _normalizeText(name);
    final wantedNumber = _normalizeNumber(number);
    final setSlug = slugify(set ?? '');

    final links = RegExp(
      r'\[([^\]]+)\]\((https://www\.pricecharting\.com/game/[^)\s]+)',
    ).allMatches(markdown);

    String? nameAndNumberMatch;
    for (final link in links) {
      final title = _normalizeText(link.group(1) ?? '');
      final url = link.group(2) ?? '';
      if (url.isEmpty) continue;

      final titleWithoutNumber = title.split('#').first.trim();
      final nameMatches = wantedName.isNotEmpty &&
          (title.contains(wantedName) ||
              wantedName.contains(titleWithoutNumber) ||
              titleWithoutNumber.contains(wantedName));
      final numberMatches = wantedNumber.isEmpty || title.contains(wantedNumber);
      if (!nameMatches || !numberMatches) continue;

      if (setSlug.isNotEmpty && url.contains(setSlug)) return url;
      nameAndNumberMatch ??= url;
    }
    // Never return an unrelated first hit: a wrong card would silently attach
    // the wrong market price. Direct URLs are still tried before this fallback.
    return nameAndNumberMatch;
  }

  static Map<String, dynamic>? parsePage(String markdown, {String? url}) {
    // Prefer the complete guide (Ungraded, Grade 1-9.5, PSA/BGS/CGC/SGC/TAG/
    // ACE 10 and their variants). The compact table only contains a subset.
    final grades = _parseFullPriceGuide(markdown);
    if (grades.isEmpty) grades.addAll(_parseGradeTable(markdown));
    final history = _parseSoldHistory(markdown);
    if (grades.isEmpty && history.isEmpty) return null;

    double price = 0;
    for (final grade in grades) {
      if (grade['label'] == 'Ungraded') {
        price = (grade['price'] as num).toDouble();
        break;
      }
    }
    if (price <= 0 && grades.isNotEmpty) {
      price = (grades.first['price'] as num).toDouble();
    }

    return <String, dynamic>{
      'url': url,
      'gradePrices': grades,
      'price': price,
      'priceHistory': history,
      'source': 'pricecharting',
      'updated': DateTime.now().toUtc().toIso8601String(),
    };
  }

  static List<Map<String, dynamic>> _parseFullPriceGuide(String markdown) {
    final lines = markdown.split(RegExp(r'\r?\n'));
    var inGuide = false;
    final result = <Map<String, dynamic>>[];
    final pricePattern =
        RegExp(r'^(.+?)\s*\$([0-9][0-9,]*(?:\.[0-9]+)?)\s*$');
    final noPricePattern = RegExp(r'^(.+?)\s*-\s*$');

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (!inGuide) {
        if (line.toLowerCase().startsWith('## full price guide')) {
          inGuide = true;
        }
        continue;
      }

      if (line.isEmpty) {
        if (result.isNotEmpty) break;
        continue;
      }
      if (line.toLowerCase().startsWith('all prices are')) break;

      final priceMatch = pricePattern.firstMatch(line);
      if (priceMatch != null) {
        final label = _cleanLabel(priceMatch.group(1) ?? '');
        final price = double.tryParse(
          (priceMatch.group(2) ?? '').replaceAll(',', ''),
        );
        if (label.isNotEmpty && price != null && price > 0) {
          result.add(<String, dynamic>{'label': label, 'price': price});
        }
        continue;
      }

      // PriceCharting lists some grades without a market price, for example
      // "TAG 10 -". They are intentionally skipped instead of shown as $0.
      if (noPricePattern.hasMatch(line)) continue;

      if (result.isNotEmpty) break;
    }

    return result;
  }

  static List<Map<String, dynamic>> _parseGradeTable(String markdown) {
    final lines = markdown.split(RegExp(r'\r?\n'));
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (!line.startsWith('|')) continue;
      if (!line.contains('Ungraded') || !line.toLowerCase().contains('grade')) {
        continue;
      }

      final headers = _tableCells(line);
      if (headers.length < 2) continue;

      var dataIndex = i + 1;
      while (dataIndex < lines.length &&
          (!lines[dataIndex].trim().startsWith('|') ||
              _isSeparator(lines[dataIndex]))) {
        dataIndex++;
      }
      if (dataIndex >= lines.length) continue;

      final values = _tableCells(lines[dataIndex]);
      if (values.isEmpty) continue;

      final result = <Map<String, dynamic>>[];
      for (var column = 0; column < headers.length; column++) {
        final label = _cleanLabel(headers[column]);
        if (label.isEmpty || label.toLowerCase() == 'volume') continue;
        final cell = column < values.length ? values[column] : '';
        final price = _firstPrice(cell);
        if (price == null || price <= 0) continue;
        result.add(<String, dynamic>{'label': label, 'price': price});
      }
      if (result.isNotEmpty) return result;
    }
    return <Map<String, dynamic>>[];
  }

  static List<Map<String, dynamic>> _parseSoldHistory(String markdown) {
    final byDate = <String, double>{};
    final linePattern = RegExp(r'^\|\s*(\d{4}-\d{2}-\d{2})\s*\|(.*)$');
    final pricePattern = RegExp(r'\$\s*([0-9][0-9,]*\.?[0-9]*)');

    for (final line in markdown.split(RegExp(r'\r?\n'))) {
      final match = linePattern.firstMatch(line.trim());
      if (match == null) continue;
      final date = match.group(1)!;
      final rest = match.group(2)!;
      final prices = pricePattern
          .allMatches(rest)
          .map((price) => double.tryParse(
                (price.group(1) ?? '').replaceAll(',', ''),
              ))
          .whereType<double>()
          .where((price) => price > 0)
          .toList();
      if (prices.isEmpty) continue;
      // The sold price is the last amount in the row (shipping/asking prices
      // can appear before it).
      byDate[date] = prices.last;
    }

    final points = byDate.entries
        .map((entry) => <String, dynamic>{
              'date': entry.key,
              'price': entry.value,
              'source': 'pricecharting',
            })
        .toList()
      ..sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));
    return points.length > 40
        ? points.sublist(points.length - 40)
        : points;
  }

  static List<String> _tableCells(String line) {
    final trimmed = line.trim();
    final withoutEdges = trimmed.startsWith('|') ? trimmed.substring(1) : trimmed;
    final value = withoutEdges.endsWith('|')
        ? withoutEdges.substring(0, withoutEdges.length - 1)
        : withoutEdges;
    return value.split('|').map((cell) => cell.trim()).toList();
  }

  static bool _isSeparator(String line) {
    final cells = _tableCells(line);
    if (cells.isEmpty) return false;
    return cells.every((cell) {
      final value = cell.replaceAll(RegExp(r'[\s:\-]'), '');
      return value.isEmpty;
    });
  }

  static String _cleanLabel(String value) {
    return value
        .replaceAllMapped(
          RegExp(r'\[([^\]]*)\]\([^)]*\)'),
          (match) => match.group(1) ?? '',
        )
        .replaceAll(RegExp(r'[*_`]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static double? _firstPrice(String value) {
    final match = RegExp(r'\$\s*([0-9][0-9,]*\.?[0-9]*)').firstMatch(value);
    if (match == null) return null;
    return double.tryParse((match.group(1) ?? '').replaceAll(',', ''));
  }

  static String _numberSlug(String value) {
    final first = value.split('/').first.trim().toLowerCase();
    final match = RegExp(r'^([a-z]*)(\d+)$').firstMatch(first);
    if (match == null) return slugify(first);
    final prefix = match.group(1) ?? '';
    final digits = (match.group(2) ?? '').replaceFirst(RegExp(r'^0+'), '');
    return slugify('$prefix${digits.isEmpty ? '0' : digits}');
  }

  static String _normalizeNumber(String value) {
    final first = value.split('/').first.trim().toLowerCase();
    final match = RegExp(r'^([a-z]*)(\d+)$').firstMatch(first);
    if (match == null) return _normalizeText(first);
    final prefix = match.group(1) ?? '';
    final digits = (match.group(2) ?? '').replaceFirst(RegExp(r'^0+'), '');
    return _normalizeText('$prefix${digits.isEmpty ? '0' : digits}');
  }

  static String _normalizeText(String value) {
    return slugify(value).replaceAll('-', ' ').trim();
  }

  static String slugify(String value) {
    const replacements = {
      'á': 'a',
      'à': 'a',
      'ä': 'a',
      'â': 'a',
      'ã': 'a',
      'å': 'a',
      'é': 'e',
      'è': 'e',
      'ë': 'e',
      'ê': 'e',
      'í': 'i',
      'ì': 'i',
      'ï': 'i',
      'î': 'i',
      'ó': 'o',
      'ò': 'o',
      'ö': 'o',
      'ô': 'o',
      'õ': 'o',
      'ú': 'u',
      'ù': 'u',
      'ü': 'u',
      'û': 'u',
      'ý': 'y',
      'ÿ': 'y',
      'ñ': 'n',
      'ç': 'c',
      'ß': 'ss',
    };
    var text = value.toLowerCase();
    replacements.forEach((from, to) {
      text = text.replaceAll(from, to);
    });
    return text
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }
}

