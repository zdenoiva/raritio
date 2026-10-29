import 'package:flutter_test/flutter_test.dart';
import 'package:raritio/services/search_query_expander.dart';

void main() {
  test('repairs the missing apostrophe in Mistys Gyarados', () {
    final variants = SearchQueryExpander.expand('Mistys Gyarados 049/182');

    expect(variants, contains("Misty's Gyarados 049"));
    expect(variants, contains("Misty's Gyarados"));
    expect(variants, contains('Gyarados 049'));
  });

  test('normalizes typographic apostrophes first', () {
    final variants = SearchQueryExpander.expand('Misty’s Gyarados 049/182');

    expect(variants.first, "Misty's Gyarados 049/182");
  });

  test('repairs the spaced apostrophe shape', () {
    final variants = SearchQueryExpander.expand('Misty s Gyarados');

    expect(variants, contains("Misty's Gyarados"));
  });

  test('does not rewrite Pokemon names that end in s', () {
    final variants = SearchQueryExpander.expand('Gyarados ex');

    expect(variants, isNot(contains("Gyarado's ex")));
    expect(variants, contains('Gyarados ex'));
  });

  test('handles a number-only query', () {
    final variants = SearchQueryExpander.expand('049/182');

    expect(variants, contains('049'));
  });

  test('deduplicates and respects the variant limit', () {
    final variants = SearchQueryExpander.expand(
      "Misty's Gyarados",
      maxVariants: 4,
    );

    expect(variants.length, lessThanOrEqualTo(4));
    expect(variants.toSet().length, variants.length);
  });

  test('keeps a Japanese name and promo suffix', () {
    final variants = SearchQueryExpander.expand('リザードン 001/S-P');

    expect(variants, contains('リザードン 001'));
    expect(variants, contains('リザードン'));
    expect(variants, contains('001'));
  });

  test('keeps a Chinese name and collector number', () {
    final variants = SearchQueryExpander.expand('喷火龙 002/165');

    expect(variants, contains('喷火龙 002'));
    expect(variants, contains('喷火龙'));
    expect(variants, contains('002'));
  });

  test('keeps a two-character Chinese name', () {
    final variants = SearchQueryExpander.expand('超夢');

    expect(variants, contains('超夢'));
  });
}

