import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' hide appBuildNumber;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:raritio/app_version.dart';
import 'package:raritio/config/supabase_config.dart';
import 'package:raritio/screens/camera_screen.dart';
import 'package:raritio/screens/shared_binder_detail_screen.dart';
import 'package:raritio/screens/shared_binders_screen.dart';
import 'package:raritio/services/bridge_service.dart';
import 'package:raritio/services/card_service.dart';
import 'package:raritio/services/custom_card_image_service.dart';
import 'package:raritio/services/price_charting_service.dart';
import 'package:raritio/services/price_service.dart';
import 'package:raritio/services/search_query_expander.dart';
import 'package:raritio/services/shared_binder_service.dart';
import 'package:raritio/services/state_service.dart';
import 'package:raritio/services/update_service.dart';
import 'package:raritio/widgets/share_binder_sheet.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.black,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.anonKey,
  );
  runApp(MaterialApp(
    title: 'Raritio',
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(useMaterial3: true).copyWith(
      scaffoldBackgroundColor: const Color(0xFF0A0A0C),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF3B82F6),
        secondary: Color(0xFF8B5CF6),
        surface: Color(0xFF16161A),
        error: Color(0xFFEF4444),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: Color(0xFF16161A),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: Color(0xFF1E1E24),
        contentTextStyle: TextStyle(color: Color(0xFFF8FAFC)),
      ),
    ),
    home: const RaritioTCG(),
  ));
}

class RaritioTCG extends StatefulWidget {
  const RaritioTCG({super.key});

  @override
  State<RaritioTCG> createState() => _RaritioTCGState();
}

class _RaritioTCGState extends State<RaritioTCG> {
  late final WebViewController _controller;
  final BridgeService _bridge = BridgeService();
  final PriceService _priceService = PriceService();
  final CardService _cardService = CardService();
  final PriceChartingService _priceChartingService = PriceChartingService();
  final StateService _stateService = StateService();
  final CustomCardImageService _customCardImageService =
      CustomCardImageService();
  final UpdateService _updateService = UpdateService();
  final SharedBinderService _sharedBinderService = SharedBinderService();
  bool _updateCheckStarted = false;
  bool _sharedScreenOpen = false;
  StreamSubscription<Uri>? _linkSubscription;
  String _lastHandledLink = '';

