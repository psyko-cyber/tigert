import 'dart:math' as math;

import '../core/fmt.dart';
import '../data/app_state.dart';
import '../data/models.dart';

/// Coach di progressione: per ogni esercizio della scheda decide se è ora di
/// aumentare il carico, cercare una ripetizione in più, scaricare o ripartire
/// più leggeri. Si basa sulla doppia progressione: contano le ripetizioni nel
/// range, non l'RPE (chi chiude le serie a cedimento deve poter salire).
enum AdviceKind { first, increase, reps, lighter, deload, cardio }

class Advice {
  final String exId;
  final String exName;
  final AdviceKind kind;
  final double kg; // carico consigliato (0 = corpo libero / primo giorno)
  final double lastKg;
  final int reps; // ripetizioni obiettivo per serie
  final String title;
  final String text;
  const Advice(this.exId, this.exName, this.kind, this.kg, this.lastKg, this.reps, this.title, this.text);

  /// Cambia qualcosa rispetto all'ultima volta (da segnalare in notifica).
  bool get isChange => kind == AdviceKind.increase || kind == AdviceKind.lighter || kind == AdviceKind.deload;

  /// Nuovo carico: si riparte dal minimo del range.
  bool get resetsReps => isChange;

  String get badge => switch (kind) {
        AdviceKind.increase => kg > lastKg ? '↑ ${fKg(kg)} kg' : '↑ $reps rip',
        AdviceKind.lighter || AdviceKind.deload => '↓ ${fKg(kg)} kg',
        AdviceKind.reps => '$reps rip',
        AdviceKind.first => 'prima volta',
        AdviceKind.cardio => '$reps min',
      };

  /// "Panca piana 62,5 kg (+2,5)"
  String get changeLine {
    final d = kg - lastKg;
    final delta = d.abs() < 0.01 ? '' : ' (${d > 0 ? '+' : '−'}${fKg(d.abs())})';
    return kg > 0 ? '$exName ${fKg(kg)} kg$delta' : '$exName $reps rip';
  }
}

const _dayMs = 86400000;

/// Giorni senza allenare un muscolo oltre i quali si riparte più leggeri (−10%)
/// e oltre i quali è un rientro vero (70%, poi +10% a seduta).
const pauseDays = 28, comebackDays = 56;

double _round(double kg, double inc) {
  if (inc <= 0) return kg;
  return double.parse(((kg / inc).round() * inc).toStringAsFixed(2));
}

/// "11 settimane", oppure "più di sei mesi" quando il conto non dice più niente.
String _since(int days) => days > 182 ? 'più di sei mesi' : '${days ~/ 7} settimane';

double _top(SessionEx e) => e.workDone.fold(0.0, (a, b) => math.max(a, b.kg));

/// Ripetizioni della serie migliore al carico più alto.
int _best(SessionEx e) {
  final top = _top(e);
  return e.workDone.where((x) => (x.kg - top).abs() < 0.01).fold(0, (a, b) => math.max(a, b.reps));
}

int _repsAt(SessionEx e, double kg) => e.workDone.where((x) => (x.kg - kg).abs() < 0.01).fold(0, (a, b) => a + b.reps);

bool _sameRange(SessionEx e, PlanItem it) => e.target.rMin == it.rMin && e.target.rMax == it.rMax;

/// Ultime [n] esecuzioni dell'esercizio, dalla più recente.
List<(Session, SessionEx)> exerciseRuns(AppState s, String exId, {int? beforeTs, int n = 8}) {
  final out = <(Session, SessionEx)>[];
  for (final ss in s.doneSessions.reversed) {
    if (beforeTs != null && ss.start >= beforeTs) continue;
    for (final e in ss.items) {
      if (e.ex == exId && e.workDone.isNotEmpty) {
        out.add((ss, e));
        break;
      }
    }
    if (out.length >= n) break;
  }
  return out;
}

/// Inizio dell'ultima seduta in cui il muscolo è stato allenato, con qualsiasi esercizio.
int? muscleLast(AppState s, String muscle, {int? beforeTs}) {
  for (final ss in s.doneSessions.reversed) {
    if (beforeTs != null && ss.start >= beforeTs) continue;
    for (final e in ss.items) {
      if (e.workDone.isNotEmpty && s.exercise(e.ex)?.muscle == muscle) return ss.start;
    }
  }
  return null;
}

