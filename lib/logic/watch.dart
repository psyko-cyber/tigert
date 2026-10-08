/// Dati letti dall'orologio (Health Connect) e regole per unirli a quelli di Tigert.
library;

import 'dart:math' as math;

import '../core/fmt.dart';
import '../data/app_state.dart';
import '../data/models.dart';
import 'activity.dart';

/// Allenamento registrato dall'orologio.
class WatchWorkout {
  final String id;
  final String type; // tipo Health Connect, es. RUNNING
  final DateTime start, end;
  final double? kcal; // totali nell'intervallo, consumo a riposo compreso
  const WatchWorkout({required this.id, required this.type, required this.start, required this.end, this.kcal});
  int get minutes => end.difference(start).inMinutes;
}

/// Un giorno letto dall'orologio: i campi null non sono disponibili.
class WatchDay {
  final String date;
  final int? steps;
  final int? sleep; // minuti dormiti
  final double? kg;
  final List<WatchWorkout> workouts;
  const WatchDay({required this.date, this.steps, this.sleep, this.kg, this.workouts = const []});
}

/// Sedute con i pesi: in Tigert sono già una sessione, non un'attività extra.
const _strength = {'STRENGTH_TRAINING', 'WEIGHTLIFTING', 'TRADITIONAL_STRENGTH_TRAINING', 'FUNCTIONAL_STRENGTH_TRAINING', 'CALISTHENICS'};

bool isStrengthWorkout(String type) => _strength.contains(type);

// l'ordine conta: TABLE_TENNIS prima di TENNIS, STAIR_CLIMBING prima di CLIMBING
const _kinds = <(String, String)>[
  ('TABLE_TENNIS', 'altro'),
  ('STAIR_CLIMBING', 'altro'),
  ('RUNNING', 'corsa'),
  ('HIKING', 'escursione'),
  ('WALKING', 'camminata'),
  ('WHEELCHAIR', 'altro'),
  ('BIKING', 'bici'),
  ('CYCLING', 'bici'),
  ('SWIMMING', 'nuoto'),
  ('SOCCER', 'calcio'),
  ('VOLLEYBALL', 'pallavolo'),
  ('BASKETBALL', 'basket'),
  ('TENNIS', 'tennis'),
  ('BOXING', 'boxe'),
  ('MARTIAL_ARTS', 'boxe'),
  ('CLIMBING', 'arrampicata'),
  ('DANCING', 'ballo'),
  ('DANCE', 'ballo'),
  ('SKIING', 'sci'),
  ('SNOWBOARDING', 'sci'),
  ('YOGA', 'yoga'),
  ('PILATES', 'yoga'),
];

const _otherNames = {
  'HIGH_INTENSITY_INTERVAL_TRAINING': 'HIIT',
  'ELLIPTICAL': 'Ellittica',
  'ROWING': 'Canottaggio',
  'ROWING_MACHINE': 'Vogatore',
  'STAIR_CLIMBING': 'Scale',
  'STAIR_CLIMBING_MACHINE': 'Scale',
  'TABLE_TENNIS': 'Ping pong',
  'BADMINTON': 'Badminton',
  'GOLF': 'Golf',
  'RUGBY': 'Rugby',
  'SKATING': 'Pattinaggio',
  'SQUASH': 'Squash',
  'STRETCHING': 'Stretching',
  'SURFING': 'Surf',
  'WATER_POLO': 'Pallanuoto',
};

/// Sport di Tigert (chiave di `sports`) e nome per un tipo di allenamento dell'orologio.
(String, String) sportFor(String type) {
  for (final (k, kind) in _kinds) {
    if (!type.contains(k)) continue;
    if (kind != 'altro') return (kind, sports.firstWhere((s) => s.$1 == kind).$2);
    break;
  }
  return ('altro', _otherNames[type] ?? 'Attività');
}

/// Kcal nette: quelle dell'orologio meno il consumo a riposo, che è già nel
/// target. Se mancano o sono fuori scala vale la stima di Tigert.
int watchKcal(WatchWorkout w, String kind, double kg) {
  final est = activityKcal(kind, w.minutes, kg);
  final tot = w.kcal;
  if (tot == null || tot <= 0) return est;
  final net = tot - kg * w.minutes / 60;
  if (net < est * 0.3 || net > est * 3) return est;
  return (net / 5).round() * 5;
}

