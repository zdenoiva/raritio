import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:raritio/services/grading_token_service.dart';

class GradingException implements Exception {
  const GradingException(this.message);
  final String message;

  @override
  String toString() => message;
}

class GradingResult {
  const GradingResult({
    required this.grade,
    required this.condition,
    this.corners,
    this.edges,
    this.surface,
    this.centering,
    this.frontImageUrl,
    this.backImageUrl,
    this.provider = 'ximilar',
    this.gradedAt,
  });

  final double grade;
  final String condition;
  final double? corners;
  final double? edges;
  final double? surface;
  final double? centering;
  final String? frontImageUrl;
  final String? backImageUrl;
  final String provider;
  final DateTime? gradedAt;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'status': 'done',
      'grade': grade,
      'condition': condition,
      'corners': corners,
      'edges': edges,
      'surface': surface,
      'centering': centering,
      'frontImageUrl': frontImageUrl,
      'backImageUrl': backImageUrl,
      'provider': provider,
      'gradedAt': (gradedAt ?? DateTime.now()).toUtc().toIso8601String(),
    };
  }
}

class PendingGradingRequest {
  const PendingGradingRequest({
    required this.cardId,
    required this.requestId,
    required this.startedAt,
  });

  final String cardId;
  final String requestId;
  final DateTime startedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'cardId': cardId,
    'requestId': requestId,
    'startedAt': startedAt.toUtc().toIso8601String(),
  };

  factory PendingGradingRequest.fromJson(Map<String, dynamic> data) {
    return PendingGradingRequest(
      cardId: (data['cardId'] ?? '').toString(),
      requestId: (data['requestId'] ?? '').toString(),
      startedAt:
          DateTime.tryParse((data['startedAt'] ?? '').toString()) ??
          DateTime.now().toUtc(),
    );
  }
}

class CardGradingService {
  CardGradingService({GradingTokenService? tokens})
    : _tokens = tokens ?? GradingTokenService();

  static const String _submitUrl =
      'https://api.ximilar.com/account/v2/request/';
  static const String _requestUrl =
      'https://api.ximilar.com/account/v2/request';
  static const String _pendingKey = 'raritio_grading_pending_v1';
  static const Duration _maxPendingAge = Duration(minutes: 20);

  final GradingTokenService _tokens;
  final http.Client _client = http.Client();

  Future<bool> isConfigured() => _tokens.isConfigured();

  Future<String> submit({
    required String frontPath,
    required String backPath,
    required String cardId,
  }) async {
    final token = await _tokens.getToken();
    if (token.isEmpty) {
      throw const GradingException(
        'Chýba Ximilar API token. Vlož ho v Nastaveniach v časti AI ohodnotenie.',
      );
    }

    final front = await _encodeImage(frontPath);
    final back = await _encodeImage(backPath);
    if (front.isEmpty || back.isEmpty) {
      throw const GradingException(
        'Fotky sa nepodarilo pripraviť na odoslanie.',
      );
    }

    late http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse(_submitUrl),
            headers: <String, String>{
              'Authorization': 'Token $token',
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(<String, dynamic>{
              'type': 'card-grader',
              'endpoint': 'grade',
              'records': <Map<String, dynamic>>[
                <String, dynamic>{'_id': 'front', '_base64': front},
                <String, dynamic>{'_id': 'back', '_base64': back},
              ],
            }),
          )
          .timeout(const Duration(seconds: 90));
    } catch (e) {
      throw GradingException('Ximilar sa nepodarilo kontaktovať: $e');
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const GradingException(
        'Ximilar token nie je platný. Skontroluj ho v Nastaveniach.',
      );
    }
    if (response.statusCode == 402) {
      throw const GradingException(
        'Ximilar nemá dostatok kreditov. Free plán má 1 000 kreditov/mesiac a jedno hodnotenie stojí 100.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GradingException(
        'Ximilar vrátil chybu ${response.statusCode}. ${_shortError(response.body)}',
      );
    }

    final decoded = _jsonMap(response.body);
    final requestId = (decoded['id'] ?? '').toString().trim();
    if (requestId.isEmpty) {
      throw const GradingException('Ximilar nevrátil ID hodnotenia.');
    }

