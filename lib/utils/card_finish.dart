const List<String> _finishPriority = [
  'rainbow',
  'gold',
  'cosmos',
  'textured',
  'etched',
  'holo',
  'foil',
  'normal',
  'reverse',
  'firstEdition',
];

String normalizeCardFinish(dynamic value) {
  final raw = (value ?? '').toString().trim().toLowerCase();
  if (raw.isEmpty) return '';
  if (raw.contains('reverse')) return 'reverse';
  if (raw.contains('rainbow')) return 'rainbow';
  if (raw.contains('gold')) return 'gold';
  if (raw.contains('cosmos')) return 'cosmos';
  if (raw.contains('texture') || raw.contains('textured')) return 'textured';
  if (raw.contains('etched')) return 'etched';
  if (raw.contains('first') || raw.contains('1st')) return 'firstEdition';
  if (raw.contains('holo') || raw == 'foil' || raw.contains('foil')) {
    return raw.contains('nonfoil') || raw.contains('non-foil')
        ? 'normal'
        : (raw.contains('foil') && !raw.contains('holo') ? 'foil' : 'holo');
  }
  if (raw.contains('normal') ||
      raw.contains('nonfoil') ||
      raw.contains('non-foil')) {
    return 'normal';
  }
  return raw;
}

String primaryCardFinish(Map<String, dynamic> card) {
  final finishes = <String>[];
  final rawFinishes = card['finishes'];
  if (rawFinishes is List) {
    for (final raw in rawFinishes) {
      final finish = normalizeCardFinish(raw);
      if (finish.isNotEmpty && !finishes.contains(finish)) {
        finishes.add(finish);
      }
    }
  }
  final explicit = normalizeCardFinish(card['finish']);
  if (explicit.isNotEmpty && !finishes.contains(explicit)) {
    finishes.add(explicit);
  }
  if (finishes.isEmpty && card['foil'] == true) {
    finishes.add('holo');
  }

  for (final preferred in _finishPriority) {
    if (finishes.contains(preferred)) return preferred;
  }
  return finishes.isNotEmpty ? finishes.first : '';
}

bool cardHasHoloFinish(Map<String, dynamic> card) {
  final finish = primaryCardFinish(card);
  return finish.isNotEmpty && finish != 'normal' && finish != 'firstEdition';
}

String finishLabelFor(String finish) {
  switch (finish) {
    case 'firstEdition':
      return '1st Edition';
    case 'reverse':
      return 'Reverse Holo';
    case 'holo':
      return 'Holo';
    case 'foil':
      return 'Foil';
    case 'cosmos':
      return 'Cosmos';
    case 'textured':
      return 'Texture';
    case 'rainbow':
      return 'Rainbow';
    case 'gold':
      return 'Gold';
    case 'etched':
      return 'Etched';
    default:
      return 'Normal';
  }
}
