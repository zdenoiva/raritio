import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:raritio/services/custom_card_image_service.dart';
import 'package:image/image.dart' as img;

void main() {
  test('crops a camera photo to a card-shaped JPEG data URI', () async {
    final source = img.Image(width: 1000, height: 1400);
    img.fill(source, color: img.ColorRgb8(120, 80, 200));

    final file = File(
      '${Directory.systemTemp.path}/raritio_custom_card_image_test.jpg',
    );
    await file.writeAsBytes(img.encodeJpg(source));

    final service = CustomCardImageService();
    final dataUri = await service.prepareFromFile(file.path);
    await file.delete();

    expect(dataUri, isNotNull);
    expect(dataUri, startsWith('data:image/jpeg;base64,'));

    final bytes = base64Decode(dataUri!.split(',').last);
    final decoded = img.decodeJpg(bytes);
    expect(decoded, isNotNull);
    expect(decoded!.width, 720);
    expect(decoded.height, closeTo(1008, 2));
  });
}

