import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:raritio/screens/camera_screen.dart';
import 'package:raritio/services/card_grading_service.dart';
import 'package:raritio/services/grading_photo_check_service.dart';
import 'package:raritio/theme/app_theme_palette.dart';

class CardGradingOutcome {
  const CardGradingOutcome({
    required this.cardId,
    this.requestId,
    this.result,
    this.background = false,
    this.cancelled = false,
  });

  final String cardId;
  final String? requestId;
  final GradingResult? result;
  final bool background;
  final bool cancelled;
}

class CardGradingScreen extends StatefulWidget {
  const CardGradingScreen({
    super.key,
    required this.cardId,
    required this.cardName,
    required this.game,
    required this.theme,
  });

  final String cardId;
  final String cardName;
  final String game;
  final String theme;

  @override
  State<CardGradingScreen> createState() => _CardGradingScreenState();
}

class _CardGradingScreenState extends State<CardGradingScreen> {
  final CardGradingService _grading = CardGradingService();
  final GradingPhotoCheckService _photoCheck = GradingPhotoCheckService();

  late final AppThemePalette _palette = AppThemePalette.forName(widget.theme);

  String? _frontPath;
  String? _backPath;
  GradingPhotoCheck? _frontCheck;
  GradingPhotoCheck? _backCheck;
  String? _error;
  bool _busy = false;
  bool _submitted = false;
  String? _requestId;
  int _elapsed = 0;
  Timer? _clock;
  Timer? _pollTimer;
  bool _polling = false;

  @override
  void dispose() {
    _clock?.cancel();
    _pollTimer?.cancel();
    _deleteTempFiles();
    super.dispose();
  }

  Future<void> _captureFront() async {
    await _captureSide('front');
  }

  Future<void> _captureBack() async {
    await _captureSide('back');
  }

  Future<void> _captureSide(String side) async {
    if (_busy) return;
    setState(() => _error = null);

    final cameraResult = await Navigator.push<CameraResult>(
      context,
      MaterialPageRoute(
        builder: (context) =>
            CameraScreen(captureOnly: true, theme: widget.theme),
      ),
    );
    if (cameraResult == null || !mounted) return;

    final path = cameraResult.path;
    GradingPhotoCheck check;
    try {
      check = await _photoCheck.check(path);
    } catch (e) {
      check = GradingPhotoCheck(
        ok: false,
        issues: ['Fotku sa nepodarilo skontrolovať: $e'],
        width: 0,
        height: 0,
        brightness: 0,
        sharpness: 0,
        glareRatio: 0,
      );
    }
    if (!mounted) return;

    final use = await _confirmPhoto(side, check);
    if (!mounted) return;
    if (!use) {
      await _deleteQuietly(path);
      return;
    }

    setState(() {
      if (side == 'front') {
        _frontPath = path;
        _frontCheck = check;
      } else {
        _backPath = path;
        _backCheck = check;
      }
    });

    if (side == 'front' && _backPath == null) {
      final next = await _askBackSide();
      if (next && mounted) {
        await _captureSide('back');
      }
    }
  }

