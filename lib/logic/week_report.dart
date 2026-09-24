import 'dart:math' as math;

import '../core/fmt.dart';
import '../data/app_state.dart';
import '../data/models.dart';
import 'day_off.dart';
import 'training.dart';
import 'volume.dart';

/// Report settimanale dei muscoli: per ogni gruppo muscolare le serie efficaci
/// della settimana (lunedì-domenica) rispetto all'obiettivo di [weekTarget],
/// cosa non va, come sistemare la scheda e una seduta a casa con gli attrezzi
/// che hai per recuperare i muscoli rimasti indietro.

const weekTarget = 10.0; // serie efficaci a settimana = 100%
const reportWeekday = DateTime.saturday;

enum MuscleStatus { none, low, under, ok, high }

extension MuscleStatusX on MuscleStatus {
  String get label => switch (this) {
        MuscleStatus.none => 'non allenato',
        MuscleStatus.low => 'poco',
        MuscleStatus.under => 'un po\' sotto',
        MuscleStatus.ok => 'va bene',
        MuscleStatus.high => 'troppo',
      };
  bool get lagging => index <= MuscleStatus.under.index;
}

/// Sotto il 50% poco, fino all'80% (8 serie) un po' sotto, sopra il 220% (22) troppo.
MuscleStatus statusFor(double eff) => eff < 0.5
    ? MuscleStatus.none
    : eff < weekTarget * 0.5
        ? MuscleStatus.low
        : eff < minEffective
            ? MuscleStatus.under
            : eff > maxEffective
                ? MuscleStatus.high
                : MuscleStatus.ok;

class MuscleWeek {
  final String muscle;
  final double done; // serie efficaci fatte
  final double planned; // serie efficaci delle sedute ancora in programma questa settimana
  final double plan; // serie efficaci che la scheda prevede in una settimana
  final double planDirect; // serie dirette della scheda in una settimana
  const MuscleWeek(this.muscle, this.done, {this.planned = 0, this.plan = 0, this.planDirect = 0});
  double get total => done + planned;
  int get pct => (done / weekTarget * 100).round();
  int get pctTotal => (total / weekTarget * 100).round();
  MuscleStatus get status => statusFor(total);
}

class HomeSession {
  final PlanDay day;
  final List<String> muscles;
  const HomeSession(this.day, this.muscles);
}

class WeekReport {
  final DateTime monday;
  final List<MuscleWeek> muscles; // nell'ordine di mainMuscles
  final int done; // sedute fatte
  final int left; // sedute ancora in programma
  final List<String> tips;
  final HomeSession? home;
  const WeekReport(this.monday, this.muscles, this.done, this.left, this.tips, this.home);

  DateTime get sunday => monday.add(const Duration(days: 6));
  bool get closed => today().isAfter(sunday);
  bool get current => !closed && !today().isBefore(monday);

  /// I muscoli indietro, dal meno allenato.
  List<MuscleWeek> get lagging => [...muscles.where((m) => m.status.lagging)]..sort((a, b) => a.total.compareTo(b.total));

  /// Una riga per notifica e card: i muscoli indietro con la percentuale.
  String get summary {
    if (done == 0 && left == 0) return 'Nessuna seduta questa settimana.';
    final l = lagging;
    if (l.isEmpty) return 'Settimana bilanciata: tutti i muscoli principali sono ad almeno l\'80%.';
    final list = l.take(3).map((m) => '${m.muscle} ${m.pctTotal}%').join(', ');
    return home != null && current ? '$list. C\'è una seduta a casa pronta per recuperare.' : '$list: guarda come bilanciare.';
  }
}

String _n(double v) => fDec(v, 1, true);

List<VolSet> sessionSets(AppState s, Session ss) => [
      for (final e in ss.items)
        for (final st in e.sets)
          if (st.done) VolSet(s.exercise(e.ex), st.t, st.rpe),
    ];

