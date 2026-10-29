import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:raritio/services/card_text_parser.dart';

TextLine line(
  String text,
  double left,
  double top,
  double width,
  double height,
) {
  return TextLine(
    text: text,
    elements: const [],
    boundingBox: Rect.fromLTWH(left, top, width, height),
    recognizedLanguages: const [],
    cornerPoints: const [],
    confidence: 1.0,
    angle: 0.0,
  );
}

void main() {
  final parser = CardTextParser();

  test('extracts name and collector number from a Pokemon card', () {
    final lines = [
      line('BASIC', 20, 20, 70, 14),
      line("Misty's Gyarados", 90, 60, 420, 44),
      line('HP 120', 760, 65, 100, 20),
      line('Water Gun', 90, 320, 220, 24),
      line('This attack does 30 damage.', 90, 360, 500, 18),
      line('WEAKNESS', 90, 980, 110, 16),
      line('049/182', 70, 1080, 130, 18),
      line('Illus. GOSSAN', 450, 1100, 220, 14),
    ];

    expect(parser.parseLines(lines, imageWidth: 720, imageHeight: 1280), "Misty's Gyarados 049/182");
  });

  test('normalizes typographic apostrophes', () {
    final lines = [
      line('Misty’s Gyarados', 90, 60, 420, 44),
      line('049/182', 70, 1080, 130, 18),
    ];

    expect(parser.parseLines(lines, imageWidth: 720, imageHeight: 1280), "Misty's Gyarados 049/182");
  });

  test('does not mistake HP for the card name', () {
    final lines = [
      line('HP 330', 760, 65, 100, 20),
      line('Charizard ex', 90, 60, 420, 44),
      line('199/165', 70, 1080, 130, 18),
    ];

    expect(parser.parseLines(lines, imageWidth: 720, imageHeight: 1280), 'Charizard ex 199/165');
  });

  test('works with trainer cards and letters in the number', () {
    final lines = [
      line('TRAINER', 20, 20, 90, 14),
      line("Professor's Research", 90, 60, 420, 44),
      line('TG01/TG30', 70, 1080, 140, 18),
    ];

    expect(parser.parseLines(lines, imageWidth: 720, imageHeight: 1280), "Professor's Research TG01/TG30");
  });

  test('returns name only when no number is visible', () {
    final lines = [
      line('BASIC', 20, 20, 70, 14),
      line('Gyarados', 90, 60, 420, 44),
      line('HP 120', 760, 65, 100, 20),
    ];

    expect(parser.parseLines(lines, imageWidth: 720, imageHeight: 1280), 'Gyarados');
  });

  test('extracts promo card numbers without a total', () {
    final lines = [
      line('BASIC', 20, 20, 70, 14),
      line('Pikachu', 90, 60, 420, 44),
      line('SWSH001', 70, 1080, 140, 18),
    ];

    expect(
      parser.parseLines(lines, imageWidth: 720, imageHeight: 1280),
      'Pikachu SWSH001',
    );
  });

  test('handles a vertical bar instead of a slash', () {
    final lines = [
      line("Misty's Gyarados", 90, 60, 420, 44),
      line('049|182', 70, 1080, 130, 18),
    ];

    expect(
      parser.parseLines(lines, imageWidth: 720, imageHeight: 1280),
      "Misty's Gyarados 049/182",
    );
  });

  test('ignores background text at the edges', () {
    final lines = [
      line('SALE 50%', 0, 10, 60, 60),
      line('Misty’s Gyarados', 90, 60, 420, 44),
      line('049/182', 70, 1080, 130, 18),
    ];

    expect(parser.parseLines(lines, imageWidth: 720, imageHeight: 1280), "Misty's Gyarados 049/182");
  });

  test('extracts a Japanese card name and promo number', () {
    final lines = [
      line('たねポケモン', 20, 20, 150, 16),
      line('リザードン', 90, 60, 360, 44),
      line('001/S-P', 70, 1080, 140, 18),
    ];

    expect(
      parser.parseLines(lines, imageWidth: 720, imageHeight: 1280),
      'リザードン 001/S-P',
    );
  });

  test('extracts a Chinese card name and collector number', () {
    final lines = [
      line('基础', 20, 20, 90, 16),
      line('喷火龙', 90, 60, 300, 44),
      line('002/165', 70, 1080, 130, 18),
    ];

    expect(
      parser.parseLines(lines, imageWidth: 720, imageHeight: 1280),
      '喷火龙 002/165',
    );
  });

  test('keeps a two-character Chinese card name', () {
    final lines = [
      line('超夢', 90, 60, 220, 44),
      line('002/165', 70, 1080, 130, 18),
    ];

    expect(
      parser.parseLines(lines, imageWidth: 720, imageHeight: 1280),
      '超夢 002/165',
    );
  });
}