  Future<bool> _confirmPhoto(String side, GradingPhotoCheck check) async {
    final title = side == 'front' ? 'Predná strana' : 'Zadná strana';
    if (check.ok) {
      if (!mounted) return false;
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: _palette.surface,
          title: Text('$title vyzerá dobre'),
          content: Text(
            'Fotka má ${check.width} × ${check.height} px. '
            'Pokračuj na ďalší krok.',
            style: TextStyle(color: _palette.muted),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Pokračovať'),
            ),
          ],
        ),
      );
      return proceed == true;
    }

    if (!mounted) return false;
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _palette.surface,
        title: Text('$title nemusí byť vhodná'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final issue in check.issues)
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 17,
                      color: _palette.accent,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        issue,
                        style: TextStyle(color: _palette.text, height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'use'),
            child: const Text('Použiť aj tak'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'retry'),
            child: const Text('Odfotiť znova'),
          ),
        ],
      ),
    );
    return action == 'use';
  }

  Future<bool> _askBackSide() async {
    if (!mounted) return false;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _palette.surface,
        title: const Text('Predná strana je hotová'),
        content: Text(
          'Otoč kartu a odfoť zadnú stranu. Na zadnej strane AI hodnotí '
          'hlavne rohy, okraje a povrch.',
          style: TextStyle(color: _palette.muted, height: 1.35),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Odfotiť zadnú'),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _submit() async {
    final front = _frontPath;
    final back = _backPath;
    if (front == null || back == null || _busy || _submitted) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final requestId = await _grading.submit(
        frontPath: front,
        backPath: back,
        cardId: widget.cardId,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _submitted = true;
        _requestId = requestId;
        _elapsed = 0;
      });
      _startPolling();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  void _startPolling() {
    _clock?.cancel();
    _pollTimer?.cancel();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed++);
    });
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _pollOnce();
    });
    _pollOnce();
  }

  Future<void> _pollOnce() async {
    final requestId = _requestId;
    if (_polling || requestId == null || !mounted) return;
    _polling = true;
    try {
      final result = await _grading.poll(requestId);
      if (!mounted) return;
      if (result != null) {
        _clock?.cancel();
        _pollTimer?.cancel();
        await _deleteTempFiles();
        if (!mounted) return;
        Navigator.pop(
          context,
          CardGradingOutcome(
            cardId: widget.cardId,
            requestId: requestId,
            result: result,
          ),
        );
        return;
      }
      if (_elapsed > 300) {
        _clock?.cancel();
        _pollTimer?.cancel();
        setState(() {
          _error = 'Hodnotenie trvá príliš dlho. Skús to neskôr alebo kartu odfoť znova.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      _clock?.cancel();
      _pollTimer?.cancel();
      setState(() => _error = e.toString());
    } finally {
      _polling = false;
    }
  }

  void _background() {
    if (_requestId == null) {
      Navigator.pop(
        context,
        CardGradingOutcome(cardId: widget.cardId, cancelled: true),
      );
      return;
    }
    Navigator.pop(
      context,
      CardGradingOutcome(
        cardId: widget.cardId,
        requestId: _requestId,
        background: true,
      ),
    );
  }

  Future<void> _close() async {
    if (_submitted && _requestId != null) {
      _background();
      return;
    }
    await _deleteTempFiles();
    if (mounted) {
      Navigator.pop(
        context,
        CardGradingOutcome(cardId: widget.cardId, cancelled: true),
      );
    }
  }

  Future<void> _deleteTempFiles() async {
    final paths = <String?>[_frontPath, _backPath];
    for (final path in paths) {
      if (path != null) await _deleteQuietly(path);
    }
  }

  Future<void> _deleteQuietly(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final canPop = !_submitted && !_busy;
    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_submitted) _background();
      },
      child: Scaffold(
        backgroundColor: _palette.background,
        appBar: AppBar(
          backgroundColor: _palette.surface,
          foregroundColor: _palette.text,
          title: const Text('Ohodnotenie karty'),
          leading: IconButton(
            onPressed: _close,
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Zavrieť',
          ),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
            children: [
              _header(),
              const SizedBox(height: 16),
              if (_submitted)
                _waitingPanel()
              else ...[
                _instructions(),
                const SizedBox(height: 14),
                _photoRow(),
                const SizedBox(height: 14),
                if (_error != null) _errorBox(_error!),
                if (_error != null) const SizedBox(height: 12),
                _submitButton(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: _palette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _palette.border),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: _palette.accentGradient),
            ),
            child: Icon(
              Icons.auto_awesome_rounded,
              color: _palette.onAccent,
              size: 23,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.cardName.isEmpty ? 'Karta' : widget.cardName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _palette.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Ximilar AI pre-grading · odhad, nie oficiálna známka',
                  style: TextStyle(color: _palette.muted, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _instructions() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _palette.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ako na to',
            style: TextStyle(
              color: _palette.text,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          for (final line in const [
            'Polož kartu na tmavú, rovnú podložku.',
            'Vyplň celý rám karty a vyhni sa odleskom.',
            'Odfoť najprv prednú, potom zadnú stranu.',
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.check_circle_outline_rounded,
                    size: 16,
                    color: _palette.success,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      line,
                      style: TextStyle(
                        color: _palette.muted,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _photoRow() {
    return Row(
      children: [
        Expanded(
          child: _photoCard(
            label: 'Predná strana',
            path: _frontPath,
            check: _frontCheck,
            onCapture: _captureFront,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _photoCard(
            label: 'Zadná strana',
            path: _backPath,
            check: _backCheck,
            onCapture: _captureBack,
          ),
        ),
      ],
    );
  }

  Widget _photoCard({
    required String label,
    required String? path,
    required GradingPhotoCheck? check,
    required VoidCallback onCapture,
  }) {
    final hasPhoto = path != null;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasPhoto
              ? _palette.success.withValues(alpha: 0.7)
              : _palette.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: _palette.text,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          AspectRatio(
            aspectRatio: 63 / 88,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: hasPhoto
                  ? Image.file(
                      File(path),
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.medium,
                    )
                  : Container(
                      color: _palette.surfaceAlt,
                      child: Icon(
                        Icons.add_a_photo_outlined,
                        color: _palette.muted,
                        size: 30,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 7),
          if (hasPhoto && check != null)
            Text(
              check.ok ? 'Fotka je v poriadku' : 'Skontroluj kvalitu',
              style: TextStyle(
                color: check.ok ? _palette.success : _palette.accent,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            )
          else
            Text(
              'Zatiaľ neodfotené',
              style: TextStyle(color: _palette.muted, fontSize: 10),
            ),
          const SizedBox(height: 7),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _busy ? null : onCapture,
              style: OutlinedButton.styleFrom(
                foregroundColor: _palette.text,
                side: BorderSide(color: _palette.border),
                padding: const EdgeInsets.symmetric(vertical: 9),
                textStyle: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: Text(hasPhoto ? 'Znova' : 'Odfotiť'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _submitButton() {
    final enabled = _frontPath != null && _backPath != null && !_busy;
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: enabled ? _submit : null,
        style: FilledButton.styleFrom(
          backgroundColor: _palette.accent,
          foregroundColor: _palette.onAccent,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        icon: _busy
            ? const SizedBox(
                width: 17,
                height: 17,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.auto_awesome_rounded, size: 19),
        label: Text(
          _busy ? 'Odosielam...' : 'Odoslať na ohodnotenie',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  Widget _waitingPanel() {
    final minutes = (_elapsed ~/ 60).toString().padLeft(2, '0');
    final seconds = (_elapsed % 60).toString().padLeft(2, '0');
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _palette.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _palette.border),
          ),
          child: Column(
            children: [
              SizedBox(
                width: 54,
                height: 54,
                child: CircularProgressIndicator(
                  strokeWidth: 4,
                  color: _palette.accent,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'AI hodnotí kartu',
                style: TextStyle(
                  color: _palette.text,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Zvyčajne to trvá 10–30 sekúnd. Môžeš počkať alebo appku '
                'nechať bežať na pozadí.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _palette.muted,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '$minutes:$seconds',
                style: TextStyle(
                  color: _palette.accent,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
        if (_error != null) ...[const SizedBox(height: 12), _errorBox(_error!)],
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _error == null ? _background : null,
            style: FilledButton.styleFrom(
              backgroundColor: _palette.accent,
              foregroundColor: _palette.onAccent,
              padding: const EdgeInsets.symmetric(vertical: 13),
            ),
            child: const Text(
              'Pokračovať na pozadí',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _error == null
              ? 'Keď bude hotovo, upozorníme ťa a ponúkneme Zobraziť hodnotenie.'
              : 'Skús to neskôr alebo kartu odfoť znova.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _palette.muted, fontSize: 11, height: 1.3),
        ),
      ],
    );
  }

  Widget _errorBox(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF3A1518),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF7F1D1D)),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: Color(0xFFFCA5A5),
          fontSize: 12,
          height: 1.35,
        ),
      ),
    );
  }
}
