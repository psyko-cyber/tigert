import 'dart:math' as math;

import '../core/fmt.dart';
import '../data/app_state.dart';
import '../data/models.dart';
import 'training.dart';
import 'volume.dart';

/// Giorno giustificato: quando la seduta prevista non si può fare (dolore,
/// malattia, impegno). Il voto non la conta e la seduta esce dal giro; con un
/// dolore si può fare una seduta alternativa che evita le zone indicate.

/// Zone del corpo che si possono escludere, con i gruppi muscolari del catalogo.
const bodyZones = <String, List<String>>{
  'Gambe': ['Quadricipiti', 'Femorali', 'Glutei', 'Polpacci', 'Total body'],
  'Petto': ['Petto'],
  'Schiena': ['Dorso'],
  'Spalle': ['Spalle'],
  'Braccia': ['Bicipiti', 'Tricipiti', 'Avambracci'],
  'Addome': ['Addome'],
};

String? zoneOf(String? muscle) {
  for (final e in bodyZones.entries) {
    if (e.value.contains(muscle)) return e.key;
  }
  return null;
}

Set<String> avoidedMuscles(Iterable<String> zones) => {for (final z in zones) ...?bodyZones[z]};

/// Le zone che la seduta allena di più (almeno il 30% delle serie): quelle proposte da escludere.
List<String> dayZones(AppState s, PlanDay day) {
  final by = <String, int>{};
  for (final it in day.items) {
    final z = zoneOf(s.exercise(it.ex)?.muscle);
    if (z != null) by[z] = (by[z] ?? 0) + it.sets;
  }
  if (by.isEmpty) return const [];
  final tot = by.values.fold(0, (a, b) => a + b);
  final top = by.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  return [
    for (final z in bodyZones.keys)
      if (z == top || (by[z] ?? 0) >= tot * 0.3) z,
  ];
}

class Alternative {
  final PlanDay day; // la seduta da fare
  final List<String> added; // muscoli messi al posto di quelli esclusi, dal meno allenato
  final Map<String, double> week; // serie efficaci della settimana per muscolo
  const Alternative(this.day, this.added, this.week);
}

/// La seduta da fare al posto di [skipped] quando non puoi allenare [zones].
///
/// Restano gli esercizi della seduta che non toccano le zone escluse; le serie
/// che mancano vanno ai muscoli allenati meno nella settimana (volume efficace
/// delle sedute fatte e di quelle ancora in programma), lasciando per ultimi
/// quelli allenati il giorno prima.
Alternative alternativeFor(AppState s, DateTime date, PlanDay skipped, List<String> zones) {
  final day = dateOnly(date);
  final key = dayKey(day);
  final prevKey = dayKey(day.subtract(const Duration(days: 1)));
  final mon = mondayOf(day);
  final avoid = avoidedMuscles(zones);
  String? muscleOf(String exId) => s.exercise(exId)?.muscle;

  final kept = [
    for (final it in skipped.items)
      if (muscleOf(it.ex) != null && !avoid.contains(muscleOf(it.ex))) it,
  ];
  final target = math.max(skipped.totalSets, 9);
  final missing = target - kept.fold(0, (a, it) => a + it.sets);

  // volume della settimana: sedute fatte prima di questo giorno e sedute ancora in programma
  final sessions = <List<VolSet>>[];
  final yesterday = <String>{};
  for (final ss in s.doneSessions) {
    final d = fromKey(ss.date);
    if (d.isBefore(mon) || !d.isBefore(day)) continue;
    sessions.add([
      for (final e in ss.items)
        for (final st in e.sets)
          if (st.done) VolSet(s.exercise(e.ex), st.t, st.rpe),
    ]);
    if (ss.date == prevKey) {
      for (final e in ss.items) {
        if (e.doneSets > 0) yesterday.add(muscleOf(e.ex) ?? '');
      }
    }
  }
  for (final sl in weekSchedule(s, ref: day)) {
    if (sl.session != null || sl.day == null || dayKey(sl.date) == key) continue;
    if (sl.status != SlotStatus.todo && sl.status != SlotStatus.today) continue;
    sessions.add([
      for (final it in sl.day!.items)
        for (var i = 0; i < it.sets; i++) VolSet(s.exercise(it.ex), setWork, it.rpe),
    ]);
    if (dayKey(sl.date) == prevKey) yesterday.addAll(sl.day!.items.map((it) => muscleOf(it.ex) ?? ''));
  }
  final vol = muscleVolume(sessions);
  double eff(String m) => vol[m]?.effective ?? 0;

  final keptMuscles = {for (final it in kept) muscleOf(it.ex)};
  final ranked = [
    for (final m in mainMuscles)
      if (!avoid.contains(m) && !keptMuscles.contains(m)) m,
  ]..sort((a, b) {
      final ya = yesterday.contains(a) ? 1 : 0, yb = yesterday.contains(b) ? 1 : 0;
      if (ya != yb) return ya - yb;
      final c = eff(a).compareTo(eff(b));
      return c != 0 ? c : mainMuscles.indexOf(a).compareTo(mainMuscles.indexOf(b));
    });

  // esercizi: prima quelli delle tue schede (la attiva per prima), poi il catalogo
  final plans = [if (s.activePlan != null) s.activePlan!, ...s.plans.where((p) => p.id != s.activePlan?.id)];
  final used = {for (final it in kept) it.ex};
  PlanItem? pick(String m) {
    for (final p in plans) {
      for (final d in p.days) {
        for (final it in d.items) {
          if (muscleOf(it.ex) == m && used.add(it.ex)) return it;
        }
      }
    }
    final cat = s.exercises.values.where((e) => e.muscle == m && !e.isCardio && !used.contains(e.id)).toList()
      ..sort((a, b) {
        final c = (a.type == 'c' ? 0 : 1).compareTo(b.type == 'c' ? 0 : 1);
        return c != 0 ? c : a.name.compareTo(b.name);
      });
    if (cat.isEmpty) return null;
    used.add(cat.first.id);
    return defaultItemFor(cat.first, cat.first.id);
  }

  final added = <String>[];
  final addedItems = <PlanItem>[];
  if (missing > 0 && ranked.isNotEmpty) {
    final nEx = math.max(1, (missing / 3).round());
    final chosen = ranked.take(math.min(3, nEx)).toList();
    for (var i = 0; i < nEx; i++) {
      final m = chosen[i % chosen.length];
      final it = pick(m);
      if (it == null) continue;
      addedItems.add(it.copyWith(sets: missing ~/ nEx + (i < missing % nEx ? 1 : 0)));
      if (!added.contains(m)) added.add(m);
    }
  }
  // prima i multiarticolari, poi il resto della seduta
  final order = [...addedItems]..sort((a, b) {
      final c = (s.exercise(a.ex)?.type == 'c' ? 0 : 1).compareTo(s.exercise(b.ex)?.type == 'c' ? 0 : 1);
      return c != 0 ? c : addedItems.indexOf(a).compareTo(addedItems.indexOf(b));
    });
  return Alternative(
    PlanDay(id: 'alt-$key', name: 'Al posto di ${skipped.name}', items: [...order, ...kept]),
    added,
    {for (final m in mainMuscles) m: eff(m)},
  );
}

