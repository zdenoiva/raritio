import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CameraResult {
  const CameraResult({required this.path, required this.game});

  final String path;
  final String game;
}

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key, this.initialGame = 'pokemon'});

  final String initialGame;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  String? _error;
  bool _isTakingPicture = false;
  bool _torchOn = false;
  late String _game = widget.initialGame == 'mtg' ? 'mtg' : 'pokemon';
  double _zoom = 1;
  double _maxZoom = 1;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras().timeout(
        const Duration(seconds: 10),
        onTimeout: () => <CameraDescription>[],
      );
      if (_cameras == null || _cameras!.isEmpty) {
        if (mounted) {
          setState(
            () => _error = "Kameru sa nepodarilo spustiť.\nSkontroluj povolenie kamery v nastaveniach aplikácie.",
          );
        }
        return;
      }

      final candidates = <CameraDescription>[
        ..._cameras!.where((c) => c.lensDirection == CameraLensDirection.back),
        ..._cameras!.where((c) => c.lensDirection != CameraLensDirection.back),
      ];

      Object? lastError;
      for (final camera in candidates) {
        CameraController? controller;
        try {
          controller = CameraController(
            camera,
            ResolutionPreset.high,
            enableAudio: false,
            imageFormatGroup: ImageFormatGroup.jpeg,
          );
          await controller.initialize().timeout(
            const Duration(seconds: 20),
            onTimeout: () => throw Exception("Kamera nereaguje (timeout)."),
          );
          try {
            await controller.setFocusMode(FocusMode.auto);
          } catch (_) {
            // Focus mode is a nice-to-have; ignore devices that do not support it.
          }
          try {
            await controller.setExposureMode(ExposureMode.auto);
          } catch (_) {}
          try {
            _maxZoom = await controller.getMaxZoomLevel();
          } catch (_) {
            _maxZoom = 1;
          }
          if (!mounted) {
            await controller.dispose();
            return;
          }
          setState(() {
            _controller = controller;
            _error = null;
          });
          return;
        } catch (e) {
          lastError = e;
          await controller?.dispose();
        }
      }

      if (mounted) {
        setState(
          () => _error =
              "Kameru sa nepodarilo spustiť.\nSkontroluj povolenie kamery v nastaveniach aplikácie.\n\n$lastError",
        );
      }
    } catch (e) {
      print("Camera init error: $e");
      if (mounted) setState(() => _error = "Chyba kamery: $e");
    }
  }

  Future<void> _takePicture() async {
    if (_isTakingPicture ||
        _controller == null ||
        !_controller!.value.isInitialized) {
      return;
    }
    setState(() => _isTakingPicture = true);
    try {
      final XFile file = await _controller!.takePicture();
      if (mounted) {
        Navigator.pop(context, CameraResult(path: file.path, game: _game));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isTakingPicture = false;
          _error = "Nepodarilo sa odfotiť: $e";
        });
      }
    }
  }

  Future<void> _pickFromGallery() async {
    final picked = await FilePicker.pickFile(
      dialogTitle: 'Vybrať fotku karty',
      type: FileType.image,
    );
    if (picked == null || !mounted) return;
    final path = picked.path;
    if (path == null || path.isEmpty) return;
    Navigator.pop(context, CameraResult(path: path, game: _game));
  }

  Future<void> _setZoom(double value) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final target = value.clamp(1.0, _maxZoom > 1 ? _maxZoom : 1.0).toDouble();
    try {
      await controller.setZoomLevel(target);
      if (mounted) setState(() => _zoom = target);
    } catch (_) {}
  }

  Future<void> _chooseGame() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF16161A),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Čo skenuješ?',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            _GameOption(
              icon: Icons.catching_pokemon_rounded,
              title: 'Pokémon',
              selected: _game == 'pokemon',
              onTap: () => Navigator.pop(context, 'pokemon'),
            ),
            _GameOption(
              icon: Icons.style_rounded,
              title: 'MTG',
              selected: _game == 'mtg',
              onTap: () => Navigator.pop(context, 'mtg'),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
    if (selected != null && mounted) {
      setState(() => _game = selected);
    }
  }

  Future<void> _showCameraSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF16161A),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                _torchOn
                    ? Icons.flashlight_on_rounded
                    : Icons.flashlight_off_rounded,
                color: Colors.white,
              ),
              title: const Text('Blesk', style: TextStyle(color: Colors.white)),
              trailing: Switch(
                value: _torchOn,
                onChanged: (_) {
                  Navigator.pop(context);
                  _toggleTorch();
                },
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 18),
              child: Text(
                'Podrž kartu v ráme, telefon rovnobežne s kartou. '
                'Pri slabom svetle zapni blesk.',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleTorch() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      await controller.setFlashMode(_torchOn ? FlashMode.off : FlashMode.torch);
      if (mounted) setState(() => _torchOn = !_torchOn);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Blesk nie je dostupný.')));
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: _error != null
            ? _CameraMessage(
                message: _error!,
                onClose: () => Navigator.pop(context),
                onRetry: () {
                  _controller?.dispose();
                  _controller = null;
                  setState(() => _error = null);
                  _initializeCamera();
                },
              )
            : _controller == null || !_controller!.value.isInitialized
            ? _CameraMessage(
                message: 'Spúšťam kameru...',
                loading: true,
                onClose: () => Navigator.pop(context),
              )
            : _buildCamera(context),
      ),
    );
  }

  Widget _buildCamera(BuildContext context) {
    final controller = _controller!;
    final screen = MediaQuery.sizeOf(context);
    final frameWidth = screen.width * 0.84;
    var frameHeight = frameWidth * 3.5 / 2.5;
    final maxHeight = screen.height * 0.58;
    final actualWidth = frameHeight > maxHeight
        ? maxHeight * 2.5 / 3.5
        : frameWidth;
    if (frameHeight > maxHeight) frameHeight = maxHeight;
    final frameRect = Rect.fromCenter(
      center: Offset(screen.width / 2, screen.height * 0.47),
      width: actualWidth,
      height: frameHeight,
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        _cameraPreview(controller),
        _ScannerOverlay(frameRect: frameRect),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: Row(
                children: [
                  _RoundIconButton(
                    icon: Icons.close_rounded,
                    onTap: () => Navigator.pop(context),
                    tooltip: 'Zavrieť',
                  ),
                  Expanded(
                    child: Center(
                      child: _GamePill(game: _game, onTap: _chooseGame),
                    ),
                  ),
                  _RoundIconButton(
                    icon: _torchOn
                        ? Icons.flashlight_on_rounded
                        : Icons.flashlight_off_rounded,
                    onTap: _toggleTorch,
                    tooltip: 'Blesk',
                    active: _torchOn,
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          top: frameRect.top - 38,
          left: 20,
          right: 20,
          child: const Text(
            'Umiestni kartu do rámu',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              shadows: [Shadow(color: Colors.black87, blurRadius: 10)],
            ),
          ),
        ),
        Positioned(
          top: frameRect.bottom + 12,
          left: 20,
          right: 20,
          child: const Text(
            'Drž telefon rovnobežne s kartou a chvíľu nehýb.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white70,
              fontSize: 11,
              height: 1.35,
              shadows: [Shadow(color: Colors.black87, blurRadius: 8)],
            ),
          ),
        ),
        Positioned(
          top: frameRect.bottom + 42,
          left: 0,
          right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [1.0, 2.0, 3.0].map((value) {
              final available = value <= _maxZoom + 0.01;
              final active = (_zoom - value).abs() < 0.05;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: GestureDetector(
                  onTap: available ? () => _setZoom(value) : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: active
                          ? const Color(0xFFFFC107)
                          : const Color(0x99000000),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: available
                            ? Colors.white.withValues(alpha: 0.25)
                            : Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                    child: Text(
                      '${value.toStringAsFixed(0)}x',
                      style: TextStyle(
                        color: active
                            ? Colors.black
                            : available
                            ? Colors.white
                            : Colors.white38,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        Positioned(
          bottom: 28 + MediaQuery.of(context).padding.bottom,
          left: 24,
          right: 24,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _BottomCircleButton(
                icon: Icons.photo_library_outlined,
                onTap: _pickFromGallery,
                tooltip: 'Vybrať z galérie',
              ),
              GestureDetector(
                onTap: _isTakingPicture ? null : _takePicture,
                child: Container(
                  width: 82,
                  height: 82,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 4),
                    color: Colors.white.withValues(alpha: 0.18),
                    boxShadow: const [
                      BoxShadow(color: Colors.black54, blurRadius: 16),
                    ],
                  ),
                  child: _isTakingPicture
                      ? const Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 3,
                          ),
                        )
                      : Center(
                          child: Container(
                            width: 58,
                            height: 58,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                            ),
                          ),
                        ),
                ),
              ),
              _BottomCircleButton(
                icon: Icons.tune_rounded,
                onTap: _showCameraSettings,
                tooltip: 'Nastavenia skenera',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _cameraPreview(CameraController controller) {
    final previewSize = controller.value.previewSize;
    if (previewSize == null) {
      return CameraPreview(controller);
    }
    final portrait = MediaQuery.of(context).orientation == Orientation.portrait;
    final width = portrait ? previewSize.height : previewSize.width;
    final height = portrait ? previewSize.width : previewSize.height;
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: width,
          height: height,
          child: CameraPreview(controller),
        ),
      ),
    );
  }
}

class _GamePill extends StatelessWidget {
  const _GamePill({required this.game, required this.onTap});

  final String game;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isMtg = game == 'mtg';
    return Material(
      color: const Color(0xAA000000),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isMtg ? Icons.style_rounded : Icons.catching_pokemon_rounded,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 7),
              Text(
                isMtg ? 'MTG' : 'Pokémon',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 5),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Colors.white70,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GameOption extends StatelessWidget {
  const _GameOption({
    required this.icon,
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: Colors.white),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      trailing: selected
          ? const Icon(Icons.check_rounded, color: Color(0xFF93C5FD))
          : null,
    );
  }
}

class _BottomCircleButton extends StatelessWidget {
  const _BottomCircleButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: const Color(0xAA000000),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(icon, color: Colors.white, size: 22),
          ),
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.active = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active ? const Color(0xCC3B82F6) : const Color(0x99000000),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(icon, color: Colors.white, size: 22),
          ),
        ),
      ),
    );
  }
}

