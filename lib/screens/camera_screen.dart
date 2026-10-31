import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_better_scanner/flutter_better_scanner.dart';
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
    this.onRecognize,
    this.onAdd,
  });

  final String initialGame;

  /// Used by the custom-card-photo flow. It only takes a photo and returns it
  /// without running recognition or showing the card suggestion sheet.
  final bool captureOnly;
  final Future<ScanRecognition> Function(String path, String game)? onRecognize;
  final Future<bool> Function(Map<String, dynamic> card)? onAdd;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  static const Color _neon = Color(0xFFB6FF3B);

  ScannerController? _controller;
  late String _game = widget.initialGame == 'mtg' ? 'mtg' : 'pokemon';
  bool _torchOn = false;
  bool _autoCapture = true;
  bool _processing = false;
  bool _resultVisible = false;
  bool _adding = false;
  String? _currentPath;
  ScanPage? _currentPage;
  String? _handledPageId;
  ScanRecognition? _recognition;
  Map<String, dynamic>? _selectedCandidate;
  String? _error;

  @override
  void initState() {
    super.initState();
    _autoCapture = !widget.captureOnly;
    _controller = ScannerController(config: _scannerConfig());
    _controller!.addListener(_onControllerChanged);
    unawaited(_initialize());
  }

  ScannerConfig _scannerConfig() {
    return ScannerConfig(
      captureMode: CaptureMode.single,
      shutterMode: widget.captureOnly ? ShutterMode.manual : ShutterMode.auto,
      autoDetectEdges: true,
      detectionQuality: DetectionQuality.high,
      autoCrop: !widget.captureOnly,
      autoEnhance: false,
      enhancement: ScanEnhancement.original,
      guide: ScanGuide.free,
      allowGuideChange: false,
      showGrid: false,
      allowGridToggle: false,
      flashMode: ScannerFlashMode.off,
      allowFlashControl: false,
      camera: CameraFacing.back,
      allowCameraSwitch: false,
      allowGalleryImport: false,
      allowZoom: true,
      afterCapture: AfterCapture.returnPaths,
      workingResolution: 2200,
      autoCaptureTuning: AutoCaptureTuning(
        holdDuration: Duration(milliseconds: 700),
        cooldown: Duration(milliseconds: 900),
        minAreaFraction: 0.2,
        minFocus: 7,
      ),
      theme: ScannerTheme(
        accent: _neon,
        detected: _neon,
        searching: Colors.white,
        warning: Color(0xFFFFC107),
        background: Colors.black,
        surface: Color(0xFF16161A),
        onSurface: Colors.white,
      ),
    );
  }

  Future<void> _initialize() async {
    try {
      await _controller?.initialize();
    } catch (e) {
      if (mounted) setState(() => _error = 'Kameru sa nepodarilo spustiť: $e');
    }
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final controller = _controller;
    if (controller == null) return;

    if (!widget.captureOnly &&
        !_processing &&
        !_resultVisible &&
        controller.pages.isNotEmpty) {
      final page = controller.pages.first;
      if (page.id != _handledPageId) {
        _handledPageId = page.id;
        unawaited(_recognizePage(page));
      }
    }

    // Keep the zoom, torch and permission UI in sync with the engine.
    if (mounted) setState(() {});
  }

  Future<void> _recognizePage(ScanPage page) async {
    final controller = _controller;
    if (controller == null) return;

    // The controller publishes the page when it is added, before the rendered
    // JPEG is necessarily on disk. Wait for the render to settle.
    for (var attempt = 0; attempt < 60 && controller.isBusy; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    final path = controller.pagePath(page);
    if (path == null || !await File(path).exists()) {
      if (mounted) {
        setState(() {
          _resultVisible = true;
          _processing = false;
          _currentPage = page;
          _error = 'Nepodarilo sa pripraviť fotku karty.';
        });
      }
      return;
    }
    await _recognizePath(path, page: page);
  }

  Future<void> _recognizePath(String path, {ScanPage? page}) async {
    final recognize = widget.onRecognize;
    if (recognize == null) return;
    _controller?.setShutterMode(ShutterMode.manual);
    if (!mounted) return;

    setState(() {
      _processing = true;
      _resultVisible = true;
      _adding = false;
      _recognition = null;
      _selectedCandidate = null;
      _error = null;
      _currentPath = path;
      _currentPage = page;
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _processing = false;
        _error = 'Kartu sa nepodarilo rozpoznať: $e';
      });
    }
  }

  Future<void> _finishResult() async {
    final page = _currentPage;
    if (!mounted) return;
    setState(() {
      _processing = false;
      _resultVisible = false;
      _adding = false;
      _recognition = null;
      _selectedCandidate = null;
      _error = null;
      _currentPath = null;
      _currentPage = null;
    });
    _handledPageId = page?.id;
    if (page != null) {
      await _controller?.deletePage(page);
    }
    _handledPageId = null;
    if (_autoCapture) {
      // Give the user a moment to move the card away before auto-capture
      // starts watching the same frame again.
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (!mounted) return;
    }
    _controller?.setShutterMode(
      _autoCapture ? ShutterMode.auto : ShutterMode.manual,
    );
  }

  Future<void> _addSelected() async {
    final card = _selectedCandidate;
    final add = widget.onAdd;
    if (card == null || _adding || add == null) return;

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
    } catch (_) {
      // The session copy is still available until the camera is disposed.
    }

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

  Future<void> _captureNow() async {
    if (_processing || _resultVisible || _adding) return;
    if (widget.captureOnly) {
      await _captureForCustomPhoto();
      return;
    }
    await _controller?.capture();
  }

  Future<void> _captureForCustomPhoto() async {
    final controller = _controller;
    if (controller == null) return;
    final rawPath = await controller.captureRaw();
    if (rawPath == null || !mounted) return;
    try {
      final dir = await getTemporaryDirectory();
      final target = p.join(
        dir.path,
        'raritio-custom-${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      await File(rawPath).copy(target);
      if (mounted) {
        Navigator.pop(context, CameraResult(path: target, game: _game));
      }
    } catch (_) {
      if (mounted) {
        Navigator.pop(context, CameraResult(path: rawPath, game: _game));
      }
    }
  }

  Future<void> _pickGallery() async {
    if (_processing || _resultVisible) return;
    if (widget.captureOnly) {
      final picked = await FilePicker.pickFile(
        dialogTitle: 'Vybrať fotku karty',
        type: FileType.image,
      );
      final path = picked?.path;
      if (path != null && path.isNotEmpty && mounted) {
        Navigator.pop(context, CameraResult(path: path, game: _game));
      }
      return;
    }
    final pages = await _controller?.pickFromGallery() ?? const <ScanPage>[];
    if (pages.isEmpty || !mounted) return;
    // The controller listener will start recognition for the first page.
  }

  Future<void> _toggleTorch() async {
    final controller = _controller;
    if (controller == null) return;
    final next = _torchOn ? ScannerFlashMode.off : ScannerFlashMode.torch;
    await controller.setFlashMode(next);
    if (mounted) setState(() => _torchOn = !_torchOn);
  }

  Future<void> _setZoom(double value) async {
    final controller = _controller;
    if (controller == null) return;
    await controller.setZoom(value);
    if (mounted) setState(() {});
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
            if (!widget.captureOnly)
              ListTile(
                leading: const Icon(
                  Icons.center_focus_strong_rounded,
                  color: Colors.white,
                ),
                title: const Text(
                  'Automatické zachytenie',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Karta sa vyfotí, keď je zaostrená a stabilná.',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                ),
                trailing: Switch(
                  value: _autoCapture,
                  onChanged: (value) {
                    Navigator.pop(context);
                    setState(() => _autoCapture = value);
                    _controller?.setShutterMode(
                      value ? ShutterMode.auto : ShutterMode.manual,
                    );
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

  @override
  void dispose() {
    _controller?.removeListener(_onControllerChanged);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: _neon)),
      );
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            ScannerPreview(
              controller: controller,
              showOutline: true,
              showGuide: false,
              showGrid: false,
              enableTapToFocus: true,
              enableZoomGesture: true,
            ),
            _buildTopBar(),
            if (!_resultVisible) ...[
              _buildZoomBar(controller),
              _buildHint(controller),
              _buildBottomBar(),
            ],
            if (_resultVisible) _buildResultSheet(),
            if (_error != null && !_resultVisible)
              Positioned(
                left: 20,
                right: 20,
                bottom: 160,
                child: _ErrorPill(message: _error!),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
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
    );
  }

  Widget _buildZoomBar(ScannerController controller) {
    final values = <double>[1, 2, 3];
    return Positioned(
      bottom: 174 + MediaQuery.of(context).padding.bottom,
      left: 0,
      right: 0,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: values.map((value) {
          final available = value <= controller.maxZoom + 0.01;
          final active = (controller.zoom - value).abs() < 0.08;
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
                  color: active ? _neon : const Color(0x99000000),
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
    );
  }

  Widget _buildHint(ScannerController controller) {
    return Positioned(
      bottom: 126 + MediaQuery.of(context).padding.bottom,
      left: 20,
      right: 20,
      child: ValueListenableBuilder<DetectionState>(
        valueListenable: controller.detection,
        builder: (context, state, _) {
          final text = _hintText(state.hint);
          if (text.isEmpty) return const SizedBox.shrink();
          return Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xAA000000),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBottomBar() {
    return Positioned(
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
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _autoCapture ? 'AUTO' : 'MANUÁL',
                style: TextStyle(
                  color: _autoCapture ? _neon : Colors.white70,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              GestureDetector(
                onTap: _captureNow,
                child: Container(
                  width: 78,
                  height: 78,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 4),
                    color: Colors.white.withValues(alpha: 0.18),
                    boxShadow: const [
                      BoxShadow(color: Colors.black54, blurRadius: 16),
                    ],
                  ),
                  child: Center(
                    child: Container(
                      width: 54,
                      height: 54,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          _BottomCircleButton(
            icon: Icons.tune_rounded,
            onTap: _showSettings,
            tooltip: 'Nastavenia skenera',
          ),
        ],
      ),
    );
  }

  Widget _buildResultSheet() {
    final recognition = _recognition;
    final selected = _selectedCandidate;
    final candidates =
        recognition?.candidates ?? const <Map<String, dynamic>>[];

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Material(
        color: const Color(0xFF101114),
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
                  const Padding(
                    padding: EdgeInsets.fromLTRB(0, 8, 0, 22),
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
                        '${candidates.length} ${candidates.length == 1 ? 'výsledok' : 'výsledky'}',
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
                            onTap: () =>
                                setState(() => _selectedCandidate = card),
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
                            Text(
                              _priceLabel(selected),
                              style: const TextStyle(
                                color: _neon,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
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
          Text(
            _error ?? 'Kartu sa nepodarilo rozpoznať.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF94A3B8), height: 1.4),
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

  String _hintText(ScanHint hint) {
    return switch (hint) {
      ScanHint.searching => 'Hľadám kartu',
      ScanHint.moveCloser => 'Priblíž kartu',
      ScanHint.holdSteady => 'Drž chvíľu',
      ScanHint.badLighting => 'Pridaj svetlo',
      ScanHint.focusing => 'Zaostrujem',
      ScanHint.ready => 'Pripravené',
      ScanHint.cooldown => 'Spracúvam…',
    };
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

class _ErrorPill extends StatelessWidget {
  const _ErrorPill({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xCC7F1D1D),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }
}
