import 'card_model.dart';

class Binder {
  final String id;
  final String name;
  final List<Card> cards;
  final String description;

  Binder({
    required this.id,
    required this.name,
    required this.cards,
    this.description = '',
  });

  factory Binder.fromJson(Map<String, dynamic> json) {
    return Binder(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      cards: (json['cards'] as List<dynamic>?)
              ?.map((c) => Card.fromJson(Map<String, dynamic>.from(c)))
              .toList() ??
          [],
      description: json['description'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'cards': cards.map((c) => c.toJson()).toList(),
      'description': description,
    };
  }
}
