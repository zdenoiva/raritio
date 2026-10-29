class Card {
  final String id;
  final String name;
  final String set;
  final String type;
  final String imageUri;
  final String game; // 'pokemon' or 'mtg'
  final double currentPrice;
  final String lastUpdated;
  final Map<String, dynamic> metadata;

  Card({
    required this.id,
    required this.name,
    required this.set,
    required this.type,
    required this.imageUri,
    required this.game,
    required this.currentPrice,
    required this.lastUpdated,
    required this.metadata,
  });

  factory Card.fromJson(Map<String, dynamic> json) {
    return Card(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      set: json['set'] ?? '',
      type: json['type'] ?? '',
      imageUri: json['imageUri'] ?? '',
      game: json['game'] ?? 'pokemon',
      currentPrice: (json['currentPrice'] as num?)?.toDouble() ?? 0.0,
      lastUpdated: json['lastUpdated'] ?? '',
      metadata: json['metadata'] ?? {},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'set': set,
      'type': type,
      'imageUri': imageUri,
      'game': game,
      'currentPrice': currentPrice,
      'lastUpdated': lastUpdated,
      'metadata': metadata,
    };
  }
}
