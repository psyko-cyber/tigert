import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tigert/core/fmt.dart';
import 'package:tigert/data/app_state.dart';
import 'package:tigert/data/catalog.dart';
import 'package:tigert/data/local_prefs.dart';
import 'package:tigert/data/models.dart';
import 'package:tigert/data/store.dart';
import 'package:tigert/logic/activity.dart';
import 'package:tigert/logic/score.dart';
import 'package:tigert/logic/week_report.dart';

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
  PlanItem(ex: 'crunch', sets: 2),
]);

Profile profile({List<int> days = const [1, 3, 5], bool heavy = false, HomeGym? home}) => Profile(
      name: '',
      sex: 'm',
      birthYear: 2005,
      heightCm: 176,
      startWeight: 62,
      startDate: '2026-01-05',
      goal: Goal.bulk,
      targetWeight: 70,
      rate: 0.25,
      heavy: heavy,
      activity: 'moderato',
      kcal: 2790,
      protein: 124,
      carbs: 398,
      fat: 78,
      kcalStart: 2790,
      waterMl: 2750,
      trainingDays: days,
      planId: 'p',
      reminders: Reminders.defaults(),
      home: home,
    );

Future<AppState> newApp({List<int> days = const [1, 3, 5], HomeGym? home}) async {
  final dir = Directory.systemTemp.createTempSync('tigert_report_');
  final store = Store();
  await store.init(dir: dir);
  final prefs = LocalPrefs();
  await prefs.init(dir);
  final app = AppState(store, prefs, catalog);
  app.savePlan(Plan(id: 'p', name: 'Scheda', startDate: '2026-01-05', days: const [upperA, upperB, legs]));
  app.saveProfile(profile(days: days, home: home));
  return app;
}

