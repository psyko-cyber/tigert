import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/fmt.dart';
import '../core/theme.dart';
import '../data/app_state.dart';
import '../data/models.dart';
import '../logic/training.dart';
import '../logic/volume.dart';
import '../logic/week_report.dart';
import 'help.dart';
import 'settings/home_gym_settings.dart';
import 'shell.dart';
import 'training.dart';
import 'volume.dart';
import 'widgets.dart';

String weekRange(DateTime mon) {
  final sun = mon.add(const Duration(days: 6));
  return mon.month == sun.month ? '${mon.day}-${sun.day} ${mesi[sun.month - 1]}' : '${shortDate(mon)} - ${shortDate(sun)}';
}

Color statusColor(BuildContext context, MuscleStatus s) => switch (s) {
      MuscleStatus.ok => context.tt.accentInk,
      MuscleStatus.under => TC.warn,
      _ => TC.danger,
    };

/// Muscoli: la settimana (percentuale per muscolo, cosa sistemare, seduta a casa)
/// e la scheda (volume previsto). [planId]: dall'editor apre la vista Scheda.
class MusclesScreen extends StatefulWidget {
  final DateTime? monday;
  final String? planId;
  const MusclesScreen({super.key, this.monday, this.planId});
  @override
  State<MusclesScreen> createState() => _MusclesScreenState();
}

class _MusclesScreenState extends State<MusclesScreen> {
  late DateTime mon = mondayOf(widget.monday ?? DateTime.now());
  late bool planView = widget.planId != null;

  @override
  Widget build(BuildContext context) => SubPage(
        title: 'Muscoli',
        actions: const [Padding(padding: EdgeInsets.only(right: 10), child: HelpDot(helpEffective))],
        body: PageBody(children: [
          Row(children: [
            PillChip('Settimana', selected: !planView, onTap: () => setState(() => planView = false)),
            const SizedBox(width: 8),
            PillChip('Scheda', selected: planView, onTap: () => setState(() => planView = true)),
          ]),
          const SizedBox(height: 8),
          if (planView) VolumeView(planId: widget.planId) else ..._week(context),
        ]),
      );

  List<Widget> _week(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final r = weekReport(app, mon);
    final isLast = !mon.isBefore(mondayOf(today()));
    final lagging = r.lagging;
    final gym = app.profile!.home;
    return [
        Row(children: [
          IconButton(
            onPressed: () => setState(() => mon = mon.subtract(const Duration(days: 7))),
            icon: const Icon(Icons.chevron_left_rounded),
            tooltip: 'Settimana prima',
          ),
          Expanded(
            child: Column(children: [
              Text(r.current ? 'Questa settimana' : weekRange(mon), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: t.ink)),
              const SizedBox(height: 2),
              Text(
                '${r.current ? '${weekRange(mon)} · ' : ''}${r.done} ${r.done == 1 ? 'seduta fatta' : 'sedute fatte'}'
                '${r.left > 0 ? ' · ${r.left} in programma' : ''}',
                textAlign: TextAlign.center,
                style: TS.muted(t, 12.5),
              ),
            ]),
          ),
          IconButton(
            onPressed: isLast ? null : () => setState(() => mon = mon.add(const Duration(days: 7))),
            icon: const Icon(Icons.chevron_right_rounded),
            tooltip: 'Settimana dopo',
          ),
        ]),
        const SectionLabel('Muscoli · 100% = 10 serie efficaci'),
        TCard(
          child: Column(children: [
            for (final m in r.muscles) _MuscleRow(m: m),
          ]),
        ),
        SectionLabel(lagging.isEmpty ? 'Com\'è andata' : 'Cosa sistemare'),
        for (final tip in r.tips)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(lagging.isEmpty ? Icons.check_circle_outline_rounded : Icons.info_outline_rounded,
                    size: 16, color: lagging.isEmpty ? t.accentInk : TC.warn),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(tip, style: TS.soft(t, 13))),
            ]),
          ),
        if (lagging.isNotEmpty && !r.closed) ...[
          const SectionLabel('Seduta extra a casa'),
          if (gym == null)
            TCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Hai attrezzi a casa?', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: t.ink)),
                const SizedBox(height: 4),
                Text('Dimmi cosa hai (sbarra, parallele, panca, manubri) e ti preparo una seduta per recuperare ${joinMuscles(lagging)}.',
                    style: TS.soft(t, 13)),
                const SizedBox(height: 10),
                SmallButton('Indica cosa hai', accent: true, onTap: () => push(context, const HomeGymScreen())),
              ]),
            )
          else if (r.home case final h?) ...[
            HomeSessionCard(home: h, gym: gym),
            PrimaryButton('Inizia a casa · oggi', icon: Icons.home_rounded, onTap: () => startSession(context, day: h.day, offPlan: true)),
          ] else
            NoteBox(text: 'Con la tua attrezzatura (${gym.summary.toLowerCase()}) non ho esercizi per ${joinMuscles(lagging)}.'),
          if (gym != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Center(
                child: TextButton(
                  onPressed: () => push(context, const HomeGymScreen()),
                  child: Text('Attrezzatura: ${gym.summary.toLowerCase()} ›', style: TextStyle(fontSize: 12.5, color: t.accentInk)),
                ),
              ),
            ),
        ],
    ];
  }
}

String joinMuscles(List<MuscleWeek> l) {
  final names = l.take(3).map((m) => m.muscle.toLowerCase()).toList();
  return names.length <= 1 ? names.join() : '${names.take(names.length - 1).join(', ')} e ${names.last}';
}

