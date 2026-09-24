import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/fmt.dart';
import '../core/theme.dart';
import '../data/app_state.dart';
import '../data/models.dart';
import '../logic/achievements.dart';
import '../logic/activity.dart';
import '../logic/nutrition.dart';
import '../logic/progression.dart';
import '../logic/score.dart';
import '../logic/supplements.dart';
import '../logic/training.dart';
import '../services/updates.dart';
import 'achievements_screen.dart';
import 'diary.dart';
import 'extra_activity.dart';
import 'score_detail.dart';
import 'session.dart';
import 'shell.dart';
import 'week_report.dart';
import 'widgets.dart';

class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final p = app.profile!;
    final k = todayKey();
    final score = app.score(k);
    final tot = app.totals(k);
    final burned = app.habit(k).burned;
    final net = netKcal(tot, app.habit(k));
    final left = p.kcal - net;
    final phase = p.phaseOn(k);
    final over = kcalOver(net, p.kcal, phase);
    final hour = DateTime.now().hour;
    final greet = hour < 12 ? 'Buongiorno' : (hour < 18 ? 'Ciao' : 'Buonasera');
    final update = UpdateInfo.fromMap(app.prefs.availableUpdate);
    final showUpdate = update != null && isNewer(update.version, '0') && app.prefs.dismissedUpdate != update.version;
    final adj = p.autoAdjust ? null : checkAdjustment(p, app.weightStats);

    return PageBody(children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(longDate(DateTime.now()).toUpperCase(), style: TS.label(t)),
            const SizedBox(height: 4),
            Text(p.name.isEmpty ? greet : '$greet, ${p.name}', style: TS.h1(t)),
          ]),
        ),
        Tap(
          onTap: () => push(context, const AchievementsScreen()),
          radius: 99,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            decoration: BoxDecoration(color: t.surf2, borderRadius: BorderRadius.circular(99)),
            child: Text('🔥 ${streak(app)}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: t.ink, fontFeatures: tabular)),
          ),
        ),
      ]),
      if (showUpdate)
        TipCard(
          title: 'Nuova versione ${update.version}',
          child: Row(children: [
            Expanded(child: Text('È disponibile un aggiornamento di Tigert.', style: TS.soft(t))),
            SmallButton('Più tardi', onTap: () => app.prefs.dismissedUpdate = update.version),
            const SizedBox(width: 8),
            SmallButton('Scarica', accent: true, onTap: () => launchUrl(Uri.parse(update.downloadUrl ?? update.pageUrl), mode: LaunchMode.externalApplication)),
          ]),
        ),
      if (adj != null)
        TipCard(
          title: 'Suggerimento target',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${adj.reason} Propongo ${fInt(adj.newKcal)} kcal (${adj.delta > 0 ? '+' : ''}${adj.delta}).', style: TS.soft(t)),
            const SizedBox(height: 10),
            Row(children: [
              SmallButton('Ignora', onTap: () => app.saveProfile(p.copyWith(lastAdjust: todayKey()))),
              const SizedBox(width: 8),
              SmallButton('Applica', accent: true, onTap: () => app.applyKcal(adj.newKcal, adj.reason)),
            ]),
          ]),
        ),
      if (showReportToday(app)) const WeekReportCard(tip: true),
      const SizedBox(height: 16),
      // ------------------------------------------------------------ voto
      TCard(
        onTap: () => push(context, ScoreDetailScreen(date: k)),
        child: Row(children: [
          ScoreGauge(value: score.v, hasData: score.hasData),
          const SizedBox(width: 18),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Label('Voto di oggi'),
              const SizedBox(height: 6),
              Text(score.label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.35, color: t.ink)),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: t.surf2, borderRadius: BorderRadius.circular(99)),
                child: Text('Vedi il calcolo →', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: t.accentInk)),
              ),
            ]),
          ),
        ]),
      ),
      if (score.rest)
        const NoteBox(
          child: Text.rich(TextSpan(children: [
            TextSpan(text: 'Oggi è '),
            TextSpan(text: 'riposo programmato', style: TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: ': l\'allenamento non entra nel voto, il peso passa su nutrizione e abitudini.'),
          ])),
        ),
      const SizedBox(height: 12),
      // ------------------------------------------------------------ calorie
      TCard(
        onTap: () => push(context, DiaryScreen(date: k)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(
                left >= 0 ? 'Calorie rimaste' : (over || phase == Phase.maintain ? 'Sopra il target' : 'Sopra il target · ok in ${phase.label.toLowerCase()}'),
                style: TS.muted(t),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text('${fInt(net)} / ${fInt(p.kcal)} kcal', style: TextStyle(fontSize: 13, color: t.dim, fontFeatures: tabular)),
          ]),
          const SizedBox(height: 2),
          Text(fInt(left.abs()), style: TS.num(t, 48, color: over ? TC.danger : null)),
          const SizedBox(height: 10),
          BarTrack(pct: net / math.max(1, p.kcal), color: over ? TC.danger : TC.accent),
          if (burned > 0) ...[
            const SizedBox(height: 8),
            Row(children: [
              Icon(Icons.local_fire_department_rounded, size: 16, color: t.accentInk),
              const SizedBox(width: 6),
              Expanded(
                child: Text('Mangiate ${fInt(tot.kcal)} − attività extra ${fInt(burned)} kcal',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: t.accentInk, fontFeatures: tabular)),
              ),
            ]),
          ],
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: _Macro('PROTEINE', tot.p, p.protein, TC.prot)),
            const SizedBox(width: 12),
            Expanded(child: _Macro('CARBO', tot.c, p.carbs, TC.carb)),
            const SizedBox(width: 12),
            Expanded(child: _Macro('GRASSI', tot.f, p.fat, TC.fat)),
          ]),
        ]),
      ),
      const SizedBox(height: 12),
      const _WorkoutCard(),
      const SizedBox(height: 12),
      const _WaterWeightRow(),
      const SizedBox(height: 12),
      const _HabitsCard(),
      const SizedBox(height: 12),
      _MealsCard(date: k),
    ]);
  }
}