/// Minuti coperti dagli intervalli, senza contare due volte le sovrapposizioni
/// (lo stesso sonno scritto da due app).
int unionMinutes(Iterable<(DateTime, DateTime)> spans) {
  final l = spans.where((s) => s.$2.isAfter(s.$1)).toList()..sort((a, b) => a.$1.compareTo(b.$1));
  var tot = Duration.zero;
  DateTime? from, to;
  for (final (a, b) in l) {
    if (to == null || a.isAfter(to)) {
      if (to != null) tot += to.difference(from!);
      from = a;
      to = b;
    } else if (b.isAfter(to)) {
      to = b;
    }
  }
  if (to != null) tot += to.difference(from!);
  return tot.inMinutes;
}

/// Minuti dormiti nella notte che finisce il giorno [date]: le sessioni di
/// sonno che terminano quel giorno, meno i risvegli al loro interno.
int? sleepOn(String date, List<(DateTime, DateTime)> sessions, List<(DateTime, DateTime)> awake) {
  final s = sessions.where((x) => dayKey(x.$2) == date).toList();
  if (s.isEmpty) return null;
  final a = awake.where((w) => s.any((x) => !w.$1.isBefore(x.$1) && !w.$2.isAfter(x.$2)));
  return math.max(0, unionMinutes(s) - unionMinutes(a));
}

/// Sotto questa durata un allenamento dell'orologio non diventa attività extra
/// (le camminate brevi contano già nei passi).
const watchMinWorkout = 10;

/// Sotto questa durata non è una notte: resta da scrivere a mano.
const watchMinSleep = 120;

/// Il giorno [h] con i dati dell'orologio, o null se non cambia nulla.
/// - passi e sonno: solo se mancano o se erano già dell'orologio;
/// - allenamenti: diventano attività extra, tranne i pesi, quelli già importati
///   ([known]), quelli sopra una seduta di Tigert ([sessions], inizio e fine in ms)
///   e gli sport che quel giorno hai già inserito a mano.
HabitDay? mergeWatchDay(
  HabitDay h,
  WatchDay d, {
  required double kg,
  Set<String> known = const {},
  List<(int, int)> sessions = const [],
}) {
  int? steps, sleep;
  if (d.steps != null && d.steps! > 0 && (h.steps == null || h.isAuto('steps')) && d.steps != h.steps) steps = d.steps;
  if (d.sleep != null && d.sleep! >= watchMinSleep && (h.sleep == null || h.isAuto('sleep')) && d.sleep != h.sleep) sleep = d.sleep;

  final extra = [...h.extra];
  for (final w in d.workouts) {
    if (w.minutes < watchMinWorkout || isStrengthWorkout(w.type)) continue;
    if (known.contains(w.id) || extra.any((e) => e.src == w.id)) continue;
    final a = w.start.millisecondsSinceEpoch, b = w.end.millisecondsSinceEpoch;
    final over = sessions.fold(0, (s, x) => s + math.max(0, math.min(b, x.$2) - math.max(a, x.$1)));
    if (over * 2 > b - a) continue;
    final (kind, name) = sportFor(w.type);
    if (kind != 'altro' && extra.any((e) => e.src == null && e.kind == kind)) continue;
    extra.add(ExtraActivity(kind: kind, name: name, min: w.minutes, kcal: watchKcal(w, kind, kg), src: w.id));
  }
  final added = extra.length > h.extra.length;
  if (steps == null && sleep == null && !added) return null;
  return h.withWatch(steps: steps, sleep: sleep, extra: added ? extra : null);
}

/// Unisce i giorni letti dall'orologio ai dati di Tigert: ritorna quanti valori
/// sono cambiati. Il peso entra solo se quel giorno manca.
int applyWatch(AppState app, List<WatchDay> days) {
  var n = 0;
  final known = app.prefs.watchSeen.toSet();
  final seen = <String>[];
  final kg = app.currentWeight;
  app.store.batch(() {
    for (final d in days) {
      final sessions = [
        for (final s in app.sessionsByDate[d.date] ?? const <Session>[]) (s.start, s.end ?? s.start + s.duration.inMilliseconds),
      ];
      final h = app.habit(d.date);
      final m = mergeWatchDay(h, d, kg: kg, known: known, sessions: sessions);
      if (m != null) {
        app.saveHabit(m);
        if (m.steps != h.steps) n++;
        if (m.sleep != h.sleep) n++;
        n += m.extra.length - h.extra.length;
        seen.addAll(m.extra.skip(h.extra.length).map((e) => e.src!));
      }
      final w = d.kg;
      if (w != null && w >= 30 && w <= 300 && app.weightOn(d.date) == null) {
        app.setWeight(d.date, (w * 10).round() / 10);
        n++;
      }
    }
  });
  // ricordo gli allenamenti già importati: se ne elimini uno non torna
  if (seen.isNotEmpty) {
    final all = [...app.prefs.watchSeen, ...seen];
    app.prefs.watchSeen = all.length > 300 ? all.sublist(all.length - 300) : all;
  }
  return n;
}
