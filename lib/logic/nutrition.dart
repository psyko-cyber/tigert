import 'dart:math' as math;

import '../core/fmt.dart';
import '../data/models.dart';

class Targets {
  final int kcal, protein, carbs, fat, water;
  final int tdee, bmr;
  const Targets(this.kcal, this.protein, this.carbs, this.fat, this.water, this.tdee, this.bmr);
}

/// Metabolismo basale (Mifflin-St Jeor).
double bmr({required String sex, required double kg, required double cm, required int age}) =>
    10 * kg + 6.25 * cm - 5 * age + (sex == 'f' ? -161 : 5);

double activityFactor(String activity) => activityLevels[activity]?.$2 ?? 1.55;

int round10(double v) => (v / 10).round() * 10;
int round250(double v) => (v / 250).round() * 250;

/// Surplus/deficit giornaliero per un ritmo in kg/settimana (7700 kcal ≈ 1 kg).
double dailyDelta(Goal goal, double rate) => switch (goal) {
      Goal.bulk => rate * 7700 / 7,
      Goal.cut => -rate * 7700 / 7,
      Goal.maintain => 0,
    };

Targets computeTargets({
  required String sex,
  required int age,
  required double heightCm,
  required double weight,
  required String activity,
  required Goal goal,
  required double rate,
}) {
  final b = bmr(sex: sex, kg: weight, cm: heightCm, age: age);
  final tdee = b * activityFactor(activity);
  var kcal = tdee + dailyDelta(goal, rate);
  final floor = sex == 'f' ? 1300.0 : 1600.0;
  kcal = math.max(kcal, math.min(floor, tdee));
  final k = round10(kcal);
  // Peso di riferimento per le proteine: se il BMI è alto uso il peso a BMI 27.
  final h = heightCm / 100;
  final refW = math.min(weight, 27 * h * h);
  final perKg = switch (goal) { Goal.cut => 2.2, Goal.bulk => 2.0, Goal.maintain => 1.8 };
  final p = (perKg * refW).round();
  final f = math.max(0.8 * weight, 0.25 * k / 9).round();
  final c = math.max(50, ((k - p * 4 - f * 9) / 4).round());
  final water = round250(35 * weight + 500).clamp(2000, 4500);
  return Targets(k, p, c, f, water, tdee.round(), b.round());
}

/// Ricalcola i carboidrati per un nuovo target calorico, mantenendo P e G.
(int, int, int) macrosFor(int kcal, int protein, int fat) {
  final c = math.max(50, ((kcal - protein * 4 - fat * 9) / 4).round());
  return (protein, c, fat);
}

// =================================================================== peso

class WeightStats {
  final List<WeightEntry> entries; // ordinati per data
  WeightStats(this.entries);

  bool get isEmpty => entries.isEmpty;
  WeightEntry? get last => entries.isEmpty ? null : entries.last;

  /// Media degli ultimi [days] giorni fino a [end] incluso.
  double? avg(DateTime end, [int days = 7]) {
    final from = end.subtract(Duration(days: days - 1));
    final xs = entries.where((e) {
      final d = fromKey(e.date);
      return !d.isBefore(dateOnly(from)) && !d.isAfter(dateOnly(end));
    }).map((e) => e.kg);
    if (xs.isEmpty) return null;
    return xs.reduce((a, b) => a + b) / xs.length;
  }

  /// Media mobile corrente (ultimi 7 giorni rispetto all'ultima pesata).
  double? get trend {
    if (entries.isEmpty) return null;
    return avg(fromKey(entries.last.date));
  }

  /// Pendenza in kg/settimana (regressione lineare) negli ultimi [days] giorni.
  double? slopePerWeek({int days = 21, DateTime? end}) {
    final e = dateOnly(end ?? DateTime.now());
    final start = e.subtract(Duration(days: days));
    final pts = entries.where((x) {
      final d = fromKey(x.date);
      return d.isAfter(start) && !d.isAfter(e);
    }).toList();
    if (pts.length < 4) return null;
    final xs = pts.map((p) => daysBetween(start, fromKey(p.date)).toDouble()).toList();
    final span = xs.last - xs.first;
    if (span < 9) return null;
    final ys = pts.map((p) => p.kg).toList();
    final mx = xs.reduce((a, b) => a + b) / xs.length;
    final my = ys.reduce((a, b) => a + b) / ys.length;
    var num = 0.0, den = 0.0;
    for (var i = 0; i < xs.length; i++) {
      num += (xs[i] - mx) * (ys[i] - my);
      den += (xs[i] - mx) * (xs[i] - mx);
    }
    if (den == 0) return null;
    return num / den * 7;
  }

  /// Variazione della media 7 giorni rispetto alla settimana precedente.
  double? get weekDelta {
    if (entries.isEmpty) return null;
    final end = fromKey(entries.last.date);
    final a = avg(end);
    final b = avg(end.subtract(const Duration(days: 7)));
    if (a == null || b == null) return null;
    return a - b;
  }
}

// =================================================================== TDEE reale

class TdeeEstimate {
  final int days;
  final double avgIntake;
  final double slopePerWeek;
  final double tdee;
  const TdeeEstimate(this.days, this.avgIntake, this.slopePerWeek, this.tdee);
  double get balance => avgIntake - tdee;
}