class _Macro extends StatelessWidget {
  final String label;
  final double value;
  final int target;
  final Color color;
  const _Macro(this.label, this.value, this.target, this.color);
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: MacroLabel(label, color)),
      ]),
      const SizedBox(height: 4),
      Text.rich(TextSpan(children: [
        TextSpan(text: fInt(value), style: TS.num(t, 19, w: FontWeight.w700)),
        TextSpan(text: ' / $target g', style: TextStyle(fontSize: 11.5, color: t.dim, fontFeatures: tabular)),
      ])),
      const SizedBox(height: 6),
      BarTrack(pct: value / math.max(1, target), color: color),
    ]);
  }
}

class _WorkoutCard extends StatelessWidget {
  const _WorkoutCard();
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final active = app.activeSession;
    final slot = todaySlot(app);
    final next = nextSlot(app);
    String title, sub;
    IconData icon;
    VoidCallback onTap = () => ShellNav.go(1);
    if (active != null) {
      title = active.name;
      sub = 'In corso · ${active.doneSets}/${active.plannedSets} serie';
      icon = Icons.play_arrow_rounded;
      onTap = () => push(context, SessionScreen(sessionId: active.id));
    } else if (slot != null && slot.status == SlotStatus.off && slot.off!.postponed) {
      final to = fromKey(slot.off!.moveTo!);
      title = '${slot.day?.name ?? 'Seduta'} · rimandata';
      sub = 'La fai ${giorni[to.weekday - 1].toLowerCase()}: oggi conta come riposo';
      icon = Icons.event_repeat_rounded;
    } else if (slot != null && slot.status == SlotStatus.off) {
      final avoid = slot.off!.avoid;
      title = avoid.isEmpty ? '${slot.day?.name ?? 'Seduta'} · giustificata' : 'Al posto di ${slot.day?.name ?? 'oggi'}';
      sub = avoid.isEmpty
          ? 'Non penalizza il voto: oggi conta come riposo'
          : 'Seduta alternativa senza ${avoid.map((z) => z.toLowerCase()).join(', ')}';
      icon = avoid.isEmpty ? Icons.event_busy_rounded : Icons.swap_horiz_rounded;
    } else if (slot != null && slot.session != null) {
      final s = slot.session!;
      title = '${s.name} · fatto';
      sub = '${s.doneSets} serie · ${fInt(s.volume)} kg · ${s.duration.inMinutes} min';
      icon = Icons.check_rounded;
    } else if (slot != null && slot.day != null) {
      final d = slot.day!;
      title = d.name;
      final ups = dayAdvice(app, d).where((a) => a.kind == AdviceKind.increase).length;
      sub = ups > 0
          ? '↑ $ups ${ups == 1 ? 'carico da alzare' : 'carichi da alzare'} · ${d.totalSets} serie'
          : '${d.items.take(4).map((i) => app.exerciseName(i.ex).split(' ').first).join(', ')} · ${d.totalSets} serie';
      icon = Icons.fitness_center_rounded;
    } else {
      title = 'Riposo';
      sub = next?.day == null ? 'Nessuna seduta in programma' : 'Prossima: ${next!.day!.name} · ${giorni[next.date.weekday - 1].toLowerCase()}';
      icon = Icons.self_improvement_rounded;
    }
    final done = slot?.session != null && !(slot!.session!.isActive);
    return TCard(
      onTap: onTap,
      child: Row(children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(color: done || active != null ? TC.accent : t.surf2, borderRadius: BorderRadius.circular(14)),
          child: Icon(icon, color: done || active != null ? TC.onAccent : t.ink),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Label('Allenamento di oggi'),
            const SizedBox(height: 3),
            Text(title, style: TS.title(t).copyWith(fontSize: 17)),
            const SizedBox(height: 2),
            Text(sub, style: TS.muted(t), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
        Icon(Icons.chevron_right_rounded, color: t.dim),
      ]),
    );
  }
}

