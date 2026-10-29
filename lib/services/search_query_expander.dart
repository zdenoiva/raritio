/// Turns noisy OCR (or a hurried manual search) into a short list of
/// increasingly tolerant card-name queries.
///
/// The first query is the normalized input. Later queries repair apostrophes,
/// drop punctuation, and finally fall back to the most distinctive words, so a
/// scan such as "Mistys Gyarados" still finds "Misty's Gyarados".
class SearchQueryExpander {
  /// Japanese kana and CJK ideographs must survive normalization so scanned
  /// Japanese/Chinese names can be sent to TCGdex unchanged.
  static const String _cjkRange =
      r'\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff';

  static final RegExp _leadingJunk =
      RegExp(r'^[^A-Za-zÀ-ž0-9' + _cjkRange + r']+');
  static final RegExp _trailingJunk =
      RegExp(r'[^A-Za-zÀ-ž0-9' + _cjkRange + r']+$');
  static final RegExp _nameJunk =
      RegExp(r"[^A-Za-zÀ-ž0-9\s'\-" + _cjkRange + r']');
  static final RegExp _wordJunk =
      RegExp(r'[^\wÀ-ž\-' + _cjkRange + r']');

  static const List<String> _apostropheChars = [
    "'",
    '’',
    '‘',
    '`',
    '´',
    'ʼ',
  ];

  /// Character names that commonly appear as possessives in card names.
  /// Only these are repaired, so a Pokémon such as "Gyarados ex" is never
  /// rewritten to "Gyarado's ex".
  static const Set<String> _possessiveStems = {
    'misty', 'brock', 'erika', 'sabrina', 'blaine', 'giovanni', 'koga',
    'janine', 'falkner', 'bugsy', 'whitney', 'morty', 'chuck', 'jasmine',
    'pryce', 'clair', 'will', 'karen', 'bruno', 'lance', 'lorelei', 'agatha',
    'blue', 'red', 'ethan', 'kris', 'silver', 'may', 'brendan', 'wally',
    'steven', 'wallace', 'cynthia', 'aaron', 'bertha', 'flint', 'lucian',
    'alder', 'iris', 'caitlin', 'marshal', 'grimsley', 'shauntal', 'bianca',
    'cheren', 'colress', 'ghetsis', 'lysandre', 'diantha', 'malva', 'siebold',
    'wikstrom', 'drasna', 'professor', 'boss', 'rocket', 'aqua', 'magma',
    'galactic', 'plasma', 'flare', 'skull', 'yell', 'star', 'aether',
    'marnie', 'raihan', 'sonia', 'bede', 'hop', 'piers', 'leon', 'nessa',
    'milo', 'kabu', 'bea', 'allister', 'opal', 'gordie', 'melony', 'sada',
    'turo', 'arven', 'nemona', 'penny', 'geeta', 'clavell', 'iono', 'larry',
    'ryme', 'tulip', 'grusha', 'katy', 'brassius', 'kofu', 'hassel',
    'crispin', 'amarys', 'lacey', 'drayton', 'oak', 'elm', 'birch', 'rowan',
    'juniper', 'sycamore', 'kukui', 'magnolia', 'willow', 'cedric', 'surge',
  };

  static List<String> expand(String rawQuery, {int maxVariants = 10}) {
    final normalized = _normalize(rawQuery);
    if (normalized.isEmpty) return const <String>[];

    final number = _extractNumber(normalized);
    final name = _extractName(normalized);
    if (name.isEmpty) {
      return _dedupe(<String>[
        normalized,
        ?number,
      ]).take(maxVariants).toList();
    }

    final apostropheName = _normalizeApostrophes(name);
    final fixedName = _fixPossessives(apostropheName);
    final noApostrophes = _removeApostrophes(apostropheName);
    final apostropheToSpace = _collapse(apostropheName.replaceAll("'", ' '));
    final withoutPossessive = _removePossessives(apostropheName);
    final words = _words(apostropheName);
    final longestWord = words.isEmpty
        ? null
        : words.reduce((best, word) => word.length > best.length ? word : best);
    final firstTwo = words.length >= 2 ? words.take(2).join(' ') : null;
    final lastTwo =
        words.length >= 2 ? words.skip(words.length - 2).join(' ') : null;

    final names = <String>[
      apostropheName,
      fixedName,
      noApostrophes,
      apostropheToSpace,
      withoutPossessive,
      ?firstTwo,
      ?lastTwo,
      ?longestWord,
      ...words.where((word) => word.length >= 4).take(2),
    ];

    final variants = <String>[normalized];
    for (final candidate in names) {
      final clean = _collapse(candidate);
      if (clean.isEmpty) continue;
      if (number != null) variants.add('$clean $number');
      variants.add(clean);
    }
    if (number != null) variants.add(number);

    return _dedupe(variants).take(maxVariants).toList();
  }

