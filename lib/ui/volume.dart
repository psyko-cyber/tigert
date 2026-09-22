import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/fmt.dart';
import '../core/theme.dart';
import '../data/app_state.dart';
import '../logic/volume.dart';
import 'shell.dart';
import 'widgets.dart';

/// Negli ultimi 14 giorni c'è almeno una settimana di allenamenti? Altrimenti si valuta la scheda.
bool _hasRecent(AppState app) {
  final from = dayKey(today().subtract(const Duration(days: 13)));
  final n = app.doneSessions.where((s) => s.date.compareTo(from) >= 0).length;
  return n >= (app.profile?.trainingDays.length ?? 3).clamp(2, 7);
}

/// Card compatta in Allena: i consigli principali sul volume per muscolo.
class VolumeCard extends StatelessWidget {
  const VolumeCard({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final plan = app.activePlan;
    final recent = _hasRecent(app);
    final tips = recent ? volumeTips(recentVolume(app)) : (plan == null ? const <VolumeTip>[] : volumeTips(planVolume(app, plan), planned: true));
    return TCard(
      margin: const EdgeInsets.only(bottom: 14),
      onTap: () => push(context, const VolumeScreen()),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Label(recent ? 'Volume efficace · ultimi 14 giorni' : 'Volume previsto dalla scheda')),
          Text('Dettagli →', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: t.accentInk)),
        ]),
        const SizedBox(height: 8),
        if (tips.isEmpty)
          Text('Volume equilibrato su tutti i gruppi muscolari.', style: TS.soft(t, 13))
        else
          for (final tip in tips.take(2))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(padding: const EdgeInsets.only(top: 2), child: Icon(Icons.info_outline_rounded, size: 16, color: TC.warn)),
                const SizedBox(width: 8),
                Expanded(child: Text(tip.text, style: TS.soft(t, 13))),
              ]),
            ),
        if (tips.length > 2) Text('+${tips.length - 2} altri consigli', style: TS.muted(t, 12)),
      ]),
    );
  }
}

class VolumeScreen extends StatelessWidget {
  final String? planId;
  const VolumeScreen({super.key, this.planId});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final plan = planId == null ? app.activePlan : app.plan(planId);
    final recent = planId == null && _hasRecent(app);
    return SubPage(
      title: 'Volume per muscolo',
      body: PageBody(children: [
        if (recent) ...[
          const SectionLabel('Fatto · media a settimana, ultimi 14 giorni'),
          MuscleVolumeTable(volumeOf: recentVolume(app)),
          VolumeTips(tips: volumeTips(recentVolume(app))),
        ],
        if (plan != null && plan.days.isNotEmpty) ...[
          SectionLabel('Previsto da ${plan.name}${plan.cycle > 1 ? ' · media sulle ${plan.cycle} settimane' : ''}'),
          MuscleVolumeTable(volumeOf: planVolume(app, plan)),
          VolumeTips(tips: volumeTips(planVolume(app, plan), planned: true)),
        ],
        const SizedBox(height: 8),
        NoteBox(
          text: 'Le serie non valgono tutte uguale. Ogni serie allenante già fatta nella seduta toglie il 2,5% alle successive (minimo 50%): '
              'le serie a fine allenamento stimolano meno. Contano anche l\'RPE (sotto 8 valgono meno), i dropset (mezza serie) '
              'e i multiarticolari, che danno mezza serie ai muscoli secondari (es. panca → tricipiti e spalle). '
              'Gli avvicinamenti non contano. Obiettivo indicativo: ${fInt(minEffective + 2)}-20 serie efficaci a settimana per muscolo.',
        ),
        Text('Serie = serie dirette · efficaci = pesate per posizione, RPE e secondari', style: TS.muted(t, 11.5)),
      ]),
    );
  }
}

class MuscleVolumeTable extends StatelessWidget {
  final Map<String, MuscleVolume> volumeOf;
  const MuscleVolumeTable({super.key, required this.volumeOf});
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    final others = volumeOf.keys.where((m) => !mainMuscles.contains(m) && m != 'Cardio').toList()..sort();
    final rows = [...mainMuscles, ...others];
    return TCard(
      child: Column(children: [
        for (final m in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Builder(builder: (context) {
              final v = volumeOf[m];
              final eff = v?.effective ?? 0;
              final main = mainMuscles.contains(m);
              final low = main && eff < minEffective, high = main && eff > maxEffective;
              final color = low ? TC.warn : (high ? TC.danger : TC.accent);
              return Row(children: [
                SizedBox(width: 104, child: Text(m, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: t.ink))),
                Expanded(child: BarTrack(pct: math.min(1, eff / 24), color: color)),
                const SizedBox(width: 10),
                SizedBox(
                  width: 92,
                  child: Text(
                    '${fDec(v?.sets ?? 0, 1, true)} → ${fDec(eff, 1, true)}',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 12.5, color: low || high ? color : t.soft, fontFeatures: tabular),
                  ),
                ),
              ]);
            }),
          ),
      ]),
    );
  }
}

class VolumeTips extends StatelessWidget {
  final List<VolumeTip> tips;
  const VolumeTips({super.key, required this.tips});
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    if (tips.isEmpty) {
      return Padding(padding: const EdgeInsets.only(top: 8), child: Text('Nessun distretto trascurato o sovraccarico.', style: TS.soft(t, 13)));
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final tip in tips)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: const EdgeInsets.only(top: 2), child: Icon(Icons.info_outline_rounded, size: 16, color: TC.warn)),
              const SizedBox(width: 8),
              Expanded(child: Text(tip.text, style: TS.soft(t, 13))),
            ]),
          ),
      ]),
    );
  }
}