    await _savePending(
      PendingGradingRequest(
        cardId: cardId,
        requestId: requestId,
        startedAt: DateTime.now().toUtc(),
      ),
    );
    return requestId;
  }

  /// Returns null while Ximilar is still processing.
  Future<GradingResult?> poll(String requestId) async {
    final token = await _tokens.getToken();
    if (token.isEmpty) {
      throw const GradingException('Chýba Ximilar API token.');
    }

    late http.Response response;
    try {
      response = await _client
          .get(
            Uri.parse('$_requestUrl/$requestId'),
            headers: <String, String>{
              'Authorization': 'Token $token',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 30));
    } catch (e) {
      throw GradingException('Nepodarilo sa overiť stav hodnotenia: $e');
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const GradingException('Ximilar token už nie je platný.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GradingException(
        'Ximilar vrátil chybu ${response.statusCode}. ${_shortError(response.body)}',
      );
    }

    final decoded = _jsonMap(response.body);
    final status = (decoded['status'] ?? '').toString().toUpperCase();
    if (status != 'DONE') return null;

    final result = _parseResult(decoded);
    if (result != null) {
      await clearPending(requestId);
    }
    return result;
  }

  Future<List<PendingGradingRequest>> loadPending() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pendingKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final now = DateTime.now().toUtc();
      final result = <PendingGradingRequest>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final pending = PendingGradingRequest.fromJson(
          Map<String, dynamic>.from(item),
        );
        if (pending.cardId.isEmpty || pending.requestId.isEmpty) continue;
        if (now.difference(pending.startedAt) > _maxPendingAge) continue;
        result.add(pending);
      }
      return result;
    } catch (_) {
      return const [];
    }
  }

  Future<void> clearPending(String requestId) async {
    final pending = await loadPending();
    final remaining = pending
        .where((item) => item.requestId != requestId)
        .toList(growable: false);
    final prefs = await SharedPreferences.getInstance();
    if (remaining.isEmpty) {
      await prefs.remove(_pendingKey);
    } else {
      await prefs.setString(
        _pendingKey,
        jsonEncode(remaining.map((item) => item.toJson()).toList()),
      );
    }
  }

  Future<void> _savePending(PendingGradingRequest request) async {
    final pending = await loadPending();
    final merged = <String, PendingGradingRequest>{
      for (final item in pending) item.requestId: item,
      request.requestId: request,
    };
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _pendingKey,
      jsonEncode(merged.values.map((item) => item.toJson()).toList()),
    );
  }

  Future<String> _encodeImage(String path) async {
    final bytes = await File(path).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return base64Encode(bytes);

    var image = img.bakeOrientation(decoded);
    final longest = math.max(image.width, image.height);
    // Ximilar recommends roughly 2,000 px on the shorter side. A 2,600 px
    // longest side keeps uploads fast while preserving corner/edge detail.
    if (longest > 2600) {
      image = img.copyResize(
        image,
        width: image.width >= image.height ? 2600 : null,
        height: image.height > image.width ? 2600 : null,
        interpolation: img.Interpolation.average,
      );
    }
    return base64Encode(img.encodeJpg(image, quality: 92));
  }

  GradingResult? _parseResult(Map<String, dynamic> response) {
    final responseData = response['response'];
    if (responseData is! Map) return null;
    final rawRecords = responseData['records'];
    if (rawRecords is! List || rawRecords.isEmpty) return null;

    final records = rawRecords
        .whereType<Map>()
        .map((record) => Map<String, dynamic>.from(record))
        .toList(growable: false);
    if (records.isEmpty) return null;

    final front = _recordForSide(records, 'front') ?? records.first;
    final back =
        _recordForSide(records, 'back') ??
        (records.length > 1 ? records[1] : null);

    double? component(Map<String, dynamic>? record, String key) {
      final grades = record?['grades'];
      if (grades is! Map) return null;
      return _number(grades[key]);
    }

    double? combined(String key) {
      final a = component(front, key);
      final b = component(back, key);
      if (a != null && b != null) return a * 0.7 + b * 0.3;
      return a ?? b;
    }

    final grade = combined('final');
    if (grade == null || grade <= 0) return null;

    String? condition(Map<String, dynamic>? record) {
      final grades = record?['grades'];
      if (grades is! Map) return null;
      final value = (grades['condition'] ?? '').toString().trim();
      return value.isEmpty ? null : value;
    }

    return GradingResult(
      grade: _round(grade),
      condition:
          condition(front) ?? condition(back) ?? _conditionForGrade(grade),
      corners: _roundOrNull(combined('corners')),
      edges: _roundOrNull(combined('edges')),
      surface: _roundOrNull(combined('surface')),
      centering: _roundOrNull(combined('centering')),
      frontImageUrl: (front['_full_url_card'] ?? front['_exact_url_card'])
          ?.toString(),
      backImageUrl: (back?['_full_url_card'] ?? back?['_exact_url_card'])
          ?.toString(),
      gradedAt: DateTime.now().toUtc(),
      provider: 'ximilar',
    );
  }

  Map<String, dynamic>? _recordForSide(
    List<Map<String, dynamic>> records,
    String side,
  ) {
    for (final record in records) {
      final card = record['card'];
      if (card is List && card.isNotEmpty && card.first is Map) {
        final tags = (card.first as Map)['_tags'];
        if (tags is Map) {
          final sideTag = tags['Side'];
          if (sideTag is List && sideTag.isNotEmpty && sideTag.first is Map) {
            final name = ((sideTag.first as Map)['name'] ?? '')
                .toString()
                .toLowerCase();
            if (name == side) return record;
          }
        }
      }
    }
    return null;
  }

  String _conditionForGrade(double grade) {
    if (grade >= 9.5) return 'Gem Mint';
    if (grade >= 9) return 'Mint';
    if (grade >= 8) return 'Near Mint';
    if (grade >= 7) return 'Excellent';
    if (grade >= 5.5) return 'Very Good';
    if (grade >= 4) return 'Good';
    if (grade >= 2.5) return 'Fair';
    return 'Poor';
  }

  double? _number(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  double _round(double value) => (value * 10).round() / 10;

  double? _roundOrNull(double? value) =>
      value == null ? null : (value * 10).round() / 10;

  Map<String, dynamic> _jsonMap(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return const <String, dynamic>{};
  }

  String _shortError(String body) {
    final decoded = _jsonMap(body);
    final detail = decoded['detail'] ?? decoded['message'] ?? decoded['error'];
    final text = detail?.toString().trim() ?? '';
    if (text.isEmpty) return '';
    return text.length > 180 ? '${text.substring(0, 180)}…' : text;
  }
}
