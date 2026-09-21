import 'dart:math' as math;

import '../core/fmt.dart';
import '../data/app_state.dart';
import '../data/models.dart';
import 'nutrition.dart';
import 'training.dart';

// =================================================================== livelli

const levelTitles = [
  'Cucciolo', 'Curioso', 'Esploratore', 'Cacciatore', 'Costante',
  'Instancabile', 'Predatore', 'Tigre', 'Tigre alfa', 'Leggenda',
];

int xpForLevel(int level) => 50 * level * (level - 1);

class LevelInfo {
  final int level;
  final int xp;
  final int from;
  final int to;
  const LevelInfo(this.level, this.xp, this.from, this.to);
  String get title => levelTitles[math.min(level, levelTitles.length) - 1];
  double get progress => to <= from ? 1 : (xp - from) / (to - from);
}

LevelInfo levelFor(int xp) {
  var l = 1;
  while (xp >= xpForLevel(l + 1)) {
    l++;
  }
  return LevelInfo(l, xp, xpForLevel(l), xpForLevel(l + 1));
}

// =================================================================== streak

/// Giorni consecutivi con voto ≥ 6. Oggi conta solo se già raggiunto.
int streak(AppState s) => s.memo('streak', () {
      var d = today();
      if (s.score(dayKey(d)).v < 6) d = d.subtract(const Duration(days: 1));
      var n = 0;
      while (n < 3650) {
        final k = dayKey(d);
        if (!s.activeDates.contains(k) || s.score(k).v < 6) break;
        n++;
        d = d.subtract(const Duration(days: 1));
      }
      return n;
    });

/// Mappa delle ultime [weeks] settimane (da lunedì): voto o null.
List<(DateTime, double?)> heatmap(AppState s, {int weeks = 10}) {
  final start = mondayOf(DateTime.now()).subtract(Duration(days: (weeks - 1) * 7));
  final t = today();
  return List.generate(weeks * 7, (i) {
    final d = start.add(Duration(days: i));
    if (d.isAfter(t)) return (d, null);
    final k = dayKey(d);
    if (!s.activeDates.contains(k)) return (d, null);
    return (d, s.score(k).v);
  });
}

// =================================================================== badge

class BadgeState {
  final String id;
  final String icon;
  final String name;
  final String desc;
  final String? unlockedAt;
  final double progress;
  final String progressLabel;
  const BadgeState(this.id, this.icon, this.name, this.desc, this.unlockedAt, this.progress, this.progressLabel);
  bool get unlocked => unlockedAt != null;
}

/// Data (chiave) in cui un conteggio cronologico raggiunge [n].
String? _nth(List<String> sortedDates, int n) => sortedDates.length >= n ? sortedDates[n - 1] : null;

List<BadgeState> badges(AppState s) => s.memo('badges', () => _badges(s));

