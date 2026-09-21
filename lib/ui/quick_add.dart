import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/fmt.dart';
import '../core/ids.dart';
import '../core/theme.dart';
import '../data/app_state.dart';
import '../data/models.dart';
import 'add_hub.dart';
import 'widgets.dart';

/// "Solo calorie": un numero e via (macro facoltativi). Usata anche per modificare.
class QuickAddScreen extends StatefulWidget {
  final String date;
  final String meal;
  final LogEntry? editEntry;
  const QuickAddScreen({super.key, required this.date, required this.meal, this.editEntry});
  @override
  State<QuickAddScreen> createState() => _QuickAddScreenState();
}

class _QuickAddScreenState extends State<QuickAddScreen> {
  late final name = TextEditingController(text: widget.editEntry?.name ?? '');
  late final kcal = TextEditingController(text: _v(widget.editEntry?.kcal));
  late final p = TextEditingController(text: _v(widget.editEntry?.p));
  late final c = TextEditingController(text: _v(widget.editEntry?.c));
  late final f = TextEditingController(text: _v(widget.editEntry?.f));
  late String meal = widget.editEntry?.meal ?? widget.meal;

  static String _v(double? x) => x == null || x == 0 ? '' : fDec(x, 1, true).replaceAll('.', '');

  @override
  void dispose() {
    for (final x in [name, kcal, p, c, f]) {
      x.dispose();
    }
    super.dispose();
  }

  Widget _num(String label, TextEditingController ctl, {String suffix = 'g', bool autofocus = false, bool big = false}) => TextField(
        controller: ctl,
        autofocus: autofocus,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
        style: big ? TS.num(context.tt, 34) : null,
        decoration: InputDecoration(labelText: label, suffixText: suffix),
        onChanged: (_) => setState(() {}),
      );

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final k = parseNum(kcal.text) ?? 0;
    final edit = widget.editEntry != null;
    return SubPage(
      title: edit ? 'Modifica voce' : 'Solo calorie',
      bottom: BottomActions(children: [
        if (edit)
          GhostButton('Elimina', color: TC.danger, onTap: () {
            app.deleteEntry(widget.editEntry!.id);
            Navigator.pop(context);
          }),
        PrimaryButton(edit ? 'Salva' : 'Aggiungi a ${mealLabels[meal]!.toLowerCase()}', onTap: k <= 0
            ? null
            : () {
                final n = name.text.trim().isEmpty ? 'Calorie rapide' : name.text.trim();
                if (edit) {
                  app.updateEntry(widget.editEntry!.copyWith(name: n, kcal: k, p: parseNum(p.text) ?? 0, c: parseNum(c.text) ?? 0, f: parseNum(f.text) ?? 0, meal: meal));
                  Navigator.pop(context);
                  return;
                }
                final e = LogEntry(
                  id: newId(),
                  date: widget.date,
                  meal: meal,
                  name: n,
                  kcal: k,
                  p: parseNum(p.text) ?? 0,
                  c: parseNum(c.text) ?? 0,
                  f: parseNum(f.text) ?? 0,
                  refType: 'quick',
                  ts: DateTime.now().millisecondsSinceEpoch,
                );
                app.addEntry(e);
                Navigator.pop(context, e);
              }),
      ]),
      body: PageBody(children: [
        _num('Calorie', kcal, suffix: 'kcal', autofocus: !edit, big: true),
        const SizedBox(height: 12),
        TextField(controller: name, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Cosa hai mangiato? (facoltativo)')),
        const SectionLabel('Macro (facoltativi)'),
        Row(children: [
          Expanded(child: _num('Proteine', p)),
          const SizedBox(width: 8),
          Expanded(child: _num('Carbo', c)),
          const SizedBox(width: 8),
          Expanded(child: _num('Grassi', f)),
        ]),
        const SectionLabel('Pasto'),
        MealChips(selected: meal, onChanged: (v) => setState(() => meal = v)),
        const NoteBox(text: 'Utile al ristorante o quando conosci già il totale. Senza proteine il voto della nutrizione sarà più basso.'),
      ]),
    );
  }
}