/// Serie dirette per muscolo di una seduta della scheda.
Map<String, double> dayMuscles(AppState s, PlanDay d) {
  final m = <String, double>{};
  for (final it in d.items) {
    final mu = s.exercise(it.ex)?.muscle;
    if (mu != null) m[mu] = (m[mu] ?? 0) + it.sets;
  }
  return m;
}

/// Serie per muscolo di quello che è in calendario in un giorno ([skip]: il giorno
/// da cui parte la seduta rimandata, che resterà libero).
Map<String, double> _musclesOn(AppState s, DateTime d, String? skip) {
  if (dayKey(d) == skip) return const {};
  final sl = slotOn(s, d);
  if (sl == null || sl.status == SlotStatus.off || sl.status == SlotStatus.missed) return const {};
  final ss = sl.session;
  if (ss == null) return sl.day == null ? const {} : dayMuscles(s, sl.day!);
  final m = <String, double>{};
  for (final e in ss.items) {
    final mu = s.exercise(e.ex)?.muscle;
    if (mu != null) m[mu] = (m[mu] ?? 0) + e.sets.where((x) => !x.isWarmup).length;
  }
  return m;
}

class MoveAdvice {
  final DateTime neighbor; // giorno vicino con gli stessi muscoli
  final String neighborName;
  final List<String> muscles; // muscoli in comune
  final DateTime? better; // giorno libero senza sovrapposizioni, se c'è
  const MoveAdvice(this.neighbor, this.neighborName, this.muscles, this.better);
}

/// Rimandare [moving] a [target]: se il giorno prima o dopo c'è una seduta che
/// allena gli stessi muscoli principali (almeno 3 serie in entrambe) lo segnala,
/// e propone tra [options] un giorno senza sovrapposizioni (preferendo i giorni
/// liberi, così le altre sedute non slittano). Non cambia la scheda.
MoveAdvice? moveAdvice(AppState s, PlanDay moving, DateTime target, {String? from, List<DateTime> options = const []}) {
  final mine = dayMuscles(s, moving);
  List<String> clash(Map<String, double> other) => [
        for (final m in mainMuscles)
          if ((mine[m] ?? 0) >= 3 && (other[m] ?? 0) >= 3) m,
      ];
  (DateTime, List<String>)? worst(DateTime d) {
    (DateTime, List<String>)? out;
    for (final n in [d.subtract(const Duration(days: 1)), d.add(const Duration(days: 1))]) {
      final c = clash(_musclesOn(s, n, from));
      if (c.isNotEmpty && (out == null || c.length > out.$2.length)) out = (n, c);
    }
    return out;
  }

  final w = worst(target);
  if (w == null) return null;
  final trains = s.profile?.trainingDays ?? const <int>[];
  DateTime? better;
  for (final d in options) {
    if (d == target || trains.contains(d.weekday) || slotOn(s, d)?.day != null) continue;
    if (worst(d) == null) {
      better = d;
      break;
    }
  }
  final sl = slotOn(s, w.$1);
  return MoveAdvice(w.$1, sl?.session?.name ?? sl?.day?.name ?? 'la seduta', w.$2, better);
}

/// "Spalle, Petto e Tricipiti"
String joinIt(List<String> l) => l.length <= 1 ? l.join() : '${l.take(l.length - 1).join(', ')} e ${l.last}';
