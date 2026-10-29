import 'package:flutter_test/flutter_test.dart';
import 'package:raritio/services/price_charting_service.dart';

void main() {
  test('builds the PriceCharting product URL from set, name and number', () {
    final url = PriceChartingService.buildUrl(
      name: 'Gengar',
      set: 'Legendary Collection',
      number: '11/110',
    );
    expect(
      url,
      'https://www.pricecharting.com/game/pokemon-legendary-collection/gengar-11',
    );

    final pokemonSet = PriceChartingService.buildUrl(
      name: 'Charizard ex',
      set: 'Pokémon 151',
      number: '006/165',
    );
    expect(
      pokemonSet,
      'https://www.pricecharting.com/game/pokemon-151/charizard-ex-6',
    );
  });

  test('parses the grade table and the ungraded price', () {
    const markdown = '''
Title: Gengar #11 Prices | Pokemon Legendary Collection

|  | Ungraded | Grade 7 | Grade 8 | Grade 9 | Grade 9.5 | PSA 10 |
| --- | --- | --- | --- | --- | --- | --- |
|  | \$156.73 \$0.00 | \$412.53 \$0.00 | \$560.29 \$0.00 | \$1,674.73 \$0.00 | \$1,999.00 \$0.00 | \$175,050.00 \$0.00 |
''';

    final parsed = PriceChartingService.parsePage(
      markdown,
      url: 'https://www.pricecharting.com/game/pokemon-legendary-collection/gengar-11',
    );

    expect(parsed, isNotNull);
    expect(parsed!['price'], 156.73);
    final grades = parsed['gradePrices'] as List<Map<String, dynamic>>;
    expect(grades.length, 6);
    expect(grades.first['label'], 'Ungraded');
    expect(grades.first['price'], 156.73);
    expect(grades.last['label'], 'PSA 10');
    expect(grades.last['price'], 175050.0);
  });

  test('parses every grade from the full price guide', () {
    const markdown = '''
## Full Price Guide: Gengar #11 (Pokemon Legendary Collection)

Ungraded\$156.73
Grade 1\$223.49
Grade 2\$90.00
Grade 3\$99.87
Grade 4\$108.19
Grade 5\$152.00
Grade 6\$190.00
Grade 7\$412.53
Grade 8\$560.29
Grade 9\$1,674.73
Grade 9.5\$1,999.00
TAG 10-
ACE 10-
SGC 10\$105,030.00
CGC 10\$70,020.00
PSA 10\$175,050.00
BGS 10\$227,565.00
BGS 10 Black\$1,137,825.00
CGC 10 Pristine\$126,036.00

All prices are the current market price.
''';

    final parsed = PriceChartingService.parsePage(markdown);

    expect(parsed, isNotNull);
    expect(parsed!['price'], 156.73);
    final grades = parsed['gradePrices'] as List<Map<String, dynamic>>;
    expect(grades.length, 17);
    expect(grades.first['label'], 'Ungraded');
    expect(grades.last['label'], 'CGC 10 Pristine');
    expect(grades.last['price'], 126036.0);
    expect(
      grades.map((grade) => grade['label']),
      containsAll(<String>['Grade 9.5', 'PSA 10', 'BGS 10 Black']),
    );
    expect(
      grades.map((grade) => grade['label']),
      isNot(contains('TAG 10')),
    );
  });

  test('parses recent sold listings into history points', () {
    const markdown = '''
| 2026-10-18 | [eBay](https://www.ebay.com/itm/1) | \$210.00 | \$190.00 | \$200.00 | Report It |
| 2026-10-20 | [eBay](https://www.ebay.com/itm/2) | \$86.92 |  |  | Report It |
''';

    final parsed = PriceChartingService.parsePage(markdown);
    expect(parsed, isNotNull);
    final history = parsed!['priceHistory'] as List<Map<String, dynamic>>;
    expect(history.length, 2);
    expect(history.first['date'], '2026-10-18');
    expect(history.first['price'], 200.0);
    expect(history.last['date'], '2026-10-20');
    expect(history.last['price'], 86.92);
  });

  test('finds a matching product URL in search results', () {
    const search = '''
| [![Image 1](https://example.com/1.jpg)](https://www.pricecharting.com/game/pokemon-30th-celebration/gengar-ex-154 "14486868") | [Gengar Ex #154](https://www.pricecharting.com/game/pokemon-30th-celebration/gengar-ex-154 "14486868") |
| [![Image 2](https://example.com/2.jpg)](https://www.pricecharting.com/game/pokemon-legendary-collection/gengar-11 "842318") | [Gengar #11](https://www.pricecharting.com/game/pokemon-legendary-collection/gengar-11 "842318") |
''';

    final url = PriceChartingService.findProductUrl(
      search,
      name: 'Gengar',
      number: '11',
      set: 'Legendary Collection',
    );

    expect(
      url,
      'https://www.pricecharting.com/game/pokemon-legendary-collection/gengar-11',
    );
  });
}

