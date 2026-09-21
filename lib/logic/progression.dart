import 'dart:math' as math;

import '../core/fmt.dart';
import '../data/app_state.dart';
import '../data/models.dart';

/// Coach di progressione: per ogni esercizio della scheda decide se è ora di
/// aumentare il carico, cercare una ripetizione in più, scaricare o ripartire
/// più leggeri. Si basa sulla doppia progressione (range di ripetizioni + RPE).
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

double _round(double kg, double inc) {
  if (inc <= 0) return kg;
  return double.parse(((kg / inc).round() * inc).toStringAsFixed(2));
}

/// Ultime [n] esecuzioni dell'esercizio, dalla più recente.
List<(Session, SessionEx)> exerciseRuns(AppState s, String exId, {int? beforeTs, int n = 4}) {
  final out = <(Session, SessionEx)>[];
  for (final ss in s.doneSessions.reversed) {
    if (beforeTs != null && ss.start >= beforeTs) continue;
    for (final e in ss.items) {
      if (e.ex == exId && e.doneSets > 0) {
        out.add((ss, e));
        break;
      }
    }
    if (out.length >= n) break;
  }
  return out;
}

Advice adviceFor(AppState s, PlanItem it, {int? beforeTs}) {
  final ex = s.exercise(it.ex);
  final name = ex?.name ?? 'Esercizio';
  final runs = exerciseRuns(s, it.ex, beforeTs: beforeTs);
  final rpeTxt = fDec(it.rpe, 1, true);
  if (runs.isEmpty) {
    return Advice(it.ex, name, AdviceKind.first, 0, 0, it.rMin, 'Prima volta',
        ex?.isCardio == true ? 'Scegli un ritmo sostenibile per ${it.rMin}-${it.rMax} minuti.' : 'Scegli un carico con cui arrivi a ${it.rMin}-${it.rMax} ripetizioni a RPE $rpeTxt.');
  }
  final (lastSession, last) = runs.first;
  final done = last.sets.where((x) => x.done).toList();
  final topKg = done.fold<double>(0, (a, b) => math.max(a, b.kg));
  final atTopKg = done.where((x) => (x.kg - topKg).abs() < 0.01).toList();
  final bestReps = atTopKg.fold<int>(0, (a, b) => math.max(a, b.reps));

  if (ex?.isCardio == true) {
    final mins = done.fold<int>(0, (a, b) => math.max(a, b.reps));
    return Advice(it.ex, name, AdviceKind.cardio, 0, 0, math.min(it.rMax, mins + 1), 'Cardio', 'Ultima volta $mins minuti: resta nel range ${it.rMin}-${it.rMax} o aggiungi un minuto.');
  }
  final inc = ex?.inc ?? 2.5;

  // 1) pausa lunga: si riparte un po' più leggeri
  final daysOff = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(lastSession.start)).inDays;
  if (daysOff > 28 && topKg > 0) {
    final kg = _round(topKg * 0.9, inc);
    return Advice(it.ex, name, AdviceKind.lighter, kg, topKg, it.rMin, 'Ripresa dopo ${daysOff ~/ 7} settimane',
        'Non lo fai da ${daysOff ~/ 7} settimane: riparti da ${fKg(kg)} kg (circa −10%) e risali in un paio di sedute.');
  }

  // 2) tetto del range raggiunto su tutte le serie entro l'RPE → si sale
  final atTop = done.length >= it.sets && done.every((x) => x.reps >= it.rMax && (x.rpe == null || x.rpe! <= it.rpe + 0.01));
  if (atTop) {
    if (inc > 0 && (topKg > 0 || ex?.isBodyweight != true)) {
      final kg = _round(topKg + inc, inc);
      return Advice(it.ex, name, AdviceKind.increase, kg, topKg, it.rMin, 'Tetto raggiunto: ${it.sets}×${it.rMax} @ RPE $rpeTxt',
          'Sali a ${fKg(kg)} kg (+${fKg(kg - topKg)}) e riparti da ${it.rMin} ripetizioni.');
    }
    if (ex?.isBodyweight == true && inc > 0) {
      return Advice(it.ex, name, AdviceKind.increase, inc, 0, it.rMin, 'Tetto raggiunto a corpo libero',
          'Aggiungi ${fKg(inc)} kg di zavorra e riparti da ${it.rMin} ripetizioni (oppure ${it.rMax + 2} ripetizioni senza zavorra).');
    }
    return Advice(it.ex, name, AdviceKind.increase, topKg, topKg, it.rMax + 1, 'Tetto raggiunto',
        'Aggiungi una ripetizione per serie (${it.rMax + 1}) o passa a una variante più dura.');
  }

  // 3) troppo pesante: metà delle serie sotto il minimo del range
  final under = done.where((x) => x.reps < it.rMin).length;
  final hard = done.where((x) => x.rpe != null && x.rpe! >= it.rpe + 1).length;
  if (topKg > 0 && inc > 0 && under * 2 >= math.max(1, done.length) && (under >= 2 || hard >= 1 || done.length == 1)) {
    final kg = _round(math.max(0, topKg - inc), inc);
    return Advice(it.ex, name, AdviceKind.lighter, kg, topKg, it.rMin, 'Carico troppo alto',
        'Ultima volta sotto le ${it.rMin} ripetizioni: scendi a ${fKg(kg)} kg e costruisci il range ${it.rMin}-${it.rMax}.');
  }

  // 4) stallo: 3 sedute allo stesso carico senza ripetizioni in più
  if (runs.length >= 3 && topKg > 0 && inc > 0) {
    int repsAt(SessionEx e, double kg) => e.sets.where((x) => x.done && (x.kg - kg).abs() < 0.01).fold(0, (a, b) => a + b.reps);
    double top(SessionEx e) => e.sets.where((x) => x.done).fold(0.0, (a, b) => math.max(a, b.kg));
    final same = runs.take(3).every((r) => (top(r.$2) - topKg).abs() < 0.01);
    if (same && repsAt(runs[0].$2, topKg) <= repsAt(runs[2].$2, topKg)) {
      final kg = _round(topKg * 0.9, inc);
      return Advice(it.ex, name, AdviceKind.deload, kg, topKg, it.rMin, 'Stallo da 3 sedute',
          'Fermo a ${fKg(topKg)} kg da 3 sedute: scarica a ${fKg(kg)} kg (−10%) e risali; di solito si supera il blocco in 2-3 settimane.');
    }
  }

  // 5) stesso carico, una ripetizione in più
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