List<VolSet> daySets(AppState s, PlanDay d) => [
      for (final it in d.items)
        for (var i = 0; i < it.sets; i++) VolSet(s.exercise(it.ex), setWork, it.rpe),
    ];

WeekReport weekReport(AppState s, DateTime ref) {
  final mon = mondayOf(ref);
  return s.memo('report:${dayKey(mon)}', () => _weekReport(s, mon));
}

WeekReport _weekReport(AppState s, DateTime mon) {
  final end = mon.add(const Duration(days: 7));
  final t = today();
  bool inWeek(DateTime d) => !d.isBefore(mon) && d.isBefore(end);
  final sessions = [for (final ss in s.doneSessions) if (inWeek(fromKey(ss.date))) ss];
  final done = muscleVolume([for (final ss in sessions) sessionSets(s, ss)]);

  // sedute della scheda ancora da fare (solo per la settimana in corso)
  final upcoming = <PlanDay>[];
  if (inWeek(t)) {
    for (final sl in weekSchedule(s, ref: mon)) {
      if (sl.session != null || sl.day == null) continue;
      if (sl.status == SlotStatus.todo || sl.status == SlotStatus.today) upcoming.add(sl.day!);
    }
  }
  final planned = muscleVolume([for (final d in upcoming) daySets(s, d)]);
  final plan = s.activePlan;
  final perWeek = plan == null ? const <String, MuscleVolume>{} : planVolume(s, plan);

  final muscles = [
    for (final m in mainMuscles)
      MuscleWeek(m, done[m]?.effective ?? 0,
          planned: planned[m]?.effective ?? 0, plan: perWeek[m]?.effective ?? 0, planDirect: perWeek[m]?.sets ?? 0),
  ];
  final draft = WeekReport(mon, muscles, sessions.length, upcoming.length, const [], null);
  final lagging = draft.lagging;
  final g = s.profile?.home;
  final home = g == null || lagging.isEmpty ? null : homeSession(s, g, lagging, id: 'casa-${dayKey(mon)}');
  final tips = _tips(s, draft, plan, home);
  return WeekReport(mon, muscles, sessions.length, upcoming.length, tips, home);
}

/// Esercizio da proporre in palestra per un muscolo indietro.
const _gymHint = <String, String>{
  'Petto': 'panca inclinata con manubri',
  'Dorso': 'rematore o lat machine',
  'Spalle': 'alzate laterali',
  'Bicipiti': 'curl con manubri',
  'Tricipiti': 'pushdown ai cavi',
  'Quadricipiti': 'leg press o squat',
  'Femorali': 'leg curl',
  'Glutei': 'hip thrust',
};

/// Il muscolo che si allena volentieri insieme: la seduta dove aggiungere le serie.
const _pairedWith = <String, String>{
  'Spalle': 'Petto',
  'Tricipiti': 'Petto',
  'Bicipiti': 'Dorso',
  'Femorali': 'Quadricipiti',
  'Glutei': 'Quadricipiti',
  'Petto': 'Tricipiti',
  'Dorso': 'Bicipiti',
  'Quadricipiti': 'Femorali',
};

/// La seduta della scheda a cui aggiungere un esercizio di [muscle]: quella che
/// allena già il muscolo "compagno", altrimenti la più corta.
PlanDay? dayToExtend(AppState s, Plan plan, String muscle) {
  if (plan.days.isEmpty) return null;
  final mate = _pairedWith[muscle];
  double setsOf(PlanDay d, String? m) => d.items.where((it) => s.exercise(it.ex)?.muscle == m).fold(0.0, (a, it) => a + it.sets);
  final withMate = plan.days.where((d) => setsOf(d, mate) > 0).toList()..sort((a, b) => setsOf(b, mate).compareTo(setsOf(a, mate)));
  if (withMate.isNotEmpty) return withMate.first;
  return ([...plan.days]..sort((a, b) => a.totalSets.compareTo(b.totalSets))).first;
}

