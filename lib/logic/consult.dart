import '../core/fmt.dart';
import '../core/ids.dart';
import '../data/app_state.dart';
import '../data/models.dart';
import 'activity.dart';
import 'balance.dart';
import 'nutrition.dart';
import 'progression.dart';
import 'score.dart' show isTrainingDay;
import 'training.dart';
import 'volume.dart';
import 'week_report.dart';

/// Consulenza: il testo con i dati degli ultimi giorni da incollare in una
/// chat con un assistente (le istruzioni sono in testa, quindi funziona in
/// una chat nuova) e la lettura delle priorità dalla risposta.

const consultMarker = 'PRIORITÀ';
const consultDays = [7, 14, 28];

String _day(DateTime d) => '${giorniBrevi[d.weekday - 1].toLowerCase()} ${d.day}/${d.month}';

String _set(SetLog x) =>
    '${x.isWarmup ? 'A ' : (x.isDrop ? 'D ' : '')}${x.kg > 0 ? '${fKg(x.kg)}×' : ''}${x.reps}${x.rpe == null ? '' : '@${fDec(x.rpe!, 1, true)}'}';

String consultText(AppState s, {int days = 14, String question = '', DateTime? now}) {
  final p = s.profile!;
  final end = dateOnly(now ?? DateTime.now());
  final start = addDays(end, -(days - 1));
  final keys = [for (var i = 0; i < days; i++) dayKey(addDays(start, i))];
  final b = StringBuffer();
  void h(String t) => b
    ..writeln()
    ..writeln('## $t');

  b.writeln('# Consulenza Tigert · ${_day(start)} - ${_day(end)} ($days giorni)');
  b.writeln();
  b.writeln('Sei il mio coach di allenamento e nutrizione. Questi sono i dati veri esportati dalla mia app.');
  b.writeln('Rispondi in italiano, breve e schematico, con i numeri:');
  b.writeln('1. Cosa va bene (massimo 3 punti).');
  b.writeln('2. Cosa non va (massimo 3 punti).');
  b.writeln('3. La risposta alla mia domanda, se c\'è.');
  b.writeln('4. Chiudi con questo blocco, identico nel formato: le tre azioni più importanti per i prossimi 7 giorni, una riga ciascuna, concrete e misurabili.');
  b.writeln(consultMarker);
  b.writeln('1) ...');
  b.writeln('2) ...');
  b.writeln('3) ...');
  b.writeln('Note: voti e consigli di carico li calcola l\'app. RPE 10 = cedimento, A = avvicinamento, D = dropset. Su dolori e infortuni resta prudente: non sei un medico.');

  h('Io');
  final rate = fDec(p.rate, 2, true);
  final goal = switch (p.goal) {
    Goal.bulk => '${p.phase.label.toLowerCase()}, +$rate kg/sett fino a ${fKg(p.targetWeight)} kg',
    Goal.cut => 'definizione, −$rate kg/sett fino a ${fKg(p.targetWeight)} kg',
    Goal.maintain => 'mantenimento',
  };
  b.writeln('${p.sex == 'f' ? 'Donna' : 'Uomo'}, ${p.age} anni, ${fDec(p.heightCm, 0)} cm, ${fDec(s.currentWeight, 1)} kg. Obiettivo: $goal.');
  b.writeln('Target: ${fInt(p.kcal)} kcal, proteine ${p.protein} g, carboidrati ${p.carbs} g, grassi ${p.fat} g. '
      'Acqua ${fDec(p.waterMl / 1000, 1, true)} L, passi ${fInt(p.steps)}, sonno ${fMinutes(p.sleepMin)}.');
  final plan = s.activePlan;
  b.writeln('Allenamento: ${p.trainingDays.length} giorni (${p.trainingDays.map((d) => giorniBrevi[d - 1].toLowerCase()).join(', ')})'
      '${plan == null ? '' : ', scheda "${plan.name}": ${plan.days.map((d) => d.name).join(' / ')}'}.');
  if (p.supplements.isNotEmpty) b.writeln('Integratori: ${p.supplements.join(', ')}.');

  if (question.trim().isNotEmpty) {
    h('La mia domanda');
    b.writeln(question.trim());
  }

  final c = s.lastConsult;
  if (c != null && c.items.isNotEmpty) {
    h('Priorità della consulenza del ${_day(fromKey(c.id))}');
    for (var i = 0; i < c.items.length; i++) {
      b.writeln('- [${c.done.contains(i) ? 'fatta' : 'non fatta'}] ${c.items[i]}');
    }
  }

  h('Peso');
  final before = s.weights.where((w) => w.date.compareTo(keys.first) < 0).toList();
  final ws = s.weights.where((w) => w.date.compareTo(keys.first) >= 0 && w.date.compareTo(keys.last) <= 0).toList();
  if (before.isNotEmpty) b.writeln('Prima del periodo: ${fKg(before.last.kg)} kg (${_day(fromKey(before.last.date))}).');
  b.writeln(ws.isEmpty ? 'Nessuna pesata nel periodo.' : 'Pesate: ${ws.map((w) => '${_day(fromKey(w.date))} ${fKg(w.kg)}').join(', ')}.');
  final tr = weightTrend(s.weightStats, now: end);
  b.writeln(tr.slope == null ? 'Andamento: non stimabile, poche pesate.' : 'Andamento: ${fSigned(tr.slope!, 2)} kg/sett (${weightVerdict(p, tr.slope!).$1}).');
  final td = realTdee(totalsByDate: s.totalsByDate, weights: s.weightStats, now: now);
  if (td != null) b.writeln('TDEE reale stimato dall\'app: ${fInt(td.tdee)} kcal (media assunta ${fInt(td.avgIntake)}).');

  h('Giorni: calorie nette, macro, voto dell\'app, allenamento, abitudini');
  final full = <(DateTime, double, double)>[];
  var photo = 0, total = 0;
  for (final k in keys) {
    final d = fromKey(k);
    final t = s.totals(k);
    final hb = s.habit(k);
    final ss = s.sessionsByDate[k] ?? const <Session>[];
    final reason = (offReasons[hb.off] ?? hb.off).toLowerCase();
    final train = ss.isNotEmpty
        ? ss.map((x) => x.name).join(' + ')
        : hb.isOff
            ? (hb.postponed ? 'rimandata ($reason)' : 'giustificata ($reason${hb.avoid.isEmpty ? '' : ': ${hb.avoid.join(', ').toLowerCase()}'})')
            : !isTrainingDay(p, d) && hb.moved == null
                ? 'riposo'
                : (d == end ? 'in programma' : 'SALTATA');
    final hab = [
      if (p.habitOn('water')) 'acqua ${fDec(hb.water / 1000, 1, true)} L',
      if (p.habitOn('sleep') && hb.sleep != null) 'sonno ${fMinutes(hb.sleep!)}',
      if (p.habitOn('steps') && hb.steps != null) 'passi ${fInt(hb.steps!)}',
      if ((hb.alcohol ?? 0) > 0) 'alcol ${hb.alcohol}',
      for (final e in hb.extra) '${e.name.toLowerCase()} ${e.min} min (−${e.kcal} kcal)',
    ].join(', ');
    final entries = s.entries(k);
    total += entries.length;
    photo += entries.where((e) => e.refType == 'photo').length;
    if (t.kcal <= 0) {
      b.writeln('- ${_day(d)}: niente registrato · $train');
      continue;
    }
    final net = netKcal(t, hb);
    final target = targetAt(p, d);
    if (t.kcal >= 900 && d != end) full.add((d, net, t.p));
    b.writeln('- ${_day(d)}: ${fInt(net)} kcal (${fSigned((net - target) / target * 100, 0)}%) · P ${fInt(t.p)} C ${fInt(t.c)} G ${fInt(t.f)}'
        ' · voto ${fDec(s.score(k).v)} · $train${hab.isEmpty ? '' : ' · $hab'}${d == end ? ' · giornata in corso' : ''}');
  }
  if (full.isNotEmpty) {
    double avg(Iterable<double> x) => x.isEmpty ? 0 : x.reduce((a, b) => a + b) / x.length;
    final wk = full.where((e) => e.$1.weekday < 6).map((e) => e.$2), we = full.where((e) => e.$1.weekday >= 6).map((e) => e.$2);
    b.writeln('Medie su ${full.length} giorni completi: ${fInt(avg(full.map((e) => e.$2)))} kcal, proteine ${fInt(avg(full.map((e) => e.$3)))} g '
        '(sotto il target in ${full.where((e) => e.$3 < p.protein).length} giorni)'
        '${wk.isNotEmpty && we.isNotEmpty ? '. Feriali ${fInt(avg(wk))} kcal, weekend ${fInt(avg(we))} kcal' : ''}.');
  }
  if (total > 0) b.writeln('Voci del diario: $total, di cui $photo stimate da foto.');

  h('Sedute: serie fatte (kg×ripetizioni@RPE) e volta prima');
  var any = false;
  for (final k in keys) {
    for (final ss in s.sessionsByDate[k] ?? const <Session>[]) {
      if (ss.isActive) continue;
      any = true;
      b.writeln('### ${_day(fromKey(k))} · ${ss.name} · ${ss.duration.inMinutes} min');
      for (final e in ss.items) {
        final sets = e.sets.where((x) => x.done).toList();
        if (sets.isEmpty) {
          b.writeln('- ${e.name}: non fatto');
          continue;
        }
        final prev = s.lastPerformance(e.ex, beforeTs: ss.start);
        final was = prev == null ? 'prima volta' : 'prima (${_day(fromKey(prev.$1.date))}): ${prev.$2.workDone.map(_set).join(' ')}';
        b.writeln('- ${e.name} [${s.exercise(e.ex)?.muscle ?? '?'}] ${e.target.scheme}: ${sets.map(_set).join(' ')} · $was');
      }
    }
  }
  if (!any) b.writeln('Nessuna seduta nel periodo.');

  final next = nextSlot(s);
  if (next?.day != null) {
    h('Coach dell\'app per la prossima seduta: ${next!.day!.name}, ${_day(next.date)}');
    for (final a in dayAdvice(s, next.day!)) {
      b.writeln('- ${a.exName}: ${a.kind == AdviceKind.first ? a.title.toLowerCase() : '${a.kg > 0 ? '${fKg(a.kg)} kg × ' : ''}${a.reps} · ${a.title.toLowerCase()}'}');
    }
  }

  h('Muscoli: serie efficaci a settimana (obiettivo ${minEffective.round()}-${maxEffective.round()})');
  for (var mon = mondayOf(start); !mon.isAfter(end); mon = addDays(mon, 7)) {
    final r = weekReport(s, mon);
    b.writeln('- settimana del ${mon.day}/${mon.month}, ${r.done} ${r.done == 1 ? 'seduta' : 'sedute'}:${r.muscles.map((m) => '${m.muscle} ${fDec(m.done, 1, true)}').join(', ')}');
  }

  final bal = weekBalance(s, end);
  h('Bilancio di questa settimana');
  for (final r in bal.rows) {
    b.writeln('- ${r.k}: ${r.v}');
  }
  if (bal.note != null) b.writeln('- ${bal.note}');

  b
    ..writeln()
    ..writeln('Tigert $appVersion');
  return b.toString();
}

/// Le priorità nella risposta: le righe numerate dopo "PRIORITÀ"; se il titolo
/// manca, l'ultimo elenco numerato del testo.
List<String> parsePriorities(String reply) {
  final lines = reply.replaceAll('\r', '').split('\n');
  final item = RegExp(r'^\s*(?:[-*•]\s*)?(\d)\s*[\)\.:\-]\s*(.+)$');
  final at = lines.lastIndexWhere((l) {
    final t = fold(l).replaceAll(RegExp(r'[^a-z ]'), '').trim();
    return t.startsWith('priorita') && t.length <= 40;
  });
  var out = <String>[];
  for (final raw in lines.skip(at + 1)) {
    final m = item.firstMatch(raw.replaceAll('**', '').replaceAll('__', ''));
    if (m == null) continue;
    if (at < 0 && m.group(1) == '1') out = [];
    final t = m.group(2)!.trim();
    if (t.isEmpty || t == '...' || t == '…') continue;
    out.add(t);
  }
  return out.take(5).toList();
}
