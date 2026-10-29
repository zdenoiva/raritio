import 'dart:math' as math;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class _LineCandidate {
  final String text;
  final double height;
  final double top;

  _LineCandidate(this.text, this.height, this.top);
}

/// Extracts a usable search query (card name + collector number) from the
/// noisy text ML Kit returns for a photo of a trading card.
class CardTextParser {
  /// Unicode ranges for Japanese kana and CJK ideographs. Keeping these
  /// characters lets Japanese and Chinese card names reach the search API.
  static const String _cjkRange =
      r'\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff';

  static final RegExp _leadingJunk =
      RegExp(r'^[^A-Za-zÀ-ž' + _cjkRange + r']+');
  static final RegExp _trailingJunk =
      RegExp(r"[^A-Za-zÀ-ž0-9\.\-\'\s" + _cjkRange + r']+$');
  static final RegExp _hasCjk = RegExp('[$_cjkRange]');
  static final RegExp _cjkLabel = RegExp(
    r'^(たねポケモン|1進化ポケモン|2進化ポケモン|グッズ|サポート|スタジアム|エネルギー|ポケモン|'
    r'基础|基礎|1阶进化|1階進化|2阶进化|2階進化|物品|支援者|竞技场|競技場|能量|宝可梦|寶可夢)$',
  );

  /// Returns e.g. "Misty's Gyarados 049/182", "Gyarados", or "049/182".
  ///
  /// [imageWidth] and [imageHeight] are the real photo dimensions. They are
  /// used to locate the top/bottom of the card; if they are not available the
  /// largest text bounds are used as a fallback.
  String? parseLines(
    List<TextLine> lines, {
    double imageWidth = 0,
    double imageHeight = 0,
  }) {
    if (lines.isEmpty) return null;

    double maxX = 0;
    double maxY = 0;
    for (final line in lines) {
      final box = line.boundingBox;
      maxX = math.max(maxX, box.right);
      maxY = math.max(maxY, box.bottom);
    }

    final width = imageWidth > 0 ? imageWidth : maxX;
    final height = imageHeight > 0 ? imageHeight : maxY;
    if (width <= 0 || height <= 0) return null;

    final number = _findCardNumber(lines, height);
    final name = _findCardName(lines, width, height);

    if (name != null && number != null) return '$name $number';
    if (name != null) return name;
    if (number != null) return number;
    return null;
  }

  /// Fallback for when no lines are available: first line that does not look
  /// like card furniture (HP, stage label, copyright...).
  String? parsePlainText(String text) {
    final lines = text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty);

    for (final line in lines) {
      if (!_isJunk(line)) return line;
    }
    final trimmed = text.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Card number is printed at the bottom, e.g. "049/182" or "TG01/TG30".
  String? _findCardNumber(List<TextLine> lines, double maxY) {
    // ML Kit sometimes reads the slash as a vertical bar. The part after the
    // slash may be a total ("182") or a promo suffix ("S-P", "SV-P").
    final regex = RegExp(
      r'([A-Z]{0,3}\d{1,3})\s*[/|\\]\s*([A-Z0-9-]{1,8})',
      caseSensitive: false,
    );

    String? best;
    double bestScore = -1;
    for (final line in lines) {
      final match = regex.firstMatch(line.text);
      if (match == null) continue;
      // Prefer the match closest to the bottom of the image.
      final score = line.boundingBox.top / maxY;
      if (score > bestScore) {
        bestScore = score;
        best = '${match.group(1)}/${match.group(2)}';
      }
    }
    if (best != null) return best;

    // Promo cards often print only "SWSH001" or "SM01", without a total.
    final promoRegex = RegExp(r'\b([A-Z]{2,4}\d{2,4})\b', caseSensitive: false);
    for (final line in lines) {
      if (line.boundingBox.top / maxY < 0.75) continue;
      final match = promoRegex.firstMatch(line.text);
      if (match != null) return match.group(1);
    }

    return null;
  }

