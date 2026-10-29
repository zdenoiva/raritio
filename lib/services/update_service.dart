import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:apk_sideload/install_apk.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.versionCode,
    required this.apkUrl,
    required this.sha256,
    required this.changelog,
    this.size = 0,
    this.publishedAt = '',
  });

  final String version;
  final int versionCode;
  final String apkUrl;
  final String sha256;
  final List<String> changelog;
  final int size;
  final String publishedAt;

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    final rawChangelog = json['changelog'];
    final changelog = <String>[];
    if (rawChangelog is List) {
      for (final item in rawChangelog) {
        final text = item?.toString().trim() ?? '';
        if (text.isNotEmpty) changelog.add(text);
      }
    } else if (rawChangelog is String) {
      for (final line in rawChangelog.split('\n')) {
        final text = line.replaceFirst(RegExp(r'^\s*[-*]\s*'), '').trim();
        if (text.isNotEmpty) changelog.add(text);
      }
    }

    return UpdateInfo(
      version: (json['version'] ?? '').toString().trim(),
      versionCode: int.tryParse((json['versionCode'] ?? '').toString()) ?? 0,
      apkUrl: (json['apkUrl'] ?? '').toString().trim(),
      sha256: (json['sha256'] ?? '').toString().trim().toLowerCase(),
      changelog: changelog,
      size: int.tryParse((json['size'] ?? '').toString()) ?? 0,
      publishedAt: (json['publishedAt'] ?? '').toString().trim(),
    );
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) {
    value = data;
  }

  @override
  void close() {}
}

class UpdateService {
  static const String latestJsonUrl =
      'https://raw.githubusercontent.com/zdenoiva/raritio/main/latest.json';

  Future<UpdateInfo?> check() async {
    try {
      final response = await http.get(
        Uri.parse('$latestJsonUrl?t=${DateTime.now().millisecondsSinceEpoch}'),
        headers: const {'Cache-Control': 'no-cache'},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;

      final info = UpdateInfo.fromJson(Map<String, dynamic>.from(decoded));
      if (info.version.isEmpty ||
          info.versionCode <= 0 ||
          info.apkUrl.isEmpty ||
          info.sha256.isEmpty) {
        return null;
      }
      return info;
    } catch (_) {
      return null;
    }
  }

  Future<File> download(
    UpdateInfo info, {
    void Function(double progress, int received, int total)? onProgress,
  }) async {
    final client = http.Client();
    final digestSink = _DigestSink();
    final digestInput = sha256.startChunkedConversion(digestSink);
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'raritio-update-${info.version}.apk'));

    if (await file.exists()) {
      await file.delete();
    }

    try {
      final request = http.Request('GET', Uri.parse(info.apkUrl));
      final response = await client.send(request);
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}');
      }

      final total = response.contentLength ?? info.size;
      var received = 0;
      final sink = file.openWrite();
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          digestInput.add(chunk);
          received += chunk.length;
          if (total > 0) {
            onProgress?.call(received / total, received, total);
          }
        }
      } finally {
        await sink.flush();
        await sink.close();
      }
      digestInput.close();

      final actual = digestSink.value?.toString().toLowerCase() ?? '';
      if (actual != info.sha256) {
        await file.delete();
        throw const FormatException('SHA256 sa nezhoduje.');
      }
      return file;
    } finally {
      client.close();
    }
  }

  Future<void> install(File apk) async {
    await InstallApk().installApk(apk.path);
  }
}
