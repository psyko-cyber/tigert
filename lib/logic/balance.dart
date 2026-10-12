import 'dart:math' as math;

import '../core/fmt.dart';
import '../data/app_state.dart';
import '../data/models.dart';
import 'nutrition.dart';
import 'score.dart' show Tone;
import 'week_report.dart';

/// Bilancio della settimana: il voto di ogni giorno misura l'impegno, qui si
/// guarda il risultato. Quattro righe: peso (andamento rispetto all'obiettivo),
/// forza (esercizi saliti o scesi), volume (muscoli in linea), costanza
/// (sedute e diario).

const _dayMs = 86400000;

class BalanceRow {
  final String k;
  final String v;
  final Tone tone;
  const BalanceRow(this.k, this.v, this.tone);
}

class WeekBalance {
  final DateTime monday;
  final List<BalanceRow> rows;
  final String? note; // una seduta che salti da settimane, oppure meno sedute dei giorni scelti
  const WeekBalance(this.monday, this.rows, this.note);

  /// Una riga per la notifica del sabato.
  String get summary => rows.map((r) => '${r.k} ${r.v}').join(' · ');
}

WeekBalance weekBalance(AppState s, DateTime ref) {
  final mon = mondayOf(ref);
  return s.memo('balance:${dayKey(mon)}', () => _balance(s, mon));
}

WeekBalance _balance(AppState s, DateTime mon) {
  final p = s.profile;
  if (p == null) return WeekBalance(mon, const [], null);
  final t = today();
  final sun = addDays(mon, 6);
  final end = t.isBefore(sun) ? t : sun;
  final closed = t.isAfter(sun);
  final r = weekReport(s, mon);

  // peso
  final w = weightTrend(s.weightStats, now: end);
  final BalanceRow peso;
  if (w.slope == null) {
    peso = BalanceRow('Peso', w.missing == 1 ? 'manca 1 pesata' : 'mancano ${w.missing} pesate', Tone.dim);
  } else {
    final (word, ok) = weightVerdict(p, w.slope!);
    peso = BalanceRow('Peso', '${fSigned(w.slope!, 2)} kg/sett · $word', ok ? Tone.good : Tone.warn);
  }

  // forza
  final f = strengthWeek(s, mon);
  final forza = f.up + f.down + f.same == 0
      ? const BalanceRow('Forza', 'nessun confronto', Tone.dim)
      : BalanceRow('Forza', '${f.up} su · ${f.down} giù · ${f.same} uguali', f.up > f.down ? Tone.good : (f.down > f.up ? Tone.bad : Tone.warn));

  // volume
  final lag = r.lagging;
  final n = r.muscles.length;
  final BalanceRow volume;
  if (r.done == 0 && r.left == 0) {
    volume = const BalanceRow('Volume', 'nessuna seduta', Tone.dim);
  } else if (lag.isEmpty) {
    volume = const BalanceRow('Volume', 'tutti i muscoli in linea', Tone.good);
  } else {
    final zero = lag.where((m) => m.status == MuscleStatus.none).length;
    final parts = [
      if (n > lag.length) '${n - lag.length} in linea',
      if (lag.length > zero) '${lag.length - zero} sotto',
      if (zero > 0) '$zero a zero',
    ];
    volume = BalanceRow('Volume', parts.join(' · '), zero > 0 ? Tone.bad : Tone.warn);
  }

  // costanza
  final target = p.trainingDays.length;
  var logged = 0, offs = 0, elapsed = 0;
  for (var i = 0; i <= daysBetween(mon, end); i++) {
    final d = addDays(mon, i);
    final k = dayKey(d);
    final full = s.totals(k).kcal >= 900;
    // oggi entra nel conto del diario solo quando è una giornata completa
    if (full || d != t) elapsed++;
    if (full) logged++;
    if (s.habit(k).isOff && (s.sessionsByDate[k]?.isEmpty ?? true)) offs++;
  }
  final Tone tone;
  if (r.done >= target) {
    tone = logged >= elapsed - 1 ? Tone.good : Tone.warn;
  } else if (!closed && (r.left > 0 || s.activeSession != null)) {
    tone = Tone.dim; // settimana in corso: c'è ancora da fare
  } else {
    tone = r.done + offs >= target ? Tone.warn : Tone.bad;
  }
  final costanza = BalanceRow(
      'Costanza', '${r.done} ${r.done == 1 ? 'seduta' : 'sedute'} su $target${elapsed > 0 ? ' · diario $logged/$elapsed' : ''}', tone);

  String? note;
  if (!closed) {
    final sk = skippedDay(s);
    final pace = slowPace(s, mon);
    if (sk != null) {
      note = '«${sk.$1.name}» manca da ${sk.$2} settimane, le altre sedute le fai. Se non ci sta, sposta i suoi esercizi negli altri giorni.';
    } else if (pace != null) {
      final n = math.max(1, pace.round());
      note = 'Nelle ultime 4 settimane hai fatto ${fDec(pace, 1, true)} sedute a settimana su $target. '
          'Se è il tuo ritmo, imposta $n ${n == 1 ? 'giorno' : 'giorni'} nel Profilo: promemoria e voto si adattano.';
    }
  }
  return WeekBalance(mon, [peso, forza, volume, costanza], note);
}