  /// Card name is the largest text in the upper part of the card.
  String? _findCardName(List<TextLine> lines, double maxX, double maxY) {
    final candidates = <_LineCandidate>[];

    for (final line in lines) {
      final text = line.text.trim();
      if (text.isEmpty) continue;

      final box = line.boundingBox;

      // Name lives in the top part of the card.
      if (box.top > maxY * 0.40) continue;

      // Ignore text at the very edges (background/table).
      final centerX = box.center.dx;
      if (centerX < maxX * 0.10 || centerX > maxX * 0.90) continue;

      if (_isJunk(text)) continue;

      final cleaned = _cleanName(text);
      if (cleaned.isEmpty) continue;

      candidates.add(_LineCandidate(cleaned, box.height, box.top));
    }

    if (candidates.isEmpty) return null;

    candidates.sort((a, b) {
      final byHeight = b.height.compareTo(a.height);
      if (byHeight != 0) return byHeight;
      return a.top.compareTo(b.top);
    });

    return candidates.first.text;
  }

  bool _isJunk(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return true;
    final upper = text.toUpperCase();

    // Card type / stage labels.
    if (RegExp(
      r'^(BASIC|STAGE\s*\d|STAGE|EVOLUTION|TRAINER|SUPPORTER|ITEM|STADIUM|TOOL|ENERGY|POKÉMON|POKEMON)$',
    ).hasMatch(upper)) {
      return true;
    }

    // Japanese and Chinese card type / stage labels.
    if (_cjkLabel.hasMatch(text)) return true;

    // HP values: "HP 120", "120 HP", "120".
    if (RegExp(r'^(HP\s*)?\d{1,3}(\s*HP)?$').hasMatch(upper)) return true;
    if (RegExp(r'^\s*HP\s*\d+', caseSensitive: false).hasMatch(text)) {
      return true;
    }

    // Very short tokens / symbols. Two-character CJK names (e.g. 超夢) are
    // valid card names, so only reject them when they are a single character.
    final hasCjk = _hasCjk.hasMatch(text);
    if (text.length <= 2 && !hasCjk) return true;
    if (text.length <= 1 && hasCjk) return true;

    // Copyright / artist lines.
    if (upper.contains('ILLUS') ||
        upper.contains('NINTENDO') ||
        upper.contains('CREATURES') ||
        upper.contains('GAME FREAK') ||
        upper.contains('©')) {
      return true;
    }

    // Attack / stat labels.
    if (upper.contains('WEAKNESS') ||
        upper.contains('RESISTANCE') ||
        upper.contains('RETREAT')) {
      return true;
    }

    // Numbers only.
    if (RegExp(r'^[\d\s/]+$').hasMatch(text)) return true;

    // Lines that are mostly digits (damage counters, HP, etc.).
    final digits = text.replaceAll(RegExp(r'[^0-9]'), '').length;
    if (digits > text.length * 0.6) return true;

    return false;
  }

  String _cleanName(String raw) {
    var name = raw;

    // Normalize typographic quotes that OCR often produces.
    name = name
        .replaceAll('’', "'")
        .replaceAll('‘', "'")
        .replaceAll('`', "'")
        .replaceAll('´', "'")
        .replaceAll('“', '"')
        .replaceAll('”', '"');

    // Remove trailing HP / damage numbers.
    name = name.replaceAll(
      RegExp(r'\s*(HP\s*\d+|\d+\s*HP)\s*$', caseSensitive: false),
      '',
    );

    // Remove leading stage labels.
    name = name.replaceAll(
      RegExp(r'^\s*(BASIC|STAGE\s*\d|STAGE)\s+', caseSensitive: false),
      '',
    );

    // Remove leading/trailing symbols, keep letters, digits, apostrophes, dots,
    // dashes and CJK characters.
    name = name.replaceAll(_leadingJunk, '');
    name = name.replaceAll(_trailingJunk, '');

    // Collapse whitespace.
    name = name.replaceAll(RegExp(r'\s+'), ' ').trim();

    return name;
  }
}