List<String> _tips(AppState s, WeekReport r, Plan? plan, HomeSession? home) {
  final out = <String>[];
  if (r.done == 0 && r.left == 0) return const ['Nessuna seduta registrata in questa settimana.'];
  final lagging = r.lagging;
  for (final m in lagging.take(3)) {
    final head = '${m.muscle} al ${m.pctTotal}%';
    if (plan != null && m.plan < minEffective) {
      final d = dayToExtend(s, plan, m.muscle);
      final what = m.planDirect < 0.5 ? 'non c\'è nessun esercizio diretto' : 'ci sono solo ${_n(m.plan)} serie efficaci a settimana';
      out.add('$head: nella scheda ${plan.name} $what. In palestra aggiungi 3 serie di ${_gymHint[m.muscle]}'
          '${d == null ? '' : ' a ${d.name}'}.');
    } else if (plan != null) {
      final left = m.planned >= 0.5 ? ' e ${_n(m.planned)} sono ancora in programma' : '';
      out.add('$head: la scheda ne prevede ${_n(m.plan)} a settimana, ne hai fatte ${_n(m.done)}$left. '
          'Hai saltato o accorciato una seduta${home != null && r.current ? ': recupera con la seduta a casa' : ''}.');
    } else {
      out.add('$head: aggiungi 3 serie di ${_gymHint[m.muscle]}.');
    }
  }
  for (final m in r.muscles.where((m) => m.status == MuscleStatus.high)) {
    out.add('${m.muscle} al ${m.pctTotal}%: tanto volume, se non recuperi togli qualche serie.');
  }
  for (final (a, b) in const [('Petto', 'Dorso'), ('Quadricipiti', 'Femorali'), ('Bicipiti', 'Tricipiti')]) {
    final va = r.muscles.firstWhere((m) => m.muscle == a).total, vb = r.muscles.firstWhere((m) => m.muscle == b).total;
    if (va < 1 || vb < 1) continue;
    final ratio = math.max(va, vb) / math.min(va, vb);
    if (ratio >= 1.8) out.add('${va >= vb ? a : b} riceve ${_n(ratio)} volte il volume di ${va >= vb ? b : a}: bilancia i due distretti.');
  }
  if (out.isEmpty) out.add('Settimana bilanciata: tutti i muscoli principali sono ad almeno l\'80%.');
  return out;
}

// =================================================================== seduta a casa

/// Cosa serve per fare un esercizio a casa, oltre a quello che dice il catalogo (manubri o corpo libero).
const _homeNeeds = <String, Set<String>>{
  'trazioni': {'bar'},
  'chin-up': {'bar'},
  'trazioni-presa-neutra': {'bar'},
  'rematore-inverso': {'dip'}, // sotto le parallele della torre
  'hip-thrust-monolaterale': {'bench'},
  'leg-raise-sbarra': {'bar'},
  'dip-petto': {'dip'},
  'dip-tricipiti': {'dip'},
  'panca-piana-manubri': {'bench'},
  'croci-manubri': {'bench'},
  'pullover-manubrio': {'bench'},
  'dip-panche': {'bench'},
  'french-press-manubri': {'bench'},
  'rematore-manubrio': {'bench'},
  'panca-inclinata-manubri': {'incline'},
  'croci-inclinata-manubri': {'incline'},
  'rematore-panca-inclinata': {'incline'},
  'y-raise': {'incline'},
  'curl-inclinata': {'incline'},
  'curl-spider': {'incline'},
};

