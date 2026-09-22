import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tigert/data/app_state.dart';
import 'package:tigert/data/catalog.dart';
import 'package:tigert/data/local_prefs.dart';
import 'package:tigert/data/models.dart';
import 'package:tigert/data/store.dart';

late Catalog catalog;

Future<AppState> newApp() async {
  final dir = Directory.systemTemp.createTempSync('tigert_dishes_');
  final store = Store();
  await store.init(dir: dir);
  final prefs = LocalPrefs();
  await prefs.init(dir);
  return AppState(store, prefs, catalog);
}

Food seed(String id) => catalog.foodById[id]!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => catalog = await Catalog.load());

  test('database tutto a crudo, porzioni di pasta e riso', () {
    final cooked = catalog.foods.where((f) => RegExp(r'\((cott[oa]|cotti|cotte)\)', caseSensitive: false).hasMatch(f.name));
    expect(cooked.map((f) => f.name), isEmpty);
    for (final f in catalog.foods) {
      if (RegExp(r'^Pasta .*\(cruda\)$').hasMatch(f.name)) expect(f.portions.first.g, 200, reason: f.name);
      if (RegExp(r'^Riso .*\(crudo\)$').hasMatch(f.name)) expect(f.portions.first.g, 150, reason: f.name);
    }
  });

  test('piatti: i valori sono la somma degli ingredienti del database', () {
    final byName = {for (final f in catalog.foods) f.name: f};
    final dishes = catalog.foods.where((f) => f.isDish).toList();
    expect(dishes.length, greaterThanOrEqualTo(30));
    for (final d in dishes) {
      expect(d.parts.first.r, 1, reason: d.name);
      expect(d.parts.first.opt, isFalse, reason: d.name);
      expect(d.cook, isFalse, reason: d.name);
      var sum = Macro.zero;
      for (final x in d.parts) {
        final src = byName[x.name];
        expect(src, isNotNull, reason: '${d.name}: ${x.name}');
        expect([x.kcal, x.p, x.c, x.f], [src!.kcal, src.p, src.c, src.f], reason: '${d.name}: ${x.name}');
        if (!x.opt) sum = sum + x.per(100 * x.r);
      }
      expect(d.kcal, closeTo(sum.kcal, 0.1), reason: d.name);
      expect(d.p, closeTo(sum.p, 0.1), reason: d.name);
      expect(d.c, closeTo(sum.c, 0.1), reason: d.name);
      expect(d.f, closeTo(sum.f, 0.1), reason: d.name);
      if (d.base!.startsWith('pasta ')) expect(d.portions.first.g, 200, reason: d.name);
      if (d.base == 'riso crudo') expect(d.portions.first.g, 150, reason: d.name);
    }
  });

  test('pasta al ragù: 200 g di pasta cruda + metà di ragù, condimento e formaggio', () {
    final d = seed('s:pasta-al-ragu');
    expect(d.qtyUnit, 'g pasta cruda');
    expect(d.portions.first.g, 200);
    // 200 g di pasta (355 kcal/100 g) + 100 g di ragù (120 kcal/100 g)
    expect(d.macroFor(200).kcal, closeTo(830, 0.01));
    expect(d.partsFor(200).map((e) => e.$2), [200, 100]);
    // tanto condimento: il ragù ×1,5, la pasta resta 200 g
    expect(d.partsFor(200, const FoodOpts(sauce: 1.5)).map((e) => e.$2), [200, 150]);
    expect(d.macroFor(200, const FoodOpts(sauce: 1.5)).kcal, closeTo(890, 0.01));
    expect(d.macroFor(200, const FoodOpts(sauce: 0.6)).kcal, closeTo(782, 0.01));
    // parmigiano facoltativo, spento di default: +10 g
    expect(d.extraPart!.name, 'Parmigiano Reggiano');
    expect(d.macroFor(200, const FoodOpts(extra: true)).kcal, closeTo(830 + 39.2, 0.01));
    // il formaggio non cambia con il condimento
    expect(d.partsFor(200, const FoodOpts(sauce: 1.5, extra: true)).last.$2, 10);
  });

  test('cottura: olio stimato per carne e verdure', () {
    final chicken = seed('s:petto-di-pollo-crudo');
    expect(chicken.cook, isTrue);
    expect(chicken.macroFor(150).kcal, closeTo(165, 0.01));
    // con olio: 5 g ogni 100 g di carne
    expect(chicken.oilFor(150, 'olio'), closeTo(7.5, 0.001));
    expect(chicken.macroFor(150, const FoodOpts(cook: 'olio')).kcal, closeTo(165 + 7.5 * 8.99, 0.01));
    expect(chicken.macroFor(150, const FoodOpts(cook: 'fritto')).f, closeTo(1.8 + 15 * 0.999, 0.01));
    final zucchine = seed('s:zucchine');
    expect(zucchine.oilFor(200, 'olio'), closeTo(16, 0.001));
    // prodotti in scatola e piatti non hanno la cottura
    expect(seed("s:tonno-sott-olio-sgocciolato").cook, isFalse);
    expect(seed('s:pasta-al-ragu').cleanOpts(const FoodOpts(cook: 'fritto', sauce: 1.5)).cook, '');
    expect(chicken.cleanOpts(const FoodOpts(cook: 'fritto', sauce: 1.5, extra: true)).sauce, 1);
  });

  test('scelte salvate nella voce e riusate col + rapido', () async {
    final app = await newApp();
    final chicken = seed('s:petto-di-pollo-crudo');
    final e = app.entryFromFood(chicken, 150, date: '2026-09-22', meal: 'pranzo', opts: const FoodOpts(cook: 'olio'));
    app.addEntry(e);
    final back = LogEntry.fromMap({...e.toMap(), 'id': e.id});
    expect(back.opts.cook, 'olio');
    expect(optsLabel(back.opts), ' · con olio');
    expect(app.lastOpts(chicken.id).cook, 'olio');
    // senza scelte esplicite usa quelle dell'ultima volta
    final again = app.entryFromFood(chicken, 150, date: '2026-09-23', meal: 'pranzo');
    expect(again.opts.cook, 'olio');
    expect(again.kcal, closeTo(e.kcal, 0.001));
    // "Come ieri" copia anche le scelte
    app.copyMeal('2026-09-22', 'pranzo', '2026-09-24');
    expect(app.entries('2026-09-24').single.opts.cook, 'olio');
    final ragu = app.entryFromFood(seed('s:pasta-al-ragu'), 200, date: '2026-09-22', meal: 'cena', opts: const FoodOpts(sauce: 1.5, extra: true));
    expect(optsLabel(ragu.opts), ' · tanto condimento · con formaggio');
    expect(app.entryUnit(ragu), 'g pasta cruda');
  });

  test('le vecchie voci dei primi piatti vengono ricalcolate come pasta cruda, una volta', () async {
    final app = await newApp();
    // come salvata dalla v1.2.0: 180 g di "Pasta al pesto" pesata nel piatto (200 kcal/100 g)
    const old = LogEntry(id: 'old', date: '2026-09-21', meal: 'pranzo', name: 'Pasta al pesto', g: 180, kcal: 360, p: 10.8, c: 45, f: 15.3, refId: 's:pasta-al-pesto', ts: 1);
    const banana = LogEntry(id: 'ban', date: '2026-09-21', meal: 'merenda', name: 'Banana', g: 120, kcal: 106.8, p: 1.3, c: 24, f: 0.4, refId: 's:banana', ts: 2);
    app.addEntry(old);
    app.addEntry(banana);
    expect(app.migrateRawDishes(), 1);
    final e = app.entries('2026-09-21').firstWhere((e) => e.id == 'old');
    expect(e.g, 180);
    expect(e.kcal, closeTo(180 * 4.75, 0.01)); // 180 g pasta + 45 g pesto
    expect(app.entries('2026-09-21').firstWhere((e) => e.id == 'ban').kcal, 106.8);
    app.updateEntry(old);
    expect(app.migrateRawDishes(), 0);
  });
}
