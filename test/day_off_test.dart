import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tigert/core/fmt.dart';
import 'package:tigert/data/app_state.dart';
import 'package:tigert/data/catalog.dart';
import 'package:tigert/data/local_prefs.dart';
import 'package:tigert/data/models.dart';
import 'package:tigert/data/store.dart';
import 'package:tigert/logic/day_off.dart';
import 'package:tigert/logic/training.dart';

late Catalog catalog;

const upperA = PlanDay(id: 'A', name: 'Full upper focus schiena', items: [
  PlanItem(ex: 'lat-machine', sets: 4),
  PlanItem(ex: 'panca-piana', sets: 4),
  PlanItem(ex: 'curl-manubri', sets: 3),
]);
const upperB = PlanDay(id: 'B', name: 'Full upper', items: [
  PlanItem(ex: 'panca-inclinata', sets: 4),
  PlanItem(ex: 'lento-manubri', sets: 3),
  PlanItem(ex: 'curl-martello', sets: 3),
]);
const legs = PlanDay(id: 'C', name: 'Gambe & Core', items: [
  PlanItem(ex: 'squat', sets: 4),
  PlanItem(ex: 'stacco-rumeno', sets: 3),
  PlanItem(ex: 'leg-curl-sdraiato', sets: 3),
  PlanItem(ex: 'crunch', sets: 2),
  PlanItem(ex: 'plank', sets: 2),
]);

Future<AppState> newApp(List<int> trainingDays) async {
  final dir = Directory.systemTemp.createTempSync('tigert_off_');
  final store = Store();
  await store.init(dir: dir);
  final prefs = LocalPrefs();
  await prefs.init(dir);
  final app = AppState(store, prefs, catalog);
  app.savePlan(Plan(id: 'p', name: 'Scheda', startDate: '2026-01-05', days: const [upperA, upperB, legs]));
  app.saveProfile(Profile(
    name: '',
    sex: 'm',
    birthYear: 1996,
    heightCm: 178,
    startWeight: 75,
    startDate: '2026-01-05',
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
    trainingDays: trainingDays,
    planId: 'p',
    reminders: Reminders.defaults(),
  ));
  return app;
}

