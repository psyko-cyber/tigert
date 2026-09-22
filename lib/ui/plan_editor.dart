import 'package:flutter/material.dart';

import '../core/fmt.dart';
import '../core/ids.dart';
import '../core/theme.dart';
import '../data/app_state.dart';
import '../data/models.dart';
import '../logic/volume.dart';
import 'exercise_picker.dart';
import 'plans.dart';
import 'reorder.dart';
import 'shell.dart';
import 'volume.dart';
import 'widgets.dart';

PlanItem defaultItemFor(Exercise? e, String id) => switch (e?.type) {
      'k' => PlanItem(ex: id, sets: 1, rMin: 20, rMax: 30, rpe: 7, rest: 0),
      'i' => PlanItem(ex: id, sets: 3, rMin: 10, rMax: 15, rpe: 9, rest: 90),
      'b' => PlanItem(ex: id, sets: 3, rMin: 8, rMax: 15, rpe: 9, rest: 90),
      _ => PlanItem(ex: id, sets: 3, rMin: 6, rMax: 10, rpe: 9, rest: 150),
    };

/// "1A + 3×8-10 rip · RPE 9 · 2'30" rec"
String itemSummary(PlanItem it, String repsLabel) =>
    '${it.warm > 0 ? '${it.warm}A + ' : ''}${it.scheme} $repsLabel · RPE ${fDec(it.rpe, 1, true)}${it.rest > 0 ? ' · ${_rest(it.rest)}' : ''}';

class PlanEditorScreen extends StatelessWidget {
  final String planId;
  const PlanEditorScreen({super.key, required this.planId});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final plan = app.plan(planId);
    if (plan == null) return const SubPage(title: 'Scheda', body: Center(child: Text('Scheda non trovata')));
    final isActive = app.activePlan?.id == plan.id;
    void save(Plan p) => app.savePlan(p);

    Future<void> onMenu(String v) async {
      switch (v) {
        case 'rename':
          final n = await askText(context, title: 'Nome della scheda', initial: plan.name);
          if (n != null && n.isNotEmpty) save(plan.copyWith(name: n));
        case 'dup':
          final copy = plan.duplicate(newId(), newId);
          app.savePlan(copy);
          if (context.mounted) {
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => PlanEditorScreen(planId: copy.id)));
            toast(context, 'Creata "${copy.name}"');
          }
        case 'order':
          final keys = await push<List<String>>(
            context,
            ReorderScreen(
              title: 'Riordina i giorni',
              allowRemove: false,
              entries: [
                for (final d in plan.days) ReorderEntry(d.id, d.name, plan.cycle > 1 ? 'Settimana ${weekLetter(d.week)}' : '${d.items.length} esercizi'),
              ],
            ),
          );
          if (keys != null) save(plan.copyWith(days: [for (final k in keys) plan.days.firstWhere((d) => d.id == k)]));
        case 'cycle':
          if (!context.mounted) return;
          final n = await showModalBottomSheet<int>(
            context: context,
            builder: (c) => SafeArea(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: Text(
                    'Con più settimane ogni giorno appartiene a una settimana (A, B...). Le sedute ruotano in ordine: '
                    'prima tutti i giorni della A, poi quelli della B, e si ricomincia. Se salti un allenamento non perdi la seduta.',
                    style: TS.soft(c.tt, 13),
                  ),
                ),
                for (final w in const [1, 2, 3, 4])
                  ListTile(
                    title: Text(w == 1 ? 'Una settimana (classica)' : '$w settimane · ${[for (var i = 1; i <= w; i++) weekLetter(i)].join(', ')}'),
                    trailing: plan.cycle == w ? Icon(Icons.check_rounded, color: c.tt.accentInk) : null,
                    onTap: () => Navigator.pop(c, w),
                  ),
              ]),
            ),
          );
          if (n != null && n != plan.cycle) save(plan.copyWith(cycle: n));
        case 'del':
          if (context.mounted && await deletePlansFlow(context, [plan.id]) && context.mounted) Navigator.pop(context);
      }
    }

    final byWeek = plan.cycle > 1;
    return SubPage(
      title: 'Modifica scheda',
      actions: [
        PopupMenuButton<String>(
          icon: Icon(Icons.more_vert_rounded, color: t.ink),
          onSelected: onMenu,
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'rename', child: Text('Rinomina')),
            const PopupMenuItem(value: 'dup', child: Text('Duplica scheda')),
            if (plan.days.length > 1) const PopupMenuItem(value: 'order', child: Text('Riordina i giorni')),
            PopupMenuItem(value: 'cycle', child: Text(plan.cycle > 1 ? 'Ciclo: ${plan.cycle} settimane' : 'Ciclo su più settimane')),
            const PopupMenuItem(value: 'del', child: Text('Elimina scheda', style: TextStyle(color: TC.danger))),
          ],
        ),
      ],
      bottom: BottomActions(children: [
        GhostButton('+ Giorno', onTap: () async {
          final n = await askText(context, title: 'Nome del giorno', hint: 'es. Push, Gambe, Full body C');
          if (n != null && n.isNotEmpty) save(plan.copyWith(days: [...plan.days, PlanDay(id: newId(), name: n, week: plan.cycle)]));
        }),
        if (!isActive) PrimaryButton('Usa questa scheda', onTap: () => app.savePlan(plan, activate: true)) else PrimaryButton('Fatto', onTap: () => Navigator.pop(context)),
      ]),
      body: PageBody(children: [
        Text(plan.name, style: TS.h1(t).copyWith(fontSize: 22)),
        Text(
          [
            isActive ? 'Scheda attiva · le sedute ruotano sui tuoi giorni di allenamento' : 'Scheda non attiva',
            if (byWeek) 'ciclo di ${plan.cycle} settimane',
          ].join(' · '),
          style: TS.muted(t),
        ),
        const SizedBox(height: 14),
        for (var di = 0; di < plan.days.length; di++) ...[
          if (byWeek && (di == 0 || plan.days[di - 1].week != plan.days[di].week)) SectionLabel('Settimana ${weekLetter(plan.days[di].week)}'),
          _DayCard(plan: plan, index: di, onSave: save),
          const SizedBox(height: 12),
        ],
        if (plan.days.isEmpty) const NoteBox(text: 'Aggiungi il primo giorno con "+ Giorno".'),
        if (byWeek)
          for (var w = 1; w <= plan.cycle; w++)
            if (!plan.days.any((d) => d.week == w))
              NoteBox(text: 'La settimana ${weekLetter(w)} è vuota: aggiungi un giorno o sposta qui un giorno esistente (menu ⋮ del giorno).'),
        if (plan.days.any((d) => d.items.isNotEmpty)) ...[
          const SectionLabel('Volume previsto a settimana'),
          MuscleVolumeTable(volumeOf: planVolume(app, plan)),
          VolumeTips(tips: volumeTips(planVolume(app, plan), planned: true)),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => push(context, VolumeScreen(planId: plan.id)),
              child: Text('Come si calcola →', style: TextStyle(color: t.accentInk, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ]),
    );
  }
}

