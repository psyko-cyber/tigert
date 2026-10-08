import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tigert/core/fmt.dart';
import 'package:tigert/data/app_state.dart';
import 'package:tigert/data/catalog.dart';
import 'package:tigert/data/local_prefs.dart';
import 'package:tigert/data/models.dart';
import 'package:tigert/data/store.dart';
import 'package:tigert/logic/activity.dart';
import 'package:tigert/logic/watch.dart';
import 'package:tigert/services/gemini.dart';
import 'package:tigert/services/watch.dart';

late Catalog catalog;

Future<AppState> newApp() async {
  final dir = Directory.systemTemp.createTempSync('tigert_watch_');
  final store = Store();
  await store.init(dir: dir);
  final prefs = LocalPrefs();
  await prefs.init(dir);
  final app = AppState(store, prefs, catalog);
  app.saveProfile(Profile(
    name: '',
    sex: 'm',
    birthYear: 1996,
    heightCm: 178,
    startWeight: 80,
    startDate: '2026-01-05',
    goal: Goal.cut,
    targetWeight: 75,
    rate: 0.5,
    activity: 'moderato',
    kcal: 2200,
    protein: 170,
    carbs: 230,
    fat: 65,
    kcalStart: 2200,
    waterMl: 3000,
    trainingDays: const [1, 3, 5],
    reminders: Reminders.defaults(),
  ));
  return app;
}

class FakeSource implements WatchSource {
  List<WatchDay> days;
  Map<String, bool> perms;
  int reads = 0;
  FakeSource(this.days, {this.perms = const {'steps': true, 'sleep': true, 'workouts': true, 'weight': true}});
  @override
  Future<String> status() async => 'ok';
  @override
  Future<void> install() async {}
  @override
  Future<Map<String, bool>> permissions() async => perms;
  @override
  Future<void> request() async {}
  @override
  Future<List<WatchDay>> read(DateTime from, DateTime to) async {
    reads++;
    return days;
  }
}

