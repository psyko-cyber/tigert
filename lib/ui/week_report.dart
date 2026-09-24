import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/fmt.dart';
import '../core/theme.dart';
import '../data/app_state.dart';
import '../data/models.dart';
import '../logic/week_report.dart';
import 'settings/home_gym_settings.dart';
import 'shell.dart';
import 'training.dart';
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

/// Report della settimana: percentuale per muscolo, cosa sistemare e seduta a casa.
class WeekReportScreen extends StatefulWidget {
  final DateTime? monday;
  const WeekReportScreen({super.key, this.monday});
  @override
  State<WeekReportScreen> createState() => _WeekReportScreenState();
}

class _WeekReportScreenState extends State<WeekReportScreen> {
  late DateTime mon = mondayOf(widget.monday ?? DateTime.now());

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final r = weekReport(app, mon);
    final isLast = !mon.isBefore(mondayOf(today()));
    final lagging = r.lagging;
    final gym = app.profile!.home;
    return SubPage(
      title: 'Report settimanale',
      body: PageBody(children: [
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
        NoteBox(
          text: 'Conta le serie efficaci delle sedute fatte da lunedì a domenica${r.current ? ', più quelle ancora in programma' : ''}: '
              'le serie a fine seduta, sotto RPE 8 o in dropset valgono meno, i multiarticolari danno mezza serie ai muscoli secondari. '
              'Da 80% a 220% (8-22 serie) va bene, sotto è poco, sopra è difficile recuperare.',
        ),
      ]),
    );
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

/// Card compatta del report (Allena e Oggi): i muscoli indietro e un tocco per aprirlo.
class WeekReportCard extends StatelessWidget {
  final bool tip; // stile TipCard (in Oggi, nel weekend)
  const WeekReportCard({super.key, this.tip = false});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final r = weekReport(app, DateTime.now());
    final lagging = r.lagging;
    final body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (!tip)
        Row(children: [
          const Expanded(child: Label('Report della settimana')),
          Text('Apri →', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: t.accentInk)),
        ]),
      if (!tip) const SizedBox(height: 8),
      if (lagging.isEmpty)
        Text(r.summary, style: TS.soft(t, 13))
      else
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final m in lagging.take(4))
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: t.surf2, borderRadius: BorderRadius.circular(99)),
              child: Text('${m.muscle} ${m.pctTotal}%',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: statusColor(context, m.status), fontFeatures: tabular)),
            ),
        ]),
      if (tip && lagging.isNotEmpty) ...[
        const SizedBox(height: 10),
        Text(r.home != null ? 'C\'è una seduta a casa pronta per recuperare.' : 'Guarda come bilanciare la settimana.', style: TS.soft(t, 13)),
      ],
    ]);
    if (tip) {
      return GestureDetector(
        onTap: () => push(context, const WeekReportScreen()),
        child: TipCard(title: 'Report della settimana', child: body),
      );
    }
    return TCard(
      margin: const EdgeInsets.only(bottom: 14),
      onTap: () => push(context, const WeekReportScreen()),
      child: body,
    );
  }
}

/// In Oggi il report compare dal giorno del report a domenica.
bool showReportToday(AppState app) =>
    DateTime.now().weekday >= reportWeekday && (app.profile?.reminders.reportOn ?? true) && weekReport(app, DateTime.now()).done > 0;