/// Stima il dispendio reale da calorie registrate e andamento del peso.
/// Considera solo i giorni "completi" (≥ 900 kcal registrate) degli ultimi 28.
TdeeEstimate? realTdee({required Map<String, Macro> totalsByDate, required WeightStats weights, DateTime? now}) {
  final end = dateOnly(now ?? DateTime.now()).subtract(const Duration(days: 1));
  final intakes = <double>[];
  for (var i = 0; i < 28; i++) {
    final k = dayKey(end.subtract(Duration(days: i)));
    final t = totalsByDate[k];
    if (t != null && t.kcal >= 900) intakes.add(t.kcal);
  }
  if (intakes.length < 14) return null;
  final slope = weights.slopePerWeek(days: 28, end: end);
  if (slope == null) return null;
  final avgIntake = intakes.reduce((a, b) => a + b) / intakes.length;
  final tdee = avgIntake - slope / 7 * 7700;
  return TdeeEstimate(intakes.length, avgIntake, slope, tdee);
}

/// Quanti giorni di dati mancano per il TDEE reale.
int tdeeDaysMissing(Map<String, Macro> totalsByDate, {DateTime? now}) {
  final end = dateOnly(now ?? DateTime.now()).subtract(const Duration(days: 1));
  var n = 0;
  for (var i = 0; i < 28; i++) {
    final t = totalsByDate[dayKey(end.subtract(Duration(days: i)))];
    if (t != null && t.kcal >= 900) n++;
  }
  return math.max(0, 14 - n);
}

// =================================================================== adeguamento

class Adjustment {
  final int newKcal;
  final int delta;
  final String reason;
  const Adjustment(this.newKcal, this.delta, this.reason);
}

/// Ogni 14 giorni confronta il ritmo reale con quello desiderato.
Adjustment? checkAdjustment(Profile p, WeightStats w, {DateTime? now}) {
  final t = dateOnly(now ?? DateTime.now());
  final last = fromKey(p.lastAdjust ?? p.startDate);
  if (daysBetween(last, t) < 14) return null;
  final slope = w.slopePerWeek(days: 14, end: t);
  if (slope == null) return null;
  final s = fSigned(slope, 2);
  switch (p.goal) {
    case Goal.bulk:
      final exp = p.rate;
      if (slope < exp * 0.5) {
        final d = slope <= 0 ? 100 : 50;
        return Adjustment(p.kcal + d, d, 'Il peso va a $s kg/sett, meno della metà dell\'obiettivo (+${fDec(exp, 2, true)}).');
      }
      if (slope > exp * 1.7 && slope > 0.3) {
        return Adjustment(p.kcal - 50, -50, 'Il peso sale troppo in fretta ($s kg/sett): rischi più grasso che muscolo.');
      }
    case Goal.cut:
      final exp = -p.rate;
      if (slope > exp * 0.5) {
        final d = slope >= 0 ? -100 : -50;
        return Adjustment(p.kcal + d, d, 'Il peso va a $s kg/sett, più lento dell\'obiettivo (${fSigned(exp, 2)}).');
      }
      if (slope < exp * 1.7 && slope < -0.6) {
        return Adjustment(p.kcal + 100, 100, 'Stai perdendo troppo in fretta ($s kg/sett): proteggiamo la massa magra.');
      }
    case Goal.maintain:
      if (slope > 0.2) return Adjustment(p.kcal - 50, -50, 'Il peso sta salendo ($s kg/sett).');
      if (slope < -0.2) return Adjustment(p.kcal + 50, 50, 'Il peso sta scendendo ($s kg/sett).');
  }
  return null;
}

/// Target calorico in vigore in una certa data (dallo storico delle modifiche).
int targetAt(Profile p, DateTime d) {
  if (!d.isBefore(today())) return p.kcal;
  var v = p.kcalStart;
  final ch = [...p.changes]..sort((a, b) => a.date.compareTo(b.date));
  for (final c in ch) {
    if (!fromKey(c.date).isAfter(d)) v = c.to;
  }
  return v;
}

class RampBar {
  final String label;
  final int kcal;
  final bool future;
  final bool current;
  const RampBar(this.label, this.kcal, this.future, this.current);
}

/// 4 settimane passate + 4 previste per il grafico "salita graduale".
List<RampBar> targetRamp(Profile p) {
  final mon = mondayOf(DateTime.now());
  final out = <RampBar>[];
  for (var i = -3; i <= 0; i++) {
    final wEnd = mon.add(Duration(days: i * 7 + 6));
    final ref = i == 0 ? today() : wEnd;
    out.add(RampBar(i == 0 ? 'ora' : '${i}s', targetAt(p, ref), false, i == 0));
  }
  var v = p.kcal;
  for (var i = 1; i <= 4; i++) {
    if (p.autoAdjust && i.isEven) {
      v += switch (p.goal) { Goal.bulk => 50, Goal.cut => -50, Goal.maintain => 0 };
    }
    out.add(RampBar('+${i}s', v, true, false));
  }
  return out;
}

String rampText(Profile p) {
  final r = targetRamp(p);
  final from = r.first.kcal, to = r.last.kcal;
  final stepTxt = switch (p.goal) {
    Goal.bulk => '+50 kcal ogni 2 settimane se il peso non sale',
    Goal.cut => '−50 kcal ogni 2 settimane se il peso non scende',
    Goal.maintain => 'piccoli ritocchi se il peso si sposta',
  };
  if (!p.autoAdjust) return 'Adeguamento automatico spento: il target resta ${fInt(p.kcal)} kcal finché non lo cambi tu.';
  return 'Da ${fInt(from)} a ${fInt(to)} kcal in 8 settimane, $stepTxt.';
}

/// Data stimata per raggiungere il peso obiettivo.
DateTime? goalEta(Profile p, double currentKg) {
  if (p.goal == Goal.maintain || p.rate <= 0) return null;
  final diff = p.targetWeight - currentKg;
  if (p.goal == Goal.bulk && diff <= 0) return null;
  if (p.goal == Goal.cut && diff >= 0) return null;
  final weeks = diff.abs() / p.rate;
  return today().add(Duration(days: (weeks * 7).round()));
}