Session done(DateTime d, List<(String, int)> items, {String? dayId}) => Session(
      id: 's${dayKey(d)}',
      date: dayKey(d),
      planId: dayId == null ? null : 'p',
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

/// La settimana scorsa: tre sedute senza spalle dirette.
Future<(AppState, DateTime)> lastWeek({HomeGym? home}) async {
  final app = await newApp(home: home);
  final mon = mondayOf(today()).subtract(const Duration(days: 7));
  app.saveSession(done(mon, [('lat-machine', 4), ('panca-piana', 4), ('curl-manubri', 3)], dayId: 'A'));
  app.saveSession(done(mon.add(const Duration(days: 2)), [('panca-inclinata', 4), ('curl-martello', 3)], dayId: 'B'));
  app.saveSession(done(mon.add(const Duration(days: 4)), [('squat', 4), ('stacco-rumeno', 3)], dayId: 'C'));
  return (app, mon);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => catalog = await Catalog.load());

  group('fase e voto delle calorie', () {
    test('la tolleranza dipende dalla fase', () {
      // 3.317 su 2.790 = +19%: il caso della segnalazione
      expect(kcalScoreFor(3317, 2790), closeTo(0.55, 0.01), reason: 'mantenimento: pieno fino a +10%, zero a +30%');
      expect(kcalScoreFor(3317, 2790, Phase.lean), closeTo(0.84, 0.01), reason: 'massa pulita: pieno fino a +15%, zero a +40%');
      expect(kcalScoreFor(3317, 2790, Phase.heavy), 1, reason: 'bulk pesante: pieno fino a +30%');
      expect(kcalScoreFor(4185, 2790, Phase.heavy), closeTo(0.5, 0.01), reason: '+50%: a metà strada verso lo zero del +70%');
      expect(kcalScoreFor(4800, 2790, Phase.heavy), 0);
      // sotto il target il bulk pesante resta severo come il mantenimento
      expect(kcalScoreFor(2371, 2790, Phase.heavy), closeTo(kcalScoreFor(2371, 2790), 0.001));
      expect(kcalScoreFor(2380, 2790, Phase.cut), 1, reason: 'definizione: −15% ancora pieno');
      expect(kcalScoreFor(3208, 2790, Phase.cut), closeTo(kcalScoreFor(3208, 2790), 0.001), reason: 'in definizione andare sopra conta come in mantenimento');
      expect(kcalOver(3317, 2790, Phase.heavy), isFalse);
      expect(kcalOver(3317, 2790, Phase.maintain), isTrue);
    });

    test('la fase cambia da oggi: i giorni passati tengono la loro', () {
      final p0 = profile();
      expect(p0.phase, Phase.lean);
      final p1 = p0.copyWith(heavy: true);
      final changes = p0.phasesFor(p1, '2026-09-24');
      expect(changes.single.from, Phase.lean);
      expect(changes.single.to, Phase.heavy);
      final p = Profile.fromMap(p1.copyWith(phases: changes).toMap());
      expect(p.phase, Phase.heavy);
      expect(p.phaseOn('2026-09-23'), Phase.lean);
      expect(p.phaseOn('2026-09-24'), Phase.heavy);
      expect(p.phaseOn('2026-10-10'), Phase.heavy);
      // ripensamento nello stesso giorno: resta un solo cambio, o nessuno se torni com'eri
      expect(p.phasesFor(p.copyWith(heavy: false), '2026-09-24'), isEmpty);
      final cut = p.copyWith(goal: Goal.cut);
      final c2 = p.phasesFor(cut, '2026-09-24').single;
      expect((c2.from, c2.to), (Phase.lean, Phase.cut));
      // un profilo vecchio senza storico usa la fase attuale ovunque
      expect(profile(heavy: true).phaseOn('2020-01-01'), Phase.heavy);
    });

    test('il voto di oggi usa la fase e lo dice nel dettaglio', () async {
      final app = await newApp();
      final k = todayKey();
      app.addEntry(LogEntry(id: 'e1', date: k, meal: 'pranzo', name: 'Pasta', kcal: 3317, p: 150, c: 450, f: 99, ts: 1));
      final before = app.score(k);
      expect(before.kcalScore, closeTo(0.84, 0.01));
      final p = app.profile!;
      app.saveProfile(p.copyWith(heavy: true, phases: p.phasesFor(p.copyWith(heavy: true), k)));
      final after = app.score(k);
      expect(after.kcalScore, 1);
      expect(after.v, greaterThan(before.v));
      expect(after.parts.first.rows.any((r) => r.k == 'Fase: bulk pesante'), isTrue);
    });

    test('le attività extra tolgono le calorie bruciate da quelle mangiate', () async {
      expect(activityKcal('calcetto', 60, 80), 560, reason: '(MET 8 − 1) × 80 kg × 1 h');
      expect(activityKcal('calcetto', 60, 80, 2), 720, reason: 'intensa: MET × 1,25');
      expect(activityKcal('calcetto', 60, 80, 0), 400, reason: 'leggera: MET × 0,75');
      expect(activityKcal('beach', 90, 70), 735);
      expect(activityKcal('yoga', 30, 70), 70);

      final app = await newApp();
      final k = todayKey();
      app.addEntry(LogEntry(id: 'e1', date: k, meal: 'pranzo', name: 'Pasta', kcal: 3317, p: 150, c: 450, f: 99, ts: 1));
      expect(app.score(k).kcalScore, closeTo(0.84, 0.01));
      const calcetto = ExtraActivity(kind: 'calcetto', name: 'Calcetto', min: 60, kcal: 560);
      app.saveHabit(app.habit(k).copyWith(extra: [calcetto]));
      final after = app.score(k);
      expect(after.kcalScore, 1, reason: '3.317 − 560 = 2.757 kcal nette su 2.790');
      expect(after.parts.first.rows.first.k, startsWith('Calorie nette 2.757 / 2.790'));
      expect(after.parts.first.rows.any((r) => r.v == '−560 kcal'), isTrue);

      final h = HabitDay.fromMap(app.habit(k).toMap());
      expect(h.burned, 560);
      expect(h.withOff('dolore').extra.single.name, 'Calcetto', reason: 'il giorno giustificato non cancella le attività');
      expect(const HabitDay(date: 'x').toMap().keys, isNot(contains('extra')), reason: 'i record vecchi non cambiano');
    });
  });

  group('report settimanale', () {
    test('percentuali per muscolo, cosa non va e come sistemare la scheda', () async {
      final (app, mon) = await lastWeek();
      final r = weekReport(app, mon);
      expect(r.closed, isTrue);
      expect(r.done, 3);
      expect(r.left, 0);
      MuscleWeek m(String name) => r.muscles.firstWhere((x) => x.muscle == name);
      expect(m('Dorso').status, MuscleStatus.low, reason: 'solo 4 serie di lat machine');
      expect(m('Spalle').status, MuscleStatus.low, reason: 'solo i secondari della panca');
      expect(m('Tricipiti').status, MuscleStatus.low);
      expect(m('Petto').pct, inInclusiveRange(70, 79));
      expect(r.lagging.first.total, lessThanOrEqualTo(r.lagging.last.total));
      final spalle = r.tips.firstWhere((t) => t.startsWith('Spalle'));
      expect(spalle, contains('alzate laterali'));
      expect(spalle, contains('Full upper focus schiena'), reason: 'si aggiungono alla seduta che allena già il petto');
      expect(r.home, isNull, reason: 'attrezzatura di casa non indicata');
      expect(r.summary, contains('%'));
    });

    test('la seduta a casa usa solo gli attrezzi che hai', () async {
      const gym = HomeGym(bar: true, dip: true, bench: true, dbKg: 10);
      final (app, mon) = await lastWeek(home: gym);
      final h = weekReport(app, mon).home!;
      expect(h.muscles.length, inInclusiveRange(1, 3));
      expect(h.day.totalSets, lessThanOrEqualTo(15));
      for (final it in h.day.items) {
        final e = app.exercise(it.ex)!;
        expect(canDoAtHome(e, gym), isTrue, reason: e.name);
        expect(['Manubri', 'Corpo libero'], contains(e.equip));
        if (e.equip == 'Manubri') expect(it.rMin, 12, reason: 'manubri da 10 kg: si sale di ripetizioni');
      }
      final muscles = {for (final it in h.day.items) app.exercise(it.ex)!.muscle};
      expect(muscles, containsAll(h.muscles));

      // senza manubri né parallele: per il petto restano i piegamenti, le spalle si saltano
      const bare = HomeGym();
      expect(canDoAtHome(app.exercise('push-up')!, bare), isTrue);
      expect(canDoAtHome(app.exercise('dip-petto')!, bare), isFalse);
      expect(canDoAtHome(app.exercise('alzate-laterali')!, bare), isFalse);
      expect(canDoAtHome(app.exercise('trazioni')!, const HomeGym(bar: true)), isTrue);
      expect(canDoAtHome(app.exercise('panca-inclinata-manubri')!, gym), isFalse, reason: 'serve la panca inclinabile');
      final lagging = [const MuscleWeek('Spalle', 1), const MuscleWeek('Petto', 2)];
      final only = homeSession(app, bare, lagging, id: 'x')!;
      expect(only.muscles, ['Petto']);
      expect(only.day.items.single.ex, 'push-up');
      expect(only.day.items.single.rMin, 12);
    });

    test('la settimana in corso conta anche le sedute in programma', () async {
      final app = await newApp(days: const [1, 2, 3, 4, 5, 6, 7], home: const HomeGym(dbKg: 10));
      final r = weekReport(app, today());
      expect(r.current, isTrue);
      expect(r.left, 8 - today().weekday, reason: 'da oggi a domenica');
      expect(r.muscles.any((m) => m.planned > 0), isTrue);
      expect(reportNotificationBody(app, today()), isNotEmpty);
    });

    test('attrezzatura e promemoria del report si salvano nel profilo', () {
      final p = profile(home: const HomeGym(bar: true, incline: true, dbKg: 10));
      final back = Profile.fromMap(p.toMap());
      expect(back.home!.bar, isTrue);
      expect(back.home!.has('bench'), isTrue, reason: 'la panca inclinabile fa anche da panca piana');
      expect(back.home!.dbKg, 10);
      expect(back.home!.summary, 'sbarra · panca inclinabile · manubri fino a 10 kg');
      expect(profile().toMap().keys, isNot(contains('home')));
      expect(back.reminders.reportOn, isTrue);
      expect(back.reminders.reportTime, '09:00');
      expect(Reminders.fromMap(back.reminders.copyWith(reportOn: false).toMap()).reportOn, isFalse);
    });
  });
}
