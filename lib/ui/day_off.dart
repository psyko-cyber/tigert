import 'package:flutter/material.dart';

import '../core/fmt.dart';
import '../core/theme.dart';
import '../data/app_state.dart';
import '../data/models.dart';
import '../logic/day_off.dart';
import '../logic/training.dart';
import 'training.dart';
import 'widgets.dart';

/// "Non riesci a fare la seduta?": motivo, quando la fai (o se la salti) e zone
/// da evitare. Il giorno diventa giustificato (il voto non peggiora); la seduta
/// si sposta al giorno scelto oppure esce dal giro.
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
  // giorno in cui fare la seduta (null = la salto)
  late String? moveTo = slot.off?.moveTo;
  late bool whenTouched = slot.off != null;

  /// Giorni in cui spostarla: dal giorno dopo (o da oggi, per i giorni passati) per una settimana.
  List<DateTime> get options {
    final t = today();
    final next = slot.date.add(const Duration(days: 1));
    final from = next.isBefore(t) ? t : next;
    return [for (var i = 0; i < 7; i++) dateOnly(from.add(Duration(days: i)))];
  }

  void _reason(String k) => setState(() {
        reason = k;
        if (!whenTouched) moveTo = k == 'impegno' ? dayKey(options.first) : null;
      });

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final plan = app.activePlan;
    final name = day?.name ?? 'la seduta';
    final i = plan == null || day == null ? -1 : plan.days.indexWhere((d) => d.id == day!.id);
    final next = i < 0 ? null : plan!.days[(i + 1) % plan.days.length];
    final target = moveTo == null ? null : fromKey(moveTo!);
    final pain = reason == 'dolore' && !past && target == null;
    final targetTrains = target != null && (app.profile?.trainingDays.contains(target.weekday) ?? false);
    final advice = target == null || day == null ? null : moveAdvice(app, day!, target, from: dayKey(slot.date), options: options);
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(slot.off != null ? 'Giorno giustificato' : (past ? 'Giustifica $name' : 'Non riesci a fare $name?'), style: TS.h1(t).copyWith(fontSize: 22)),
          Text(longDate(slot.date), style: TS.muted(t)),
          const SectionLabel('Motivo'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final MapEntry(key: k, value: l) in offReasons.entries) PillChip(l, selected: reason == k, onTap: () => _reason(k)),
          ]),
          const SectionLabel('Quando la fai?'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            PillChip('La salto', selected: moveTo == null, onTap: () => setState(() {
                  moveTo = null;
                  whenTouched = true;
                })),
            for (final d in options)
              PillChip(_chip(app, d), selected: moveTo == dayKey(d), onTap: () => setState(() {
                    moveTo = dayKey(d);
                    whenTouched = true;
                  })),
          ]),
          if (advice != null)
            NoteBox(
              icon: Icons.tips_and_updates_outlined,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  advice.better == null
                      ? moveAdviceText(advice, name, target!)
                      : '${sameMusclesText(advice, name, target!)} Ti conviene ${whenLabel(advice.better!, long: true)}: '
                          'il giorno prima e quello dopo non alleni gli stessi muscoli.',
                  style: TS.body(t),
                ),
                if (advice.better != null) ...[
                  const SizedBox(height: 10),
                  SmallButton('Scegli ${whenLabel(advice.better!, long: true)}', accent: true, onTap: () => setState(() => moveTo = dayKey(advice.better!))),
                ],
              ]),
            ),
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
              if (target != null) ...[
                '$name si sposta a ${whenLabel(target, long: true)}.',
                targetTrains ? 'Le sedute dopo slittano di un giorno di allenamento.' : 'Quel giorno diventa di allenamento, solo per questa volta.',
              ] else if (next != null && next.id != day?.id)
                '$name esce dal giro: la prossima seduta sarà ${next.name}.',
              if (pain && zones.isNotEmpty) 'Ti preparo una seduta senza ${joinIt(zones.map((z) => z.toLowerCase()).toList())}, con i muscoli che hai allenato meno questa settimana.',
            ].join(' '),
          ),
          const SizedBox(height: 16),
          PrimaryButton(target != null ? 'Sposta a ${whenLabel(target, long: true)}' : (slot.off != null ? 'Salva' : 'Conferma'), onTap: () {
            app.setDayOff(
              dayKey(slot.date),
              reason,
              dayId: day?.id,
              avoid: pain ? [for (final z in bodyZones.keys) if (zones.contains(z)) z] : const [],
              moveTo: moveTo,
            );
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

/// Chip del giorno, con la seduta già in programma quel giorno.
String _chip(AppState app, DateTime d) {
  final planned = slotOn(app, d)?.day?.name;
  if (planned == null) return whenLabel(d);
  return '${whenLabel(d)} · ${planned.length > 14 ? '${planned.substring(0, 13)}…' : planned}';
}

/// "Full upper giovedì e Gambe & Core venerdì allenano entrambe Petto e Spalle."
String sameMusclesText(MoveAdvice a, String name, DateTime target) =>
    '$name ${whenLabel(target, long: true)} e ${a.neighborName} ${whenLabel(a.neighbor, long: true)} allenano entrambe '
    '${joinIt(a.muscles.map((m) => m.toLowerCase()).toList())}.';

/// Consiglio senza cambiare la scheda: alleggerire la seconda delle due sedute.
String moveAdviceText(MoveAdvice a, String name, DateTime target) {
  final later = a.neighbor.isAfter(target) ? a.neighbor : target;
  return '${sameMusclesText(a, name, target)} Senza cambiare la scheda: ${whenLabel(later, long: true)} fai 1-2 serie in meno di '
      '${joinIt(a.muscles.map((m) => m.toLowerCase()).toList())}, o tienile a RPE più basso.';
}

/// "Domani", "Ven 26" ([long]: "domani", "venerdì 26").
String whenLabel(DateTime d, {bool long = false}) {
  final diff = daysBetween(today(), d);
  if (diff == 0) return long ? 'oggi' : 'Oggi';
  if (diff == 1) return long ? 'domani' : 'Domani';
  return long ? '${giorni[d.weekday - 1].toLowerCase()} ${d.day}' : '${giorniBrevi[d.weekday - 1]} ${d.day}';
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
