import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ScanRecognition {
  const ScanRecognition({
    required this.query,
    required this.language,
    required this.candidates,
    this.error,
  });

  final String query;
  final String language;
  final List<Map<String, dynamic>> candidates;
  final String? error;

  bool get hasCandidates => candidates.isNotEmpty;
}

class CameraResult {
  const CameraResult({
    required this.path,
    required this.game,
    this.ocrText,
    this.ocrLanguage,
  });

  final String path;
  final String game;
  final String? ocrText;
  final String? ocrLanguage;
}

class CameraScreen extends StatefulWidget {
  const CameraScreen({
    super.key,
    this.initialGame = 'pokemon',
    this.captureOnly = false,
    this.theme = 'classic',
    this.onRecognize,
    this.onResolveDetails,
    this.onAdd,
  });

  final String initialGame;
  final String theme;

  /// Used by the custom-card-photo flow. It only takes a photo and returns it
  /// without running recognition or showing the card suggestion sheet.
  final bool captureOnly;
  final Future<ScanRecognition> Function(String path, String game)? onRecognize;
  final Future<Map<String, dynamic>?> Function(Map<String, dynamic> card)?
  onResolveDetails;
  final Future<bool> Function(Map<String, dynamic> card)? onAdd;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  static const double _cardAspect = 63 / 88;
  late final _ScannerPalette _palette = _paletteFor(widget.theme);
  Color get _neon => _palette.accent;

  CameraController? _controller;
  List<CameraDescription>? _cameras;
  String? _error;
  bool _isTakingPicture = false;
  bool _torchOn = false;
  late String _game = widget.initialGame == 'mtg' ? 'mtg' : 'pokemon';
  double _zoom = 1;
  double _maxZoom = 1;