/// Sedute a settimana nelle 4 settimane prima di [mon], quando sono almeno
/// una in meno dei giorni di allenamento scelti (e ti alleni con regolarità).
double? slowPace(AppState s, DateTime mon) {
  final p = s.profile;
  if (p == null) return null;
  final from = addDays(mon, -28);
  final n = s.doneSessions.where((x) {
    final d = fromKey(x.date);
    return !d.isBefore(from) && d.isBefore(mon);
  }).length;
  return n >= 4 && p.trainingDays.length - n / 4 >= 0.75 ? n / 4 : null;
}

double _strength(SessionEx e) => e.workDone.fold(0.0, (a, x) => math.max(a, x.kg > 0 ? x.e1rm : x.reps.toDouble()));

/// Esercizi della settimana saliti, scesi o fermi rispetto alla volta prima
/// (1RM stimato della serie migliore; conta solo se la volta prima è entro 5 settimane).
({int up, int down, int same}) strengthWeek(AppState s, DateTime mon) {
  final end = addDays(mon, 7);
  var up = 0, down = 0, same = 0;
  final seen = <String>{};
  for (final ss in s.doneSessions.reversed) {
    final d = fromKey(ss.date);
    if (!d.isBefore(end)) continue;
    if (d.isBefore(mon)) break;
    for (final e in ss.items) {
      if (e.type == 'k' || e.workDone.isEmpty || !seen.add(e.ex)) continue;
      final prev = s.lastPerformance(e.ex, beforeTs: ss.start);
      if (prev == null || ss.start - prev.$1.start > 35 * _dayMs) continue;
      final a = _strength(e), b = _strength(prev.$2);
      if (a > b * 1.01) {
        up++;
      } else if (a < b * 0.99) {
        down++;
      } else {
        same++;
      }
    }
  }
  return (up: up, down: down, same: same);
}

/// Una seduta della scheda che non fai da almeno 3 settimane mentre le altre sì,
/// con le settimane passate dall'ultima volta.
(PlanDay, int)? skippedDay(AppState s, {DateTime? now}) {
  final plan = s.activePlan;
  if (plan == null || plan.days.length < 2) return null;
  final t = (now ?? DateTime.now()).millisecondsSinceEpoch;
  final last = <String, int>{};
  int? first;
  var recent = 0;
  for (final ss in s.doneSessions) {
    if (ss.planId != plan.id || ss.dayId == null) continue;
    first ??= ss.start;
    last[ss.dayId!] = ss.start;
    if (t - ss.start <= 21 * _dayMs) recent++;
  }
  if (first == null || t - first < 21 * _dayMs || recent < 3) return null;
  (PlanDay, int)? worst;
  for (final d in plan.days) {
    final since = t - (last[d.id] ?? first);
    if (since < 21 * _dayMs) continue;
    final weeks = since ~/ (7 * _dayMs);
    if (worst == null || weeks > worst.$2) worst = (d, weeks);
  }
  return worst;
}

/// Testo della notifica del sabato.
String balanceNotificationBody(AppState s, DateTime day) => weekBalance(s, day).summary;
