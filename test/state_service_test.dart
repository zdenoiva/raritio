import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:raritio/services/state_service.dart';

void main() {
  final service = StateService();

  test('createBackup wraps state in an envelope', () {
    final stateJson = jsonEncode({
      'binders': [
        {
          'id': 'b1',
          'name': 'Balík',
          'cards': <dynamic>[],
        }
      ],
      'currentBinderId': 'b1',
    });

    final backup = service.createBackup(stateJson);
    final decoded = jsonDecode(backup) as Map<String, dynamic>;

    expect(decoded['app'], 'raritio');
    expect(decoded['version'], 1);
    expect(decoded['state'], isA<Map>());
    expect((decoded['state'] as Map)['binders'], isA<List>());
  });

  test('extractState accepts a backup envelope', () {
    final state = {
      'binders': [
        {
          'id': 'b1',
          'name': 'Balík',
          'cards': <dynamic>[],
        }
      ],
      'currentBinderId': 'b1',
    };

    final backup = jsonEncode({
      'app': 'raritio',
      'version': 1,
      'state': state,
    });

    final extracted = service.extractState(backup);

    expect(extracted, isNotNull);
    expect(extracted!['currentBinderId'], 'b1');
  });

  test('extractState accepts a raw state object', () {
    final raw = jsonEncode({
      'binders': <dynamic>[],
      'currentBinderId': 'b1',
    });

    final extracted = service.extractState(raw);

    expect(extracted, isNotNull);
    expect(extracted!['binders'], isA<List>());
  });

  test('extractState rejects invalid files', () {
    expect(service.extractState('not json'), isNull);
    expect(service.extractState(jsonEncode({'foo': 'bar'})), isNull);
    expect(
      service.extractState(jsonEncode({'app': 'raritio', 'state': {}})),
      isNull,
    );
  });

  test('backup file name is a json file', () {
    final name = service.backupFileName();

    expect(name, startsWith('raritio-zaloha-'));
    expect(name, endsWith('.json'));
  });
}

