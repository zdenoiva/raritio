import 'dart:io';
import 'dart:ui' as ui;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'card_text_parser.dart';

/// Text plus the language whose OCR model produced it. The language is used
/// for the TCGdex search and for the flag shown on the card.
class OcrScanResult {
  final String text;
  final String rawText;
  final String language;

  const OcrScanResult({
    required this.text,
    required this.rawText,
    required this.language,
  });
}

class _OcrCandidate {
  final String text;
  final String rawText;
  final String language;
  final int score;

  const _OcrCandidate(this.text, this.rawText, this.language, this.score);
}

class OCRService {
  final CardTextParser _parser = CardTextParser();
  final Map<TextRecognitionScript, TextRecognizer> _recognizers = {};

  OCRService() {
    // Keep the Latin model warm for the common case. Japanese and Chinese
    // models are created lazily on the first scan that needs them.
    _recognizers[TextRecognitionScript.latin] = TextRecognizer(
      script: TextRecognitionScript.latin,
    );
  }

  TextRecognizer _recognizer(TextRecognitionScript script) {
    return _recognizers.putIfAbsent(
      script,
      () => TextRecognizer(script: script),
    );
  }

  Future<OcrScanResult?> scanImage(File imageFile) async {
    final size = await _readImageSize(imageFile);

    // Run all scripts on the same photo. A Japanese card can contain Latin
    // HP/attack text, and an English card may contain no CJK at all, so the
    // best parsed candidate is chosen by script-aware scoring.
    final candidates = await Future.wait([
      _recognize(imageFile, TextRecognitionScript.latin, 'en', size),
      _recognize(imageFile, TextRecognitionScript.japanese, 'ja', size),
      _recognize(imageFile, TextRecognitionScript.chinese, 'zh-cn', size),
    ]);

    final valid = candidates.whereType<_OcrCandidate>().toList();
    if (valid.isEmpty) return null;

    var best = valid.first;
    for (final candidate in valid.skip(1)) {
      if (candidate.score > best.score) best = candidate;
    }

    return OcrScanResult(
      text: best.text,
      rawText: best.rawText,
      language: best.language,
    );
  }

  Future<_OcrCandidate?> _recognize(
    File imageFile,
    TextRecognitionScript script,
    String language,
    ({double width, double height}) size,
  ) async {
    try {
      final inputImage = InputImage.fromFile(imageFile);
      final recognizedText = await _recognizer(script)
          .processImage(inputImage)
          .timeout(const Duration(seconds: 15));

      if (recognizedText.text.trim().isEmpty) return null;

      final parsed = _parse(recognizedText, size);
      if (parsed == null || parsed.trim().isEmpty) return null;

      return _OcrCandidate(
        parsed,
        recognizedText.text,
        language,
        _score(parsed, language, recognizedText.text),
      );
    } catch (e) {
      print('OCR $script error: $e');
      return null;
    }
  }

  String? _parse(
    RecognizedText recognizedText,
    ({double width, double height}) size,
  ) {
    final lines = <TextLine>[];
    for (final block in recognizedText.blocks) {
      lines.addAll(block.lines);
    }

    final parsed = _parser.parseLines(
      lines,
      imageWidth: size.width,
      imageHeight: size.height,
    );
    if (parsed != null && parsed.trim().isNotEmpty) return parsed;

    return _parser.parsePlainText(recognizedText.text);
  }

  /// Scores a parsed query for the script that produced it. A Latin name on
  /// an English card should beat the Japanese model's Latin noise, while a
  /// kana name on a Japanese card should beat the Latin model's HP/number.
  int _score(String parsed, String language, String fullText) {
    final text = parsed.trim();
    if (text.isEmpty) return -100;

    final hasLatin = RegExp(r'[A-Za-z]').hasMatch(text);
    final hasKana = RegExp(r'[\u3040-\u30ff]').hasMatch(text);
    final hasHan = RegExp(r'[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]')
        .hasMatch(text);
    final hasDigit = RegExp(r'\d').hasMatch(text);
    final hasSlash = RegExp(r'[/|\\]').hasMatch(text);
    final numberOnly = RegExp(
      r'^[A-Za-z]{0,4}\d{1,4}(?:\s*[/|\\]\s*[A-Z0-9-]{1,8})?$',
    ).hasMatch(text);

    var score = 0;
    if (text.length >= 3) score += 1;
    if (hasDigit) score += 2;
    if (hasSlash) score += 1;
    // A bare collector number is a weak result; a card name is far more useful
    // for the search, even when the model that found it is not the "right" one.
    if (numberOnly) score -= 6;

    switch (language) {
      case 'ja':
        if (hasKana) score += 6;
        if (hasHan) score += 2;
        if (hasLatin) score += 1;
        if (!hasKana && !hasHan) score -= 4;
        break;
      case 'zh-cn':
        if (hasHan) score += 6;
        if (hasKana) score -= 5;
        if (hasLatin) score += 1;
        if (!hasHan) score -= 4;
        break;
      default:
        if (hasLatin) score += 6;
        if (hasKana || hasHan) score -= 5;
        break;
    }

    // Prefer a parsed name over a bare collector number.
    if (RegExp(r'[A-Za-z\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff]')
        .hasMatch(text)) {
      score += 1;
    }

    // The full OCR text can reveal the script even when the parser picked a
    // short line. This helps a Japanese card whose name was split in two.
    if (language == 'ja' && RegExp(r'[\u3040-\u30ff]').hasMatch(fullText)) {
      score += 1;
    }
    if (language == 'zh-cn' &&
        RegExp(r'[\u3400-\u4dbf\u4e00-\u9fff]').hasMatch(fullText) &&
        !RegExp(r'[\u3040-\u30ff]').hasMatch(fullText)) {
      score += 1;
    }

    return score;
  }

  Future<({double width, double height})> _readImageSize(File imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final width = frame.image.width.toDouble();
      final height = frame.image.height.toDouble();
      frame.image.dispose();
      codec.dispose();
      return (width: width, height: height);
    } catch (_) {
      // If decoding fails, the parser falls back to text bounds.
      return (width: 0.0, height: 0.0);
    }
  }

  void dispose() {
    for (final recognizer in _recognizers.values) {
      recognizer.close();
    }
    _recognizers.clear();
  }
}