class _WaterWeightRow extends StatelessWidget {
  const _WaterWeightRow();
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final p = app.profile!;
    final k = todayKey();
    final h = app.habit(k);
    final glasses = (p.waterMl / 250).ceil().clamp(4, 16);
    final full = (h.water / 250).floor();
    final ws = app.weightStats;
    final todayW = app.weightOn(k);
    final shown = todayW ?? app.latestWeight;
    final wd = ws.weekDelta;
    final trend = ws.trend;
    final toGo = trend == null ? null : p.targetWeight - trend;

    final water = TCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Label('Acqua'),
        const SizedBox(height: 4),
        Text.rich(TextSpan(children: [
          TextSpan(text: fDec(h.water / 1000, 2, true), style: TS.num(t, 26)),
          TextSpan(text: ' / ${fDec(p.waterMl / 1000, 1, true)} L', style: TextStyle(fontSize: 14, color: t.dim, fontWeight: FontWeight.w600)),
        ])),
        const SizedBox(height: 10),
        Row(children: [
          for (var i = 0; i < glasses; i++) ...[
            if (i > 0) const SizedBox(width: 3),
            Expanded(
              child: Container(
                height: 16,
                decoration: BoxDecoration(color: i < full ? TC.prot : t.surf2, borderRadius: BorderRadius.circular(4)),
              ),
            ),
          ],
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: SmallButton('+ 250 ml', onTap: () => app.addWater(k, 250))),
          const SizedBox(width: 6),
          SmallButton('−', onTap: h.water <= 0 ? null : () => app.addWater(k, -250)),
        ]),
      ]),
    );

    final weight = TCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Label('Peso'),
        const SizedBox(height: 4),
        Text.rich(TextSpan(children: [
          TextSpan(text: shown == null ? '—' : fDec(shown, 1), style: TS.num(t, 26)),
          TextSpan(text: ' kg', style: TextStyle(fontSize: 14, color: t.dim, fontWeight: FontWeight.w600)),
        ])),
        const SizedBox(height: 6),
        Text(
          [
            if (wd != null) 'Media 7 gg ${fSigned(wd, 2)} kg',
            if (todayW == null) 'Non ancora registrato oggi',
            if (toGo != null && p.goal != Goal.maintain)
              (p.goal == Goal.bulk ? toGo <= 0.05 : toGo >= -0.05) ? 'Obiettivo raggiunto 🎯' : 'Mancano ${fDec(toGo.abs(), 1)} kg ai ${fKg(p.targetWeight)}',
          ].join('\n'),
          style: TextStyle(fontSize: 12, color: t.dim, height: 1.4),
          maxLines: 3,
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: SmallButton(todayW == null ? 'Registra peso' : 'Modifica', onTap: () async {
            final v = await askNumber(context, title: 'Peso di oggi', initial: todayW ?? app.latestWeight, unit: 'kg', decimals: 2, min: 30, max: 300);
            if (v != null) app.setWeight(k, double.parse(v.toStringAsFixed(2)));
          }),
        ),
      ]),
    );
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: water),
        const SizedBox(width: 12),
        Expanded(child: weight),
      ]),
    );
  }
}