List<BadgeState> _badges(AppState s) {
  final p = s.profile;
  if (p == null) return const [];
  final out = <BadgeState>[];
  final logDates = s.logByDate.keys.toList()..sort();
  final sessions = s.doneSessions;
  final prs = allPrs(s);

  BadgeState count(String id, String icon, String name, String desc, List<String> dates, int n, String unit) {
    final at = _nth(dates, n);
    return BadgeState(id, icon, name, desc, at, math.min(1, dates.length / n), '${math.min(dates.length, n)} / $n $unit');
  }

  out.add(count('primo-pasto', '🍽️', 'Primo pasto', 'Registra il tuo primo alimento.', logDates, 1, ''));
  out.add(count('prima-sessione', '🏋️', 'Prima sessione', 'Completa il primo allenamento.', sessions.map((e) => e.date).toList(), 1, ''));

  // 7 giorni di fila con proteine sopra il target
  {
    String? at;
    var run = 0, best = 0;
    String? prev;
    for (final k in logDates) {
      final ok = s.totals(k).p >= p.protein;
      if (ok && prev != null && daysBetween(fromKey(prev), fromKey(k)) == 1 && run > 0) {
        run++;
      } else {
        run = ok ? 1 : 0;
      }
      prev = k;
      best = math.max(best, run);
      if (run >= 7 && at == null) at = k;
    }
    final cur = at != null ? 7 : math.min(7, run);
    out.add(BadgeState('proteine-7', '🥇', '7 giorni proteine ok', 'Sette giorni di fila sopra i ${p.protein} g di proteine.', at, cur / 7, '$cur / 7 giorni'));
  }

  // Settimana perfetta: 6 giorni su 7 con voto ≥ 8
  {
    String? at;
    final byWeek = <String, List<String>>{};
    for (final k in s.activeDates) {
      if (s.score(k).v >= 8) (byWeek[dayKey(mondayOf(fromKey(k)))] ??= []).add(k);
    }
    final weeks = byWeek.keys.toList()..sort();
    for (final w in weeks) {
      final l = byWeek[w]!..sort();
      if (l.length >= 6) {
        at = l[5];
        break;
      }
    }
    final cur = byWeek[dayKey(mondayOf(DateTime.now()))]?.length ?? 0;
    out.add(BadgeState('settimana-perfetta', '🔥', 'Settimana perfetta', '6 giorni su 7 con voto ≥ 8 nella stessa settimana.', at, at != null ? 1 : cur / 6,
        at != null ? 'Raggiunta' : '$cur / 6 questa settimana'));
  }

  // Streak 30
  {
    final st = streak(s);
    out.add(BadgeState('streak-30', '⚡', '30 giorni di fila', 'Voto ≥ 6 per 30 giorni consecutivi.', st >= 30 ? todayKey() : null, math.min(1, st / 30), '${math.min(st, 30)} / 30 giorni'));
  }

  // Acqua
  {
    final dates = s.habitsByDate.values.where((h) => h.water >= p.waterMl).map((h) => h.date).toList()..sort();
    out.add(count('idratato-30', '💧', '30 giorni idratato', 'Obiettivo acqua raggiunto 30 volte.', dates, 30, 'giorni'));
  }

  out.add(count('nuovo-pr', '📈', 'Nuovo record', 'Batti un tuo record su un esercizio.', prs.map((e) => e.date).toList(), 1, ''));
  out.add(count('pr-10', '🏆', '10 record', 'Dieci record battuti.', prs.map((e) => e.date).toList(), 10, 'record'));
  out.add(count('sessioni-10', '💪', '10 sessioni', 'Dieci allenamenti completati.', sessions.map((e) => e.date).toList(), 10, 'sessioni'));
  out.add(count('sessioni-50', '🐅', '50 sessioni', 'Cinquanta allenamenti completati.', sessions.map((e) => e.date).toList(), 50, 'sessioni'));

  // Volume totale
  {
    var tot = 0.0;
    String? at;
    for (final ss in sessions) {
      tot += ss.volume;
      if (tot >= 100000 && at == null) at = ss.date;
    }
    out.add(BadgeState('tonnellate-100', '🏗️', '100 tonnellate', '100.000 kg di volume totale sollevato.', at, math.min(1, tot / 100000), '${fInt(tot / 1000)} / 100 t'));
  }

  // Peso verso l'obiettivo
  final ws = s.weightStats;
  if (p.goal != Goal.maintain && !ws.isEmpty) {
    final dir = p.goal == Goal.bulk ? 1 : -1;
    final total = (p.targetWeight - p.startWeight).abs();
    String? at1, atHalf, atGoal;
    var best = 0.0;
    for (final e in ws.entries) {
      final a = ws.avg(fromKey(e.date)) ?? e.kg;
      final moved = (a - p.startWeight) * dir;
      best = math.max(best, moved);
      if (moved >= 1 && at1 == null) at1 = e.date;
      if (total > 0 && moved >= total / 2 && atHalf == null) atHalf = e.date;
      if (total > 0 && moved >= total && atGoal == null) atGoal = e.date;
    }
    out.add(BadgeState('kg-1', p.goal == Goal.bulk ? '⬆️' : '⬇️', p.goal == Goal.bulk ? '+1 kg' : '−1 kg', 'Media 7 giorni spostata di 1 kg verso l\'obiettivo.', at1,
        clamp01(best), '${fDec(math.max(0, best), 1)} / 1 kg'));
    if (total > 0) {
      out.add(BadgeState('meta-strada', '🎯', 'Metà strada', 'A metà del percorso verso ${fKg(p.targetWeight)} kg.', atHalf, clamp01(best / (total / 2)),
          '${fDec(math.max(0, best), 1)} / ${fDec(total / 2, 1)} kg'));
      out.add(BadgeState('obiettivo', '🐯', 'Obiettivo raggiunto', 'Media 7 giorni a ${fKg(p.targetWeight)} kg.', atGoal, clamp01(best / total),
          '${fDec(math.max(0, best), 1)} / ${fDec(total, 1)} kg'));
    }
  } else if (p.goal == Goal.maintain) {
    out.add(count('bilancia', '⚖️', 'Costanza sulla bilancia', 'Pesati 14 volte.', ws.entries.map((e) => e.date).toList(), 14, 'pesate'));
  }

  // TDEE
  {
    final t = realTdee(totalsByDate: s.totalsByDate, weights: ws);
    final missing = tdeeDaysMissing(s.totalsByDate);
    out.add(BadgeState('tdee', '📊', 'TDEE calcolato', 'Due settimane di pasti e pesate: ora conosciamo il tuo dispendio reale.', t != null ? todayKey() : null,
        t != null ? 1 : (14 - missing) / 14, t != null ? 'Calcolato' : '${14 - missing} / 14 giorni'));
  }

  out.add(count('chef', '👨‍🍳', 'Chef', 'Crea 5 ricette.', List.filled(s.recipes.length, todayKey()), 5, 'ricette'));
  {
    final scanned = s.userFoods.values.where((f) => f.src == 'off').length;
    out.add(count('scanner', '🔎', 'Scanner', 'Aggiungi 10 prodotti con il codice a barre.', List.filled(scanned, todayKey()), 10, 'prodotti'));
  }
  {
    final tens = s.activeDates.where((k) => s.score(k).v >= 9.95).toList()..sort();
    out.add(BadgeState('dieci', '🔟', 'Dieci pieno', 'Una giornata con voto 10.', tens.isEmpty ? null : tens.first, tens.isEmpty ? 0 : 1, tens.isEmpty ? 'Mai ancora' : 'Raggiunto'));
  }
  return out;
}

// =================================================================== XP

int totalXp(AppState s) => s.memo('xp', () {
      final p = s.profile;
      if (p == null) return 0;
      var xp = 0;
      for (final k in s.logByDate.keys) {
        xp += 10;
        final v = s.score(k).v;
        if (v >= 8) xp += 20;
        if (v >= 9.5) xp += 10;
      }
      xp += s.doneSessions.length * 50;
      xp += allPrs(s).length * 25;
      xp += s.weights.length * 5;
      xp += badges(s).where((b) => b.unlocked).length * 50;
      return xp;
    });

String xpBreakdown() =>
    'Giorno registrato +10 · voto ≥ 8 +20 · sessione +50 · record +25 · pesata +5 · badge +50';
