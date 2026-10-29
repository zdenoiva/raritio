import 'dart:io';

import 'package:raritio/services/ocr_service.dart';

class BridgeService {
  final OCRService _ocrService = OCRService();

  /// Processes an image and returns `{text, language}` for the web UI, or
  /// `{error}` when OCR could not run at all.
  Future<Map<String, dynamic>?> scanImagePath(String path) async {
    try {
      final result = await _ocrService.scanImage(File(path));
      if (result == null) return null;
      return <String, dynamic>{
        'text': result.text,
        'language': result.language,
      };
    } catch (e) {
      print("Error during OCR: $e");
      return <String, dynamic>{'error': e.toString()};
    }
  }
}

