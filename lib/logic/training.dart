import 'dart:math' as math;

import '../core/fmt.dart';
import '../core/ids.dart';
import '../data/app_state.dart';
import '../data/models.dart';
import 'progression.dart';

// =================================================================== settimana

enum SlotStatus { done, today, todo, missed, extra, off }

class WeekSlot {
  final DateTime date;
  final PlanDay? day;
  final SlotStatus status;
  final Session? session;
  final HabitDay? off; // giorno giustificato
  final PlanDay? queued; // per i giorni saltati: la seduta rimasta in coda
  final String? movedFrom; // giorno in più: la seduta arriva rimandata da questo giorno
  const WeekSlot(this.date, this.day, this.status, this.session, {this.off, this.queued, this.movedFrom});

  String get statusLabel => switch (status) {
        SlotStatus.done || SlotStatus.extra => 'Fatto',
        SlotStatus.today => session != null && session!.isActive ? 'In corso' : 'Oggi',
        SlotStatus.todo => 'Da fare',
        SlotStatus.missed => 'Saltato',
        SlotStatus.off => off?.postponed == true ? 'Rimandata' : 'Giustificato',
      };
}

/// Calendario della settimana: le sedute della scheda ruotano sui giorni
/// scelti. Se salti un giorno, la seduta successiva resta quella in coda.
/// Un giorno giustificato invece toglie dal giro la sua seduta, come se fosse fatta;
/// se la seduta è rimandata, resta fissata al giorno scelto (che diventa di
/// allenamento) e la coda va avanti: se quel giorno aveva già una seduta, le successive slittano.
List<WeekSlot> weekSchedule(AppState s, {DateTime? ref}) =>
    s.memo('week:${dayKey(mondayOf(ref ?? DateTime.now()))}', () => _weekSchedule(s, ref));