class _MuscleRow extends StatelessWidget {
  final MuscleWeek m;
  const _MuscleRow({required this.m});
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    final c = statusColor(context, m.status);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(m.muscle, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: t.ink))),
          Text(m.status.label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c)),
          const SizedBox(width: 10),
          SizedBox(
            width: 46,
            child: Text('${m.pctTotal}%', textAlign: TextAlign.right, style: TS.num(t, 15, w: FontWeight.w800, color: c)),
          ),
        ]),
        const SizedBox(height: 6),
        BarTrack(pct: math.min(1, m.total / weekTarget), color: c),
        if (m.planned >= 0.5) ...[
          const SizedBox(height: 4),
          Text('Fatto ${m.pct}% · il resto con le sedute in programma', style: TS.muted(t, 11.5)),
        ],
      ]),
    );
  }
}

/// La seduta a casa proposta: esercizi, serie e ripetizioni.
class HomeSessionCard extends StatelessWidget {
  final HomeSession home;
  final HomeGym gym;
  const HomeSessionCard({super.key, required this.home, required this.gym});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    return TCard(
      margin: const EdgeInsets.only(bottom: 12),
      borderColor: TC.accent.withValues(alpha: 0.7),
      onTap: () => showDayPreview(context, home.day, offPlan: true),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.home_rounded, size: 18, color: t.accentInk),
          const SizedBox(width: 8),
          Expanded(child: Label(home.day.name, color: t.accentInk)),
        ]),
        const SizedBox(height: 10),
        for (final it in home.day.items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Expanded(child: Text(app.exerciseName(it.ex), style: TS.body(t), maxLines: 1, overflow: TextOverflow.ellipsis)),
              Text('${it.scheme} ${app.exercise(it.ex)?.repsLabel ?? 'rip'}', style: TS.muted(t)),
            ]),
          ),
        const SizedBox(height: 6),
        Text(
          '${home.day.totalSets} serie · circa ${(home.day.totalSets * 2.5).round()} minuti'
          '${gym.dbKg > 0 && gym.dbKg < 16 ? ' · con i manubri leggeri fermati a 1-2 ripetizioni dal cedimento' : ''}',
          style: TS.muted(t, 12),
        ),
      ]),
    );
  }
}

/// Card unica dei muscoli (Allena e Progressi): serie della settimana,
/// muscoli rimasti indietro e avviso se la scheda ne prevede poche.
class MusclesCard extends StatelessWidget {
  const MusclesCard({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final r = weekReport(app, DateTime.now());
    final vol = weekVolume(app);
    final plan = app.activePlan;
    final pv = plan == null || plan.days.isEmpty ? const <String, MuscleVolume>{} : planVolume(app, plan);
    final low = [
      for (final m in mainMuscles)
        if (pv.isNotEmpty && (pv[m]?.effective ?? 0) < minEffective) m.toLowerCase(),
    ];
    return TCard(
      margin: const EdgeInsets.only(bottom: 14),
      onTap: () => push(context, const MusclesScreen()),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Label('Muscoli della settimana')),
          const HelpDot(helpEffective),
          const SizedBox(width: 4),
          Text('Apri →', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: t.accentInk)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          _Stat('${vol.done}', 'serie fatte'),
          _Stat('${vol.planned}', 'previste'),
          _Stat('${vol.prs}', 'record', accent: vol.prs > 0),
        ]),
        const SizedBox(height: 12),
        if (r.lagging.isEmpty) Text(r.summary, style: TS.soft(t, 13)) else _LaggingChips(r.lagging),
        if (low.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.info_outline_rounded, size: 16, color: TC.warn)),
            const SizedBox(width: 8),
            Expanded(child: Text('La scheda prevede poche serie per ${_join(low)}.', style: TS.soft(t, 13))),
          ]),
        ],
      ]),
    );
  }
}

String _join(List<String> l) => l.length <= 1 ? l.join() : '${l.take(l.length - 1).join(', ')} e ${l.last}';

class _Stat extends StatelessWidget {
  final String v;
  final String k;
  final bool accent;
  const _Stat(this.v, this.k, {this.accent = false});
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    return Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(v, style: TS.num(t, 22, color: accent ? t.accentInk : null)),
        Text(k, style: TS.muted(t, 11)),
      ]),
    );
  }
}

/// I muscoli indietro come chip colorate (percentuale della settimana).
class _LaggingChips extends StatelessWidget {
  final List<MuscleWeek> lagging;
  const _LaggingChips(this.lagging);
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    return Wrap(spacing: 6, runSpacing: 6, children: [
      for (final m in lagging.take(4))
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(color: t.surf2, borderRadius: BorderRadius.circular(99)),
          child: Text('${m.muscle} ${m.pctTotal}%',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: statusColor(context, m.status), fontFeatures: tabular)),
        ),
    ]);
  }
}

/// Nel weekend in Oggi: il report della settimana come suggerimento.
class WeekReportCard extends StatelessWidget {
  const WeekReportCard({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final r = weekReport(app, DateTime.now());
    final lagging = r.lagging;
    return GestureDetector(
      onTap: () => push(context, const MusclesScreen()),
      child: TipCard(
        title: 'Report della settimana',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (lagging.isEmpty) Text(r.summary, style: TS.soft(t, 13)) else _LaggingChips(lagging),
          if (lagging.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(r.home != null ? 'C\'è una seduta a casa pronta per recuperare.' : 'Guarda come bilanciare la settimana.', style: TS.soft(t, 13)),
          ],
        ]),
      ),
    );
  }
}

/// In Oggi il report compare dal giorno del report a domenica.
bool showReportToday(AppState app) =>
    DateTime.now().weekday >= reportWeekday && (app.profile?.reminders.reportOn ?? true) && weekReport(app, DateTime.now()).done > 0;