  static String _normalize(String value) {
    var text = value
        .replaceAll('’', "'")
        .replaceAll('‘', "'")
        .replaceAll('`', "'")
        .replaceAll('´', "'")
        .replaceAll('ʼ', "'")
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // Remove leading/trailing punctuation that OCR often adds.
    text = text.replaceAll(_leadingJunk, '');
    text = text.replaceAll(_trailingJunk, '');
    return text;
  }

  static String? _extractNumber(String query) {
    final trailing = RegExp(
      r'^(.+?)\s+#?([A-Za-z]{0,4}\d{1,4})(?:\s*/\s*[A-Za-z0-9-]+)?$',
    ).firstMatch(query);
    if (trailing != null) return trailing.group(2);

    final leading = RegExp(
      r'^#?([A-Za-z]{0,4}\d{1,4})(?:\s*/\s*[A-Za-z0-9-]+)?\s+(.+)$',
    ).firstMatch(query);
    if (leading != null) return leading.group(1);

    final only = RegExp(
      r'^#?([A-Za-z]{0,4}\d{1,4})(?:\s*/\s*[A-Za-z0-9-]+)?$',
    ).firstMatch(query);
    if (only != null) return only.group(1);

    return null;
  }

  static String _extractName(String query) {
    var name = query;

    final trailing = RegExp(
      r'^(.+?)\s+#?[A-Za-z]{0,4}\d{1,4}(?:\s*/\s*[A-Za-z0-9-]+)?$',
    ).firstMatch(name);
    if (trailing != null) {
      name = trailing.group(1)!;
    } else {
      final leading = RegExp(
        r'^#?[A-Za-z]{0,4}\d{1,4}(?:\s*/\s*[A-Za-z0-9-]+)?\s+(.+)$',
      ).firstMatch(name);
      if (leading != null) name = leading.group(1)!;
    }

    name = name
        .replaceAll(_nameJunk, ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return name;
  }

  static String _normalizeApostrophes(String value) {
    var text = value;
    for (final char in _apostropheChars) {
      text = text.replaceAll(char, "'");
    }
    return _collapse(text);
  }

  static String _removeApostrophes(String value) {
    return _collapse(value.replaceAll("'", ''));
  }

  static String _removePossessives(String value) {
    return _collapse(
      value.replaceAll(RegExp(r"'s\b", caseSensitive: false), ''),
    );
  }

  /// Repairs the common OCR shapes "Mistys Gyarados" and "Misty s Gyarados".
  /// Only known character names are touched, which keeps real card names such
  /// as "Gyarados ex" and "Lapras GX" intact.
  static String _fixPossessives(String value) {
    var text = value;

    // "Misty s Gyarados" -> "Misty's Gyarados"
    text = text.replaceAllMapped(
      RegExp(r'\b([A-Za-zÀ-ž]{2,})\s+s\b', caseSensitive: false),
      (match) {
        final stem = match.group(1)!;
        if (!_possessiveStems.contains(stem.toLowerCase())) {
          return match.group(0)!;
        }
        return "$stem's";
      },
    );

    // "Mistys Gyarados" -> "Misty's Gyarados"
    text = text.replaceAllMapped(
      RegExp(
        r'\b([A-Za-zÀ-ž]{2,})s\b(?=\s+[A-Za-zÀ-ž])',
        caseSensitive: false,
      ),
      (match) {
        // The regex captures the stem (everything before the final "s").
        final stem = match.group(1)!;
        if (!_possessiveStems.contains(stem.toLowerCase())) {
          return match.group(0)!;
        }
        return "$stem's";
      },
    );

    // "Ns Zoroark" -> "N's Zoroark"
    text = text.replaceAllMapped(
      RegExp(r'\bNs\b(?=\s+[A-Za-zÀ-ž])', caseSensitive: false),
      (match) => "N's",
    );

    return _collapse(text);
  }

  static List<String> _words(String value) {
    return value
        .split(RegExp(r'\s+'))
        .map((word) => word.replaceAll(_wordJunk, ''))
        .where((word) => word.length >= 3)
        .toList();
  }

  static String _collapse(String value) {
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static List<String> _dedupe(List<String> values) {
    final seen = <String>{};
    final result = <String>[];
    for (final value in values) {
      final clean = _collapse(value);
      if (clean.isEmpty) continue;
      final key = clean.toLowerCase();
      if (seen.add(key)) result.add(clean);
    }
    return result;
  }
}
