import 'package:flutter/material.dart';

import '../core/fmt.dart';
import '../core/theme.dart';
import '../data/app_state.dart';
import '../data/models.dart';
import '../logic/day_off.dart';
import '../logic/training.dart';
import 'training.dart';
import 'widgets.dart';

/// "Non riesci a fare la seduta?": motivo e zone da evitare. Il giorno diventa
/// giustificato (il voto non peggiora) e la seduta esce dal giro.
Future<void> showDayOffSheet(BuildContext context, WeekSlot slot) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (c) => DayOffSheet(slot: slot),
  );
}

class DayOffSheet extends StatefulWidget {
  final WeekSlot slot;
  const DayOffSheet({super.key, required this.slot});
  @override
  State<DayOffSheet> createState() => _DayOffSheetState();
}

class _DayOffSheetState extends State<DayOffSheet> {
  WeekSlot get slot => widget.slot;
  PlanDay? get day => slot.day ?? slot.queued;
  bool get past => slot.date.isBefore(today());
  late String reason = slot.off?.off ?? 'dolore';
  late final Set<String> zones = {...(slot.off?.avoid ?? (day == null ? const <String>[] : dayZones(context.appRead, day!)))};

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final plan = app.activePlan;
    final name = day?.name ?? 'la seduta';
    final i = plan == null || day == null ? -1 : plan.days.indexWhere((d) => d.id == day!.id);
    final next = i < 0 ? null : plan!.days[(i + 1) % plan.days.length];
    final pain = reason == 'dolore' && !past;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(slot.off != null ? 'Giorno giustificato' : (past ? 'Giustifica $name' : 'Non riesci a fare $name?'), style: TS.h1(t).copyWith(fontSize: 22)),
          Text(longDate(slot.date), style: TS.muted(t)),
          const SectionLabel('Motivo'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final MapEntry(key: k, value: l) in offReasons.entries) PillChip(l, selected: reason == k, onTap: () => setState(() => reason = k)),
          ]),
          if (pain) ...[
            const SectionLabel('Cosa non puoi allenare'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final z in bodyZones.keys)
                PillChip(z, selected: zones.contains(z), onTap: () => setState(() => zones.contains(z) ? zones.remove(z) : zones.add(z))),
            ]),
          ],
          NoteBox(
            margin: const EdgeInsets.only(top: 16),
            text: [
              'Il voto non peggiora: se non ti alleni, il giorno conta come riposo.',
              if (next != null && next.id != day?.id) '$name esce dal giro: la prossima seduta sarà ${next.name}.',
              if (pain && zones.isNotEmpty) 'Ti preparo una seduta senza ${joinIt(zones.map((z) => z.toLowerCase()).toList())}, con i muscoli che hai allenato meno questa settimana.',
            ].join(' '),
          ),
          const SizedBox(height: 16),
          PrimaryButton(slot.off != null ? 'Salva' : 'Conferma', onTap: () {
            app.setDayOff(dayKey(slot.date), reason, dayId: day?.id, avoid: pain ? [for (final z in bodyZones.keys) if (zones.contains(z)) z] : const []);
            Navigator.pop(context);
          }),
          if (slot.off != null) ...[
            const SizedBox(height: 10),
            GhostButton('Annulla: ${day?.name ?? 'la seduta'} torna in programma', color: TC.danger, onTap: () {
              app.clearDayOff(dayKey(slot.date));
              Navigator.pop(context);
            }),
          ],
        ]),
      ),
    );
  }
}

/// Seduta alternativa di un giorno giustificato per dolore.
class AlternativeCard extends StatelessWidget {
  final WeekSlot slot;
  final Alternative alt;
  const AlternativeCard({super.key, required this.slot, required this.alt});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final zones = slot.off!.avoid.map((z) => z.toLowerCase()).toList();
    final why = alt.added.isEmpty
        ? 'Restano gli esercizi che puoi fare.'
        : '${joinIt(alt.added)}: ${alt.added.length == 1 ? 'è il muscolo' : 'sono i muscoli'} con meno serie efficaci questa settimana '
            '(${alt.added.map((m) => '$m ${fDec(alt.week[m] ?? 0, 1, true)}').join(' · ')}).';
    return TCard(
      margin: const EdgeInsets.only(bottom: 12),
      borderColor: TC.accent.withValues(alpha: 0.7),
      onTap: () => showDayPreview(context, alt.day, offPlan: true),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.swap_horiz_rounded, size: 18, color: t.accentInk),
          const SizedBox(width: 8),
          Expanded(child: Label(alt.day.name, color: t.accentInk)),
        ]),
        const SizedBox(height: 8),
        Text('Niente ${joinIt(zones)}. $why', style: TS.muted(t, 12.5)),
        const SizedBox(height: 10),
        for (final it in alt.day.items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Expanded(child: Text(app.exerciseName(it.ex), style: TS.body(t), maxLines: 1, overflow: TextOverflow.ellipsis)),
              Text('${it.scheme} ${app.exercise(it.ex)?.repsLabel ?? 'rip'}', style: TS.muted(t)),
            ]),
          ),
        const SizedBox(height: 6),
        Text('${alt.day.items.length} esercizi · ${alt.day.totalSets} serie · tocca per i carichi', style: TS.muted(t, 12)),
      ]),
    );
  }
}