Advice adviceFor(AppState s, PlanItem it, {int? beforeTs}) {
  final ex = s.exercise(it.ex);
  final name = ex?.name ?? 'Esercizio';
  final runs = exerciseRuns(s, it.ex, beforeTs: beforeTs);
  final range = '${it.rMin}-${it.rMax}';
  final now = beforeTs ?? DateTime.now().millisecondsSinceEpoch;
  final muscle = ex?.muscle;
  if (runs.isEmpty) {
    // esercizio nuovo, ma il muscolo torna da una pausa lunga: niente carichi tirati
    final seen = muscle == null || ex?.isCardio == true ? null : muscleLast(s, muscle, beforeTs: beforeTs);
    final off = seen == null ? 0 : (now - seen) ~/ _dayMs;
    if (off > comebackDays) {
      return Advice(it.ex, name, AdviceKind.first, 0, 0, it.rMin, 'Prima volta, al rientro',
          'Non alleni ${muscle!.toLowerCase()} da ${_since(off)}: scegli un carico leggero e fermati con 2-3 ripetizioni di margine.');
    }
    return Advice(it.ex, name, AdviceKind.first, 0, 0, it.rMin, 'Prima volta',
        ex?.isCardio == true ? 'Scegli un ritmo sostenibile per $range minuti.' : 'Scegli un carico con cui arrivi a $range ripetizioni a RPE ${fDec(it.rpe, 1, true)}.');
  }
  final (lastSession, last) = runs.first;
  if (ex?.isCardio == true) {
    final mins = last.workDone.fold<int>(0, (a, b) => math.max(a, b.reps));
    return Advice(it.ex, name, AdviceKind.cardio, 0, 0, math.min(it.rMax, mins + 1), 'Cardio', 'Ultima volta $mins minuti: resta nel range $range o aggiungi un minuto.');
  }
  final inc = ex?.inc ?? 2.5;
  final step = inc > 0 ? inc : 0.5;
  final lastTop = _top(last);
  final mid = ((it.rMin + it.rMax) / 2).round();

  // 1) pausa lunga: conta da quando non alleni il muscolo, non il singolo esercizio
  final seen = muscle == null ? lastSession.start : (muscleLast(s, muscle, beforeTs: beforeTs) ?? lastSession.start);
  final daysOff = (now - seen) ~/ _dayMs;
  final what = muscle == null ? 'Non lo fai' : 'Non alleni ${muscle.toLowerCase()}';
  if (daysOff > comebackDays) {
    final w = _since(daysOff);
    if (lastTop <= 0) {
      return Advice(it.ex, name, AdviceKind.reps, 0, 0, it.rMin, 'Rientro dopo $w',
          '$what da $w: riparti con calma, ${it.rMin} ${ex?.repsLabel ?? 'rip'} per serie e lontano dal cedimento.');
    }
    final kg = _round(lastTop * 0.7, step);
    return Advice(it.ex, name, AdviceKind.lighter, kg, lastTop, it.rMax, 'Rientro dopo $w',
        '$what da $w: riparti da ${fKg(kg)} kg (circa il 70%), fermati con 2-3 ripetizioni di margine e risali del 10% a seduta.');
  }
  if (daysOff > pauseDays && lastTop > 0) {
    final kg = _round(lastTop * 0.9, step);
    return Advice(it.ex, name, AdviceKind.lighter, kg, lastTop, it.rMin, 'Ripresa dopo ${daysOff ~/ 7} settimane',
        '$what da ${daysOff ~/ 7} settimane: riparti da ${fKg(kg)} kg (circa −10%) e risali in un paio di sedute.');
  }

  // 2) rientro in corso: +10% a seduta fino al carico di prima della pausa
  if (lastTop > 0 && _best(last) >= it.rMin) {
    for (var i = 0; i < runs.length - 1 && i <= 4; i++) {
      final back = runs[i].$1.start; // prima seduta dopo la pausa
      if (back - runs[i + 1].$1.start <= comebackDays * _dayMs) continue;
      final pre = _top(runs[i + 1].$2);
      // rientro vero: recente, ripartito più leggero, e con il muscolo fermo (non solo l'esercizio)
      final idle = muscle == null ? null : muscleLast(s, muscle, beforeTs: back);
      final real = now - back <= 60 * _dayMs && (idle == null || back - idle > comebackDays * _dayMs);
      if (!real || pre <= 0 || _top(runs[i].$2) > pre * 0.85 || lastTop >= pre * 0.97) break;
      final kg = math.min(pre, _round(math.max(lastTop * 1.1, lastTop + step), step));
      final full = kg >= pre - 0.01;
      return Advice(it.ex, name, AdviceKind.increase, kg, lastTop, full ? it.rMin : mid, 'Rientro: verso ${fKg(pre)} kg',
          full
              ? 'Torni ai ${fKg(pre)} kg di prima della pausa: riparti da ${it.rMin} ripetizioni.'
              : 'Sali a ${fKg(kg)} kg (+10%), ancora con un paio di ripetizioni di margine: così torni ai ${fKg(pre)} kg in poche sedute.');
    }
  }

  // 3) ogni range ha il suo storico: lo stesso esercizio in due sedute con
  //    ripetizioni diverse non si disturba
  final same = [for (final r in runs) if (_sameRange(r.$2, it)) r];
  final track = same.isNotEmpty && lastSession.start - same.first.$1.start <= pauseDays * _dayMs;
  final hist = track ? same : [runs.first];
  final base = hist.first.$2;
  final done = base.workDone;
  final topKg = _top(base);
  final bestReps = _best(base);

  if (!track && topKg > 0 && bestReps < it.rMin) {
    // fatto con un altro range e con meno ripetizioni di quelle che servono qui:
    // il carico con cui si entra appena nel range, poi ci pensa la progressione
    final e1 = done.fold<double>(0, (a, b) => math.max(a, b.e1rm));
    final aim = math.min(it.rMax, it.rMin + 1);
    final kg = math.max(0.0, math.min(_round(e1 / (1 + aim / 30), step), _round(topKg - step, step)));
    return Advice(it.ex, name, AdviceKind.lighter, kg, topKg, it.rMin, 'Range diverso: $range',
        'L\'ultima volta ${fKg(topKg)} kg × $bestReps con un altro range: per $range ripetizioni parti da ${fKg(kg)} kg.');
  }

  // 4) tetto del range su tutte le serie → si sale, anche se chiudi a cedimento
  final atTop = done.length >= it.sets && done.every((x) => x.reps >= it.rMax);
  if (atTop) {
    if (inc > 0 && (topKg > 0 || ex?.isBodyweight != true)) {
      final kg = _round(topKg + inc, inc);
      return Advice(it.ex, name, AdviceKind.increase, kg, topKg, it.rMin, 'Tetto raggiunto: ${it.sets}×${it.rMax}',
          'Sali a ${fKg(kg)} kg (+${fKg(kg - topKg)}) e riparti da ${it.rMin} ripetizioni.');
    }
    if (ex?.isBodyweight == true && inc > 0) {
      return Advice(it.ex, name, AdviceKind.increase, inc, 0, it.rMin, 'Tetto raggiunto a corpo libero',
          'Aggiungi ${fKg(inc)} kg di zavorra e riparti da ${it.rMin} ripetizioni (oppure ${it.rMax + 2} ripetizioni senza zavorra).');
    }
    return Advice(it.ex, name, AdviceKind.increase, topKg, topKg, it.rMax + 1, 'Tetto raggiunto',
        'Aggiungi una ripetizione per serie (${it.rMax + 1}) o passa a una variante più dura.');
  }

  // 5) troppo pesante: nemmeno la serie migliore arriva al minimo, per due
  //    sedute di fila con lo stesso carico. La prima volta si riprova.
  if (topKg > 0 && inc > 0 && bestReps < it.rMin) {
    final again = hist.length >= 2 && _best(hist[1].$2) < it.rMin && (_top(hist[1].$2) - topKg).abs() < 0.01;
    if (again) {
      final kg = _round(math.max(0, topKg - inc), inc);
      return Advice(it.ex, name, AdviceKind.lighter, kg, topKg, it.rMin, 'Carico troppo alto',
          'Due sedute di fila sotto le ${it.rMin} ripetizioni: scendi a ${fKg(kg)} kg e costruisci il range $range.');
    }
    return Advice(it.ex, name, AdviceKind.reps, topKg, topKg, it.rMin, 'Obiettivo di oggi',
        'Stesso carico (${fKg(topKg)} kg): l\'ultima volta eri sotto le ${it.rMin} ripetizioni, riprova ad arrivarci.');
  }

  // 6) stallo: 4 sedute allo stesso carico senza ripetizioni in più
  //    (solo se l'esercizio lo stai facendo: su sedute di mesi fa non dice niente)
  if (hist.length >= 4 && topKg > 0 && inc > 0 && now - hist.first.$1.start <= pauseDays * _dayMs) {
    final still = hist.take(4).every((r) => (_top(r.$2) - topKg).abs() < 0.01);
    if (still && _repsAt(hist[0].$2, topKg) <= _repsAt(hist[3].$2, topKg)) {
      final kg = _round(topKg * 0.9, inc);
      return Advice(it.ex, name, AdviceKind.deload, kg, topKg, it.rMin, 'Stallo da 4 sedute',
          'Fermo a ${fKg(topKg)} kg da 4 sedute: scarica a ${fKg(kg)} kg (−10%) e risali; di solito si supera il blocco in 2-3 settimane.');
    }
  }

  // 7) stesso carico, una ripetizione in più
  final target = math.min(it.rMax, math.max(it.rMin, bestReps + 1));
  return Advice(it.ex, name, AdviceKind.reps, topKg, topKg, target, 'Obiettivo di oggi',
      topKg > 0 ? 'Stesso carico (${fKg(topKg)} kg): punta a $target ripetizioni per serie.' : 'Punta a $target ${ex?.repsLabel ?? 'rip'} per serie.');
}

/// Consigli per tutti gli esercizi di una seduta.
List<Advice> dayAdvice(AppState s, PlanDay d) => [for (final it in d.items) adviceFor(s, it)];

/// Testo breve per la notifica: "↑ Panca piana 62,5 kg (+2,5) · ↓ Squat 90 kg".
String? adviceSummary(List<Advice> l, {int max = 3}) {
  final ch = l.where((a) => a.isChange).toList();
  if (ch.isEmpty) return null;
  final parts = [for (final a in ch.take(max)) '${a.kind == AdviceKind.increase ? '↑' : '↓'} ${a.changeLine}'];
  if (ch.length > max) parts.add('e altri ${ch.length - max}');
  return parts.join(' · ');
}