class _HabitsCard extends StatelessWidget {
  const _HabitsCard();
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final p = app.profile!;
    final k = todayKey();
    final h = app.habit(k);
    final items = <Widget>[];
    if (p.habitOn('sleep')) {
      items.add(_HabitTile(
        icon: Icons.bedtime_rounded,
        label: 'Sonno',
        value: h.sleep == null ? 'Registra' : fMinutes(h.sleep!),
        ok: h.sleep != null && h.sleep! >= p.sleepMin,
        onTap: () async {
          final v = await askNumber(context, title: 'Ore di sonno stanotte', initial: h.sleep == null ? null : h.sleep! / 60, unit: 'ore', decimals: 1, max: 16, hint: 'es. 7,5');
          if (v != null) app.saveHabit(h.copyWith(sleep: (v * 60).round()));
        },
      ));
    }
    if (p.habitOn('steps')) {
      items.add(_HabitTile(
        icon: Icons.directions_walk_rounded,
        label: 'Passi',
        value: h.steps == null ? 'Registra' : fInt(h.steps!),
        ok: h.steps != null && h.steps! >= p.steps,
        onTap: () async {
          final v = await askNumber(context, title: 'Passi di oggi', initial: h.steps?.toDouble(), decimals: 0, max: 100000);
          if (v != null) app.saveHabit(h.copyWith(steps: v.round()));
        },
      ));
    }
    final supps = p.habitOn('supp') ? p.supplements : const <String>[];
    return TCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Label('Abitudini'),
        const SizedBox(height: 10),
        if (items.isNotEmpty)
          Row(children: [
            for (var i = 0; i < items.length; i++) ...[if (i > 0) const SizedBox(width: 10), Expanded(child: items[i])],
          ]),
        // attività extra (calcetto, beach volley...): tolgono calorie da quelle mangiate
        for (var i = 0; i < h.extra.length; i++) ...[
          const SizedBox(height: 10),
          ExtraActivityRow(day: h, index: i),
        ],
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: SmallButton('Attività extra', icon: Icons.add_rounded, onTap: () => editExtraActivity(context, h)),
        ),
        if (p.habitOn('alcohol')) ...[
          const SizedBox(height: 12),
          Row(children: [
            Icon(Icons.wine_bar_rounded, size: 18, color: t.dim),
            const SizedBox(width: 8),
            Text('Alcol', style: TextStyle(fontSize: 13, color: t.soft)),
            const Spacer(),
            for (final (v, l) in const [(0, 'No'), (1, '1'), (2, '2'), (3, '3+')]) ...[
              const SizedBox(width: 6),
              PillChip(l, selected: (h.alcohol ?? 0) == v, onTap: () => app.saveHabit(h.copyWith(alcohol: v))),
            ],
          ]),
        ],
        for (final s in supps) ...[
          const SizedBox(height: 10),
          _SupplementRow(name: s, day: h),
        ],
      ]),
    );
  }
}

/// Integratore da spuntare: serie di giorni consecutivi e ultimi 7 giorni.
class _SupplementRow extends StatelessWidget {
  final String name;
  final HabitDay day;
  const _SupplementRow({required this.name, required this.day});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final taken = day.took(name);
    final streak = supplementStreak(app.habitsByDate, name, today());
    final last = supplementLastDays(app.habitsByDate, name, today());
    return Material(
      color: t.surf2,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => app.saveHabit(day.toggleSupp(name)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          child: Row(children: [
            Icon(Icons.medication_rounded, size: 20, color: taken ? t.accentInk : t.dim),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: t.ink)),
                const SizedBox(height: 4),
                Row(children: [
                  for (var i = 0; i < last.length; i++) ...[
                    if (i > 0) const SizedBox(width: 4),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: last[i] ? TC.accent : Colors.transparent,
                        border: Border.all(color: last[i] ? TC.accent : t.dim, width: 1.2),
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      streak == 0 ? 'da spuntare' : '$streak ${streak == 1 ? 'giorno' : 'giorni'} di fila',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: t.dim),
                    ),
                  ),
                ]),
              ]),
            ),
            Icon(taken ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, size: 28, color: taken ? TC.accent : t.dim),
          ]),
        ),
      ),
    );
  }
}

class _HabitTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool ok;
  final VoidCallback onTap;
  const _HabitTile({required this.icon, required this.label, required this.value, required this.ok, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    return Material(
      color: t.surf2,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Icon(icon, size: 20, color: ok ? t.accentInk : t.dim),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: TextStyle(fontSize: 12, color: t.dim)),
                Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: t.ink, fontFeatures: tabular)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _MealsCard extends StatelessWidget {
  final String date;
  const _MealsCard({required this.date});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final entries = app.entries(date);
    final byMeal = <String, double>{};
    for (final e in entries) {
      byMeal[e.meal] = (byMeal[e.meal] ?? 0) + e.kcal;
    }
    return TCard(
      onTap: () => push(context, DiaryScreen(date: date)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Label('Pasti di oggi')),
          Text('Diario ›', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: t.accentInk)),
        ]),
        const SizedBox(height: 8),
        if (entries.isEmpty)
          Text('Ancora niente. Tocca + per aggiungere il primo pasto.', style: TS.muted(t))
        else
          for (final m in mealKeys)
            if (byMeal.containsKey(m))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Expanded(child: Text(mealLabels[m]!, style: TextStyle(fontSize: 14, color: t.ink))),
                  Text('${fInt(byMeal[m]!)} kcal', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: t.ink, fontFeatures: tabular)),
                ]),
              ),
      ]),
    );
  }
}