/// Seduta conclusa il giorno [d] con tutte le serie fatte a RPE 8.
Session done(DateTime d, List<(String, int)> items, {String? planId, String? dayId}) => Session(
      id: 's${dayKey(d)}${dayId ?? ''}',
      date: dayKey(d),
      planId: planId,
      dayId: dayId,
      name: 'Test',
      start: d.add(const Duration(hours: 18)).millisecondsSinceEpoch,
      end: d.add(const Duration(hours: 19)).millisecondsSinceEpoch,
      status: 'done',
      items: [
        for (final (ex, n) in items)
          SessionEx(ex: ex, name: ex, type: 'c', target: PlanItem(ex: ex, sets: n), sets: [
            for (var i = 0; i < n; i++) SetLog(kg: 50, reps: 8, rpe: 8, done: true),
          ]),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => catalog = await Catalog.load());

  test('il giorno giustificato si salva nelle abitudini e resta con le altre modifiche', () {
    final h = const HabitDay(date: '2026-09-25', water: 500).withOff('dolore', dayId: 'C', avoid: ['Gambe']);
    final back = HabitDay.fromMap(h.toMap());
    expect(back.isOff, isTrue);
    expect(back.offDay, 'C');
    expect(back.avoid, ['Gambe']);
    expect(back.copyWith(water: 1000).avoid, ['Gambe'], reason: 'aggiungere acqua non cancella il giorno giustificato');
    final cleared = back.withOff('').toMap();
    expect(cleared.keys, isNot(contains('off')));
    expect(cleared.keys, isNot(contains('avoid')));
    expect(const HabitDay(date: 'x').toMap().keys, isNot(contains('off')), reason: 'i record vecchi non cambiano');
  });

  test('oggi giustificato: il voto lo conta come riposo e la seduta esce dal giro', () async {
    final app = await newApp([DateTime.now().weekday]);
    final k = todayKey();
    expect(todaySlot(app)!.day!.id, 'A');
    expect(app.score(k).rest, isFalse, reason: 'senza giustificazione il giorno di allenamento conta');

    app.setDayOff(k, 'dolore', dayId: 'A', avoid: ['Schiena']);
    final sl = todaySlot(app)!;
    expect(sl.status, SlotStatus.off);
    expect(sl.statusLabel, 'Giustificato');
    expect(sl.day!.id, 'A');
    expect(nextSlot(app)!.day!.id, 'B', reason: 'la settimana prossima si riparte dalla seduta successiva');
    final sc = app.score(k);
    expect(sc.rest, isTrue);
    expect(sc.allen, isNull);
    expect(sc.parts[1].rows.first.k, 'Giorno giustificato: dolore o infortunio');
    expect(sc.tips.any((t) => t.text.contains('allenamento')), isFalse);
    expect(weekVolume(app).planned, 0, reason: 'la seduta saltata non è più prevista');

    // seduta alternativa fatta lo stesso: conta nel voto ma non tocca il giro
    app.saveSession(done(today(), [('curl-manubri', 3)]));
    expect(todaySlot(app)!.status, SlotStatus.done);
    expect(app.score(k).rest, isFalse);
    expect(app.score(k).allen, 1);
    expect(nextSlot(app)!.day!.id, 'B');

    app.deleteSession('s$k');
    app.clearDayOff(k);
    expect(todaySlot(app)!.status, SlotStatus.today);
    expect(todaySlot(app)!.day!.id, 'A');
  });

  test('un giorno giustificato della settimana scorsa conta per il giro', () async {
    final app = await newApp([DateTime.now().weekday]);
    final lastMon = mondayOf(today()).subtract(const Duration(days: 7));
    app.saveSession(done(lastMon, [('lat-machine', 4)], planId: 'p', dayId: 'A'));
    app.saveSession(done(lastMon.add(const Duration(days: 2)), [('panca-inclinata', 4)], planId: 'p', dayId: 'B'));
    expect(todaySlot(app)!.day!.id, 'C', reason: 'senza giustificazione toccherebbe a Gambe');
    app.setDayOff(dayKey(lastMon.add(const Duration(days: 4))), 'dolore', dayId: 'C', avoid: ['Gambe']);
    expect(todaySlot(app)!.day!.id, 'A');
  });

  test('mercoledì rimandata a giovedì, venerdì gambe saltate con la seduta alternativa', () async {
    final app = await newApp(const [1, 3, 5]);
    final mon = mondayOf(today()).add(const Duration(days: 7)); // settimana prossima
    DateTime day(int i) => mon.add(Duration(days: i));
    String k(int i) => dayKey(day(i));
    expect([for (final i in [0, 2, 4]) slotOn(app, day(i))!.day!.id], ['A', 'B', 'C']);

    // mercoledì ho un impegno: Full upper la faccio giovedì
    app.setDayOff(k(2), 'impegno', dayId: 'B', moveTo: k(3));
    final wed = slotOn(app, day(2))!;
    expect(wed.status, SlotStatus.off);
    expect(wed.statusLabel, 'Rimandata');
    expect(wed.day!.id, 'B');
    final thu = slotOn(app, day(3))!;
    expect(thu.status, SlotStatus.todo);
    expect(thu.day!.id, 'B');
    expect(thu.movedFrom, k(2));
    expect(slotOn(app, day(4))!.day!.id, 'C', reason: 'venerdì resta Gambe & Core');
    expect(app.score(k(2)).rest, isTrue, reason: 'mercoledì non penalizza il voto');
    expect(app.score(k(2)).parts[1].rows.first.k, startsWith('Seduta rimandata a giovedì'));
    expect(app.score(k(3)).trainingDay, isTrue, reason: 'giovedì diventa un giorno di allenamento');

    // venerdì le gambe no: resta il core, il resto ai muscoli meno allenati
    app.setDayOff(k(4), 'dolore', dayId: 'C', avoid: ['Gambe']);
    expect(slotOn(app, day(4))!.statusLabel, 'Giustificato');
    final alt = alternativeFor(app, day(4), legs, ['Gambe']);
    expect(alt.day.items.map((it) => it.ex), containsAll(['crunch', 'plank']));
    expect(alt.added.take(2).toSet(), {'Dorso', 'Tricipiti'}, reason: 'petto, spalle e bicipiti li fai giovedì: in fondo (${alt.week})');
    expect(slotOn(app, day(7))!.day!.id, 'A', reason: 'lunedì dopo si riparte dal giro');

    // cambio idea: la faccio sabato; giovedì torna libero
    app.setDayOff(k(2), 'impegno', dayId: 'B', moveTo: k(5));
    expect(app.habit(k(3)).moved, isNull);
    expect(slotOn(app, day(3)), isNull);
    expect(slotOn(app, day(5))!.day!.id, 'B');
    // annullo: mercoledì torna com'era, sabato libero
    app.clearDayOff(k(2));
    expect(app.habit(k(5)).moved, isNull);
    expect(slotOn(app, day(2))!.day!.id, 'B');
    expect(slotOn(app, day(5)), isNull);
  });

  test('rimandare a un giorno che ha già una seduta fa slittare le successive', () async {
    final app = await newApp(const [1, 3, 5]);
    final mon = mondayOf(today()).add(const Duration(days: 7));
    app.setDayOff(dayKey(mon.add(const Duration(days: 2))), 'impegno', dayId: 'B', moveTo: dayKey(mon.add(const Duration(days: 4))));
    expect(slotOn(app, mon.add(const Duration(days: 4)))!.day!.id, 'B');
    expect(slotOn(app, mon.add(const Duration(days: 7)))!.day!.id, 'C');
  });

  test('rimandata due volte: la seduta arriva al giorno finale e la coda non salta niente', () async {
    final app = await newApp(const [1, 3, 5]);
    final mon = mondayOf(today()).add(const Duration(days: 7));
    String k(int i) => dayKey(mon.add(Duration(days: i)));
    app.setDayOff(k(2), 'impegno', dayId: 'B', moveTo: k(3));
    final thu = slotOn(app, mon.add(const Duration(days: 3)))!;
    // giovedì non riesco nemmeno: la sposto a sabato
    app.setDayOff(k(3), 'impegno', dayId: thu.day!.id, moveTo: k(5));
    expect(slotOn(app, mon.add(const Duration(days: 3)))!.statusLabel, 'Rimandata');
    expect(slotOn(app, mon.add(const Duration(days: 4)))!.day!.id, 'C');
    expect(slotOn(app, mon.add(const Duration(days: 5)))!.day!.id, 'B');
    // fatte venerdì Gambe e sabato Full upper: lunedì si riparte da capo, senza sedute perse
    app.saveSession(done(mon.add(const Duration(days: 4)), [('squat', 4)], planId: 'p', dayId: 'C'));
    app.saveSession(done(mon.add(const Duration(days: 5)), [('panca-inclinata', 4)], planId: 'p', dayId: 'B'));
    expect(slotOn(app, mon.add(const Duration(days: 7)))!.day!.id, 'A');
  });

  test('consiglio sullo spostamento: stessi muscoli il giorno dopo, propone un giorno libero migliore', () async {
    final app = await newApp(const [1, 3, 5]);
    final mon = mondayOf(today()).add(const Duration(days: 7));
    DateTime day(int i) => mon.add(Duration(days: i));
    final options = [for (var i = 1; i <= 7; i++) day(i)];
    // Full upper di mercoledì a giovedì: venerdì ci sono le gambe, nessun problema
    expect(moveAdvice(app, upperB, day(3), from: dayKey(day(2)), options: options), isNull);
    // Full upper focus schiena di lunedì a martedì: mercoledì c'è l'altra Full upper
    final a = moveAdvice(app, upperA, day(1), from: dayKey(day(0)), options: options)!;
    expect(a.neighbor, day(2));
    expect(a.neighborName, 'Full upper');
    expect(a.muscles, ['Petto', 'Bicipiti']);
    expect(a.better, day(5), reason: 'sabato è libero e venerdì ci sono le gambe');
  });

  test('zone della seduta: Gambe & Core propone di escludere le gambe', () async {
    final app = await newApp(const []);
    expect(dayZones(app, legs), ['Gambe']);
    expect(dayZones(app, upperA), ['Petto', 'Schiena']);
    expect(avoidedMuscles(['Gambe']), containsAll(['Quadricipiti', 'Femorali', 'Glutei', 'Polpacci']));
  });

  test('seduta alternativa: niente gambe, resta il core, i muscoli meno allenati della settimana', () async {
    final app = await newApp(const []);
    final fri = mondayOf(today()).add(const Duration(days: 11)); // venerdì della settimana prossima
    app.saveSession(done(fri.subtract(const Duration(days: 4)), [('panca-piana', 4), ('lat-machine', 4), ('curl-manubri', 3)]));
    app.saveSession(done(fri.subtract(const Duration(days: 2)), [('panca-piana', 3), ('lat-machine', 3), ('curl-manubri', 3)]));

    final alt = alternativeFor(app, fri, legs, ['Gambe']);
    final muscles = [for (final it in alt.day.items) app.exercise(it.ex)!.muscle];
    expect(alt.day.name, 'Al posto di Gambe & Core');
    expect(muscles.where((m) => ['Quadricipiti', 'Femorali', 'Glutei', 'Polpacci'].contains(m)), isEmpty);
    expect(alt.day.items.map((it) => it.ex), containsAll(['crunch', 'plank']), reason: 'gli esercizi che non toccano le gambe restano');
    expect(alt.day.totalSets, legs.totalSets, reason: 'stesse serie della seduta saltata');
    expect(alt.added.take(2), ['Spalle', 'Tricipiti'], reason: 'solo serie indirette dalla panca: ${alt.week}');
    expect(alt.day.items.first.ex, 'lento-manubri', reason: 'prima gli esercizi delle tue schede');
    expect(alt.day.items.map((it) => it.sets).take(3), [4, 3, 3]);

    // spalle allenate il giorno prima: passano in fondo
    app.saveSession(done(fri.subtract(const Duration(days: 1)), [('lento-manubri', 3)]));
    final alt2 = alternativeFor(app, fri, legs, ['Gambe']);
    expect(alt2.added.first, 'Tricipiti');
    expect(alt2.added, isNot(contains('Spalle')));
  });
}
