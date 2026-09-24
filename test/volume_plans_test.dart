import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tigert/core/fmt.dart';
import 'package:tigert/data/app_state.dart';
import 'package:tigert/data/catalog.dart';
import 'package:tigert/data/local_prefs.dart';
import 'package:tigert/data/models.dart';
import 'package:tigert/data/store.dart';
import 'package:tigert/logic/training.dart';
import 'package:tigert/logic/volume.dart';

const panca = Exercise(id: 'panca', name: 'Panca', muscle: 'Petto', equip: 'Bilanciere', type: 'c', inc: 2.5);
const curl = Exercise(id: 'curl', name: 'Curl', muscle: 'Bicipiti', equip: 'Manubri', type: 'i', inc: 1);
const squat = Exercise(id: 'squat', name: 'Squat', muscle: 'Quadricipiti', equip: 'Bilanciere', type: 'c', inc: 2.5);

List<VolSet> sets(Exercise ex, int n, {String t = setWork, double? rpe}) => [for (var i = 0; i < n; i++) VolSet(ex, t, rpe)];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('volume efficace', () {
    test('8 serie di petto a inizio seduta valgono più di 10 di bicipiti in coda', () {
      final v = muscleVolume([
        [...sets(panca, 8), ...sets(squat, 8), ...sets(curl, 10)],
      ]);
      expect(v['Petto']!.sets, 8);
      expect(v['Bicipiti']!.sets, 10);
      expect(v['Petto']!.direct, greaterThan(v['Bicipiti']!.direct));
      expect(v['Bicipiti']!.quality, lessThan(0.7));
      // la panca dà mezza serie (pesata) a tricipiti e spalle, il curl (isolamento) a nessuno
      expect(v['Tricipiti']!.effective, closeTo(v['Petto']!.direct * 0.5, 0.001));
      expect(v['Tricipiti']!.sets, 0);
    });

    test('al parchetto trazioni e dip contano anche per bicipiti e tricipiti', () {
      const trazioni = Exercise(id: 'trazioni', name: 'Trazioni', muscle: 'Dorso', equip: 'Corpo libero', type: 'b', inc: 2.5);
      const dip = Exercise(id: 'dip-petto', name: 'Dip', muscle: 'Petto', equip: 'Corpo libero', type: 'b', inc: 2.5);
      const plank = Exercise(id: 'plank', name: 'Plank (secondi)', muscle: 'Addome', equip: 'Corpo libero', type: 'b', inc: 0);
      final v = muscleVolume([
        [...sets(trazioni, 4), ...sets(dip, 4), ...sets(plank, 3)],
      ]);
      expect(v['Bicipiti']!.effective, closeTo(v['Dorso']!.direct * 0.5, 0.001));
      expect(v['Tricipiti']!.effective, closeTo(v['Petto']!.direct * 0.5, 0.001));
      expect(isCompound(plank), isFalse);
    });

    test('avvicinamenti esclusi, dropset a metà, RPE basso vale meno', () {
      final v = muscleVolume([
        [...sets(panca, 2, t: setWarmup), ...sets(panca, 1), ...sets(panca, 1, t: setDrop)],
      ]);
      expect(v['Petto']!.sets, 1.5);
      expect(v['Petto']!.direct, closeTo(1 + 0.5 * 0.975, 0.001), reason: 'il dropset arriva dopo una serie allenante');
      final easy = muscleVolume([sets(panca, 1, rpe: 6)]);
      expect(easy['Petto']!.direct, 0.5);
    });

    test('consigli: serie in coda, volume basso, squilibri', () {
      final v = muscleVolume([
        for (var d = 0; d < 2; d++) [...sets(panca, 6), ...sets(squat, 12), ...sets(curl, 5)],
      ]);
      final tips = volumeTips(v);
      expect(tips.any((t) => t.muscle == 'Bicipiti' && t.text.contains('fine seduta')), isTrue, reason: tips.map((t) => t.text).join('\n'));
      expect(tips.where((t) => t.text.startsWith('Nessuna serie')).single.text, contains('Dorso, Femorali'), reason: 'un solo consiglio per tutti');
      final unbalanced = volumeTips(muscleVolume([
        [...sets(squat, 12), ...sets(const Exercise(id: 'lc', name: 'Leg curl', muscle: 'Femorali', equip: 'Macchina', type: 'i', inc: 2.5), 4)],
      ]));
      expect(unbalanced.any((t) => t.text.startsWith('Quadricipiti riceve')), isTrue, reason: unbalanced.map((t) => t.text).join('\n'));
    });
  });

  group('schede', () {
    test('ciclo su 2 settimane: giorni in ordine di settimana e salvataggio compatto', () {
      final p = Plan(id: 'p', name: 'Split', startDate: '2026-09-01', cycle: 2, days: const [
        PlanDay(id: 'a', name: 'Upper A'),
        PlanDay(id: 'push', name: 'Push', week: 2),
        PlanDay(id: 'b', name: 'Upper B'),
        PlanDay(id: 'legs2', name: 'Legs', week: 2),
        PlanDay(id: 'legs', name: 'Legs'),
      ]).normalized();
      expect(p.days.map((d) => d.id), ['a', 'b', 'legs', 'push', 'legs2']);
      final back = Plan.fromMap({...p.toMap(), 'id': 'p'});
      expect(back.cycle, 2);
      expect(back.days.map((d) => d.week), [1, 1, 1, 2, 2]);
      // tornando a una settimana tutti i giorni finiscono nella A
      expect(back.copyWith(cycle: 1).normalized().days.every((d) => d.week == 1), isTrue);
      expect(const PlanDay(id: 'x', name: 'x').toMap().containsKey('week'), isFalse);
      expect(weekLetter(2), 'B');
      final copy = back.duplicate('q', () => 'd${DateTime.now().microsecondsSinceEpoch}');
      expect(copy.name, 'Split (copia)');
      expect(copy.cycle, 2);
      expect(copy.days.map((d) => d.id).toSet().intersection(back.days.map((d) => d.id).toSet()), isEmpty);
    });

    test('eliminare la scheda attiva ne attiva un\'altra; la rotazione segue il ciclo', () async {
      final dir = Directory.systemTemp.createTempSync('tigert_plans_');
      final store = Store();
      await store.init(dir: dir);
      final prefs = LocalPrefs();
      await prefs.init(dir);
      final app = AppState(store, prefs, await Catalog.load());
      final a = templateByKey('ulpp').toPlan();
      final b = Plan(id: 'cyc', name: 'Ciclo', startDate: todayKey(), cycle: 2, days: [
        for (var i = 0; i < a.days.length; i++) a.days[i].copyWith(week: i.isEven ? 1 : 2),
      ]);
      app.savePlan(a);
      app.savePlan(b);
      app.saveProfile(Profile(
        name: '',
        sex: 'm',
        birthYear: 1996,
        heightCm: 178,
        startWeight: 75,
        startDate: todayKey(),
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
        trainingDays: const [1, 2, 3, 4, 5, 6, 7],
        planId: a.id,
        reminders: Reminders.defaults(),
      ));
      expect(app.plan('cyc')!.days.map((d) => d.week), [1, 1, 2, 2], reason: 'salvata già ordinata per settimana');
      app.deletePlan(a.id, activate: 'cyc');
      expect(app.plans.map((p) => p.id), ['cyc']);
      expect(app.activePlan!.id, 'cyc');
      final slots = weekSchedule(app).where((s) => s.day != null).map((s) => s.day!.week).take(4).toList();
      // la settimana in corso può avere meno di 4 giorni rimasti (venerdì-domenica)
      expect(slots, isNotEmpty);
      expect(slots, [1, 1, 2, 2].take(slots.length).toList());
      expect(planVolume(app, app.activePlan!), isNotEmpty);
    });
  });
}
