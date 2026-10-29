import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Stores the whole web-app state (binders, cards, prices) as a small JSON
/// file in the app's private documents directory.
///
/// The JSON file is also the format used for manual backups, so a backup can
/// be restored on another phone without any server.
class StateService {
  static const String _fileName = 'raritio_state.json';
  static const MethodChannel _backupChannel =
      MethodChannel('sk.zdenoiva.raritio/backup');
  static const int maxBackups = 5;

  Future<File> _stateFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, _fileName));
  }

  /// Returns the saved state, or null when there is no valid state yet.
  Future<Map<String, dynamic>?> loadState() async {
    try {
      final file = await _stateFile();
      if (!await file.exists()) return null;

      final content = await file.readAsString();
      if (content.trim().isEmpty) return null;

      final decoded = jsonDecode(content);
      if (decoded is! Map) return null;

      final state = Map<String, dynamic>.from(decoded);
      if (state['binders'] is! List) return null;
      return state;
    } catch (_) {
      // A corrupt state file must not prevent the app from starting.
      return null;
    }
  }

  /// Writes the state atomically: a crash during the write keeps the old file.
  Future<void> saveState(String json) async {
    final file = await _stateFile();
    final temp = File('${file.path}.tmp');

    await temp.writeAsString(json, flush: true);

    // On Android/Linux rename replaces the old file atomically. On Windows it
    // cannot overwrite, so fall back to delete + rename there.
    try {
      await temp.rename(file.path);
    } on FileSystemException {
      if (await file.exists()) {
        await file.delete();
      }
      await temp.rename(file.path);
    }
  }

  Future<Directory> _backupDirectory() async {
    final dir = await getApplicationDocumentsDirectory();
    final backupDir = Directory(p.join(dir.path, 'backups'));
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }
    return backupDir;
  }

  /// Writes a backup into the public Downloads/Raritio folder on Android.
  /// If the platform channel is unavailable (tests/desktop), it falls back to
  /// the app's private documents/backups folder.
  Future<String> saveBackup(String backup) async {
    final fileName = backupFileName();
    try {
      final path = await _backupChannel.invokeMethod<String>(
        'saveBackupToDownloads',
        {
          'fileName': fileName,
          'content': backup,
          'maxBackups': maxBackups,
        },
      );
      if (path != null && path.trim().isNotEmpty) return path;
    } catch (_) {
      // Fall through to the private app folder.
    }

    final dir = await _backupDirectory();
    final file = File(p.join(dir.path, fileName));
    await file.writeAsString(backup, flush: true);
    await _pruneBackups(dir);
    return file.path;
  }

  /// Creates at most one automatic backup per day. Returns the saved path, or
  /// null when today's backup already exists.
  Future<String?> ensureDailyBackup(String backup) async {
    final dir = await getApplicationDocumentsDirectory();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final marker = File(p.join(dir.path, '.auto-backup-$today'));
    if (await marker.exists()) return null;

    final path = await saveBackup(backup);
    await marker.writeAsString(path, flush: true);
    return path;
  }

  Future<void> _pruneBackups(Directory dir) async {
    try {
      final files = await dir
          .list()
          .where((entity) => entity is File &&
              p.basename(entity.path).startsWith('raritio-zaloha-'))
          .cast<File>()
          .toList();
      files.sort((a, b) => a.path.compareTo(b.path));
      while (files.length > maxBackups) {
        final oldest = files.removeAt(0);
        await oldest.delete();
      }
    } catch (_) {
      // Cleanup is best-effort; a backup must never fail because pruning did.
    }
  }

  /// Wraps the state in a versioned backup envelope.
  String createBackup(String stateJson) {
    final state = jsonDecode(stateJson);
    final envelope = <String, dynamic>{
      'app': 'raritio',
      'version': 1,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'state': state,
    };
    return const JsonEncoder.withIndent('  ').convert(envelope);
  }

  /// Accepts both the versioned envelope and a raw state object.
  Map<String, dynamic>? extractState(String backupJson) {
    try {
      final decoded = jsonDecode(backupJson);
      if (decoded is! Map) return null;

      final map = Map<String, dynamic>.from(decoded);
      Map<String, dynamic>? state;
      final appName = map['app'];
      if ((appName == 'raritio' || appName == 'holodex_tcg') &&
          map['state'] is Map) {
        state = Map<String, dynamic>.from(map['state'] as Map);
      } else if (map['binders'] is List) {
        state = map;
      }

      if (state == null || state['binders'] is! List) return null;
      return state;
    } catch (_) {
      return null;
    }
  }

  String backupFileName() {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return 'raritio-zaloha-${now.year}-${two(now.month)}-${two(now.day)}'
        '-${two(now.hour)}${two(now.minute)}${two(now.second)}.json';
  }
}