List<WeekSlot> _weekSchedule(AppState s, DateTime? ref) {
  final p = s.profile;
  final plan = s.activePlan;
  if (p == null || plan == null || plan.days.isEmpty) return const [];
  final mon = mondayOf(ref ?? DateTime.now());
  final monKey = dayKey(mon);
  final t = today();
  final n = plan.days.length;
  final habits = s.habitsByDate;
  int after(String? dayId, int cur) {
    final k = plan.days.indexWhere((d) => d.id == dayId);
    return k >= 0 ? k + 1 : cur + 1;
  }

  bool planSessionOn(String key) => (s.sessionsByDate[key] ?? const <Session>[]).any((x) => !x.isActive && x.planId == plan.id);
  // la seduta arrivata rimandata da un altro giorno è già uscita dalla coda lì
  bool consumes(HabitDay h) => !(h.moved != null && habits[h.moved]?.offDay == h.offDay);
  // e se la fai nel giorno in cui l'hai rimandata non sposta il giro
  bool pinnedOn(String date, String? dayId) {
    final from = habits[date]?.moved;
    return from != null && dayId != null && habits[from]?.offDay == dayId;
  }

  // si riparte dalla seduta successiva all'ultima fatta (anche se importata) o giustificata
  final past = <(String, int, String?)>[
    for (final x in s.doneSessions)
      if (x.planId == plan.id && x.date.compareTo(monKey) < 0 && !pinnedOn(x.date, x.dayId)) (x.date, x.start, x.dayId),
    for (final h in habits.values)
      if (h.isOff && consumes(h) && h.date.compareTo(monKey) < 0 && plan.day(h.offDay ?? '') != null && !planSessionOn(h.date)) (h.date, 0, h.offDay),
  ]..sort((a, b) {
      final c = a.$1.compareTo(b.$1);
      return c != 0 ? c : a.$2.compareTo(b.$2);
    });
  var idx = 0;
  for (final e in past) {
    idx = after(e.$3, idx);
  }
  final out = <WeekSlot>[];
  for (var i = 0; i < 7; i++) {
    final d = mon.add(Duration(days: i));
    final key = dayKey(d);
    final sessions = (s.sessionsByDate[key] ?? const <Session>[]).toList();
    final h = habits[key];
    final moved = h?.moved;
    // seduta rimandata qui: fissata a questo giorno, non prende la prossima della coda
    final pinned = moved == null ? null : plan.day(habits[moved]?.offDay ?? '');
    final trainDay = p.trainingDays.contains(d.weekday) || moved != null;
    if (h != null && h.isOff && !planSessionOn(key)) {
      final skipped = plan.day(h.offDay ?? '') ?? pinned ?? plan.days[idx % n];
      if (consumes(h)) idx = after(skipped.id, idx);
      // se ti alleni lo stesso (seduta alternativa) si vede la seduta, non il giorno giustificato
      if (sessions.isEmpty) {
        out.add(WeekSlot(d, skipped, SlotStatus.off, null, off: h));
        continue;
      }
    }
    if (sessions.isNotEmpty) {
      for (final ss in sessions) {
        final day = plan.day(ss.dayId ?? '') ?? (ss.planId == plan.id ? plan.days[idx % n] : null);
        final isToday = d == t;
        out.add(WeekSlot(d, day, ss.isActive ? SlotStatus.today : (trainDay || isToday ? SlotStatus.done : SlotStatus.extra), ss, movedFrom: moved));
        if (!ss.isActive && ss.planId == plan.id && !pinnedOn(key, ss.dayId)) idx = after(ss.dayId, idx);
      }
      continue;
    }
    if (!trainDay) continue;
    final next = pinned ?? plan.days[idx % n];
    if (d.isBefore(t)) {
      out.add(WeekSlot(d, null, SlotStatus.missed, null, queued: next, movedFrom: moved));
    } else {
      out.add(WeekSlot(d, next, d == t ? SlotStatus.today : SlotStatus.todo, null, movedFrom: moved));
      if (pinned == null) idx++;
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

/// La seduta prevista in un certo giorno (anche nelle settimane successive).
WeekSlot? slotOn(AppState s, DateTime d) {
  final day = dateOnly(d);
  for (final sl in weekSchedule(s, ref: day)) {
    if (sl.date == day) return sl;
  }
  return null;
}

/// Testo del promemoria di allenamento, con i carichi da cambiare.
String trainingReminderBody(AppState s, DateTime d) {
  final sl = slotOn(s, d);
  final day = sl?.day;
  if (day == null) return 'Oggi tocca a te: apri la scheda e inizia.';
  final coach = s.profile?.reminders.coachOn ?? true;
  final sum = coach ? adviceSummary(dayAdvice(s, day)) : null;
  return sum == null ? 'Oggi ${day.name}: apri la scheda e inizia.' : 'Oggi ${day.name}: $sum';
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
    } else if (sl.day != null && sl.status != SlotStatus.off) {
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

/// Serie, ripetizioni e recupero proposti quando aggiungi un esercizio.
PlanItem defaultItemFor(Exercise? e, String id) => switch (e?.type) {
      'k' => PlanItem(ex: id, sets: 1, rMin: 20, rMax: 30, rpe: 7, rest: 0),
      'i' => PlanItem(ex: id, sets: 3, rMin: 10, rMax: 15, rpe: 9, rest: 90),
      'b' => PlanItem(ex: id, sets: 3, rMin: 8, rMax: 15, rpe: 9, rest: 90),
      _ => PlanItem(ex: id, sets: 3, rMin: 6, rMax: 10, rpe: 9, rest: 150),
    };

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
  final a = adviceFor(s, it);
  final last = s.lastPerformance(it.ex);
  final prevWork = last?.$2.sets.where((x) => x.isWork).toList() ?? const <SetLog>[];
  final workKg = a.kg > 0 ? a.kg : (prevWork.isEmpty ? 0.0 : prevWork.first.kg);
  final sets = <SetLog>[
    for (var i = 0; i < it.warm; i++) warmupSet(workKg, i, it.warm, ex?.inc ?? 2.5, it.rMin),
  ];
  for (var i = 0; i < it.sets; i++) {
    final prev = i < prevWork.length ? prevWork[i] : null;
    sets.add(SetLog(
      kg: a.kg > 0 ? a.kg : (prev?.kg ?? 0),
      reps: a.kind == AdviceKind.first ? it.rMin : a.reps,
      rpe: null,
      done: false,
    ));
  }
  return SessionEx(ex: it.ex, name: ex?.name ?? 'Esercizio', type: ex?.type ?? 'c', target: it, sets: sets);
}

/// Serie di avvicinamento [i] di [n]: dal 40% all'80% del carico di lavoro, ripetizioni a scendere.
SetLog warmupSet(double workKg, int i, int n, double inc, int rMin) {
  if (workKg <= 0) return SetLog(t: setWarmup, reps: rMin);
  final pct = n <= 1 ? 0.6 : 0.4 + 0.4 * i / (n - 1);
  final step = inc > 0 ? inc : 2.5;
  final kg = double.parse(((workKg * pct / step).round() * step).toStringAsFixed(2));
  return SetLog(t: setWarmup, kg: kg, reps: math.max(3, 10 - 3 * i));
}

/// Etichetta della serie: 1, 2, 3 per le allenanti, A e D per avvicinamento e dropset.
String setBadge(List<SetLog> sets, int i) {
  final s = sets[i];
  if (s.isWarmup) return 'A';
  if (s.isDrop) return 'D';
  return '${sets.take(i).where((x) => x.isWork).length + 1}';
}

String setTypeName(String t) => switch (t) {
      setWarmup => 'Avvicinamento',
      setDrop => 'Dropset',
      _ => 'Allenante',
    };

/// La serie della volta scorsa corrispondente: stessa posizione tra le serie dello stesso tipo.
SetLog? matchingPrevSet(List<SetLog> prev, List<SetLog> cur, int i) {
  final t = cur[i].t;
  final k = cur.take(i).where((x) => x.t == t).length;
  final same = prev.where((x) => x.t == t).toList();
  return k < same.length ? same[k] : null;
}

class Suggestion {
  final double kg;
  final int reps;
  final bool increase;
  final String title;
  final String text;
  final AdviceKind kind;
  const Suggestion(this.kg, this.reps, this.increase, this.title, this.text, [this.kind = AdviceKind.reps]);
}

/// Doppia progressione (vedi progression.dart): quando tutte le serie arrivano
/// al tetto delle ripetizioni entro l'RPE target, si alza il carico.
Suggestion suggestFor(AppState s, PlanItem it, {int? beforeTs}) {
  final a = adviceFor(s, it, beforeTs: beforeTs);
  return Suggestion(a.kg, a.reps, a.kind == AdviceKind.increase, a.title, a.text, a.kind);
}

/// Suggerimento dal vivo mentre si allena: tetto raggiunto in questa sessione?
Suggestion? liveTip(AppState s, SessionEx e) {
  final ex = s.exercise(e.ex);
  final done = e.workDone;
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
        if (!st.counts || st.reps <= 0) continue;
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
        if (st.counts && st.reps > 0) (byEx[e.ex] ??= []).add((ss, st));
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
        if (!st.counts) continue;
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
  final done = e.workDone;
  if (done.isEmpty) return 'saltato';
  if (prev == null) return 'nuovo';
  final pd = prev.$2.workDone;
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