WatchWorkout run(String id, DateTime start, int min, {String type = 'RUNNING', double? kcal}) =>
    WatchWorkout(id: id, type: type, start: start, end: start.add(Duration(minutes: min)), kcal: kcal);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => catalog = await Catalog.load());

  test('nota dell\'esercizio: resta, si cambia e si sincronizza', () async {
    final app = await newApp();
    expect(app.exNote('panca-piana'), isNull, reason: 'mai scritta: vale la nota della scheda');
    app.setExNote('panca-piana', '  Sellino 4, schienale 2 ');
    expect(app.exNote('panca-piana'), 'Sellino 4, schienale 2');
    expect(app.exNote('squat'), isNull);
    app.setExNote('panca-piana', '');
    expect(app.exNote('panca-piana'), '', reason: 'cancellata apposta: non torna quella della scheda');
    expect(Store.synced, contains('exnotes'));
  });

  test('orologio: passi e sonno si aggiornano finché non li scrivi a mano', () {
    const day = HabitDay(date: '2026-10-05', water: 500);
    final a = mergeWatchDay(day, const WatchDay(date: '2026-10-05', steps: 4200, sleep: 431), kg: 80)!;
    expect([a.steps, a.sleep, a.water], [4200, 431, 500]);
    expect(a.isAuto('steps') && a.isAuto('sleep'), isTrue);
    expect(HabitDay.fromMap(a.toMap()).auto, ['steps', 'sleep']);
    // più tardi l'orologio ne ha contati altri
    final b = mergeWatchDay(a, const WatchDay(date: '2026-10-05', steps: 9100, sleep: 431), kg: 80)!;
    expect(b.steps, 9100);
    expect(mergeWatchDay(b, const WatchDay(date: '2026-10-05', steps: 9100, sleep: 431), kg: 80), isNull, reason: 'niente di nuovo');
    // corretti a mano: da lì vince il valore scritto
    final c = b.copyWith(steps: 12000);
    expect(c.isAuto('steps'), isFalse);
    expect(c.isAuto('sleep'), isTrue);
    expect(mergeWatchDay(c, const WatchDay(date: '2026-10-05', steps: 9500, sleep: 431), kg: 80), isNull);
    // altre modifiche a mano (acqua) non toccano i valori dell'orologio
    expect(b.copyWith(water: 1500).isAuto('steps'), isTrue);
    expect(b.withOff('impegno').auto, b.auto);
    // un pisolino senza la notte non diventa "il sonno"
    expect(mergeWatchDay(day, const WatchDay(date: '2026-10-05', sleep: 40), kg: 80), isNull);
    expect(const HabitDay(date: 'x').toMap().keys, isNot(contains('auto')), reason: 'i record vecchi non cambiano');
  });

  test('orologio: sonno senza doppioni e senza i risvegli', () {
    DateTime t(int d, int h, [int m = 0]) => DateTime(2026, 10, d, h, m);
    // la stessa notte scritta da due app + un pisolino al pomeriggio
    final sessions = [(t(4, 23, 30), t(5, 7)), (t(4, 23, 40), t(5, 6, 50)), (t(5, 15), t(5, 15, 30))];
    final awake = [(t(5, 3), t(5, 3, 20)), (t(5, 3, 10), t(5, 3, 20))];
    expect(unionMinutes(sessions), 450 + 30);
    expect(sleepOn('2026-10-05', sessions, awake), 480 - 20);
    expect(sleepOn('2026-10-04', sessions, awake), isNull, reason: 'la notte conta per il giorno in cui ti svegli');
  });

  test('orologio: allenamenti come attività extra', () {
    final d0 = DateTime(2026, 10, 5, 18);
    final gym = (d0.millisecondsSinceEpoch, d0.add(const Duration(minutes: 70)).millisecondsSinceEpoch);
    const day = HabitDay(date: '2026-10-05');
    WatchDay wd(List<WatchWorkout> w) => WatchDay(date: '2026-10-05', workouts: w);
    // corsa di 30 min: 80 kg → riposo 40 kcal; 340 totali → 300 nette
    final a = mergeWatchDay(day, wd([run('r1', DateTime(2026, 10, 5, 7), 30, kcal: 340)]), kg: 80)!;
    expect(a.extra.single.kind, 'corsa');
    expect([a.extra.single.min, a.extra.single.kcal, a.extra.single.src], [30, 300, 'r1']);
    expect(a.burned, 300);
    expect(ExtraActivity.fromMap(a.extra.single.toMap()).src, 'r1');
    // già importata: non raddoppia
    expect(mergeWatchDay(a, wd([run('r1', DateTime(2026, 10, 5, 7), 30, kcal: 340)]), kg: 80), isNull);
    // eliminata a mano: l'id è tra quelli già visti e non torna
    expect(mergeWatchDay(day, wd([run('r1', DateTime(2026, 10, 5, 7), 30)]), kg: 80, known: {'r1'}), isNull);
    // senza calorie, o con calorie fuori scala (totale del giorno), vale la stima di Tigert
    final est = activityKcal('corsa', 30, 80);
    expect(watchKcal(run('x', d0, 30), 'corsa', 80), est);
    expect(watchKcal(run('x', d0, 30, kcal: 2600), 'corsa', 80), est);
    // pesi, allenamenti troppo corti e quelli sopra una seduta di Tigert restano fuori
    expect(mergeWatchDay(day, wd([run('w', d0, 60, type: 'STRENGTH_TRAINING')]), kg: 80), isNull);
    expect(mergeWatchDay(day, wd([run('w', d0, 6, type: 'WALKING')]), kg: 80), isNull);
    expect(mergeWatchDay(day, wd([run('w', d0.add(const Duration(minutes: 5)), 55, type: 'OTHER')]), kg: 80, sessions: [gym]), isNull);
    // lo sport già scritto a mano quel giorno non si ripete
    final manual = day.copyWith(extra: const [ExtraActivity(kind: 'corsa', name: 'Corsa', min: 30, kcal: 280)]);
    expect(mergeWatchDay(manual, wd([run('r2', DateTime(2026, 10, 5, 7), 32)]), kg: 80), isNull);
    expect(mergeWatchDay(manual, wd([run('b1', DateTime(2026, 10, 5, 9), 45, type: 'BIKING')]), kg: 80)!.extra.length, 2);
    // nomi e sport
    expect(sportFor('WALKING'), ('camminata', 'Camminata'));
    expect(sportFor('RUNNING_TREADMILL').$1, 'corsa');
    expect(sportFor('HIKING').$1, 'escursione');
    expect(sportFor('BIKING_STATIONARY').$1, 'bici');
    expect(sportFor('TABLE_TENNIS'), ('altro', 'Ping pong'));
    expect(sportFor('TENNIS').$1, 'tennis');
    expect(sportFor('SWIMMING_POOL').$1, 'nuoto');
    expect(sportFor('SOMETHING_NEW'), ('altro', 'Attività'));
    for (final (_, kind) in [for (final t in ['RUNNING', 'WALKING', 'HIKING', 'BIKING', 'YOGA', 'DANCING', 'SKIING', 'BOXING']) (t, sportFor(t).$1)]) {
      expect(sports.any((s) => s.$1 == kind), isTrue, reason: kind);
    }
  });

  test('orologio: lettura completa, peso solo se manca, niente doppioni al secondo giro', () async {
    final app = await newApp();
    final today = todayKey();
    final yest = addDaysKey(today, -1);
    app.setWeight(yest, 79.4);
    app.saveHabit(HabitDay(date: yest, steps: 7000)); // scritti a mano
    final morning = dateOnly(DateTime.now()).add(const Duration(hours: 7));
    final src = FakeSource([
      WatchDay(date: yest, steps: 8123, sleep: 400, kg: 79.9),
      WatchDay(date: today, steps: 3500, sleep: 455, kg: 79.26, workouts: [run('run-1', morning, 40, kcal: 450)]),
    ]);
    final w = WatchService(app, src);
    expect(w.available, isTrue);
    expect(w.enabled, isFalse);
    expect(await w.sync(force: true), 0, reason: 'non collegato: non legge');
    expect(src.reads, 0);

    expect(await w.connect(), isTrue);
    expect(w.enabled, isTrue);
    expect(w.lastAt, isNotNull);
    expect(app.habit(yest).steps, 7000, reason: 'i passi scritti a mano restano');
    expect(app.habit(yest).sleep, 400);
    expect(app.weightOn(yest), 79.4, reason: 'il peso già registrato resta');
    expect(app.habit(today).steps, 3500);
    expect(app.habit(today).sleep, 455);
    expect(app.weightOn(today), 79.3);
    expect(app.habit(today).extra.single.name, 'Corsa');
    expect(app.prefs.watchSeen, ['run-1']);

    // secondo giro con più passi: cambia solo quello
    src.days = [WatchDay(date: today, steps: 5200, sleep: 455, kg: 79.26, workouts: [run('run-1', morning, 40, kcal: 450)])];
    expect(await w.sync(force: true), 1);
    expect(app.habit(today).steps, 5200);
    expect(app.habit(today).extra.length, 1);
    // attività eliminata a mano: non viene reimportata
    app.saveHabit(app.habit(today).copyWith(extra: const []));
    expect(await w.sync(force: true), 0);
    expect(app.habit(today).extra, isEmpty);
    // subito dopo non rilegge (una lettura al minuto al massimo)
    final n = src.reads;
    await w.sync();
    expect(src.reads, n);

    w.disconnect();
    expect(w.enabled, isFalse);
    // senza nessun permesso non si collega
    final none = WatchService(app, FakeSource(const [], perms: const {'steps': false, 'sleep': false}));
    expect(await none.connect(), isFalse);
    expect(WatchService(app, null).available, isFalse, reason: 'sul PC non c\'è Health Connect');
  });

  test('stima da foto: il piatto si salva come ricetta o come alimento', () {
    final est = parseEstimate('{"tigert":1,"piatto":"Cosce di pollo burro e salvia","affidabilita":"media","alimenti":['
        '{"nome":"Cosce di pollo","grammi":300,"grammi_min":250,"grammi_max":350,"kcal_100g":200,"proteine_100g":24,"carboidrati_100g":0,"grassi_100g":11},'
        '{"nome":"Burro","grammi":10,"grammi_min":5,"grammi_max":15,"kcal_100g":740,"proteine_100g":0.7,"carboidrati_100g":0.6,"grassi_100g":82}],"note":""}');
    final r = recipeFromEstimate(est, 'Cosce in padella', id: 'r1');
    expect(r.items.map((i) => i.name), ['Cosce di pollo', 'Burro']);
    expect(r.perServing.kcal, closeTo(est.total.kcal, 0.01));
    expect(r.totalGrams, 310);
    expect(Recipe.fromMap({...r.toMap(), 'id': 'r1'}).items.length, 2);
    final f = foodFromEstimate(est, 'Cosce in padella', id: 'f1');
    expect(f.portions.single.g, 310);
    expect(f.cat, 'Piatti pronti');
    expect(f.isSeed, isFalse);
    // 674 kcal in 310 g → 217 kcal/100 g: la porzione torna alle calorie della stima
    expect(f.kcal, 217);
    expect(f.macroFor(310).kcal, closeTo(est.total.kcal, 2));
    expect(Food.fromMap({...f.toMap(), 'id': 'f1'}).src, 'photo');
  });

  test('catalogo ampliato: più scelta per le ricerche comuni', () async {
    final app = await newApp();
    expect(catalog.foods.length, greaterThan(600));
    expect(catalog.foods.map((f) => f.id).toSet().length, catalog.foods.length);
    expect(app.searchFoods('cornetto').length, greaterThanOrEqualTo(6));
    expect(app.searchFoods('pollo').length, greaterThanOrEqualTo(15));
    expect(app.searchFoods('yogurt greco').length, greaterThanOrEqualTo(6));
    final brands = app.searchFoods('', onlyBrands: true);
    expect(brands.length, greaterThanOrEqualTo(45));
    expect(app.searchFoods('nutella').first.displayName, 'Nutella · Ferrero');
    for (final f in catalog.foods) {
      expect(f.portions, isNotEmpty, reason: f.name);
      if (f.isDish) continue; // i piatti sono per 100 g di base, condimento compreso
      expect(f.kcal, inInclusiveRange(0, 900), reason: f.name);
      expect(f.p + f.c + f.f, lessThanOrEqualTo(100.5), reason: f.name);
    }
    // le cosce in padella dell'esempio: 150 g di coscia + burro e olio
    final cosce = catalog.foodById['s:cosce-di-pollo-in-padella']!;
    expect(cosce.qtyUnit, 'g cosce crude');
    expect(cosce.partsFor(150).map((e) => e.$1.name), ['Cosce di pollo con pelle (crude)', 'Burro', "Olio extravergine d'oliva"]);
  });
}