  bool _processing = false;
  bool _resultVisible = false;
  bool _adding = false;
  bool _resolvingDetails = false;
  String? _currentPath;
  bool _currentPathIsTemporary = false;
  ScanRecognition? _recognition;
  Map<String, dynamic>? _selectedCandidate;

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
            () => _error = 'Kameru sa nepodarilo spustiť.\nSkontroluj povolenie kamery v nastaveniach aplikácie.',
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
            ResolutionPreset.max,
            enableAudio: false,
            imageFormatGroup: ImageFormatGroup.jpeg,
          );
          await controller.initialize().timeout(
            const Duration(seconds: 20),
            onTimeout: () => throw Exception('Kamera nereaguje (timeout).'),
          );
          try {
            await controller.setFocusMode(FocusMode.auto);
          } catch (_) {}
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
              'Kameru sa nepodarilo spustiť.\nSkontroluj povolenie kamery v nastaveniach aplikácie.\n\n$lastError',
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Chyba kamery: $e');
    }
  }

  Future<void> _takePicture() async {
    final controller = _controller;
    if (_isTakingPicture ||
        controller == null ||
        !controller.value.isInitialized) {
      return;
    }
    setState(() => _isTakingPicture = true);
    try {
      final file = await controller.takePicture();
      if (!mounted) return;
      setState(() => _isTakingPicture = false);
      await _recognizePath(file.path, temporary: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isTakingPicture = false;
        _error = 'Nepodarilo sa odfotiť: $e';
      });
    }
  }

  Future<void> _captureForCustomPhoto() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      final file = await controller.takePicture();
      final dir = await getTemporaryDirectory();
      final target = p.join(
        dir.path,
        'raritio-custom-${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      await File(file.path).copy(target);
      if (mounted) {
        Navigator.pop(context, CameraResult(path: target, game: _game));
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Nepodarilo sa odfotiť: $e');
    }
  }

  Future<void> _pickGallery() async {
    if (_processing || _resultVisible || _isTakingPicture) return;
    final picked = await FilePicker.pickFile(
      dialogTitle: 'Vybrať fotku karty',
      type: FileType.image,
    );
    final path = picked?.path;
    if (path == null || path.isEmpty || !mounted) return;
    if (widget.captureOnly) {
      Navigator.pop(context, CameraResult(path: path, game: _game));
      return;
    }
    await _recognizePath(path);
  }

  Future<void> _recognizePath(String path, {bool temporary = false}) async {
    final recognize = widget.onRecognize;
    if (recognize == null || !mounted) return;

    setState(() {
      _processing = true;
      _resultVisible = true;
      _adding = false;
      _resolvingDetails = false;
      _recognition = null;
      _selectedCandidate = null;
      _currentPath = path;
      _currentPathIsTemporary = temporary;
    });

    try {
      final result = await recognize(path, _game);
      if (!mounted) return;
      setState(() {
        _processing = false;
        _recognition = result;
        _selectedCandidate = result.candidates.isEmpty
            ? null
            : result.candidates.first;
        if (result.candidates.isEmpty) {
          _error = result.error ?? 'Kartu sa nepodarilo rozpoznať.';
        }
      });
      if (_selectedCandidate != null) {
        unawaited(_resolveSelected());
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _processing = false;
        _error = 'Kartu sa nepodarilo rozpoznať: $e';
      });
    }
  }

  Future<void> _resolveSelected() async {
    final selected = _selectedCandidate;
    if (selected == null || selected['detailsLoaded'] == true) return;
    await _resolveCandidate(selected);
  }

  Future<void> _resolveCandidate(Map<String, dynamic> card) async {
    final resolver = widget.onResolveDetails;
    if (resolver == null || card['detailsLoaded'] == true) return;
    if (mounted) setState(() => _resolvingDetails = true);
    try {
      final details = await resolver(card);
      if (!mounted) return;
      if (details != null) {
        final candidates = _recognition?.candidates;
        if (candidates != null) {
          final index = candidates.indexWhere(
            (item) => item['id'] == card['id'],
          );
          if (index >= 0) candidates[index] = details;
        }
        if (_selectedCandidate?['id'] == card['id']) {
          _selectedCandidate = details;
        }
      }
    } catch (_) {
      // Keep the summary if details fail.
    } finally {
      if (mounted) setState(() => _resolvingDetails = false);
    }
  }

  void _selectCandidate(Map<String, dynamic> card) {
    setState(() => _selectedCandidate = card);
    unawaited(_resolveCandidate(card));
  }

  Future<void> _addSelected() async {
    var card = _selectedCandidate;
    final add = widget.onAdd;
    if (card == null || _adding || add == null) return;

    if (card['detailsLoaded'] != true) {
      await _resolveCandidate(card);
      card = _selectedCandidate;
      if (card == null) return;
    }

    setState(() => _adding = true);
    var added = false;
    try {
      added = await add(card);
    } catch (_) {
      added = false;
    }
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          added
              ? 'Karta pridaná do aktuálneho balíka.'
              : 'Kartu nebolo možné pridať. Možno už je v balíku.',
        ),
      ),
    );
    await _finishResult();
  }

  Future<void> _manualSearch() async {
    final path = _currentPath;
    if (path == null) return;

    var target = path;
    try {
      final dir = await getTemporaryDirectory();
      final copy = File(
        p.join(
          dir.path,
          'raritio-scan-${DateTime.now().microsecondsSinceEpoch}.jpg',
        ),
      );
      await File(path).copy(copy.path);
      target = copy.path;
    } catch (_) {}

    if (!mounted) return;
    final recognition = _recognition;
    Navigator.pop(
      context,
      CameraResult(
        path: target,
        game: _game,
        ocrText: recognition?.query,
        ocrLanguage: recognition?.language,
      ),
    );
  }

  Future<void> _finishResult() async {
    final path = _currentPath;
    final temporary = _currentPathIsTemporary;
    if (!mounted) return;
    setState(() {
      _processing = false;
      _resultVisible = false;
      _adding = false;
      _resolvingDetails = false;
      _recognition = null;
      _selectedCandidate = null;
      _currentPath = null;
      _currentPathIsTemporary = false;
    });
    if (temporary && path != null) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
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
    if (selected != null && mounted) setState(() => _game = selected);
  }

  Future<void> _showSettings() async {
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
                'Umiestni celú kartu do rámika a stlač spúšť. '
                'Pri slabom svetle zapni blesk.',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
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
    final frameWidth = screen.width * 0.82;
    var frameHeight = frameWidth / _cardAspect;
    final maxHeight = screen.height * 0.62;
    final actualWidth = frameHeight > maxHeight
        ? maxHeight * _cardAspect
        : frameWidth;
    if (frameHeight > maxHeight) frameHeight = maxHeight;
    final frameRect = Rect.fromCenter(
      center: Offset(screen.width / 2, screen.height * 0.46),
      width: actualWidth,
      height: frameHeight,
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        _cameraPreview(controller),
        _FixedFrameOverlay(frameRect: frameRect, accent: _palette.accent),
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
          top: frameRect.top - 36,
          left: 20,
          right: 20,
          child: const Text(
            'Umiestni kartu do rámika',
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
          top: frameRect.bottom + 10,
          left: 20,
          right: 20,
          child: const Text(
            'Karta musí byť celá v rámiku.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white70,
              fontSize: 11,
              shadows: [Shadow(color: Colors.black87, blurRadius: 8)],
            ),
          ),
        ),
        Positioned(
          top: frameRect.bottom + 38,
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
          bottom: 24 + MediaQuery.of(context).padding.bottom,
          left: 24,
          right: 24,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _BottomCircleButton(
                icon: Icons.photo_library_outlined,
                onTap: _pickGallery,
                tooltip: 'Vybrať z galérie',
              ),
              GestureDetector(
                onTap: _isTakingPicture
                    ? null
                    : widget.captureOnly
                    ? _captureForCustomPhoto
                    : _takePicture,
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
                onTap: _showSettings,
                tooltip: 'Nastavenia skenera',
              ),
            ],
          ),
        ),
        if (_resultVisible) _buildResultSheet(),
      ],
    );
  }

  Widget _cameraPreview(CameraController controller) {
    final previewSize = controller.value.previewSize;
    if (previewSize == null) return CameraPreview(controller);
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

  Widget _buildResultSheet() {
    final recognition = _recognition;
    final selected = _selectedCandidate;
    final candidates =
        recognition?.candidates ?? const <Map<String, dynamic>>[];
    final styles = selected == null
        ? const <_CardStyle>[]
        : _styleOptions(selected);

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Material(
        color: _palette.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: _finishResult,
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white70,
                      ),
                      tooltip: 'Zavrieť návrh',
                    ),
                  ],
                ),
                if (_processing)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 8, 0, 22),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: _neon,
                          ),
                        ),
                        SizedBox(width: 12),
                        Text(
                          'Rozpoznávam kartu…',
                          style: TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                  )
                else if (selected == null)
                  _buildFailure()
                else ...[
                  Row(
                    children: [
                      const Text(
                        'Návrh karty',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${candidates.length} ${_resultsLabel(candidates.length)}',
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  if (candidates.length > 1) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 76,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: candidates.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final card = candidates[index];
                          final active = identical(card, selected);
                          return GestureDetector(
                            onTap: () => _selectCandidate(card),
                            child: Container(
                              width: 54,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: active ? _neon : Colors.white24,
                                  width: active ? 2 : 1,
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: _cardImage(card),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 64,
                        height: 90,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: _cardImage(selected),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              (selected['name'] ?? '').toString(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _cardSubtitle(selected),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1E2A16),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: _neon.withValues(alpha: 0.45),
                                    ),
                                  ),
                                  child: Text(
                                    _cardTypeLabel(selected),
                                    style: TextStyle(
                                      color: _neon,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _resolvingDetails
                                      ? 'Načítavam…'
                                      : _priceLabel(selected),
                                  style: TextStyle(
                                    color: _neon,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const Spacer(),
                                if (styles.length > 1)
                                  _styleMenu(selected, styles),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _adding ? null : _addSelected,
                      icon: _adding
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.black,
                              ),
                            )
                          : const Icon(Icons.add_rounded),
                      label: const Text('Pridať do aktuálneho balíka'),
                      style: FilledButton.styleFrom(
                        backgroundColor: _neon,
                        foregroundColor: Colors.black,
                        minimumSize: const Size.fromHeight(46),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: _manualSearch,
                        child: const Text('Hľadať ručne'),
                      ),
                      TextButton(
                        onPressed: _finishResult,
                        child: const Text('Skúsiť znova'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFailure() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.search_off_rounded, color: Colors.white54, size: 34),
          const SizedBox(height: 8),
          const Text(
            'Kartu sa nepodarilo rozpoznať.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF94A3B8), height: 1.4),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: _manualSearch,
                child: const Text('Hľadať ručne'),
              ),
              FilledButton(
                onPressed: _finishResult,
                style: FilledButton.styleFrom(
                  backgroundColor: _neon,
                  foregroundColor: Colors.black,
                ),
                child: const Text('Skúsiť znova'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cardImage(Map<String, dynamic> card) {
    final raw = (card['imageUri'] ?? '').toString().trim();
    final valid = raw.startsWith('http://') || raw.startsWith('https://');
    if (!valid) {
      return const ColoredBox(
        color: Color(0xFF1E1E24),
        child: Icon(Icons.style_rounded, color: Colors.white24),
      );
    }
    return Image.network(
      raw,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => const ColoredBox(
        color: Color(0xFF1E1E24),
        child: Icon(Icons.style_rounded, color: Colors.white24),
      ),
    );
  }

  String _resultsLabel(int count) {
    if (count == 1) return 'výsledok';
    if (count < 5) return 'výsledky';
    return 'výsledkov';
  }

  String _cardTypeLabel(Map<String, dynamic> card) {
    return switch ((card['cardType'] ?? '').toString()) {
      'energy' => 'Energy',
      'trainer' => 'Trainer',
      'mtg' => 'MTG',
      _ => 'Pokémon',
    };
  }

  List<_CardStyle> _styleOptions(Map<String, dynamic> card) {
    final rawVariants = card['variants'];
    final result = <_CardStyle>[];
    if (rawVariants is List) {
      for (final raw in rawVariants) {
        if (raw is! Map) continue;
        final finish = (raw['finish'] ?? '').toString();
        final id = (raw['id'] ?? finish).toString();
        if (id.isEmpty) continue;
        final label = (raw['label'] ?? '').toString();
        result.add(
          _CardStyle(
            id: id,
            label: label.isNotEmpty ? label : _finishLabel(finish),
            finish: finish,
            image: (raw['image'] ?? '').toString(),
            price: raw['price'] is num
                ? (raw['price'] as num).toDouble()
                : null,
            currency: (raw['priceCurrency'] ?? '').toString(),
          ),
        );
      }
    }
    if (result.isNotEmpty) return result;

    final finishes = card['finishes'];
    if (finishes is List && finishes.length > 1) {
      for (final raw in finishes) {
        final finish = raw.toString();
        if (finish.isEmpty) continue;
        result.add(
          _CardStyle(
            id: finish,
            label: _finishLabel(finish),
            finish: finish,
            image: '',
            price: card['price'] is num
                ? (card['price'] as num).toDouble()
                : null,
            currency: (card['priceCurrency'] ?? '').toString(),
          ),
        );
      }
    }
    return result;
  }

  String _finishLabel(String raw) {
    return switch (raw.toLowerCase()) {
      'normal' => 'Normal',
      'holo' => 'Holo',
      'reverse' => 'Reverse Holo',
      'reverseholofoil' => 'Reverse Holo',
      'foil' => 'Foil',
      'nonfoil' => 'Normal',
      '1st edition' || 'firstedition' => '1st Edition',
      _ => raw,
    };
  }

  Widget _styleMenu(Map<String, dynamic> card, List<_CardStyle> styles) {
    final variantId = (card['variantId'] ?? '').toString();
    final finish = (card['finish'] ?? '').toString();
    var current = styles.first;
    for (final style in styles) {
      if (variantId.isNotEmpty && style.id == variantId) {
        current = style;
        break;
      }
      if (variantId.isEmpty && style.finish == finish) {
        current = style;
      }
    }

    return PopupMenuButton<String>(
      tooltip: 'Vybrať vizuál karty',
      onSelected: (id) {
        final style = styles.firstWhere((item) => item.id == id);
        _selectStyle(style);
      },
      itemBuilder: (context) => styles
          .map(
            (style) => PopupMenuItem<String>(
              value: style.id,
              child: Row(
                children: [
                  if (style.id == current.id)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(Icons.check_rounded, size: 16, color: _neon),
                    ),
                  Text(style.label),
                ],
              ),
            ),
          )
          .toList(),
      child: Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFF1E2A16),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _neon.withValues(alpha: 0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.palette_outlined, color: _neon, size: 15),
            const SizedBox(width: 5),
            Text(
              current.label,
              style: TextStyle(
                color: _neon,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            Icon(Icons.arrow_drop_down_rounded, color: _neon, size: 19),
          ],
        ),
      ),
    );
  }

  void _selectStyle(_CardStyle style) {
    final card = _selectedCandidate;
    if (card == null) return;
    setState(() {
      card['finish'] = style.finish;
      card['variantId'] = style.id;
      card['variantLabel'] = style.label;
      if (style.image.isNotEmpty) card['imageUri'] = style.image;
      if (style.price != null) {
        card['price'] = style.price;
        card['currentPrice'] = style.price;
      }
      if (style.currency.isNotEmpty) {
        card['priceCurrency'] = style.currency;
      }
    });
  }

  String _cardSubtitle(Map<String, dynamic> card) {
    final parts = <String>[
      if ((card['set'] ?? '').toString().trim().isNotEmpty)
        card['set'].toString(),
      if ((card['number'] ?? '').toString().trim().isNotEmpty)
        '#${card['number']}',
    ];
    return parts.join(' • ');
  }

  String _priceLabel(Map<String, dynamic> card) {
    final raw = card['currentPrice'] ?? card['price'];
    final price = raw is num ? raw.toDouble() : double.tryParse('$raw') ?? 0;
    if (price <= 0) return 'Cena neznáma';
    final currency = (card['priceCurrency'] ?? '').toString().toUpperCase();
    final symbol = currency == 'EUR' ? '€' : r'$';
    return '$symbol${price.toStringAsFixed(2)}';
  }
}

class _ScannerPalette {
  const _ScannerPalette({required this.accent, required this.surface});

  final Color accent;
  final Color surface;
}

_ScannerPalette _paletteFor(String theme) {
  return switch (theme) {
    'poke' => const _ScannerPalette(
      accent: Color(0xFFFFCB05),
      surface: Color(0xFF131C2E),
    ),
    'magic' => const _ScannerPalette(
      accent: Color(0xFFE8C967),
      surface: Color(0xFF081F2C),
    ),
    'stone' => const _ScannerPalette(
      accent: Color(0xFFC9A227),
      surface: Color(0xFF211912),
    ),
    _ => const _ScannerPalette(
      accent: Color(0xFFB6FF3B),
      surface: Color(0xFF101114),
    ),
  };
}

class _CardStyle {
  const _CardStyle({
    required this.id,
    required this.label,
    required this.finish,
    required this.image,
    required this.price,
    required this.currency,
  });

  final String id;
  final String label;
  final String finish;
  final String image;
  final double? price;
  final String currency;
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

class _FixedFrameOverlay extends StatelessWidget {
  const _FixedFrameOverlay({required this.frameRect, required this.accent});

  final Rect frameRect;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _FixedFramePainter(frameRect, accent),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _FixedFramePainter extends CustomPainter {
  _FixedFramePainter(this.frameRect, this.accent);

  final Rect frameRect;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = Path()..addRect(Offset.zero & size);
    final frame = Path()
      ..addRRect(RRect.fromRectAndRadius(frameRect, const Radius.circular(22)));
    final cutout = Path.combine(PathOperation.difference, outer, frame);
    canvas.drawPath(
      cutout,
      Paint()..color = Colors.black.withValues(alpha: 0.45),
    );

    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..color = accent.withValues(alpha: 0.27)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);
    canvas.drawRRect(
      RRect.fromRectAndRadius(frameRect, const Radius.circular(22)),
      glow,
    );
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = Colors.white;
    canvas.drawRRect(
      RRect.fromRectAndRadius(frameRect, const Radius.circular(22)),
      border,
    );

    final cornerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..color = accent;
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
      canvas.drawPath(path, cornerPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _FixedFramePainter oldDelegate) {
    return oldDelegate.frameRect != frameRect || oldDelegate.accent != accent;
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
