import 'package:flutter/material.dart';

import '../core/fmt.dart';
import '../core/ids.dart';
import '../core/theme.dart';
import '../data/app_state.dart';
import '../data/models.dart';
import 'exercise_picker.dart';
import 'shell.dart';
import 'widgets.dart';

PlanItem defaultItemFor(Exercise? e, String id) => switch (e?.type) {
      'k' => PlanItem(ex: id, sets: 1, rMin: 20, rMax: 30, rpe: 7, rest: 0),
      'i' => PlanItem(ex: id, sets: 3, rMin: 10, rMax: 15, rpe: 9, rest: 90),
      'b' => PlanItem(ex: id, sets: 3, rMin: 8, rMax: 15, rpe: 9, rest: 90),
      _ => PlanItem(ex: id, sets: 3, rMin: 6, rMax: 10, rpe: 9, rest: 150),
    };

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

    return SubPage(
      title: 'Modifica scheda',
      actions: [
        IconButton(
          tooltip: 'Rinomina',
          icon: const Icon(Icons.drive_file_rename_outline_rounded),
          onPressed: () async {
            final n = await askText(context, title: 'Nome della scheda', initial: plan.name);
            if (n != null && n.isNotEmpty) save(plan.copyWith(name: n));
          },
        ),
      ],
      bottom: BottomActions(children: [
        GhostButton('+ Giorno', onTap: () async {
          final n = await askText(context, title: 'Nome del giorno', hint: 'es. Push, Gambe, Full body C');
          if (n != null && n.isNotEmpty) save(plan.copyWith(days: [...plan.days, PlanDay(id: newId(), name: n)]));
        }),
        if (!isActive) PrimaryButton('Usa questa scheda', onTap: () => app.savePlan(plan, activate: true)) else PrimaryButton('Fatto', onTap: () => Navigator.pop(context)),
      ]),
      body: PageBody(children: [
        Text(plan.name, style: TS.h1(t).copyWith(fontSize: 22)),
        Text(isActive ? 'Scheda attiva · le sedute ruotano sui tuoi giorni di allenamento' : 'Scheda non attiva', style: TS.muted(t)),
        const SizedBox(height: 14),
        for (var di = 0; di < plan.days.length; di++) ...[
          _DayCard(plan: plan, index: di, onSave: save),
          const SizedBox(height: 12),
        ],
        if (plan.days.isEmpty) const NoteBox(text: 'Aggiungi il primo giorno con "+ Giorno".'),
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

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final day = plan.days[index];
    return TCard(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
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
                case 'up':
                  if (index > 0) {
                    days.insert(index - 1, days.removeAt(index));
                    onSave(plan.copyWith(days: days));
                  }
                case 'down':
                  if (index < days.length - 1) {
                    days.insert(index + 1, days.removeAt(index));
                    onSave(plan.copyWith(days: days));
                  }
                case 'dup':
                  days.insert(index + 1, PlanDay(id: newId(), name: '${day.name} (copia)', items: day.items));
                  onSave(plan.copyWith(days: days));
                case 'del':
                  if (context.mounted && await confirm(context, title: 'Eliminare ${day.name}?', body: 'Le sessioni già fatte restano nello storico.', ok: 'Elimina', danger: true)) {
                    days.removeAt(index);
                    onSave(plan.copyWith(days: days));
                  }
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('Rinomina')),
              PopupMenuItem(value: 'up', child: Text('Sposta su')),
              PopupMenuItem(value: 'down', child: Text('Sposta giù')),
              PopupMenuItem(value: 'dup', child: Text('Duplica')),
              PopupMenuItem(value: 'del', child: Text('Elimina')),
            ],
          ),
        ]),
        const SizedBox(height: 6),
        for (var i = 0; i < day.items.length; i++)
          Tap(
            radius: 10,
            onTap: () => showModalBottomSheet(
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
                onMove: (dir) {
                  final items = [...day.items];
                  final j = (i + dir).clamp(0, items.length - 1);
                  items.insert(j, items.removeAt(i));
                  _setDay(day.copyWith(items: items));
                },
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
              child: Row(children: [
                Text('${i + 1}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: t.dim)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(app.exerciseName(day.items[i].ex), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: t.ink)),
                    Text(
                      '${day.items[i].scheme} ${app.exercise(day.items[i].ex)?.repsLabel ?? 'rip'} · RPE ${fDec(day.items[i].rpe, 1, true)}${day.items[i].rest > 0 ? ' · ${_rest(day.items[i].rest)}' : ''}',
                      style: TS.muted(t, 12),
                    ),
                  ]),
                ),
                Icon(Icons.tune_rounded, size: 18, color: t.dim),
                const SizedBox(width: 8),
              ]),
            ),
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
  final ValueChanged<int> onMove;
  const _ItemSheet({required this.item, required this.onSave, required this.onDelete, required this.onMove});
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
          const SectionLabel('Serie'),
          Stepper2(
            value: '${it.sets}',
            onMinus: () => setState(() => it = it.copyWith(sets: (it.sets - 1).clamp(1, 12))),
            onPlus: () => setState(() => it = it.copyWith(sets: (it.sets + 1).clamp(1, 12))),
          ),
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
          NoteBox(text: 'Doppia progressione: quando fai ${it.sets}×${it.rMax} a RPE ≤ ${fDec(it.rpe, 1, true)}, Tigert ti propone di salire di ${fKg(ex?.inc ?? 2.5)} kg e ripartire da ${it.rMin}.'),
          const SizedBox(height: 16),
          Row(children: [
            IconButton(tooltip: 'Sposta su', onPressed: () {
              widget.onMove(-1);
              Navigator.pop(context);
            }, icon: const Icon(Icons.arrow_upward_rounded)),
            IconButton(tooltip: 'Sposta giù', onPressed: () {
              widget.onMove(1);
              Navigator.pop(context);
            }, icon: const Icon(Icons.arrow_downward_rounded)),
            const SizedBox(width: 6),
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
