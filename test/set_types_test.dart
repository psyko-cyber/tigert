import 'package:flutter_test/flutter_test.dart';
import 'package:tigert/data/models.dart';
import 'package:tigert/logic/training.dart';

void main() {
  test('tipo di serie: default allenante e salvataggio compatto', () {
    const s = SetLog(kg: 60, reps: 8, done: true);
    expect(s.t, setWork);
    expect(s.toMap().containsKey('t'), isFalse);
    expect(SetLog.fromMap(const {'kg': 60, 'r': 8}).t, setWork, reason: 'le sessioni vecchie restano allenanti');
    expect(SetLog.fromMap(const {'kg': 30, 'r': 10, 't': 'a'}).isWarmup, isTrue);
    expect(SetLog.fromMap(const {'kg': 30, 'r': 10, 't': 'x'}).t, setWork);
    final d = s.copyWith(t: setDrop);
    expect(SetLog.fromMap(d.toMap()).isDrop, isTrue);
    expect(d.copyWith(kg: 50).isDrop, isTrue, reason: 'cambiare kg non cambia il tipo');
    expect(d.counts, isFalse);
    expect(s.counts, isTrue);
  });

  test('numerazione, serie precedente corrispondente e conteggi', () {
    final sets = [
      const SetLog(t: setWarmup, kg: 30, reps: 10, done: true),
      const SetLog(t: setWarmup, kg: 45, reps: 5, done: true),
      const SetLog(kg: 60, reps: 8, done: true),
      const SetLog(kg: 60, reps: 7, done: true),
      const SetLog(t: setDrop, kg: 45, reps: 8, done: true),
    ];
    expect([for (var i = 0; i < sets.length; i++) setBadge(sets, i)], ['A', 'A', '1', '2', 'D']);
    final prev = [const SetLog(kg: 57.5, reps: 8), const SetLog(kg: 57.5, reps: 8), const SetLog(t: setWarmup, kg: 20, reps: 10)];
    expect(matchingPrevSet(prev, sets, 0)?.kg, 20);
    expect(matchingPrevSet(prev, sets, 1), isNull);
    expect(matchingPrevSet(prev, sets, 3)?.kg, 57.5);
    expect(matchingPrevSet(prev, sets, 4), isNull);
    final e = SessionEx(ex: 'panca', name: 'Panca', type: 'c', target: const PlanItem(ex: 'panca', sets: 2), sets: sets);
    expect(e.doneSets, 3, reason: 'gli avvicinamenti non contano, il dropset sì');
    expect(e.plannedSets, 3);
    expect(e.workDone.map((x) => x.reps), [8, 7]);
    final ss = Session(id: 's', date: '2026-09-22', name: 'x', start: 0, items: [e]);
    expect(ss.volume, 60 * 8 + 60 * 7 + 45 * 8);
  });

  test('avvicinamento precompilato dalla scheda', () {
    expect(warmupSet(100, 0, 1, 2.5, 8).kg, 60);
    expect([for (var i = 0; i < 3; i++) warmupSet(100, i, 3, 2.5, 8).kg], [40, 60, 80]);
    expect([for (var i = 0; i < 3; i++) warmupSet(100, i, 3, 2.5, 8).reps], [10, 7, 4]);
    expect(warmupSet(0, 0, 2, 2.5, 8).reps, 8, reason: 'a corpo libero o prima volta');
    expect(warmupSet(62.5, 0, 1, 2.5, 8).t, setWarmup);
    expect(PlanItem.fromMap(const PlanItem(ex: 'x', warm: 2).toMap()).warm, 2);
    expect(const PlanItem(ex: 'x').toMap().containsKey('warm'), isFalse);
  });
}
