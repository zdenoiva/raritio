import 'dart:io';

import 'package:raritio/services/ocr_service.dart';
import 'package:raritio/services/scan_image_service.dart';

class BridgeService {
  final OCRService _ocrService = OCRService();
  final ScanImageService _scanImageService = ScanImageService();

  /// Processes an image and returns `{text, language}` for the web UI, or
  /// `{error}` when OCR could not run at all.
  Future<Map<String, dynamic>?> scanImagePath(
    String path, {
    bool cropToFrame = true,
    double widthFraction = 0.88,
  }) async {
    File? cropped;
    try {
      if (cropToFrame) {
        cropped = await _scanImageService.prepareForOcr(
          path,
          widthFraction: widthFraction,
        );
      }
      final result = await _ocrService.scanImage(cropped ?? File(path));
      if (result == null) return null;
      return <String, dynamic>{
        'text': result.text,
        'rawText': result.rawText,
        'language': result.language,
      };
    } catch (e) {
      print("Error during OCR: $e");
      return <String, dynamic>{'error': e.toString()};
    } finally {
      if (cropped != null) {
        try {
          if (await cropped.exists()) await cropped.delete();
        } catch (_) {}
      }
    }
  }
}