/// Esercizi da fare a casa per ogni muscolo, dal più utile con pesi leggeri.
const homePicks = <String, List<String>>{
  'Petto': ['dip-petto', 'push-up', 'panca-inclinata-manubri', 'panca-piana-manubri', 'croci-manubri', 'floor-press-manubri', 'push-up-declinati'],
  'Dorso': ['trazioni', 'rematore-manubrio', 'chin-up', 'rematore-panca-inclinata', 'trazioni-presa-neutra', 'rematore-inverso'],
  'Spalle': ['lento-manubri', 'alzate-laterali', 'alzate-posteriori', 'y-raise', 'arnold-press', 'alzate-frontali', 'pike-push-up'],
  'Bicipiti': ['curl-manubri', 'curl-inclinata', 'curl-martello', 'curl-concentrato', 'curl-zottman'],
  'Tricipiti': ['dip-tricipiti', 'estensioni-manubrio', 'dip-panche', 'french-press-manubri', 'kickback', 'push-up-diamante'],
  'Quadricipiti': ['bulgarian', 'goblet-squat', 'affondi-inversi', 'step-up', 'pistol-squat-assistito', 'bulgarian-corpo-libero'],
  'Femorali': ['stacco-rumeno-monolaterale', 'stacco-rumeno-manubri', 'leg-curl-scivolamento'],
  'Glutei': ['glute-bridge', 'frog-pump', 'hip-thrust-monolaterale', 'glute-bridge-monolaterale'],
};

const _easyBodyweight = {'push-up', 'glute-bridge', 'frog-pump', 'bulgarian-corpo-libero', 'glute-bridge-monolaterale'};

bool canDoAtHome(Exercise e, HomeGym g) {
  if (e.isCardio) return false;
  if (!(_homeNeeds[e.id] ?? const <String>{}).every(g.has)) return false;
  return switch (e.equip) { 'Manubri' => g.dbKg > 0, 'Corpo libero' => true, _ => false };
}

/// Serie e ripetizioni a casa: con manubri leggeri si sale di ripetizioni.
PlanItem homeItem(Exercise e, HomeGym g, int sets) {
  if (e.type == 'b') {
    final easy = _easyBodyweight.contains(e.id);
    return PlanItem(ex: e.id, sets: sets, rMin: easy ? 12 : 6, rMax: easy ? 25 : 15, rpe: 9, rest: 90);
  }
  final light = g.dbKg < 16;
  if (e.type == 'i') return PlanItem(ex: e.id, sets: sets, rMin: 12, rMax: 20, rpe: 9, rest: 60);
  return PlanItem(ex: e.id, sets: sets, rMin: light ? 12 : 8, rMax: light ? 20 : 12, rpe: 9, rest: 90);
}

/// Seduta extra a casa per i muscoli più indietro (massimo 3, circa 15 serie):
/// a ognuno le serie che mancano per arrivare a [weekTarget], da 3 a 6.
HomeSession? homeSession(AppState s, HomeGym g, List<MuscleWeek> lagging, {required String id}) {
  final items = <PlanItem>[];
  final muscles = <String>[];
  var budget = 15;
  for (final m in lagging) {
    if (budget < 3 || muscles.length == 3) break;
    final options = [
      for (final x in homePicks[m.muscle] ?? const <String>[])
        if (s.exercise(x) case final e? when canDoAtHome(e, g)) e,
    ];
    if (options.isEmpty) continue;
    final need = math.min(budget, (weekTarget - m.total).ceil().clamp(3, 6));
    final n = need >= 5 && options.length > 1 ? 2 : 1;
    for (var i = 0; i < n; i++) {
      items.add(homeItem(options[i], g, need ~/ n + (i < need % n ? 1 : 0)));
    }
    budget -= need;
    muscles.add(m.muscle);
  }
  if (items.isEmpty) return null;
  // prima i multiarticolari, poi il resto
  final order = [...items]..sort((a, b) {
      final c = (s.exercise(a.ex)?.type == 'i' ? 1 : 0).compareTo(s.exercise(b.ex)?.type == 'i' ? 1 : 0);
      return c != 0 ? c : items.indexOf(a).compareTo(items.indexOf(b));
    });
  return HomeSession(PlanDay(id: id, name: 'A casa · ${joinIt(muscles)}', items: order), muscles);
}

/// Testo della notifica del sabato.
String reportNotificationBody(AppState s, DateTime day) => weekReport(s, day).summary;
