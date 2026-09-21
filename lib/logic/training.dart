import 'dart:math' as math;

import '../core/fmt.dart';
import '../core/ids.dart';
import '../data/app_state.dart';
import '../data/models.dart';

// =================================================================== settimana

enum SlotStatus { done, today, todo, missed, extra }

class WeekSlot {
  final DateTime date;
  final PlanDay? day;
  final SlotStatus status;
  final Session? session;
  const WeekSlot(this.date, this.day, this.status, this.session);

  String get statusLabel => switch (status) {
        SlotStatus.done || SlotStatus.extra => 'Fatto',
        SlotStatus.today => session != null && session!.isActive ? 'In corso' : 'Oggi',
        SlotStatus.todo => 'Da fare',
        SlotStatus.missed => 'Saltato',
      };
}

/// Calendario della settimana: le sedute della scheda ruotano sui giorni
/// scelti. Se salti un giorno, la seduta successiva resta quella in coda.
List<WeekSlot> weekSchedule(AppState s, {DateTime? ref}) =>
    s.memo('week:${dayKey(mondayOf(ref ?? DateTime.now()))}', () => _weekSchedule(s, ref));

List<WeekSlot> _weekSchedule(AppState s, DateTime? ref) {
  final p = s.profile;
  final plan = s.activePlan;
  if (p == null || plan == null || plan.days.isEmpty) return const [];
  final mon = mondayOf(ref ?? DateTime.now());
  final t = today();
  final n = plan.days.length;
  var idx = s.doneSessions.where((x) => x.planId == plan.id && fromKey(x.date).isBefore(mon)).length;
  final out = <WeekSlot>[];
  for (var i = 0; i < 7; i++) {
    final d = mon.add(Duration(days: i));
    final key = dayKey(d);
    final sessions = (s.sessionsByDate[key] ?? const <Session>[]).toList();
    final trainDay = p.trainingDays.contains(d.weekday);
    if (sessions.isNotEmpty) {
      for (final ss in sessions) {
        final day = plan.day(ss.dayId ?? '') ?? (ss.planId == plan.id ? plan.days[idx % n] : null);
        final isToday = d == t;
        out.add(WeekSlot(d, day, ss.isActive ? SlotStatus.today : (trainDay || isToday ? SlotStatus.done : SlotStatus.extra), ss));
        if (!ss.isActive && ss.planId == plan.id) idx++;
      }
      continue;
    }
    if (!trainDay) continue;
    if (d.isBefore(t)) {
      out.add(WeekSlot(d, null, SlotStatus.missed, null));
    } else {
      out.add(WeekSlot(d, plan.days[idx % n], d == t ? SlotStatus.today : SlotStatus.todo, null));
      idx++;
    }
  }
  return out;
}

/// La prossima seduta da fare (oggi se è un giorno di allenamento).
WeekSlot? nextSlot(AppState s) {
  final slots = weekSchedule(s);
  for (final sl in slots) {
    if (sl.status == SlotStatus.today || sl.status == SlotStatus.todo) return sl;
  }
  // settimana finita: primo slot della prossima
  final next = weekSchedule(s, ref: DateTime.now().add(const Duration(days: 7)));
  for (final sl in next) {
    if (sl.status == SlotStatus.todo || sl.status == SlotStatus.today) return sl;
  }
  return null;
}

WeekSlot? todaySlot(AppState s) {
  final t = today();
  for (final sl in weekSchedule(s)) {
    if (sl.date == t) return sl;
  }
  return null;
}

int planWeek(Plan plan) => math.max(1, daysBetween(fromKey(plan.startDate), today()) ~/ 7 + 1);

class WeekVolume {
  final int done, planned, prs;
  const WeekVolume(this.done, this.planned, this.prs);
}

WeekVolume weekVolume(AppState s) {
  final slots = weekSchedule(s);
  var done = 0, planned = 0;
  for (final sl in slots) {
    if (sl.session != null) {
      done += sl.session!.doneSets;
      planned += sl.session!.plannedSets;
    } else if (sl.day != null) {
      planned += sl.day!.totalSets;
    }
  }
  final mon = mondayOf(DateTime.now());
  final prs = allPrs(s).where((e) => !fromKey(e.date).isBefore(mon)).length;
  return WeekVolume(done, planned, prs);
}

// =================================================================== sessione

String _fmtPrev(SetLog s, Exercise? ex) {
  if (ex?.isCardio == true) return '${s.reps} min';
  if (s.kg <= 0) return '${s.reps} ${ex?.repsLabel ?? 'rip'}';
  return '${fKg(s.kg)}×${s.reps}';
}

String prevLabel(SetLog s, Exercise? ex) => _fmtPrev(s, ex);