class _ScannerOverlay extends StatelessWidget {
  const _ScannerOverlay({required this.frameRect});

  final Rect frameRect;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _ScannerOverlayPainter(frameRect),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _ScannerOverlayPainter extends CustomPainter {
  _ScannerOverlayPainter(this.frameRect);

  final Rect frameRect;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = Path()..addRect(Offset.zero & size);
    final frame = Path()
      ..addRRect(RRect.fromRectAndRadius(frameRect, const Radius.circular(26)));
    final cutout = Path.combine(PathOperation.difference, outer, frame);

    canvas.drawPath(
      cutout,
      Paint()..color = Colors.black.withValues(alpha: 0.52),
    );

    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..color = const Color(0x44B6FF3B)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);
    canvas.drawRRect(
      RRect.fromRectAndRadius(frameRect, const Radius.circular(26)),
      glow,
    );

    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.white
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.7);
    canvas.drawRRect(
      RRect.fromRectAndRadius(frameRect, const Radius.circular(26)),
      border,
    );

    final accent = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFB6FF3B);
    const corner = 26.0;
    final corners = <List<Offset>>[
      [
        Offset(frameRect.left, frameRect.top + corner),
        Offset(frameRect.left, frameRect.top),
        Offset(frameRect.left + corner, frameRect.top),
      ],
      [
        Offset(frameRect.right - corner, frameRect.top),
        Offset(frameRect.right, frameRect.top),
        Offset(frameRect.right, frameRect.top + corner),
      ],
      [
        Offset(frameRect.left, frameRect.bottom - corner),
        Offset(frameRect.left, frameRect.bottom),
        Offset(frameRect.left + corner, frameRect.bottom),
      ],
      [
        Offset(frameRect.right - corner, frameRect.bottom),
        Offset(frameRect.right, frameRect.bottom),
        Offset(frameRect.right, frameRect.bottom - corner),
      ],
    ];
    for (final points in corners) {
      final path = Path()..moveTo(points[0].dx, points[0].dy);
      path.lineTo(points[1].dx, points[1].dy);
      path.lineTo(points[2].dx, points[2].dy);
      canvas.drawPath(path, accent);
    }
  }

  @override
  bool shouldRepaint(covariant _ScannerOverlayPainter oldDelegate) {
    return oldDelegate.frameRect != frameRect;
  }
}

class _CameraMessage extends StatelessWidget {
  const _CameraMessage({
    required this.message,
    required this.onClose,
    this.onRetry,
    this.loading = false,
  });

  final String message;
  final VoidCallback onClose;
  final VoidCallback? onRetry;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Stack(
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (loading)
                    const CircularProgressIndicator(color: Colors.white)
                  else
                    const Icon(
                      Icons.camera_alt_outlined,
                      color: Colors.redAccent,
                      size: 44,
                    ),
                  const SizedBox(height: 16),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: loading ? Colors.white : Colors.redAccent,
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                  if (onRetry != null) ...[
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: onRetry,
                      child: const Text('Skúsiť znova'),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Positioned(
            top: 8,
            left: 14,
            child: _RoundIconButton(
              icon: Icons.close_rounded,
              onTap: onClose,
              tooltip: 'Zavrieť',
            ),
          ),
        ],
      ),
    );
  }
}
