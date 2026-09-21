import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/fmt.dart';
import '../core/theme.dart';
import '../data/app_state.dart';
import '../data/models.dart';
import '../logic/achievements.dart';
import 'charts.dart';
import 'widgets.dart';

class AchievementsScreen extends StatelessWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final p = app.profile!;
    final lv = levelFor(totalXp(app));
    final list = badges(app);
    final unlocked = list.where((b) => b.unlocked).length;
    final cells = heatmap(app);
    final scored = cells.where((c) => c.$2 != null).map((c) => c.$2!).toList();
    final avg = scored.isEmpty ? null : scored.reduce((a, b) => a + b) / scored.length;
    final cur = app.currentWeight;
    final lo = math.min(p.startWeight, p.targetWeight), hi = math.max(p.startWeight, p.targetWeight);
    final progress = p.goal == Goal.maintain || hi - lo < 0.1 ? null : ((cur - p.startWeight) / (p.targetWeight - p.startWeight)).clamp(0.0, 1.0);

    return SubPage(
      title: 'Traguardi',
      body: PageBody(children: [
        TCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('Livello ${lv.level} · ${lv.title}', style: TS.title(t).copyWith(fontSize: 15))),
              Text('${fInt(lv.xp)} / ${fInt(lv.to)} XP', style: TS.muted(t, 12)),
            ]),
            const SizedBox(height: 8),
            BarTrack(pct: lv.progress, color: TC.accent),
            const SizedBox(height: 8),
            Text(xpBreakdown(), style: TS.muted(t, 11)),
          ]),
        ),
        const SectionLabel('Ultime 10 settimane'),
        Heatmap(cells: cells),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: Text('🔥 Streak ${streak(app)} giorni', style: TS.muted(t, 12))),
          Text(avg == null ? 'Nessun voto ancora' : 'Voto medio ${fDec(avg)}', style: TS.muted(t, 12)),
        ]),
        if (progress != null) ...[
          const SectionLabel('Percorso peso'),
          TCard(
            child: Column(children: [
              BarTrack(pct: progress, color: TC.accent, height: 10),
              const SizedBox(height: 8),
              Row(children: [
                for (var i = 0; i <= 3; i++)
                  Expanded(
                    child: Text(
                      '${fDec(p.startWeight + (p.targetWeight - p.startWeight) * i / 3, 1, true)}${i == 3 || i == 0 ? ' kg' : ''}',
                      textAlign: i == 0 ? TextAlign.left : (i == 3 ? TextAlign.right : TextAlign.center),
                      style: TextStyle(fontSize: 11, color: t.dim, fontFeatures: tabular),
                    ),
                  ),
              ]),
              const SizedBox(height: 6),
              Text('Media attuale ${fDec(cur, 1)} kg · ${(progress * 100).round()}% del percorso', style: TS.muted(t, 12)),
            ]),
          ),
        ],
        SectionLabel('Badge · $unlocked / ${list.length}'),
        LayoutBuilder(builder: (context, c) {
          final cols = c.maxWidth > 560 ? 3 : 2;
          return GridView.count(
            crossAxisCount: cols,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.25,
            children: [for (final b in list) _BadgeTile(b)],
          );
        }),
      ]),
    );
  }
}

class _BadgeTile extends StatelessWidget {
  final BadgeState b;
  const _BadgeTile(this.b);
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    return TCard(
      padding: const EdgeInsets.all(14),
      borderColor: b.unlocked ? TC.accent.withValues(alpha: 0.5) : null,
      onTap: () => showBadgeDialog(context, [b], preview: true),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Opacity(opacity: b.unlocked ? 1 : 0.35, child: Text(b.icon, style: const TextStyle(fontSize: 26))),
        const Spacer(),
        Text(b.name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: b.unlocked ? t.ink : t.soft), maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 2),
        Text(b.unlocked ? 'Sbloccato il ${shortDate(fromKey(b.unlockedAt!))}' : b.progressLabel, style: TS.muted(t, 11)),
        if (!b.unlocked) ...[const SizedBox(height: 6), BarTrack(pct: b.progress, color: TC.accent, height: 4)],
      ]),
    );
  }
}

/// Finestra "Badge sbloccato" (anche anteprima dalla griglia).
Future<void> showBadgeDialog(BuildContext context, List<BadgeState> list, {bool preview = false}) {
  final b = list.first;
  final t = context.tt;
  return showDialog(
    context: context,
    builder: (c) => Dialog(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 26, 22, 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.7, end: 1),
            duration: const Duration(milliseconds: 450),
            curve: Curves.elasticOut,
            builder: (_, s, child) => Transform.scale(scale: s, child: child),
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(color: b.unlocked ? TC.accent : t.surf2, borderRadius: BorderRadius.circular(28)),
              alignment: Alignment.center,
              child: Text(b.icon, style: const TextStyle(fontSize: 46)),
            ),
          ),
          const SizedBox(height: 16),
          Text(b.unlocked ? (preview ? 'BADGE' : 'BADGE SBLOCCATO') : 'DA SBLOCCARE', style: TS.label(t, t.accentInk)),
          const SizedBox(height: 6),
          Text(b.name, textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: t.ink)),
          const SizedBox(height: 8),
          Text(b.desc, textAlign: TextAlign.center, style: TS.soft(t)),
          if (!b.unlocked) ...[const SizedBox(height: 8), Text(b.progressLabel, style: TS.muted(t, 12))],
          if (!preview && b.unlocked) ...[const SizedBox(height: 8), Text('+50 XP', style: TextStyle(fontWeight: FontWeight.w800, color: t.accentInk))],
          if (list.length > 1) ...[
            const SizedBox(height: 10),
            Text('e altri ${list.length - 1}: ${list.skip(1).map((x) => x.name).join(', ')}', textAlign: TextAlign.center, style: TS.muted(t, 12)),
          ],
          const SizedBox(height: 18),
          PrimaryButton('Continua', onTap: () => Navigator.pop(c)),
        ]),
      ),
    ),
  );
}
