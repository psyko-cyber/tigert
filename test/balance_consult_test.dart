import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tigert/core/fmt.dart';
import 'package:tigert/data/app_state.dart';
import 'package:tigert/data/catalog.dart';
import 'package:tigert/data/local_prefs.dart';
import 'package:tigert/data/models.dart';
import 'package:tigert/data/store.dart';
import 'package:tigert/logic/balance.dart';
import 'package:tigert/logic/consult.dart';
import 'package:tigert/logic/nutrition.dart';
import 'package:tigert/logic/score.dart';
import 'package:tigert/services/notifications.dart';

late Catalog catalog;

Future<AppState> newApp() async {
  final dir = Directory.systemTemp.createTempSync('tigert_bal_');
  final store = Store();
  await store.init(dir: dir);
  final prefs = LocalPrefs();
  await prefs.init(dir);
  final app = AppState(store, prefs, catalog);
  final plan = templateByKey('ulpp').toPlan();
  store.put('plans', plan.id, plan.toMap());
  app.saveProfile(Profile(
    name: '',
    sex: 'm',
    birthYear: 1996,
    heightCm: 178,
    startWeight: 75,
    startDate: addDaysKey(todayKey(), -60),
    goal: Goal.bulk,
    targetWeight: 80,
    rate: 0.25,
    activity: 'moderato',
    kcal: 2800,
    protein: 150,
    carbs: 380,
    fat: 75,
    kcalStart: 2800,
    waterMl: 3000,
    trainingDays: const [1, 3, 5],
    planId: plan.id,
    reminders: Reminders.defaults(),
  ));
  return app;
}

