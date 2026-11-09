import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

/// Suche nach verpackten Produkten.
abstract class FoodLookup {
  Future<Food?> byBarcode(String barcode);
  Future<List<Food>> search(String query);
}

class FoodLookupException implements Exception {
  const FoodLookupException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// EAN-8, UPC-A, EAN-13 und GTIN-14.
bool isValidBarcode(String code) => RegExp(r'^\d{8,14}$').hasMatch(code);

const offFields =
    'code,product_name,product_name_de,brands,nutriments,serving_size,'
    'serving_quantity,product_quantity_unit,quantity';

double? _num(Object? v) {
  final d = switch (v) {
    num n => n.toDouble(),
    String s => double.tryParse(s.replaceAll(',', '.')),
    _ => null,
  };
  return d == null || !d.isFinite || d < 0 ? null : d;
}

/// Wandelt ein Produkt von Open Food Facts um. Ohne Namen oder Energiewert
/// taugt es nicht für die Kalorienzählung und ergibt `null`.
Food? foodFromOpenFoodFacts(Map<String, Object?> product) {
  final code = '${product['code'] ?? ''}';
  final de = product['product_name_de'];
  final fallback = product['product_name'];
  final name = (de is String && de.trim().isNotEmpty ? de : fallback);
  if (name is! String || name.trim().isEmpty || code.isEmpty) return null;
  final n = (product['nutriments'] as Map?)?.cast<String, Object?>() ?? {};
  var kcal = _num(n['energy-kcal_100g']);
  if (kcal == null) {
    final kj = _num(n['energy-kj_100g']) ?? _num(n['energy_100g']);
    if (kj != null) kcal = kj / 4.184;
  }
  // Mehr als reines Fett (900 kcal) ist ein Tippfehler in der Datenbank.
  if (kcal == null || kcal > 950) return null;
  final brands = product['brands'];
  final quantity = '${product['quantity'] ?? ''}'.toLowerCase();
  final unitText = '${product['product_quantity_unit'] ?? ''}'.toLowerCase();
  final liquid =
      unitText == 'ml' ||
      unitText == 'l' ||
      RegExp(r'\d\s*(ml|cl|l)\b').hasMatch(quantity);
  final servingAmount = _num(product['serving_quantity']);
  final servingName = product['serving_size'];
  return Food(
    id: 'off-$code',
    name: name.trim(),
    brand: brands is String && brands.trim().isNotEmpty
        ? brands.split(',').first.trim()
        : null,
    barcode: code,
    unit: liquid ? 'ml' : 'g',
    source: FoodSource.openFoodFacts,
    per100: Nutrients(
      kcal: kcal,
      protein: _num(n['proteins_100g']) ?? 0,
      carbs: _num(n['carbohydrates_100g']) ?? 0,
      fat: _num(n['fat_100g']) ?? 0,
      sugar: _num(n['sugars_100g']),
      fiber: _num(n['fiber_100g']),
      saturatedFat: _num(n['saturated-fat_100g']),
      salt: _num(n['salt_100g']),
    ),
    servings: [
      if (servingAmount != null && servingAmount > 0)
        Serving(
          servingName is String && servingName.trim().isNotEmpty
              ? servingName.trim()
              : 'Portion',
          servingAmount,
        ),
    ],
  );
}

/// Greift direkt auf Open Food Facts zu (ODbL; die App nennt die Quelle).
class OpenFoodFactsClient implements FoodLookup {
  OpenFoodFactsClient({http.Client? client, this.userAgent = 'Bociva/0.1'})
    : _client = client ?? http.Client();

  static final _base = Uri.https('world.openfoodfacts.org');

  final http.Client _client;
  final String userAgent;

  Future<Map<String, Object?>> _get(Uri uri) async {
    final http.Response res;
    try {
      res = await _client
          .get(uri, headers: {'user-agent': userAgent})
          .timeout(const Duration(seconds: 15));
    } on Exception {
      throw const FoodLookupException(
        'Die Produktdatenbank ist gerade nicht erreichbar.',
      );
    }
    if (res.statusCode == 404) return const {};
    if (res.statusCode != 200) {
      throw const FoodLookupException(
        'Die Produktdatenbank antwortet gerade nicht.',
      );
    }
    return (jsonDecode(utf8.decode(res.bodyBytes)) as Map)
        .cast<String, Object?>();
  }

  @override
  Future<Food?> byBarcode(String barcode) async {
    if (!isValidBarcode(barcode)) return null;
    final json = await _get(
      _base.replace(
        path: '/api/v2/product/$barcode.json',
        queryParameters: {'fields': offFields},
      ),
    );
    if (json['status'] != 1 || json['product'] is! Map) return null;
    return foodFromOpenFoodFacts({
      ...(json['product'] as Map).cast<String, Object?>(),
      'code': barcode,
    });
  }

  @override
  Future<List<Food>> search(String query) async {
    final json = await _get(
      _base.replace(
        path: '/cgi/search.pl',
        queryParameters: {
          'search_terms': query,
          'search_simple': '1',
          'action': 'process',
          'json': '1',
          'page_size': '25',
          'fields': offFields,
        },
      ),
    );
    return [
      for (final p in json['products'] as List? ?? const [])
        ?foodFromOpenFoodFacts((p as Map).cast<String, Object?>()),
    ];
  }
}
