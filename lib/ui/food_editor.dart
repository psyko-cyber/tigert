import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/fmt.dart';
import '../core/ids.dart';
import '../core/theme.dart';
import '../data/app_state.dart';
import '../data/models.dart';
import 'widgets.dart';

/// Crea o modifica un alimento (valori per 100 g, come in etichetta).
class FoodEditorScreen extends StatefulWidget {
  final Food? food;
  final bool copy;
  final String? ean;
  final String? initialName;
  const FoodEditorScreen({super.key, this.food, this.copy = false, this.ean, this.initialName});
  @override
  State<FoodEditorScreen> createState() => _FoodEditorScreenState();
}

class _FoodEditorScreenState extends State<FoodEditorScreen> {
  late final name = TextEditingController(text: widget.food?.name ?? widget.initialName ?? '');
  late final brand = TextEditingController(text: widget.food?.brand ?? '');
  late final ean = TextEditingController(text: widget.food?.ean ?? widget.ean ?? '');
  late final kcal = TextEditingController(text: _v(widget.food?.kcal));
  late final p = TextEditingController(text: _v(widget.food?.p));
  late final c = TextEditingController(text: _v(widget.food?.c));
  late final f = TextEditingController(text: _v(widget.food?.f));
  late final fiber = TextEditingController(text: _v(widget.food?.fiber));
  late final portionLabel = TextEditingController(text: widget.food?.portions.isNotEmpty == true ? widget.food!.portions.first.label : '');
  late final portionG = TextEditingController(text: widget.food?.portions.isNotEmpty == true ? _v(widget.food!.portions.first.g) : '');
  late bool ml = widget.food?.ml ?? isLiquidFood(widget.initialName ?? '', '');
  String? error;

  static String _v(double? x) => x == null || x == 0 ? '' : fDec(x, 1, true).replaceAll('.', '');

  @override
  void dispose() {
    for (final x in [name, brand, ean, kcal, p, c, f, fiber, portionLabel, portionG]) {
      x.dispose();
    }
    super.dispose();
  }

  double get _computed => (parseNum(p.text) ?? 0) * 4 + (parseNum(c.text) ?? 0) * 4 + (parseNum(f.text) ?? 0) * 9;

  void _save() {
    final app = context.appRead;
    final n = name.text.trim();
    if (n.isEmpty) return setState(() => error = 'Dai un nome all\'alimento.');
    final k = parseNum(kcal.text) ?? _computed;
    if (k <= 0 && (parseNum(p.text) ?? 0) + (parseNum(c.text) ?? 0) + (parseNum(f.text) ?? 0) <= 0) {
      return setState(() => error = 'Inserisci almeno le calorie per 100 ${ml ? 'ml' : 'g'}.');
    }
    final pg = parseNum(portionG.text);
    final editing = widget.food != null && !widget.copy && !widget.food!.isSeed;
    final food = Food(
      id: editing ? widget.food!.id : 'u:${newId()}',
      name: n,
      brand: brand.text.trim().isEmpty ? null : brand.text.trim(),
      ean: ean.text.trim().isEmpty ? null : ean.text.trim(),
      cat: widget.food?.cat.isNotEmpty == true ? widget.food!.cat : (ean.text.trim().isNotEmpty ? 'Prodotti' : 'I miei alimenti'),
      kcal: k,
      p: parseNum(p.text) ?? 0,
      c: parseNum(c.text) ?? 0,
      f: parseNum(f.text) ?? 0,
      fiber: parseNum(fiber.text) ?? 0,
      portions: pg != null && pg > 0 ? [Portion(portionLabel.text.trim().isEmpty ? 'porzione' : portionLabel.text.trim(), pg)] : const [],
      src: editing ? widget.food!.src : 'user',
      ml: ml,
    );
    app.saveFood(food);
    Navigator.pop(context, food);
  }

  Widget _num(String label, TextEditingController ctl, {String suffix = 'g'}) => TextField(
        controller: ctl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
        decoration: InputDecoration(labelText: label, suffixText: suffix),
        onChanged: (_) => setState(() {}),
      );

  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    final app = context.app;
    final canDelete = widget.food != null && !widget.food!.isSeed && !widget.copy;
    return SubPage(
      title: widget.food == null ? 'Nuovo alimento' : (widget.copy ? 'Copia alimento' : 'Modifica alimento'),
      bottom: BottomActions(children: [
        if (canDelete)
          GhostButton('Elimina', color: TC.danger, onTap: () async {
            if (await confirm(context, title: 'Eliminare l\'alimento?', body: 'Le voci già nel diario restano.', ok: 'Elimina', danger: true)) {
              app.deleteFood(widget.food!.id);
              if (context.mounted) Navigator.pop(context);
            }
          }),
        PrimaryButton('Salva alimento', onTap: _save),
      ]),
      body: PageBody(children: [
        if (widget.copy) const NoteBox(margin: EdgeInsets.only(bottom: 12), text: 'Gli alimenti di base non si modificano: salvo una tua copia con i valori corretti.'),
        TextField(controller: name, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Nome')),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: TextField(controller: brand, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Marca (facoltativa)'))),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: ean,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Codice EAN'),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Liquido', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              Text('Quantità in ml invece che in grammi', style: TS.muted(t, 12)),
            ]),
          ),
          Switch(value: ml, onChanged: (v) => setState(() => ml = v)),
        ]),
        SectionLabel('Valori per 100 ${ml ? 'ml' : 'g'} (dall\'etichetta)'),
        _num('Energia', kcal, suffix: 'kcal'),
        if (kcal.text.isEmpty && _computed > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text('Calcolate dai macro: ${fInt(_computed)} kcal', style: TS.muted(t, 12)),
          ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _num('Proteine', p)),
          const SizedBox(width: 10),
          Expanded(child: _num('Carboidrati', c)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _num('Grassi', f)),
          const SizedBox(width: 10),
          Expanded(child: _num('Fibre', fiber)),
        ]),
        const SectionLabel('Porzione tipica (facoltativa)'),
        Row(children: [
          Expanded(flex: 3, child: TextField(controller: portionLabel, decoration: const InputDecoration(labelText: 'Nome', hintText: 'es. vasetto'))),
          const SizedBox(width: 10),
          Expanded(flex: 2, child: _num(ml ? 'Volume' : 'Peso', portionG, suffix: ml ? 'ml' : 'g')),
        ]),
        if (error != null) NoteBox(icon: Icons.error_outline_rounded, text: error),
      ]),
    );
  }
}
