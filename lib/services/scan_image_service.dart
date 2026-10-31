import 'dart:io';

import 'package:image/image.dart' as img;

/// Crops a camera photo to the area covered by the scan frame before OCR.
/// This removes most of the table/background and gives ML Kit a larger,
/// cleaner card view.
class ScanImageService {
  static const double _cardAspect = 2.5 / 3.5;

  Future<File?> prepareForOcr(
    String path, {
    double widthFraction = 0.88,
  }) async {
    try {
      final bytes = await File(path).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;
      final oriented = img.bakeOrientation(decoded);

      var cropWidth = (oriented.width * widthFraction.clamp(0.35, 1.0)).round();
      var cropHeight = (cropWidth / _cardAspect).round();
      final maxHeight = (oriented.height * 0.99).round();
      if (cropHeight > maxHeight) {
        cropHeight = maxHeight;
        cropWidth = (cropHeight * _cardAspect).round();
      }
      cropWidth = cropWidth.clamp(1, oriented.width);
      cropHeight = cropHeight.clamp(1, oriented.height);

      final x = ((oriented.width - cropWidth) / 2).round();
      final y = ((oriented.height - cropHeight) / 2)
          .clamp(0, oriented.height - cropHeight)
          .toInt();

      var cropped = img.copyCrop(
        oriented,
        x: x,
        y: y,
        width: cropWidth,
        height: cropHeight,
      );
      if (cropped.width > 1600) {
        cropped = img.copyResize(
          cropped,
          width: 1600,
          interpolation: img.Interpolation.average,
        );
      }
      final jpeg = img.encodeJpg(cropped, quality: 92);
      final file = File('$path.crop.jpg');
      await file.writeAsBytes(jpeg, flush: true);
      return file;
    } catch (_) {
      return null;
    }
  }
}
