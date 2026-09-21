import 'dart:math' as math;

import '../core/fmt.dart';
import '../data/app_state.dart';
import '../data/models.dart';

/// Tono di una riga del dettaglio voto.
enum Tone { good, warn, bad, dim }

class ScoreRow {
  final String k;
  final String v;
  final Tone tone;
  const ScoreRow(this.k, this.v, this.tone);
}

class ScorePart {
  final String name;
  final double points;
  final double max;
  final List<ScoreRow> rows;
  const ScorePart(this.name, this.points, this.max, this.rows);
  double get ratio => max <= 0 ? 0 : points / max;
}

class Tip {
  final double gain;
  final String text;
  const Tip(this.gain, this.text);
}

class DayScore {
  final String date;
  final double v;
  final bool rest;
  final bool trainingDay;
  final bool hasData;
  final double nutri;
  final double? allen;
  final double abit;
  final double kcalScore, protScore;
  final List<ScorePart> parts;
  final List<Tip> tips;

  const DayScore({
    required this.date,
    required this.v,
    required this.rest,
    required this.trainingDay,
    required this.hasData,
    required this.nutri,
    required this.allen,
    required this.abit,
    required this.kcalScore,
    required this.protScore,
    required this.parts,
    required this.tips,
  });

  String get label {
    if (!hasData) return 'Registra il primo pasto per far partire il voto.';
    final head = v >= 9
        ? 'Giornata da tigre.'
        : v >= 8
            ? 'Ottima giornata.'
            : v >= 6.5
                ? 'Sulla buona strada.'
                : v >= 5
                    ? 'Si può ancora recuperare.'
                    : 'Giornata in salita.';
    if (tips.isEmpty) return head;
    return '$head ${tips.first.text}';
  }
}

/// Punteggio calorie: pieno entro ±10%, poi scende linearmente fino a 0 al ±30%.
double kcalScoreFor(double kcal, int target) {
  if (kcal <= 0 || target <= 0) return 0;
  final dev = (kcal - target).abs() / target;
  return dev <= 0.10 ? 1 : math.max(0, 1 - (dev - 0.10) / 0.20);
}

double alcoholScore(int? drinks) => switch (drinks) {
      null || 0 => 1,
      1 => 0.6,
      2 => 0.3,
      _ => 0,
    };

bool isTrainingDay(Profile p, DateTime d) => p.trainingDays.contains(d.weekday);

