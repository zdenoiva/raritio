import 'package:flutter/material.dart';

/// Native colours for the Raritio themes.
///
/// The WebView owns the source of truth for the selected theme. Native screens
/// receive its id and use this palette so Zdieľané and the scanner feel like
/// part of the same app.
class AppThemePalette {
  const AppThemePalette({
    required this.id,
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.accent,
    required this.accentAlt,
    required this.text,
    required this.muted,
    required this.onAccent,
    required this.success,
  });

  final String id;
  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color border;
  final Color accent;
  final Color accentAlt;
  final Color text;
  final Color muted;
  final Color onAccent;
  final Color success;

  bool get isClassic => id == 'classic';

  List<Color> get accentGradient => [accent, accentAlt];

  static AppThemePalette forName(String? name) {
    return switch (name) {
      'poke' => const AppThemePalette(
        id: 'poke',
        background: Color(0xFF0B1220),
        surface: Color(0xFF131C2E),
        surfaceAlt: Color(0xFF1B2740),
        border: Color(0xFF2A3A57),
        accent: Color(0xFFFFCB05),
        accentAlt: Color(0xFFE3350D),
        text: Color(0xFFFFF8E7),
        muted: Color(0xFFA9B4C8),
        onAccent: Color(0xFF3A2200),
        success: Color(0xFFFFCB05),
      ),
      'magic' => const AppThemePalette(
        id: 'magic',
        background: Color(0xFF061724),
        surface: Color(0xFF081F2C),
        surfaceAlt: Color(0xFF0D2A38),
        border: Color(0xFF2A4A58),
        accent: Color(0xFFE8C967),
        accentAlt: Color(0xFF2DD4BF),
        text: Color(0xFFF2E8C8),
        muted: Color(0xFF9FC4C7),
        onAccent: Color(0xFF061724),
        success: Color(0xFFE8C967),
      ),
      'stone' => const AppThemePalette(
        id: 'stone',
        background: Color(0xFF16120F),
        surface: Color(0xFF211912),
        surfaceAlt: Color(0xFF2A2018),
        border: Color(0xFF4B3824),
        accent: Color(0xFFE8C967),
        accentAlt: Color(0xFFC9A227),
        text: Color(0xFFF4E6C8),
        muted: Color(0xFFCBBFA8),
        onAccent: Color(0xFF140F0A),
        success: Color(0xFFE8C967),
      ),
      'glass' => const AppThemePalette(
        id: 'glass',
        background: Color(0xFF0A0E15),
        surface: Color(0xFF121A26),
        surfaceAlt: Color(0xFF1A2433),
        border: Color(0xFF3B4A60),
        accent: Color(0xFF7DD3FC),
        accentAlt: Color(0xFFC084FC),
        text: Color(0xFFF4F9FF),
        muted: Color(0xFFB4C4D8),
        onAccent: Color(0xFF07111C),
        success: Color(0xFF86EFAC),
      ),
      _ => const AppThemePalette(
        id: 'classic',
        background: Color(0xFF0A0A0C),
        surface: Color(0xFF16161A),
        surfaceAlt: Color(0xFF1E1E24),
        border: Color(0xFF2D2D35),
        accent: Color(0xFF3B82F6),
        accentAlt: Color(0xFF8B5CF6),
        text: Color(0xFFF8FAFC),
        muted: Color(0xFF94A3B8),
        onAccent: Colors.white,
        success: Color(0xFF10B981),
      ),
    };
  }
}