/// Una seduta conclusa `daysAgo` giorni fa con un esercizio; [day] la lega alla scheda.
Session done(AppState app, String exId, int daysAgo, List<(double, int)> sets, {PlanDay? day}) {
  final d = DateTime.now().subtract(Duration(days: daysAgo));
  return Session(
    id: 's$exId$daysAgo',
    date: dayKey(d),
    planId: day == null ? null : app.activePlan!.id,
    dayId: day?.id,
    name: day?.name ?? 'Test',
    start: d.millisecondsSinceEpoch,
    end: d.millisecondsSinceEpoch + 3600000,
    status: 'done',
    items: [
      SessionEx(ex: exId, name: app.exerciseName(exId), type: 'c', target: PlanItem(ex: exId, sets: sets.length), sets: [
        for (final (kg, r) in sets) SetLog(kg: kg, reps: r, rpe: 10, done: true),
      ]),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => catalog = await Catalog.load());

  group('peso', () {
    test('poche pesate: dice quante ne mancano', () async {
      final app = await newApp();
      expect(weightTrend(app.weightStats).missing, 4);
      app.setWeight(todayKey(), 76.1);
      app.setWeight(addDaysKey(todayKey(), -30), 75);
      final t = weightTrend(app.weightStats);
      expect((t.slope, t.missing), (null, 3), reason: 'conta solo le ultime 3 settimane');
    });

    test('con 4 pesate in 3 settimane c\'è l\'andamento e il giudizio sul ritmo', () async {
      final app = await newApp();
      for (final (ago, kg) in [(18, 75.0), (12, 75.2), (6, 75.45), (0, 75.65)]) {
        app.setWeight(addDaysKey(todayKey(), -ago), kg);
      }
      final t = weightTrend(app.weightStats);
      expect(t.slope, closeTo(0.25, 0.03));
      final p = app.profile!;
      expect(weightVerdict(p, t.slope!), ('in linea', true));
      expect(weightVerdict(p, 0.05), ('lento', false));
      expect(weightVerdict(p, 0.6), ('veloce', false));
      expect(weightVerdict(p.copyWith(goal: Goal.maintain), 0.3), ('in salita', false));
    });

    test('promemoria: tre mattine a settimana', () {
      expect(weighDays, [DateTime.monday, DateTime.thursday, DateTime.saturday]);
    });
  });

  group('bilancio della settimana', () {
    test('quattro righe: peso, forza, volume, costanza', () async {
      final app = await newApp();
      app.saveSession(done(app, 'panca-piana', 8, [(60, 8), (60, 8)]));
      app.saveSession(done(app, 'lat-machine', 8, [(55, 8)]));
      app.saveSession(done(app, 'panca-piana', 0, [(62.5, 8), (62.5, 7)]));
      app.saveSession(done(app, 'lat-machine', 0, [(50, 8)]));
      final mon = mondayOf(today());
      expect(strengthWeek(app, mon), (up: 1, down: 1, same: 0));
      final b = weekBalance(app, today());
      expect(b.rows.map((r) => r.k), ['Peso', 'Forza', 'Volume', 'Costanza']);
      expect(b.rows[0].v, 'mancano 4 pesate');
      expect((b.rows[1].v, b.rows[1].tone), ('1 su · 1 giù · 0 uguali', Tone.warn));
      expect(b.rows[3].v, startsWith('2 sedute su 3'));
      expect(balanceNotificationBody(app, today()), contains('Forza 1 su'));
    });

    test('confronto di forza solo con una volta prima recente', () async {
      final app = await newApp();
      app.saveSession(done(app, 'leg-press', 90, [(70, 8)]));
      app.saveSession(done(app, 'leg-press', 0, [(50, 10)]));
      expect(strengthWeek(app, mondayOf(today())), (up: 0, down: 0, same: 0), reason: 'un rientro non è un calo');
    });

    test('seduta della scheda saltata da settimane', () async {
      final app = await newApp();
      final days = app.activePlan!.days;
      expect(skippedDay(app), isNull);
      for (final ago in [22, 15, 8, 1]) {
        app.saveSession(done(app, 'panca-piana', ago, [(60, 8)], day: days.first));
      }
      // le altre le fai, queste no: segnala quella ferma da più tempo
      final sk = skippedDay(app)!;
      expect(days.skip(1).map((d) => d.id), contains(sk.$1.id));
      expect(sk.$2, 3);
      expect(weekBalance(app, today()).note, contains('manca da 3 settimane'));
      for (final d in days.skip(1)) {
        app.saveSession(done(app, 'squat', 2 + days.indexOf(d), [(80, 8)], day: d));
      }
      expect(skippedDay(app), isNull);
    });

    test('meno sedute dei giorni scelti: propone di adeguare i giorni', () async {
      final app = await newApp();
      final mon = mondayOf(today());
      expect(slowPace(app, mon), isNull, reason: 'senza sedute non c\'è un ritmo da leggere');
      // 2 sedute a settimana per 4 settimane, con 3 giorni in profilo
      for (var w = 1; w <= 4; w++) {
        for (final day in [1, 4]) {
          final ago = daysBetween(addDays(mon, -7 * w + day), today());
          app.saveSession(done(app, 'panca-piana', ago, [(60, 8)]));
        }
      }
      expect(slowPace(app, mon), 2);
      expect(weekBalance(app, today()).note, contains('2 sedute a settimana su 3'));
      expect(weekBalance(app, today()).note, contains('imposta 2 giorni nel Profilo'));
      app.saveProfile(app.profile!.copyWith(trainingDays: const [1, 4]));
      expect(slowPace(app, mon), isNull);
    });
  });

  group('consulenza', () {
    test('il testo da copiare ha istruzioni, dati e domanda', () async {
      final app = await newApp();
      app.setWeight(todayKey(), 76.1);
      app.saveSession(done(app, 'panca-piana', 3, [(60, 8), (60, 7)]));
      app.saveHabit(HabitDay(date: addDaysKey(todayKey(), -1), water: 3000, sleep: 420).withOff('dolore', avoid: const ['Gambe']));
      final chicken = catalog.foods.firstWhere((f) => fold(f.name).contains('petto di pollo'));
      app.addEntry(app.entryFromFood(chicken, 1000, date: addDaysKey(todayKey(), -2), meal: 'pranzo'));
      final t = consultText(app, days: 7, question: 'Conviene passare a 2 sedute?');
      expect(t, startsWith('# Consulenza Tigert'));
      for (final part in [
        consultMarker,
        '## Io',
        'massa pulita, +0,25 kg/sett fino a 80 kg',
        '## La mia domanda\nConviene passare a 2 sedute?',
        '## Peso',
        '76,1',
        'giustificata (dolore o infortunio: gambe)',
        '- Panca piana con bilanciere [Petto] 2×8-12: 60×8@10 60×7@10 · prima volta',
        '## Bilancio di questa settimana',
      ]) {
        expect(t, contains(part));
      }
      expect(t, isNot(contains('Priorità della consulenza')), reason: 'nessuna consulenza prima');
    });

    test('priorità lette dalla risposta, salvate e riportate nella consulenza dopo', () async {
      final app = await newApp();
      const reply = 'Va bene il diario.\n\n**PRIORITÀ**\n1) Pesati lunedì, giovedì e sabato\n2) **Gambe** al 70%, niente cedimento\n3) Nel weekend +300 kcal\n';
      final items = parsePriorities(reply);
      expect(items, ['Pesati lunedì, giovedì e sabato', 'Gambe al 70%, niente cedimento', 'Nel weekend +300 kcal']);
      app.saveConsult(Consult(id: todayKey(), reply: reply, items: items));
      app.saveConsult(app.lastConsult!.toggle(1));
      expect(app.lastConsult!.done, [1]);
      final t = consultText(app, days: 7);
      expect(t, contains('- [fatta] Gambe al 70%, niente cedimento'));
      expect(t, contains('- [non fatta] Nel weekend +300 kcal'));
    });

    test('risposte scritte in altri modi', () {
      expect(parsePriorities('## Priorità\n1. Uno\n2. Due'), ['Uno', 'Due']);
      expect(parsePriorities('Le priorità sono importanti.\n\nPRIORITÀ:\n- 1) Uno\n- 2) Due\n- 3) Tre'), ['Uno', 'Due', 'Tre']);
      // senza il titolo: vale l'ultimo elenco numerato
      expect(parsePriorities('Cosa va:\n1. bene\n2. benino\n\nAzioni:\n1) Prima\n2) Seconda'), ['Prima', 'Seconda']);
      expect(parsePriorities('PRIORITÀ\n1) ...\n2) ...'), isEmpty, reason: 'il modello vuoto non è una risposta');
      expect(parsePriorities('Nessun elenco qui.'), isEmpty);
    });
  });

  test('acqua: due promemoria al giorno nella fascia scelta', () {
    final t = waterTimes(DateTime(2026, 10, 12, 9), DateTime(2026, 10, 12, 21));
    expect(t.map(hhmm), ['13:00', '17:00']);
  });
}