DayScore computeScore(AppState s, String date) {
  final p = s.profile;
  final d = fromKey(date);
  if (p == null) {
    return DayScore(date: date, v: 0, rest: false, trainingDay: false, hasData: false, nutri: 0, allen: 0, abit: 0, kcalScore: 0, protScore: 0, parts: const [], tips: const []);
  }
  final t = s.totals(date);
  final h = s.habit(date);
  final isToday = date == todayKey();

  // ---------------------------------------------------------- nutrizione
  final kS = kcalScoreFor(t.kcal, p.kcal);
  final pS = t.p <= 0 ? 0.0 : math.min(1.0, t.p / math.max(1, p.protein));
  final nutri = 0.6 * kS + 0.4 * pS;

  // ---------------------------------------------------------- allenamento
  final daySessions = (s.sessionsByDate[date] ?? const <Session>[]);
  final planned = daySessions.fold<int>(0, (a, x) => a + x.plannedSets);
  final done = daySessions.fold<int>(0, (a, x) => a + x.doneSets);
  final trainingDay = isTrainingDay(p, d) || daySessions.isNotEmpty;
  double? allen;
  if (trainingDay) {
    if (daySessions.isEmpty) {
      allen = 0;
    } else {
      allen = planned <= 0 ? 1 : math.min(1.0, done / planned);
    }
  }
  final rest = allen == null;
  final allenV = allen ?? 0.0;

  // ---------------------------------------------------------- abitudini
  final habitScores = <double>[];
  final habitRows = <ScoreRow>[];
  Tone toneOf(double x) => x >= 0.999 ? Tone.good : (x >= 0.5 ? Tone.warn : Tone.bad);
  if (p.habitOn('water')) {
    final x = math.min(1.0, h.water / math.max(1, p.waterMl));
    habitScores.add(x);
    habitRows.add(ScoreRow('Acqua ${fDec(h.water / 1000, 2)} / ${fDec(p.waterMl / 1000, 1, true)} L', '${(x * 100).round()}%', toneOf(x)));
  }
  if (p.habitOn('sleep')) {
    final x = h.sleep == null ? 0.0 : math.min(1.0, h.sleep! / math.max(1, p.sleepMin));
    habitScores.add(x);
    habitRows.add(ScoreRow(h.sleep == null ? 'Sonno non registrato' : 'Sonno ${fMinutes(h.sleep!)}', h.sleep == null ? '—' : (x >= 0.999 ? 'ok' : '${(x * 100).round()}%'), h.sleep == null ? Tone.dim : toneOf(x)));
  }
  if (p.habitOn('steps')) {
    final x = h.steps == null ? 0.0 : math.min(1.0, h.steps! / math.max(1, p.steps));
    habitScores.add(x);
    habitRows.add(ScoreRow(h.steps == null ? 'Passi non registrati' : 'Passi ${fInt(h.steps!)} / ${fInt(p.steps)}', h.steps == null ? '—' : '${(x * 100).round()}%', h.steps == null ? Tone.dim : toneOf(x)));
  }
  if (p.habitOn('alcohol')) {
    final x = alcoholScore(h.alcohol);
    habitScores.add(x);
    final a = h.alcohol ?? 0;
    habitRows.add(ScoreRow('Alcol', a == 0 ? 'nessuno' : '$a ${a == 1 ? 'bicchiere' : 'bicchieri'}', toneOf(x)));
  }
  final abit = habitScores.isEmpty ? 1.0 : habitScores.reduce((a, b) => a + b) / habitScores.length;

  // ---------------------------------------------------------- totale
  final double v;
  final double kMax, pMax, aMax, hMax;
  if (rest) {
    v = 10 * ((0.5 * nutri + 0.15 * abit) / 0.65);
    kMax = 3 / 0.65;
    pMax = 2 / 0.65;
    aMax = 0;
    hMax = 1.5 / 0.65;
  } else {
    v = 10 * (0.5 * nutri + 0.35 * allenV + 0.15 * abit);
    kMax = 3;
    pMax = 2;
    aMax = 3.5;
    hMax = 1.5;
  }

  final hasData = t.kcal > 0 || daySessions.isNotEmpty || h.water > 0 || h.steps != null || h.sleep != null;

  // ---------------------------------------------------------- dettaglio
  final devPct = p.kcal <= 0 ? 0 : ((t.kcal - p.kcal) / p.kcal * 100).round();
  final devTxt = t.kcal <= 0 ? '' : ' (${devPct > 0 ? '+' : devPct < 0 ? '−' : '±'}${devPct.abs()}%)';
  final parts = <ScorePart>[
    ScorePart('Nutrizione', kMax * kS + pMax * pS, kMax + pMax, [
      ScoreRow('Calorie ${fInt(t.kcal)} / ${fInt(p.kcal)}$devTxt', '${fDec(kMax * kS)} / ${fDec(kMax)}', kS > 0.8 ? Tone.good : (kS > 0.3 ? Tone.warn : Tone.bad)),
      ScoreRow('Proteine ${fInt(t.p)} / ${p.protein} g', '${fDec(pMax * pS)} / ${fDec(pMax)}', pS > 0.9 ? Tone.good : (pS > 0.5 ? Tone.warn : Tone.bad)),
    ]),
    if (rest)
      const ScorePart('Allenamento', 0, 0, [
        ScoreRow('Giorno di riposo programmato', 'non penalizzato', Tone.dim),
        ScoreRow('Peso redistribuito', 'su nutrizione e abitudini', Tone.dim),
      ])
    else
      ScorePart('Allenamento', aMax * allenV, aMax, [
        ScoreRow('Sessione svolta', daySessions.isEmpty ? 'no' : (daySessions.any((x) => !x.isActive) ? 'sì' : 'in corso'), daySessions.isEmpty ? Tone.bad : Tone.good),
        ScoreRow('Serie completate $done / $planned', '${fDec(aMax * allenV)} / ${fDec(aMax)}', allenV >= 0.999 ? Tone.good : (allenV > 0.5 ? Tone.warn : Tone.bad)),
      ]),
    ScorePart('Abitudini', hMax * abit, hMax, habitRows),
  ];

  // ---------------------------------------------------------- suggerimenti
  final tips = <Tip>[];
  final remaining = p.kcal - t.kcal;
  if (kS < 1 && remaining > p.kcal * 0.10) {
    final gain = kMax * (1 - kS);
    tips.add(Tip(gain, isToday || d.isAfter(today()) ? 'Mangia ancora circa ${fInt(round50(remaining))} kcal.' : 'Mancavano ${fInt(remaining)} kcal.'));
  }
  if (pS < 1) {
    final miss = p.protein - t.p;
    if (miss > 3) tips.add(Tip(pMax * (1 - pS), 'Altri ${fInt(miss)} g di proteine (un vasetto di yogurt greco ne ha 17).'));
  }
  if (!rest && allenV < 1) {
    final gain = aMax * (1 - allenV);
    tips.add(Tip(gain, daySessions.isEmpty ? 'Fai l\'allenamento di oggi.' : 'Completa le ${planned - done} serie mancanti.'));
  }
  if (p.habitOn('water') && h.water < p.waterMl) {
    final miss = (p.waterMl - h.water) / 1000;
    tips.add(Tip(hMax / habitScores.length * (1 - h.water / p.waterMl), 'Bevi ancora ${fDec(miss, miss < 1 ? 2 : 1, true)} L d\'acqua.'));
  }
  if (p.habitOn('steps') && (h.steps ?? 0) < p.steps) {
    tips.add(Tip(hMax / habitScores.length * (1 - (h.steps ?? 0) / p.steps),
        h.steps == null ? 'Registra i passi di oggi.' : 'Fai ancora ${fInt(p.steps - h.steps!)} passi.'));
  }
  if (p.habitOn('sleep') && h.sleep == null) {
    tips.add(Tip(hMax / habitScores.length, 'Registra le ore di sonno.'));
  }
  tips.sort((a, b) => b.gain.compareTo(a.gain));

  return DayScore(
    date: date,
    v: (v * 10).round() / 10,
    rest: rest,
    trainingDay: trainingDay,
    hasData: hasData,
    nutri: nutri,
    allen: allen,
    abit: abit,
    kcalScore: kS,
    protScore: pS,
    parts: parts,
    tips: tips.take(4).toList(),
  );
}

double round50(double v) => (v / 50).round() * 50;