/// Crea una nuova sessione precompilata con i carichi suggeriti.
Session buildSession(AppState s, {Plan? plan, PlanDay? day, String? name}) {
  final items = <SessionEx>[];
  for (final it in day?.items ?? const <PlanItem>[]) {
    items.add(buildSessionEx(s, it));
  }
  return Session(
    id: newId(),
    date: todayKey(),
    planId: plan?.id,
    dayId: day?.id,
    name: name ?? day?.name ?? 'Allenamento libero',
    start: DateTime.now().millisecondsSinceEpoch,
    items: items,
  );
}

SessionEx buildSessionEx(AppState s, PlanItem it) {
  final ex = s.exercise(it.ex);
  final sug = suggestFor(s, it);
  final last = s.lastPerformance(it.ex);
  final sets = <SetLog>[];
  for (var i = 0; i < it.sets; i++) {
    final prev = (last != null && i < last.$2.sets.length) ? last.$2.sets[i] : null;
    sets.add(SetLog(
      kg: sug.kg > 0 ? sug.kg : (prev?.kg ?? 0),
      reps: sug.increase ? it.rMin : (prev?.reps ?? it.rMin),
      rpe: null,
      done: false,
    ));
  }
  return SessionEx(ex: it.ex, name: ex?.name ?? 'Esercizio', type: ex?.type ?? 'c', target: it, sets: sets);
}

class Suggestion {
  final double kg;
  final int reps;
  final bool increase;
  final String title;
  final String text;
  const Suggestion(this.kg, this.reps, this.increase, this.title, this.text);
}

/// Doppia progressione: quando tutte le serie arrivano al tetto delle
/// ripetizioni entro l'RPE target, si alza il carico e si riparte dal minimo.
Suggestion suggestFor(AppState s, PlanItem it, {int? beforeTs}) {
  final ex = s.exercise(it.ex);
  final last = s.lastPerformance(it.ex, beforeTs: beforeTs);
  if (last == null) {
    return Suggestion(0, it.rMin, false, 'Prima volta',
        ex?.isCardio == true ? 'Scegli un ritmo sostenibile per ${it.rMin}-${it.rMax} minuti.' : 'Scegli un carico con cui arrivi a ${it.rMin}-${it.rMax} ripetizioni a RPE ${fDec(it.rpe, 1, true)}.');
  }
  final done = last.$2.sets.where((x) => x.done).toList();
  final topKg = done.fold<double>(0, (a, b) => math.max(a, b.kg));
  final atTop = done.length >= it.sets &&
      done.every((x) => x.reps >= it.rMax && (x.rpe == null || x.rpe! <= it.rpe + 0.01));
  if (atTop) {
    final inc = ex?.inc ?? 2.5;
    if (inc > 0 && ex?.isCardio != true) {
      final kg = topKg + inc;
      return Suggestion(kg, it.rMin, true, 'Tetto raggiunto: ${it.sets}×${it.rMax} @ RPE ${fDec(it.rpe, 1, true)}',
          'Sali a ${fKg(kg)} kg e riparti da ${it.rMin} ripetizioni.');
    }
    return Suggestion(topKg, it.rMax + 1, false, 'Tetto raggiunto', 'Aggiungi una ripetizione per serie o passa a una variante più dura.');
  }
  final bestReps = done.where((x) => x.kg == topKg).fold<int>(0, (a, b) => math.max(a, b.reps));
  final target = math.min(it.rMax, bestReps + 1);
  return Suggestion(topKg, target, false, 'Obiettivo di oggi',
      topKg > 0 ? 'Stesso carico (${fKg(topKg)} kg): punta a $target ripetizioni per serie.' : 'Punta a $target ${ex?.repsLabel ?? 'rip'} per serie.');
}

/// Suggerimento dal vivo mentre si allena: tetto raggiunto in questa sessione?
Suggestion? liveTip(AppState s, SessionEx e) {
  final ex = s.exercise(e.ex);
  final done = e.sets.where((x) => x.done).toList();
  final it = e.target;
  if (done.length < it.sets || done.isEmpty) return null;
  final atTop = done.every((x) => x.reps >= it.rMax && (x.rpe == null || x.rpe! <= it.rpe + 0.01));
  if (!atTop) return null;
  final topKg = done.fold<double>(0, (a, b) => math.max(a, b.kg));
  final inc = ex?.inc ?? 2.5;
  if (inc <= 0 || ex?.isCardio == true) {
    return Suggestion(topKg, it.rMax + 1, false, 'Tetto raggiunto', 'La prossima volta aggiungi una ripetizione per serie.');
  }
  return Suggestion(topKg + inc, it.rMin, true, 'Tetto raggiunto: ${it.sets}×${it.rMax} @ RPE ${fDec(it.rpe, 1, true)}',
      'Sali a ${fKg(topKg + inc)} kg la prossima volta e riparti da ${it.rMin} ripetizioni.');
}

// =================================================================== record

class PrEvent {
  final String exId;
  final String exName;
  final String date;
  final SetLog set;
  final double e1rm;
  final double? prev;
  const PrEvent(this.exId, this.exName, this.date, this.set, this.e1rm, this.prev);
  double get pct => prev == null || prev! <= 0 ? 0 : (e1rm - prev!) / prev! * 100;
}

