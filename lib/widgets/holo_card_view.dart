import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// A card image with the same tilt + glare idea as the WebView card detail.
/// It follows the phone's accelerometer when available and also reacts to
/// dragging a finger across the card.
class HoloCardView extends StatefulWidget {
  const HoloCardView({
    super.key,
    required this.image,
    required this.finish,
    this.maxWidth = 340,
    this.borderRadius = 18,
  });

  final Widget image;
  final String finish;
  final double maxWidth;
  final double borderRadius;

  @override
  State<HoloCardView> createState() => _HoloCardViewState();
}

class _HoloCardViewState extends State<HoloCardView> {
  StreamSubscription<AccelerometerEvent>? _sensorSubscription;
  Size _cardSize = Size.zero;
  double? _baseX;
  double? _baseY;
  double _rotateX = 0;
  double _rotateY = 0;
  double _shineX = 50;
  double _shineY = 50;
  DateTime _lastSensorUpdate = DateTime.fromMillisecondsSinceEpoch(0);

  bool get _hasHolo =>
      widget.finish.isNotEmpty &&
      widget.finish != 'normal' &&
      widget.finish != 'firstEdition';

  @override
  void initState() {
    super.initState();
    if (_hasHolo) _listenToSensors();
  }

  void _listenToSensors() {
    try {
      _sensorSubscription = accelerometerEventStream().listen(
        (event) {
          final now = DateTime.now();
          if (now.difference(_lastSensorUpdate).inMilliseconds < 16) return;
          _lastSensorUpdate = now;
          if (_baseX == null || _baseY == null) {
            _baseX = event.x;
            _baseY = event.y;
            return;
          }
          final dx = event.x - _baseX!;
          final dy = event.y - _baseY!;
          final targetRy = (dx * 2.6).clamp(-14.0, 14.0);
          final targetRx = (-dy * 2.2).clamp(-12.0, 12.0);
          final targetShineX = (50 + dx * 2.0).clamp(0.0, 100.0);
          final targetShineY = (50 + dy * 1.6).clamp(0.0, 100.0);
          if (!mounted) return;
          setState(() {
            _rotateX = _rotateX * 0.72 + targetRx * 0.28;
            _rotateY = _rotateY * 0.72 + targetRy * 0.28;
            _shineX = _shineX * 0.72 + targetShineX * 0.28;
            _shineY = _shineY * 0.72 + targetShineY * 0.28;
          });
        },
        onError: (_) {},
        cancelOnError: false,
      );
    } catch (_) {
      // Devices without an accelerometer still get the drag effect.
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_cardSize.isEmpty) return;
    final x = (event.localPosition.dx / _cardSize.width).clamp(0.0, 1.0);
    final y = (event.localPosition.dy / _cardSize.height).clamp(0.0, 1.0);
    setState(() {
      _rotateY = (x - 0.5) * 24;
      _rotateX = (0.5 - y) * 20;
      _shineX = x * 100;
      _shineY = y * 100;
    });
  }

  void _resetTilt() {
    if (!mounted) return;
    setState(() {
      _rotateX = 0;
      _rotateY = 0;
      _shineX = 50;
      _shineY = 50;
    });
  }

  @override
  void dispose() {
    _sensorSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final card = SizedBox(
      width: widget.maxWidth,
      child: AspectRatio(
        aspectRatio: 2.5 / 3.5,
        child: LayoutBuilder(
          builder: (context, constraints) {
            _cardSize = Size(constraints.maxWidth, constraints.maxHeight);
            return Listener(
              onPointerMove: _onPointerMove,
              onPointerUp: (_) => _resetTilt(),
              onPointerCancel: (_) => _resetTilt(),
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0014)
                  ..rotateX(_rotateX * math.pi / 180)
                  ..rotateY(_rotateY * math.pi / 180),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(widget.borderRadius),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      widget.image,
                      if (_hasHolo)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: _HoloShinePainter(
                                finish: widget.finish,
                                shineX: _shineX,
                                shineY: _shineY,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );

    return Center(child: card);
  }
}

class _HoloShinePainter extends CustomPainter {
  _HoloShinePainter({
    required this.finish,
    required this.shineX,
    required this.shineY,
  });

  final String finish;
  final double shineX;
  final double shineY;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final dx = (shineX / 100 - 0.5) * 2;
    final dy = (shineY / 100 - 0.5) * 2;

    final gradient = LinearGradient(
      begin: Alignment(-1.6 + dx, -1.6 + dy),
      end: Alignment(1.6 + dx, 1.6 + dy),
      colors: _shineColors(finish),
      stops: const [0.0, 0.30, 0.48, 0.62, 1.0],
    );
    final paint = Paint()
      ..shader = gradient.createShader(rect)
      ..blendMode = BlendMode.screen;
    canvas.drawRect(rect, paint);

    final hotspot = Paint()
      ..shader = RadialGradient(
        center: Alignment(dx, dy),
        radius: 0.55,
        colors: [
          Colors.white.withValues(alpha: 0.30),
          Colors.white.withValues(alpha: 0.0),
        ],
      ).createShader(rect)
      ..blendMode = BlendMode.screen;
    canvas.drawRect(rect, hotspot);
  }

  List<Color> _shineColors(String finish) {
    switch (finish) {
      case 'gold':
        return [
          Colors.transparent,
          const Color(0x66FFF7C8),
          const Color(0x99FACC15),
          const Color(0x66B45309),
          Colors.transparent,
        ];
      case 'rainbow':
        return [
          Colors.transparent,
          const Color(0x66EF4444),
          const Color(0x66F59E0B),
          const Color(0x6622C55E),
          Colors.transparent,
        ];
      case 'cosmos':
        return [
          Colors.transparent,
          const Color(0x6693C5FD),
          const Color(0x66C4B5FD),
          const Color(0x6622D3EE),
          Colors.transparent,
        ];
      case 'textured':
      case 'etched':
        return [
          Colors.transparent,
          const Color(0x55FFFFFF),
          const Color(0x77E2E8F0),
          const Color(0x55FFFFFF),
          Colors.transparent,
        ];
      default:
        return [
          Colors.transparent,
          const Color(0x55FFFFFF),
          const Color(0x66A5F3FC),
          const Color(0x55F0ABFC),
          Colors.transparent,
        ];
    }
  }

  @override
  bool shouldRepaint(covariant _HoloShinePainter oldDelegate) {
    return oldDelegate.finish != finish ||
        oldDelegate.shineX != shineX ||
        oldDelegate.shineY != shineY;
  }
}