class _DayCard extends StatelessWidget {
  final Plan plan;
  final int index;
  final ValueChanged<Plan> onSave;
  const _DayCard({required this.plan, required this.index, required this.onSave});

  void _setDay(PlanDay d) {
    final days = [...plan.days];
    days[index] = d;
    onSave(plan.copyWith(days: days));
  }

  void _openItem(BuildContext context, PlanDay day, int i) => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => _ItemSheet(
          item: day.items[i],
          onSave: (it) {
            final items = [...day.items];
            items[i] = it;
            _setDay(day.copyWith(items: items));
          },
          onDelete: () {
            final items = [...day.items]..removeAt(i);
            _setDay(day.copyWith(items: items));
          },
        ),
      );

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final day = plan.days[index];
    return TCard(
      padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(day.name, style: TS.title(t)),
              Text('${day.items.length} esercizi · ${day.totalSets} serie', style: TS.muted(t, 12)),
            ]),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded, color: t.dim),
            onSelected: (v) async {
              final days = [...plan.days];
              switch (v) {
                case 'rename':
                  final n = await askText(context, title: 'Nome del giorno', initial: day.name);
                  if (n != null && n.isNotEmpty) _setDay(day.copyWith(name: n));
                case 'dup':
                  days.insert(index + 1, PlanDay(id: newId(), name: '${day.name} (copia)', items: day.items, week: day.week));
                  onSave(plan.copyWith(days: days));
                case 'del':
                  if (context.mounted && await confirm(context, title: 'Eliminare ${day.name}?', body: 'Le sessioni già fatte restano nello storico.', ok: 'Elimina', danger: true)) {
                    days.removeAt(index);
                    onSave(plan.copyWith(days: days));
                  }
                default:
                  if (v.startsWith('w')) _setDay(day.copyWith(week: int.parse(v.substring(1))));
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'rename', child: Text('Rinomina')),
              const PopupMenuItem(value: 'dup', child: Text('Duplica')),
              if (plan.cycle > 1)
                for (var w = 1; w <= plan.cycle; w++)
                  if (w != day.week) PopupMenuItem(value: 'w$w', child: Text('Sposta nella settimana ${weekLetter(w)}')),
              const PopupMenuItem(value: 'del', child: Text('Elimina')),
            ],
          ),
        ]),
        const SizedBox(height: 6),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: day.items.length,
          onReorderItem: (from, to) {
            final items = [...day.items];
            items.insert(to, items.removeAt(from));
            _setDay(day.copyWith(items: items));
          },
          proxyDecorator: (child, _, _) => Material(color: t.surf2, elevation: 6, borderRadius: BorderRadius.circular(10), child: child),
          itemBuilder: (_, i) {
            final it = day.items[i];
            return Tap(
              key: ValueKey('${day.id}-$i-${it.ex}'),
              radius: 10,
              onTap: () => _openItem(context, day, i),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                child: Row(children: [
                  SizedBox(width: 18, child: Text('${i + 1}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: t.dim))),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(app.exerciseName(it.ex), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: t.ink)),
                      Text(itemSummary(it, app.exercise(it.ex)?.repsLabel ?? 'rip'), style: TS.muted(t, 12)),
                    ]),
                  ),
                  DragHandle(i),
                ]),
              ),
            );
          },
        ),
        TextButton.icon(
          onPressed: () async {
            final id = await push<String>(context, const ExercisePickerScreen());
            if (id == null) return;
            _setDay(day.copyWith(items: [...day.items, defaultItemFor(app.exercise(id), id)]));
          },
          icon: Icon(Icons.add_rounded, color: t.accentInk),
          label: Text('Aggiungi esercizio', style: TextStyle(color: t.accentInk, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }
}

String _rest(int s) => s % 60 == 0 ? '${s ~/ 60}\' rec' : '${s ~/ 60}\'${(s % 60).toString().padLeft(2, '0')}" rec';

class _ItemSheet extends StatefulWidget {
  final PlanItem item;
  final ValueChanged<PlanItem> onSave;
  final VoidCallback onDelete;
  const _ItemSheet({required this.item, required this.onSave, required this.onDelete});
  @override
  State<_ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends State<_ItemSheet> {
  late PlanItem it = widget.item;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final ex = app.exercise(it.ex);
    final unit = ex?.repsLabel ?? 'rip';
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(ex?.name ?? it.ex, style: TS.h2(t))),
            TextButton(
              onPressed: () async {
                final id = await push<String>(context, ExercisePickerScreen(initialMuscle: ex?.muscle));
                if (id != null) setState(() => it = it.copyWith(ex: id));
              },
              child: Text('Cambia', style: TextStyle(color: t.accentInk)),
            ),
          ]),
          Text('${ex?.muscle ?? ''} · ${ex?.equip ?? ''}', style: TS.muted(t)),
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const SectionLabel('Serie allenanti'),
                Stepper2(
                  value: '${it.sets}',
                  onMinus: () => setState(() => it = it.copyWith(sets: (it.sets - 1).clamp(1, 12))),
                  onPlus: () => setState(() => it = it.copyWith(sets: (it.sets + 1).clamp(1, 12))),
                ),
              ]),
            ),
            if (ex?.isCardio != true) ...[
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const SectionLabel('Avvicinamento'),
                  Stepper2(
                    value: it.warm == 0 ? 'no' : '${it.warm}',
                    onMinus: () => setState(() => it = it.copyWith(warm: (it.warm - 1).clamp(0, 5))),
                    onPlus: () => setState(() => it = it.copyWith(warm: (it.warm + 1).clamp(0, 5))),
                  ),
                ]),
              ),
            ],
          ]),
          SectionLabel('Range ${unit == 'rip' ? 'ripetizioni' : unit == 'min' ? 'minuti' : 'secondi'} (min - max)'),
          Row(children: [
            Expanded(
              child: Stepper2(
                value: '${it.rMin}',
                onMinus: () => setState(() => it = it.copyWith(rMin: (it.rMin - 1).clamp(1, it.rMax))),
                onPlus: () => setState(() => it = it.copyWith(rMin: (it.rMin + 1).clamp(1, it.rMax))),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Stepper2(
                value: '${it.rMax}',
                onMinus: () => setState(() => it = it.copyWith(rMax: (it.rMax - 1).clamp(it.rMin, 300))),
                onPlus: () => setState(() => it = it.copyWith(rMax: (it.rMax + 1).clamp(it.rMin, 300))),
              ),
            ),
          ]),
          const SectionLabel('RPE target'),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final r in [6.0, 7.0, 7.5, 8.0, 8.5, 9.0, 9.5, 10.0]) PillChip(fDec(r, 1, true), selected: it.rpe == r, onTap: () => setState(() => it = it.copyWith(rpe: r))),
          ]),
          const SectionLabel('Recupero'),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final s in [0, 45, 60, 90, 120, 150, 180, 240, 300])
              PillChip(s == 0 ? 'nessuno' : _rest(s).replaceAll(' rec', ''), selected: it.rest == s, onTap: () => setState(() => it = it.copyWith(rest: s))),
          ]),
          const SizedBox(height: 10),
          NoteBox(
            text: 'Doppia progressione: quando fai ${it.sets}×${it.rMax} a RPE ≤ ${fDec(it.rpe, 1, true)}, Tigert ti propone di salire di ${fKg(ex?.inc ?? 2.5)} kg e ripartire da ${it.rMin}.'
                '${it.warm > 0 ? ' Gli avvicinamenti (${it.warm}) si precompilano tra il 40% e l\'80% del carico e non contano nel volume.' : ''}',
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: GhostButton('Rimuovi', color: TC.danger, dense: true, onTap: () {
                widget.onDelete();
                Navigator.pop(context);
              }),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: PrimaryButton('Salva', dense: true, onTap: () {
                widget.onSave(it);
                Navigator.pop(context);
              }),
            ),
          ]),
        ]),
      ),
    );
  }
}