/// Tutti i record battuti (1RM stimato) in ordine cronologico.
/// La prima volta che si fa un esercizio non conta come record.
List<PrEvent> allPrs(AppState s) => s.memo('allPrs', () => _allPrs(s));

List<PrEvent> _allPrs(AppState s) {
  final best = <String, double>{};
  final out = <PrEvent>[];
  for (final ss in s.doneSessions) {
    for (final e in ss.items) {
      if (e.type == 'k') continue;
      SetLog? top;
      for (final st in e.sets) {
        if (!st.done || st.reps <= 0) continue;
        final v = st.kg > 0 ? st.e1rm : st.reps.toDouble();
        if (top == null || v > (top.kg > 0 ? top.e1rm : top.reps.toDouble())) top = st;
      }
      if (top == null) continue;
      final v = top.kg > 0 ? top.e1rm : top.reps.toDouble();
      final prev = best[e.ex];
      if (prev != null && v > prev + 0.01) out.add(PrEvent(e.ex, e.name, ss.date, top, v, prev));
      if (prev == null || v > prev) best[e.ex] = v;
    }
  }
  return out;
}

List<PrEvent> sessionPrs(AppState s, Session ss) => allPrs(s).where((p) => p.date == ss.date && ss.items.any((e) => e.ex == p.exId)).toList();

class ExerciseBest {
  final String exId;
  final String name;
  final SetLog best;
  final String date;
  final double e1rm;
  final double? pct4w; // variazione rispetto a 4 settimane fa
  const ExerciseBest(this.exId, this.name, this.best, this.date, this.e1rm, this.pct4w);
}

List<ExerciseBest> bestByExercise(AppState s) => s.memo('bestByExercise', () => _bestByExercise(s));

List<ExerciseBest> _bestByExercise(AppState s) {
  final byEx = <String, List<(Session, SetLog)>>{};
  final names = <String, String>{};
  for (final ss in s.doneSessions) {
    for (final e in ss.items) {
      if (e.type == 'k') continue;
      names[e.ex] = e.name;
      for (final st in e.sets) {
        if (st.done && st.reps > 0) (byEx[e.ex] ??= []).add((ss, st));
      }
    }
  }
  final cutoff = today().subtract(const Duration(days: 28));
  final out = <ExerciseBest>[];
  byEx.forEach((ex, list) {
    double val(SetLog st) => st.kg > 0 ? st.e1rm : st.reps.toDouble();
    var best = list.first;
    for (final x in list) {
      if (val(x.$2) > val(best.$2)) best = x;
    }
    final older = list.where((x) => fromKey(x.$1.date).isBefore(cutoff)).toList();
    double? pct;
    if (older.isNotEmpty) {
      final ob = older.map((x) => val(x.$2)).reduce(math.max);
      if (ob > 0) pct = (val(best.$2) - ob) / ob * 100;
    }
    out.add(ExerciseBest(ex, s.exercise(ex)?.name ?? names[ex] ?? ex, best.$2, best.$1.date, val(best.$2), pct));
  });
  out.sort((a, b) => b.date.compareTo(a.date));
  return out;
}

/// Storico di un esercizio: miglior serie per sessione.
List<(Session, SetLog)> exerciseHistory(AppState s, String exId) {
  final out = <(Session, SetLog)>[];
  for (final ss in s.doneSessions) {
    for (final e in ss.items) {
      if (e.ex != exId) continue;
      SetLog? top;
      for (final st in e.sets) {
        if (!st.done) continue;
        if (top == null || st.e1rm > top.e1rm || (st.kg == 0 && st.reps > top.reps)) top = st;
      }
      if (top != null) out.add((ss, top));
    }
  }
  return out;
}

/// Confronto di un esercizio con la volta precedente, per il riepilogo.
String compareTag(AppState s, Session ss, SessionEx e) {
  final prev = s.lastPerformance(e.ex, beforeTs: ss.start);
  final done = e.sets.where((x) => x.done).toList();
  if (done.isEmpty) return 'saltato';
  if (prev == null) return 'nuovo';
  final pd = prev.$2.sets.where((x) => x.done).toList();
  if (pd.isEmpty) return 'nuovo';
  final kgNow = done.map((x) => x.kg).reduce(math.max);
  final kgPrev = pd.map((x) => x.kg).reduce(math.max);
  if (kgNow > kgPrev + 0.01) return '+${fKg(kgNow - kgPrev)} kg';
  if (kgNow < kgPrev - 0.01) return '−${fKg(kgPrev - kgNow)} kg';
  final rNow = done.fold<int>(0, (a, b) => a + b.reps);
  final rPrev = pd.fold<int>(0, (a, b) => a + b.reps);
  if (rNow > rPrev) return '+${rNow - rPrev} rip';
  if (rNow < rPrev) return '−${rPrev - rNow} rip';
  return '=';
}
