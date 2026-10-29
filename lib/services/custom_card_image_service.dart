import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;

/// Turns a camera photo into a small, card-shaped JPEG that can be stored in
/// the web state as a data URI. The camera preview already shows a 2.5:3.5
/// guide, so a centered crop is enough here; the user can retake it if needed.
class CustomCardImageService {
  static const double _cardAspect = 2.5 / 3.5;
  static const int _outputWidth = 720;
  static const int _jpegQuality = 84;

  Future<String?> prepareFromFile(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null || decoded.width < 2 || decoded.height < 2) {
        return null;
      }

      final oriented = img.bakeOrientation(decoded);
      var cropWidth = (oriented.width * 0.72).round();
      var cropHeight = (cropWidth / _cardAspect).round();
      final maxHeight = (oriented.height * 0.94).round();

      if (cropHeight > maxHeight) {
        cropHeight = maxHeight;
        cropWidth = (cropHeight * _cardAspect).round();
      }

      cropWidth = cropWidth.clamp(1, oriented.width);
      cropHeight = cropHeight.clamp(1, oriented.height);

      final x = ((oriented.width - cropWidth) / 2).round();
      final desiredY = ((oriented.height - cropHeight) / 2).round() +
          (oriented.height * 0.015).round();
      final y = desiredY.clamp(0, oriented.height - cropHeight).toInt();

      final cropped = img.copyCrop(
        oriented,
        x: x,
        y: y,
        width: cropWidth,
        height: cropHeight,
      );
      final resized = img.copyResize(
        cropped,
        width: _outputWidth,
        interpolation: img.Interpolation.average,
      );
      final jpeg = img.encodeJpg(resized, quality: _jpegQuality);
      return 'data:image/jpeg;base64,${base64Encode(jpeg)}';
    } catch (_) {
      return null;
    }
  }
}
