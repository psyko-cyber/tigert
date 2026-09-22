import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/ids.dart';
import '../data/models.dart';

/// Open Food Facts: database libero (ODbL) di prodotti confezionati.
class OffApi {
  static const _ua = 'Tigert/$appVersion (https://github.com/$githubRepo)';
  static const _fields =
      'code,product_name,product_name_it,generic_name_it,brands,nutriments,serving_quantity,serving_quantity_unit,serving_size,product_quantity,product_quantity_unit,quantity';

  /// Cerca un prodotto per codice a barre. Ritorna null se non esiste.
  static Future<Food?> byBarcode(String ean) async {
    final code = ean.replaceAll(RegExp(r'\D'), '');
    if (code.length < 6) return null;
    final r = await http
        .get(Uri.parse('https://world.openfoodfacts.org/api/v2/product/$code.json?fields=$_fields'), headers: {'User-Agent': _ua})
        .timeout(const Duration(seconds: 15));
    if (r.statusCode == 404) return null;
    if (r.statusCode != 200) throw Exception('Open Food Facts ha risposto ${r.statusCode}');
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map;
    if (j['status'] != 1 || j['product'] is! Map) return null;
    return _toFood(j['product'] as Map, code);
  }

  /// Ricerca testuale (prodotti venduti in Italia prima).
  static Future<List<Food>> search(String q) async {
    final uri = Uri.parse('https://world.openfoodfacts.org/cgi/search.pl').replace(queryParameters: {
      'search_terms': q,
      'search_simple': '1',
      'action': 'process',
      'json': '1',
      'page_size': '30',
      'fields': _fields,
      'lc': 'it',
      'cc': 'it',
    });
    final r = await http.get(uri, headers: {'User-Agent': _ua}).timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) throw Exception('Open Food Facts ha risposto ${r.statusCode}');
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map;
    final out = <Food>[];
    for (final p in (j['products'] as List? ?? const [])) {
      if (p is! Map) continue;
      final code = (p['code'] ?? '').toString();
      if (code.isEmpty) continue;
      final f = _toFood(p, code);
      if (f != null) out.add(f);
    }
    return out;
  }

  static double? _n(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.replaceAll(',', '.'));
    return null;
  }

  static Food? _toFood(Map p, String code) {
    final n = (p['nutriments'] as Map?) ?? const {};
    var kcal = _n(n['energy-kcal_100g']);
    if (kcal == null) {
      final kj = _n(n['energy-kj_100g']) ?? _n(n['energy_100g']);
      if (kj != null) kcal = kj / 4.184;
    }
    if (kcal == null) return null;
    String name = '';
    for (final k in ['product_name_it', 'product_name', 'generic_name_it']) {
      final v = (p[k] ?? '').toString().trim();
      if (v.isNotEmpty) {
        name = v;
        break;
      }
    }
    if (name.isEmpty) name = 'Prodotto $code';
    final brand = (p['brands'] ?? '').toString().split(',').first.trim();
    final portions = <Portion>[];
    final sq = _n(p['serving_quantity']);
    if (sq != null && sq > 0 && sq < 2000) portions.add(Portion('porzione', sq));
    final pq = _n(p['product_quantity']);
    if (pq != null && pq > 0 && pq <= 1500 && pq != sq) portions.add(Portion('confezione', pq));
    final units = [p['product_quantity_unit'], p['serving_quantity_unit']].map((e) => (e ?? '').toString().toLowerCase());
    final liquid = units.any((u) => u == 'ml' || u == 'cl' || u == 'l') ||
        RegExp(r'\d\s*(ml|cl|l)\b', caseSensitive: false).hasMatch('${p['quantity'] ?? ''} ${p['serving_size'] ?? ''}');
    return Food(
      id: 'off:$code',
      name: name,
      brand: brand.isEmpty ? null : brand,
      ean: code,
      cat: 'Prodotti',
      kcal: double.parse(kcal.toStringAsFixed(1)),
      p: _n(n['proteins_100g']) ?? 0,
      c: _n(n['carbohydrates_100g']) ?? 0,
      f: _n(n['fat_100g']) ?? 0,
      fiber: _n(n['fiber_100g']) ?? 0,
      portions: portions,
      src: 'off',
      ml: liquid || isLiquidFood(name, ''),
    );
  }
}
