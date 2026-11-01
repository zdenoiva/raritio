import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

class GradingPhotoCheck {
  const GradingPhotoCheck({
    required this.ok,
    required this.issues,
    required this.width,
    required this.height,
    required this.brightness,
    required this.sharpness,
    required this.glareRatio,
  });

  final bool ok;
  final List<String> issues;
  final int width;
  final int height;
  final double brightness;
  final double sharpness;
  final double glareRatio;
}

/// Cheap local checks before spending an API credit. They cannot detect every
/// bad photo, but catch the common ones: too small, dark, blurred or glared.
class GradingPhotoCheckService {
  Future<GradingPhotoCheck> check(String path) async {
    final bytes = await File(path).readAsBytes();
    final raw = img.decodeImage(bytes);
    final decoded = raw == null ? null : img.bakeOrientation(raw);
    if (decoded == null) {
      return const GradingPhotoCheck(
        ok: false,
        issues: ['Fotku sa nepodarilo prečítať. Odfot ju znova.'],
        width: 0,
        height: 0,
        brightness: 0,
        sharpness: 0,
        glareRatio: 0,
      );
    }

    final width = decoded.width;
    final height = decoded.height;
    final issues = <String>[];

    if (math.min(width, height) < 900) {
      issues.add('Fotka je primalá. Priblíž sa ku karte a odfoť ju znova.');
    }

    final sample = img.copyResize(
      decoded,
      width: math.min(360, width),
      interpolation: img.Interpolation.average,
    );

    var brightnessSum = 0.0;
    var glarePixels = 0;
    var pixels = 0;
    for (var y = 0; y < sample.height; y++) {
      for (var x = 0; x < sample.width; x++) {
        final pixel = sample.getPixel(x, y);
        final luminance = _luminance(pixel);
        brightnessSum += luminance;
        if (luminance >= 247) glarePixels++;
        pixels++;
      }
    }

    final brightness = pixels == 0 ? 0.0 : brightnessSum / pixels;
    final glareRatio = pixels == 0 ? 0.0 : glarePixels / pixels;

    var sharpnessSum = 0.0;
    var sharpnessPixels = 0;
    for (var y = 1; y < sample.height - 1; y++) {
      for (var x = 1; x < sample.width - 1; x++) {
        final center = _luminance(sample.getPixel(x, y));
        final left = _luminance(sample.getPixel(x - 1, y));
        final right = _luminance(sample.getPixel(x + 1, y));
        final up = _luminance(sample.getPixel(x, y - 1));
        final down = _luminance(sample.getPixel(x, y + 1));
        sharpnessSum += (4 * center - left - right - up - down).abs();
        sharpnessPixels++;
      }
    }

    final sharpness = sharpnessPixels == 0
        ? 0.0
        : sharpnessSum / sharpnessPixels;

    if (brightness < 42) {
      issues.add('Fotka je príliš tmavá. Pridaj svetlo alebo použi blesk.');
    } else if (brightness > 232) {
      issues.add('Fotka je príliš presvetlená. Zníž svetlo alebo vypni blesk.');
    }

    if (glareRatio > 0.085) {
      issues.add('Na karte je veľa odleskov. Zmeň uhol alebo svetlo.');
    }

    // A low Laplacian variance means there is very little detail. The limit is
    // deliberately forgiving so textured holo cards are not rejected.
    if (sharpness < 3.2) {
      issues.add('Fotka môže byť rozmazaná. Podrž telefón pevne a zaostri.');
    }

    return GradingPhotoCheck(
      ok: issues.isEmpty,
      issues: issues,
      width: width,
      height: height,
      brightness: brightness,
      sharpness: sharpness,
      glareRatio: glareRatio,
    );
  }

  double _luminance(img.Pixel pixel) {
    return 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
  }
}
