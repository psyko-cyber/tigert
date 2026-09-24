import 'package:flutter/material.dart';

import '../core/fmt.dart';
import '../core/ids.dart';
import '../core/theme.dart';
import '../data/app_state.dart';
import '../data/models.dart';
import 'widgets.dart';

/// Libreria esercizi: ritorna l'id dell'esercizio scelto.
class ExercisePickerScreen extends StatefulWidget {
  final String? initialMuscle;
  const ExercisePickerScreen({super.key, this.initialMuscle});
  @override
  State<ExercisePickerScreen> createState() => _ExercisePickerScreenState();
}

class _ExercisePickerScreenState extends State<ExercisePickerScreen> {
  final ctl = TextEditingController();
  late String? muscle = widget.initialMuscle;
  String? kit; // filtro attrezzo (chiave di _kits)

  /// Filtri per attrezzo: il parchetto è corpo libero, anelli ed elastici.
  static const _kits = {
    'Corpo libero': {'Corpo libero', 'Anelli', 'Elastici', 'Elastico'},
    'Manubri': {'Manubri', 'Kettlebell'},
    'Bilanciere': {'Bilanciere'},
    'Macchine e cavi': {'Macchina', 'Cavi', 'Multipower'},
  };

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final app = context.appRead;
    final res = await showModalBottomSheet<Exercise>(context: context, isScrollControlled: true, builder: (_) => _NewExerciseSheet(initialName: ctl.text.trim(), muscle: muscle));
    if (res == null) return;
    app.saveExercise(res);
    if (mounted) Navigator.pop(context, res.id);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final q = fold(ctl.text.trim());
    final list = app.exercises.values.where((e) {
      if (muscle != null && e.muscle != muscle) return false;
      if (kit != null && !_kits[kit]!.contains(e.equip)) return false;
      if (q.isEmpty) return true;
      return fold('${e.name} ${e.muscle} ${e.equip}').contains(q);
    }).toList()
      ..sort((a, b) {
        final c = (b.custom ? 1 : 0).compareTo(a.custom ? 1 : 0);
        return c != 0 ? c : a.name.compareTo(b.name);
      });

    return SubPage(
      title: 'Esercizi',
      actions: [IconButton(tooltip: 'Crea esercizio', icon: const Icon(Icons.add_box_outlined), onPressed: _create)],
      body: Column(children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
              child: Column(children: [
                TextField(
                  controller: ctl,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(hintText: 'Cerca, es. panca, rematore, squat', prefixIcon: Icon(Icons.search_rounded)),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 36,
                  child: ListView(scrollDirection: Axis.horizontal, children: [
                    PillChip('Tutti', selected: muscle == null, onTap: () => setState(() => muscle = null)),
                    for (final m in muscleGroups) ...[const SizedBox(width: 6), PillChip(m, selected: muscle == m, onTap: () => setState(() => muscle = m))],
                  ]),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 36,
                  child: ListView(scrollDirection: Axis.horizontal, children: [
                    PillChip('Ogni attrezzo', selected: kit == null, onTap: () => setState(() => kit = null)),
                    for (final k in _kits.keys) ...[
                      const SizedBox(width: 6),
                      PillChip(k, icon: k == 'Corpo libero' ? Icons.park_rounded : null, selected: kit == k, onTap: () => setState(() => kit = k)),
                    ],
                  ]),
                ),
              ]),
            ),
          ),
        ),
        Expanded(
          child: PageBody(padding: const EdgeInsets.fromLTRB(18, 4, 18, 28), children: [
            for (final e in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: RowTile(
                  title: e.name,
                  subtitle: '${e.muscle} · ${e.equip}${e.custom ? ' · creato da te' : ''}',
                  onTap: () => Navigator.pop(context, e.id),
                ),
              ),
            if (list.isEmpty) Text('Nessun esercizio trovato.', style: TS.muted(t)),
            const SizedBox(height: 8),
            GhostButton('Crea un nuovo esercizio', icon: Icons.add_rounded, onTap: _create),
          ]),
        ),
      ]),
    );
  }
}

class _NewExerciseSheet extends StatefulWidget {
  final String initialName;
  final String? muscle;
  const _NewExerciseSheet({required this.initialName, this.muscle});
  @override
  State<_NewExerciseSheet> createState() => _NewExerciseSheetState();
}

class _NewExerciseSheetState extends State<_NewExerciseSheet> {
  late final name = TextEditingController(text: widget.initialName);
  late String muscle = widget.muscle ?? 'Petto';
  String equip = 'Manubri';
  String type = 'c';

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Nuovo esercizio', style: TS.h2(t)),
          const SizedBox(height: 12),
          TextField(controller: name, autofocus: true, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Nome')),
          const SectionLabel('Muscolo principale'),
          Wrap(spacing: 6, runSpacing: 6, children: [for (final m in muscleGroups) PillChip(m, selected: muscle == m, onTap: () => setState(() => muscle = m))]),
          const SectionLabel('Attrezzo'),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final e in ['Bilanciere', 'Manubri', 'Macchina', 'Cavi', 'Multipower', 'Corpo libero', 'Anelli', 'Kettlebell', 'Elastici'])
              PillChip(e, selected: equip == e, onTap: () => setState(() => equip = e)),
          ]),
          const SectionLabel('Tipo'),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final (k, l) in const [('c', 'Multiarticolare'), ('i', 'Isolamento'), ('b', 'Corpo libero'), ('k', 'Cardio (minuti)')])
              PillChip(l, selected: type == k, onTap: () => setState(() => type = k)),
          ]),
          const SizedBox(height: 18),
          PrimaryButton('Crea esercizio', onTap: () {
            if (name.text.trim().isEmpty) return;
            Navigator.pop(
              context,
              Exercise(
                id: 'x:${newId()}',
                name: name.text.trim(),
                muscle: muscle,
                equip: equip,
                type: type,
                inc: type == 'k' ? 0 : (equip == 'Manubri' ? 2 : 2.5),
                custom: true,
              ),
            );
          }),
        ]),
      ),
    );
  }
}