  final List<Map<String, dynamic>> _priceQueue = [];
  bool _priceWorkerRunning = false;
  Future<void> _stateWriteChain = Future.value();

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => _hydrateStateFromDisk(),
        ),
      )
      ..addJavaScriptChannel(
        'flutterBridge',
        onMessageReceived: (JavaScriptMessage message) {
          _handleMessage(message.message);
        },
      )
      ..loadFlutterAsset('assets/web_assets/index.html');
    unawaited(_initDeepLinks());
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  void _handleMessage(String message) {
    if (message.startsWith('scanCard:')) {
      _handleScanAction();
    } else if (message.startsWith('searchCards:')) {
      _handleSearchCards(message);
    } else if (message.startsWith('cardDetails:')) {
      _handleCardDetails(message);
    } else if (message.startsWith('reloadCardImage:')) {
      _handleReloadCardImage(message);
    } else if (message.startsWith('captureCardPhoto:')) {
      _handleCaptureCardPhoto(message);
    } else if (message.startsWith('openShared:')) {
      unawaited(_openSharedScreen());
    } else if (message.startsWith('shareBinder:')) {
      unawaited(_handleShareBinder(message));
    } else if (message.startsWith('sharedSync:')) {
      unawaited(_handleSharedSync(message));
    } else if (message.startsWith('stopShared:')) {
      unawaited(_handleStopShared(message));
    } else if (message.startsWith('fetchPrice:')) {
      _handleFetchPrice(message);
    } else if (message.startsWith('fetchPriceCharting:')) {
      _handleFetchPriceCharting(message);
    } else if (message.startsWith('saveState:')) {
      _handleSaveState(message);
    } else if (message.startsWith('backupState:')) {
      _handleBackupState(message);
    } else if (message.startsWith('autoBackup:')) {
      _handleAutoBackup(message);
    } else if (message.startsWith('restoreState:')) {
      _handleRestoreState();
    }
  }

  Future<void> _hydrateStateFromDisk() async {
    _controller.runJavaScript(
      'setAppVersion(${jsonEncode(appVersion)})',
    );
    try {
      // Let any pending save finish before reading, so a page reload never
      // restores an older snapshot.
      await _stateWriteChain;
      final state = await _stateService.loadState();
      _controller.runJavaScript('hydrateState(${jsonEncode(state)})');
    } catch (e) {
      print('State load error: $e');
      _controller.runJavaScript('hydrateState(null)');
    }
    unawaited(_maybeCheckForUpdates());
  }

  Future<void> _maybeCheckForUpdates() async {
    if (_updateCheckStarted) return;
    _updateCheckStarted = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getInt('raritio_last_update_check') ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - last < const Duration(hours: 24).inMilliseconds) return;
      await prefs.setInt('raritio_last_update_check', now);

      final info = await _updateService.check();
      if (!mounted || info == null || info.versionCode <= appBuildNumber) {
        return;
      }
      await _showUpdateDialog(info);
    } catch (_) {
      // Update checks must never block the app.
    }
  }

  Future<void> _showUpdateDialog(UpdateInfo info) async {
    if (!mounted) return;
    final changelog = info.changelog.isEmpty
        ? const ['Menšie opravy a vylepšenia.']
        : info.changelog;
    final sizeText = info.size > 0
        ? '${(info.size / (1024 * 1024)).toStringAsFixed(1)} MB'
        : '';

    final shouldDownload = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Nová verzia ${info.version}'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 360),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (sizeText.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      'Veľkosť: $sizeText',
                      style: const TextStyle(color: Color(0xFF94A3B8)),
                    ),
                  ),
                ...changelog.map((line) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('•  '),
                          Expanded(child: Text(line)),
                        ],
                      ),
                    )),
                const SizedBox(height: 8),
                const Text(
                  'Android ešte vyžiada potvrdenie inštalácie. Ak je to potrebné, povoľ Rariťiu inštaláciu neznámych aplikácií.',
                  style: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Neskôr'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Stiahnuť a nainštalovať'),
          ),
        ],
      ),
    );

    if (shouldDownload == true) {
      await _downloadAndInstallUpdate(info);
    }
  }

  Future<void> _downloadAndInstallUpdate(UpdateInfo info) async {
    if (!mounted) return;
    final progress = ValueNotifier<double>(0);
    final received = ValueNotifier<int>(0);
    var dialogOpen = true;

    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text('Sťahujem Raritio ${info.version}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ValueListenableBuilder<double>(
                valueListenable: progress,
                builder: (context, value, child) => LinearProgressIndicator(
                  value: value <= 0 ? null : value,
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 12),
              ValueListenableBuilder<int>(
                valueListenable: received,
                builder: (context, value, child) => Text(
                  '${(value / (1024 * 1024)).toStringAsFixed(1)} MB'
                  '${info.size > 0 ? ' / ${(info.size / (1024 * 1024)).toStringAsFixed(1)} MB' : ''}',
                  style: const TextStyle(color: Color(0xFF94A3B8)),
                ),
              ),
            ],
          ),
        ),
      ),
    ));

    try {
      final file = await _updateService.download(
        info,
        onProgress: (value, bytes, total) {
          progress.value = value.clamp(0, 1).toDouble();
          received.value = bytes;
        },
      );
      if (mounted && dialogOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        dialogOpen = false;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Otváram inštalátor aktualizácie...')),
      );
      await _updateService.install(file);
    } catch (e) {
      if (mounted && dialogOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        dialogOpen = false;
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Aktualizáciu sa nepodarilo stiahnuť'),
          content: Text('$e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Zavrieť'),
            ),
          ],
        ),
      );
    } finally {
      progress.dispose();
      received.dispose();
    }
  }

  Future<void> _handleScanAction() async {
    try {
      final String? imagePath = await Navigator.push<String>(
        context,
        MaterialPageRoute(builder: (context) => CameraScreen()),
      );

      if (imagePath == null) {
        // The user closed the camera without taking a photo.
        _controller.runJavaScript('isScanning = false');
        return;
      }

      final result = await _bridge.scanImagePath(imagePath);
      if (result == null) {
        _controller.runJavaScript(
            'showError(${jsonEncode("Nepodarilo sa rozpoznať text. Skús kartu odfotiť znovu.")})');
        return;
      }

      final error = result['error'];
      if (error is String && error.isNotEmpty) {
        _controller.runJavaScript('showError(${jsonEncode(error)})');
      } else {
        _controller.runJavaScript('handleScanResult(${jsonEncode(result)})');
      }
    } catch (e) {
      _controller.runJavaScript('showError(${jsonEncode("Chyba kamery: $e")})');
    }
  }

  Future<void> _handleSearchCards(String message) async {
    dynamic requestId;
    try {
      final payload = message.substring('searchCards:'.length).trim();
      var query = payload;
      var fromOcr = false;
      var requestedLanguage = 'auto';

      if (payload.startsWith('{')) {
        final data = jsonDecode(payload);
        if (data is Map) {
          query = (data['query'] as String? ?? '').trim();
          fromOcr = data['ocr'] == true;
          requestId = data['requestId'];
          requestedLanguage =
              (data['language']?.toString() ?? 'auto').trim().toLowerCase();
        }
      }

      if (query.isEmpty) {
        _controller.runJavaScript(
            'handleSearchResults([], ${jsonEncode(query)}, ${jsonEncode(requestId)})');
        return;
      }

      final language = _resolveSearchLanguage(query, requestedLanguage);
      final variants = SearchQueryExpander.expand(
        query,
        maxVariants: fromOcr ? 10 : 6,
      );

      var usedQuery = query;
      var results = <Map<String, dynamic>>[];

      // English cards are searched in TCGdex and Scryfall in parallel. For
      // Japanese/Chinese text, MTG is skipped and the other CJK language is
      // used as a fallback in case the script detector picked the wrong one.
      final cjkLanguages = language == 'ja'
          ? const <String>['ja', 'zh-cn']
          : const <String>['zh-cn', 'ja'];

      for (final variant in variants) {
        if (language == 'en') {
          final searches = await Future.wait([
            _cardService.searchPokemon(variant),
            _cardService.searchMtg(variant),
          ]);
          final combined = <Map<String, dynamic>>[
            ...searches[0],
            ...searches[1],
          ];
          if (combined.isNotEmpty) {
            results = combined;
            usedQuery = variant;
            break;
          }
        } else {
          for (final searchLanguage in cjkLanguages) {
            final found = await _cardService.searchPokemon(
              variant,
              language: searchLanguage,
            );
            if (found.isNotEmpty) {
              results = found;
              usedQuery = variant;
              break;
            }
          }
          if (results.isNotEmpty) break;
        }
      }

      _controller.runJavaScript(
          'handleSearchResults(${jsonEncode(results)}, ${jsonEncode(usedQuery)}, ${jsonEncode(requestId)})');
    } catch (e) {
      print("Search error: $e");
      _controller.runJavaScript(
          'handleSearchResults([], ${jsonEncode(null)}, ${jsonEncode(requestId)})');
    }
  }

  String _detectLanguage(String query) {
    if (RegExp(r'[\u3040-\u30ff]').hasMatch(query)) return 'ja';
    if (RegExp(r'[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]').hasMatch(query)) {
      return 'zh-cn';
    }
    return 'en';
  }

  /// Trusts the script actually found in the OCR text. Han-only text can be
  /// either Chinese or Japanese, so an explicit Japanese request is kept.
  String _resolveSearchLanguage(String query, String requested) {
    final detected = _detectLanguage(query);
    if (detected == 'en') return 'en';
    if (detected == 'ja') return 'ja';
    if (requested == 'ja') return 'ja';
    return 'zh-cn';
  }

  Future<void> _handleCardDetails(String message) async {
    try {
      final payload = message.substring('cardDetails:'.length).trim();
      var game = '';
      var id = '';
      var language = 'en';

      if (payload.startsWith('{')) {
        final data = jsonDecode(payload);
        if (data is Map) {
          game = (data['game'] as String? ?? '').trim();
          id = (data['id'] as String? ?? '').trim();
          language = (data['language'] as String? ?? 'en').trim();
        }
      } else {
        // Backward-compatible "game:id" form.
        final parts = payload.split(':');
        game = parts.length > 1 ? parts[1] : '';
        id = parts.length > 2 ? parts.sublist(2).join(':') : '';
      }

      Map<String, dynamic>? details;
      if (game == 'pokemon') {
        details = await _cardService.getPokemonDetails(id, language: language);
      }

      if (details != null) {
        _controller.runJavaScript('handleCardDetails(${jsonEncode(details)})');
      } else {
        _controller.runJavaScript('handleCardDetailsError(${jsonEncode(id)})');
      }
    } catch (e) {
      print("Card detail error: $e");
    }
  }

  Future<void> _handleReloadCardImage(String message) async {
    String cardId = '';
    try {
      final payload = message.substring('reloadCardImage:'.length).trim();
      final data = jsonDecode(payload);
      if (data is! Map) return;

      cardId = (data['id'] as String? ?? '').trim();
      if (cardId.isEmpty) return;

      final game = (data['game'] as String? ?? 'pokemon').trim().toLowerCase();
      final language = (data['language'] as String? ?? 'en').trim();
      String? imageUri;

      if (game == 'mtg') {
        imageUri = await _cardService.getMtgImage(cardId);
      } else {
        final details = await _cardService.getPokemonDetails(
          cardId,
          language: language,
        );
        imageUri = details?['imageUri'] as String?;
      }

      if (imageUri != null && imageUri.isNotEmpty) {
        _controller.runJavaScript(
          'handleCardImageReload(${jsonEncode(cardId)}, ${jsonEncode(imageUri)})',
        );
      } else {
        _controller.runJavaScript(
          'handleCardImageReloadError(${jsonEncode(cardId)})',
        );
      }
    } catch (e) {
      print('Card image reload error: $e');
      if (cardId.isNotEmpty) {
        _controller.runJavaScript(
          'handleCardImageReloadError(${jsonEncode(cardId)})',
        );
      }
    }
  }

  Future<void> _handleCaptureCardPhoto(String message) async {
    String cardId = '';
    try {
      final payload = message.substring('captureCardPhoto:'.length).trim();
      final data = jsonDecode(payload);
      if (data is! Map) return;

      cardId = (data['id'] as String? ?? '').trim();
      if (cardId.isEmpty) return;

      final String? imagePath = await Navigator.push<String>(
        context,
        MaterialPageRoute(builder: (context) => const CameraScreen()),
      );

      if (imagePath == null) {
        _controller.runJavaScript(
          'handleCustomCardImageCancelled(${jsonEncode(cardId)})',
        );
        return;
      }

      _controller.runJavaScript(
        'handleCustomCardImageProcessing(${jsonEncode(cardId)})',
      );
      final dataUri =
          await _customCardImageService.prepareFromFile(imagePath);
      try {
        await File(imagePath).delete();
      } catch (_) {
        // The camera cache is cleaned up by the OS if this fails.
      }

      if (dataUri == null || dataUri.isEmpty) {
        _controller.runJavaScript(
          'handleCustomCardImageError(${jsonEncode(cardId)})',
        );
        return;
      }

      _controller.runJavaScript(
        'handleCustomCardImage(${jsonEncode(cardId)}, ${jsonEncode(dataUri)})',
      );
    } catch (e) {
      print('Custom card photo error: $e');
      if (cardId.isNotEmpty) {
        _controller.runJavaScript(
          'handleCustomCardImageError(${jsonEncode(cardId)})',
        );
      }
    }
  }

  Future<void> _openSharedScreen() async {
    if (_sharedScreenOpen || !mounted) return;
    _sharedScreenOpen = true;
    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SharedBindersScreen(
            service: _sharedBinderService,
          ),
        ),
      );
    } finally {
      _sharedScreenOpen = false;
      if (mounted) _controller.runJavaScript("updateNav('nav-binder')");
    }
  }

  Future<void> _handleShareBinder(String message) async {
    try {
      final payload = message.substring('shareBinder:'.length).trim();
      final decoded = jsonDecode(payload);
      if (decoded is! Map) return;
      final data = Map<String, dynamic>.from(decoded);
      final localId = (data['localId'] ?? '').toString().trim();
      final sharedId = (data['sharedId'] ?? '').toString().trim();
      final token = (data['token'] ?? '').toString().trim();
      final name = (data['name'] ?? 'Balík').toString().trim();
      final snapshot = data['snapshot'] is Map
          ? Map<String, dynamic>.from(data['snapshot'] as Map)
          : <String, dynamic>{};
      final cardCount =
          int.tryParse(data['cardCount']?.toString() ?? '') ?? 0;
      final totalValue =
          double.tryParse(data['totalValue']?.toString() ?? '') ?? 0.0;

      final summary = await _sharedBinderService.shareBinder(
        sharedId: sharedId.isEmpty ? null : sharedId,
        name: name.isEmpty ? 'Balík' : name,
        snapshot: snapshot,
        cardCount: cardCount,
        totalValue: totalValue,
        existingToken: token.isEmpty ? null : token,
      );

      if (!mounted) return;
      _controller.runJavaScript(
        'handleShareBinderResult(${jsonEncode({
              'localId': localId,
              'id': summary.id,
              'token': summary.shareToken,
            })})',
      );
      _controller.runJavaScript('closeBinderActions()');

      final stopped = await showShareBinderSheet(
        context,
        summary: summary,
        service: _sharedBinderService,
      );
      if (stopped == true && mounted) {
        _controller.runJavaScript(
          'handleSharedStopped(${jsonEncode(summary.id)})',
        );
      }
    } catch (e) {
      final message = e.toString().replaceFirst('Exception: ', '');
      if (mounted) {
        _controller.runJavaScript(
          'handleSharedError(${jsonEncode(message)})',
        );
      }
    }
  }

  Future<void> _handleSharedSync(String message) async {
    try {
      final payload = message.substring('sharedSync:'.length).trim();
      final decoded = jsonDecode(payload);
      if (decoded is! Map) return;
      final binders = decoded['binders'];
      if (binders is! List) return;

      for (final raw in binders) {
        if (raw is! Map) continue;
        final item = Map<String, dynamic>.from(raw);
        final id = (item['id'] ?? '').toString().trim();
        if (id.isEmpty) continue;
        final snapshot = item['snapshot'] is Map
            ? Map<String, dynamic>.from(item['snapshot'] as Map)
            : <String, dynamic>{};
        await _sharedBinderService.syncSharedBinder(
          sharedId: id,
          name: (item['name'] ?? 'Balík').toString(),
          snapshot: snapshot,
          cardCount: int.tryParse(item['cardCount']?.toString() ?? '') ?? 0,
          totalValue:
              double.tryParse(item['totalValue']?.toString() ?? '') ?? 0.0,
        );
      }
    } catch (_) {
      // A shared snapshot sync is best-effort; the next state change retries.
    }
  }

  Future<void> _handleStopShared(String message) async {
    try {
      final payload = message.substring('stopShared:'.length).trim();
      final decoded = jsonDecode(payload);
      if (decoded is! Map) return;
      final id = (decoded['id'] ?? '').toString().trim();
      if (id.isEmpty) return;
      await _sharedBinderService.stopSharing(id);
    } catch (_) {
      // Deleting a local binder must succeed even when the network is down.
    }
  }

  Future<void> _initDeepLinks() async {
    try {
      final appLinks = AppLinks();
      _linkSubscription = appLinks.uriLinkStream.listen(
        (uri) => unawaited(_handleDeepLink(uri)),
        onError: (_) {},
      );
      final initial = await appLinks.getInitialLink();
      if (initial != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(_handleDeepLink(initial));
        });
      }
    } catch (_) {
      // Deep links are optional; QR scanning inside the app still works.
    }
  }

  Future<void> _handleDeepLink(Uri uri) async {
    if (uri.scheme != 'raritio') return;
    final key = uri.toString();
    if (key == _lastHandledLink) return;
    _lastHandledLink = key;

    try {
      if (uri.host == 'share') {
        final token =
            uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '';
        if (token.isEmpty) return;
        final data = await _sharedBinderService.acceptShareToken(token);
        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SharedBinderDetailScreen(
              service: _sharedBinderService,
              summary: data.summary,
            ),
          ),
        );
        return;
      }

      if (uri.host == 'friend') {
        final code =
            uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '';
        if (code.isEmpty) return;
        final friend = await _sharedBinderService.addFriendByCode(code);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kamoš ${friend.nickname} je pridaný.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  void _handleFetchPrice(String message) {
    try {
      final data = jsonDecode(message.substring('fetchPrice:'.length));
      if (data is Map) {
        _priceQueue.add(Map<String, dynamic>.from(data));
        _processPriceQueue();
      }
    } catch (e) {
      print("Invalid price request: $e");
    }
  }

  /// Prices are fetched one by one so a large binder does not flood the APIs.
  Future<void> _processPriceQueue() async {
    if (_priceWorkerRunning) return;
    _priceWorkerRunning = true;

    var success = 0;
    var failed = 0;

    while (_priceQueue.isNotEmpty) {
      final data = _priceQueue.removeAt(0);
      final ok = await _fetchAndSendPrice(data);
      if (ok) {
        success++;
      } else {
        failed++;
      }
      await Future.delayed(const Duration(milliseconds: 120));
    }

    _priceWorkerRunning = false;

    // A new request may have arrived while the last one was finishing.
    if (_priceQueue.isNotEmpty) {
      _processPriceQueue();
      return;
    }

    if (success + failed > 0) {
      _controller.runJavaScript('onPriceRefreshFinished($success, $failed)');
    }
  }

  Future<bool> _fetchAndSendPrice(Map<String, dynamic> data) async {
    try {
      final cardId = data['id'] as String? ?? '';
      final game = data['game'] as String? ?? '';
      final cardName = data['name'] as String? ?? '';
      final source = data['source'] as String? ?? 'tcgdex';
      final language = data['language'] as String? ?? 'en';
      final set = data['set'] as String? ?? '';
      final number = data['number'] as String? ?? '';
      final existingUrl = data['priceChartingUrl'] as String? ?? '';

      if (cardId.isEmpty) return false;

      double price = 0.0;
      if (game == 'pokemon') {
        price = await _priceService.getPokemonPrice(
          cardId,
          source: source,
          language: language,
        );
      } else {
        price = await _priceService.getMtgPrice(cardName);
      }

      if (price > 0) {
        _controller.runJavaScript(
            'updatePriceInUI(${jsonEncode(cardId)}, $price, '
            '${jsonEncode(language)}, ${jsonEncode(game)})');
        return true;
      }

      // A missing standard price is exactly where PriceCharting helps most.
      // Japanese/Chinese names are skipped because they are not indexed there.
      if (cardName.isNotEmpty && RegExp(r'[A-Za-z]').hasMatch(cardName)) {
        final fallback = await _priceChartingService.fetchForCard(
          name: cardName,
          set: set,
          number: number,
          game: game,
          language: language,
          existingUrl: existingUrl,
        );
        if (fallback != null) {
          _controller.runJavaScript(
              'handlePriceCharting(${jsonEncode(cardId)}, '
              '${jsonEncode(fallback)}, ${jsonEncode(language)}, '
              '${jsonEncode(game)})');
          final hasPrice = (fallback['price'] as num? ?? 0) > 0;
          final hasGrades =
              (fallback['gradePrices'] as List?)?.isNotEmpty ?? false;
          return hasPrice || hasGrades;
        }
      }
      return false;
    } catch (e) {
      print("Error fetching price: $e");
      return false;
    }
  }

  Future<void> _handleFetchPriceCharting(String message) async {
    String cardId = '';
    String language = 'en';
    String game = 'pokemon';
    try {
      final payload = message.substring('fetchPriceCharting:'.length).trim();
      final data = jsonDecode(payload);
      if (data is! Map) return;

      cardId = (data['id'] as String? ?? '').trim();
      if (cardId.isEmpty) return;
      game = (data['game'] as String? ?? 'pokemon').trim();
      language = (data['language'] as String? ?? 'en').trim();

      final result = await _priceChartingService.fetchForCard(
        name: (data['name'] as String? ?? '').trim(),
        set: (data['set'] as String? ?? '').trim(),
        number: (data['number'] as String? ?? '').trim(),
        game: game,
        language: language,
        existingUrl: (data['priceChartingUrl'] as String? ?? '').trim(),
      );

      if (result == null) {
        _controller.runJavaScript(
            'handlePriceChartingError(${jsonEncode(cardId)}, '
            '${jsonEncode(language)}, ${jsonEncode(game)})');
      } else {
        _controller.runJavaScript(
            'handlePriceCharting(${jsonEncode(cardId)}, '
            '${jsonEncode(result)}, ${jsonEncode(language)}, '
            '${jsonEncode(game)})');
      }
    } catch (e) {
      print("PriceCharting error: $e");
      if (cardId.isNotEmpty) {
        _controller.runJavaScript(
            'handlePriceChartingError(${jsonEncode(cardId)}, '
            '${jsonEncode(language)}, ${jsonEncode(game)})');
      }
    }
  }

  void _handleSaveState(String message) {
    try {
      final json = message.substring('saveState:'.length);
      jsonDecode(json); // validate before writing

      _stateWriteChain = _stateWriteChain.then((_) {
        return _stateService.saveState(json);
      }).catchError((Object error) {
        print('State save error: $error');
      });
    } catch (e) {
      print("Invalid state payload: $e");
    }
  }

  Future<void> _handleBackupState(String message) async {
    try {
      final stateJson = message.substring('backupState:'.length);
      jsonDecode(stateJson); // validate before wrapping

      final backup = _stateService.createBackup(stateJson);
      final file = await _stateService.saveBackup(backup);
      final statusMessage =
          'Záloha uložená: ${p.basename(file.path)}\n${file.path}';
      _controller.runJavaScript(
          'onBackupResult(true, ${jsonEncode(statusMessage)})');
    } catch (e) {
      print("Backup error: $e");
      _controller.runJavaScript(
          'onBackupResult(false, ${jsonEncode("Zálohu sa nepodarilo uložiť: $e")})');
    }
  }

  Future<void> _handleAutoBackup(String message) async {
    try {
      final stateJson = message.substring('autoBackup:'.length);
      jsonDecode(stateJson); // validate before wrapping
      final backup = _stateService.createBackup(stateJson);
      final file = await _stateService.ensureDailyBackup(backup);
      if (file != null) {
        print('Automatic backup: ${file.path}');
      }
    } catch (e) {
      print('Automatic backup error: $e');
    }
  }

  Future<void> _handleRestoreState() async {
    try {
      final picked = await FilePicker.pickFile(
        dialogTitle: 'Vybrať zálohu Raritio',
        type: FileType.any,
      );

      if (picked == null) {
        _controller.runJavaScript(
            'onRestoreResult(false, ${jsonEncode("Obnova bola zrušená.")})');
        return;
      }

      final bytes = await picked.readAsBytes();
      final content = utf8.decode(bytes);
      final state = _stateService.extractState(content);

      if (state == null) {
        _controller.runJavaScript(
            'onRestoreResult(false, ${jsonEncode("Vybraný súbor nie je platná záloha Raritio.")})');
        return;
      }

      final stateJson = jsonEncode(state);

      // Write the restored state before the web app switches to it.
      _stateWriteChain = _stateWriteChain.then((_) {
        return _stateService.saveState(stateJson);
      });
      await _stateWriteChain;

      _controller.runJavaScript('hydrateState(${jsonEncode(state)}, true)');
    } catch (e) {
      print("Restore error: $e");
      _controller.runJavaScript(
          'onRestoreResult(false, ${jsonEncode("Obnovu sa nepodarilo dokončiť: $e")})');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: WebViewWidget(controller: _controller),
      ),
    );
  }
}

