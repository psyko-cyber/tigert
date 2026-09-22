import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/fmt.dart';
import '../core/theme.dart';
import '../data/app_state.dart';
import '../data/models.dart';
import 'add_hub.dart';
import 'food_editor.dart';
import 'shell.dart';
import 'widgets.dart';

/// Scheda alimento: quantità, valori calcolati, pasto. Usata anche per
/// modificare una voce del diario ([editEntry]) o per scegliere i grammi
/// in una ricetta ([pickMode], ritorna i grammi).
class FoodAmountScreen extends StatefulWidget {
  final Food food;
  final String date;
  final String meal;
  final double? initialG;
  final bool pickMode;
  final LogEntry? editEntry;
  final bool productStyle; // stile "scheda prodotto" per il barcode
  const FoodAmountScreen({
    super.key,
    required this.food,
    required this.date,
    required this.meal,
    this.initialG,
    this.pickMode = false,
    this.editEntry,
    this.productStyle = false,
  });
  @override
  State<FoodAmountScreen> createState() => _FoodAmountScreenState();
}

class _FoodAmountScreenState extends State<FoodAmountScreen> {
  late double g = widget.editEntry?.g ?? widget.initialG ?? (widget.food.portions.isNotEmpty ? widget.food.portions.first.g : 100);
  late String meal = widget.editEntry?.meal ?? widget.meal;
  late Food food = widget.food;
  // condimento, formaggio e cottura: quelli della voce o dell'ultima volta
  late FoodOpts opts = widget.pickMode ? FoodOpts.none : (widget.editEntry?.opts ?? context.appRead.lastOpts(widget.food.id));

  void _set(double v) => setState(() => g = v.clamp(0, 5000).toDouble());

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final o = food.cleanOpts(opts);
    final m = food.macroFor(g, o);
    final oil = food.oilFor(g, o.cook);
    final extra = food.extraPart;
    final fav = app.favorites.contains(food.id);
    final step = widget.productStyle ? 25.0 : 10.0;
    final u = food.unit;
    final chips = <(String, double)>[
      for (final p in food.portions) ('${p.label} · ${fG(p.g)} $u', p.g),
      for (final v in (food.ml ? [100.0, 200.0, 250.0, 330.0, 500.0] : [50.0, 100.0, 150.0, 200.0]))
        if (!food.portions.any((p) => p.g == v)) ('${fG(v)} $u', v),
    ];
    final edit = widget.editEntry != null;
    final qtyTitle = food.base != null ? 'Peso ${food.base}' : (food.cook ? 'Peso da crudo' : 'Quantità');

    return SubPage(
      title: food.name,
      actions: [
        IconButton(
          tooltip: fav ? 'Togli dai preferiti' : 'Aggiungi ai preferiti',
          icon: Icon(fav ? Icons.star_rounded : Icons.star_border_rounded, color: fav ? TC.accent : null),
          onPressed: () => app.toggleFav(food.id),
        ),
        IconButton(
          tooltip: food.isSeed ? 'Crea una copia modificabile' : 'Modifica alimento',
          icon: const Icon(Icons.edit_outlined),
          onPressed: () async {
            final f = await push<Food>(context, FoodEditorScreen(food: food, copy: food.isSeed));
            if (f != null && mounted) setState(() => food = f);
          },
        ),
      ],
      bottom: BottomActions(children: [
        if (edit)
          GhostButton('Elimina', color: TC.danger, onTap: () {
            app.deleteEntry(widget.editEntry!.id);
            Navigator.pop(context);
          }),
        PrimaryButton(
          widget.pickMode ? 'Usa ${fG(g)} $u' : (edit ? 'Salva' : 'Aggiungi a ${mealLabels[meal]!.toLowerCase()}'),
          onTap: g <= 0
              ? null
              : () {
                  if (widget.pickMode) {
                    Navigator.pop(context, g);
                    return;
                  }
                  if (edit) {
                    final e = widget.editEntry!;
                    app.updateEntry(e.copyWith(g: g, meal: meal, kcal: m.kcal, p: m.p, c: m.c, f: m.f, name: food.displayName, opts: o));
                    Navigator.pop(context);
                    return;
                  }
                  final e = app.entryFromFood(food, g, date: widget.date, meal: meal, opts: o);
                  app.addEntry(e);
                  Navigator.pop(context, e);
                },
        ),
      ]),
      body: PageBody(children: [
        if (food.brand != null || food.ean != null)
          Text([if (food.brand != null) food.brand!, if (food.ean != null) 'EAN ${food.ean}'].join(' · '), style: TS.muted(t, 12)),
        if (widget.productStyle) ...[
          const SizedBox(height: 12),
          TCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Label('Per 100 $u'),
              const SizedBox(height: 10),
              Row(children: [
                _Tile('KCAL', fInt(food.kcal), t.dim),
                const SizedBox(width: 8),
                _Tile('P', '${fDec(food.p, 1, true)} g', TC.prot),
                const SizedBox(width: 8),
                _Tile('C', '${fDec(food.c, 1, true)} g', TC.carb),
                const SizedBox(width: 8),
                _Tile('G', '${fDec(food.f, 1, true)} g', TC.fat),
              ]),
            ]),
          ),
        ],
        const SizedBox(height: 12),
        TCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Label(widget.productStyle ? 'Porzione' : qtyTitle),
            const SizedBox(height: 6),
            Tap(
              radius: 8,
              onTap: () async {
                final v = await askNumber(context, title: qtyTitle, initial: g, unit: u, decimals: 0, max: 5000);
                if (v != null) _set(v);
              },
              child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                Text(fG(g), style: TS.num(t, 44)),
                const SizedBox(width: 6),
                Text(u, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: t.dim)),
                const SizedBox(width: 8),
                Icon(Icons.edit_rounded, size: 16, color: t.dim),
              ]),
            ),
            if (widget.productStyle) ...[
              const SizedBox(height: 6),
              Slider(
                value: g.clamp(0, math.max(500.0, (food.portions.isEmpty ? 100.0 : food.portions.first.g) * 3)).toDouble(),
                min: 0,
                max: math.max(500.0, (food.portions.isEmpty ? 100.0 : food.portions.first.g) * 3),
                divisions: 100,
                onChanged: (v) => _set((v / 5).round() * 5.0),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (l, v) in chips) PillChip(l, selected: g == v, onTap: () => _set(v)),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: SmallButton('−${fG(step)}', onTap: () => _set(g - step))),
              const SizedBox(width: 10),
              Expanded(child: SmallButton('+${fG(step)}', onTap: () => _set(g + step))),
            ]),
          ]),
        ),
        if (!widget.pickMode && food.isDish) ...[
          const SizedBox(height: 12),
          TCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Label('Condimento'),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final (k, l) in sauceLevels) PillChip(l, selected: o.sauce == k, onTap: () => setState(() => opts = FoodOpts(sauce: k, extra: o.extra, cook: o.cook))),
              ]),
              if (extra != null) ...[
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Con ${extra.name.toLowerCase()}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      Text('+${fG(g * extra.r)} g', style: TS.muted(t, 12)),
                    ]),
                  ),
                  Switch(value: o.extra, onChanged: (v) => setState(() => opts = FoodOpts(sauce: o.sauce, extra: v, cook: o.cook))),
                ]),
              ],
            ]),
          ),
        ],
        if (!widget.pickMode && food.cook) ...[
          const SizedBox(height: 12),
          TCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Label('Cottura'),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final MapEntry(key: k, value: l) in cookLabels.entries)
                  PillChip(l, selected: o.cook == k, onTap: () => setState(() => opts = FoodOpts(sauce: o.sauce, extra: o.extra, cook: k))),
              ]),
              const SizedBox(height: 8),
              Text(oil > 0 ? '+${fG(oil)} g di olio stimato (${fInt(oil * 8.99)} kcal)' : 'Crudo, lesso, alla griglia o al forno senza olio', style: TS.muted(t, 12.5)),
            ]),
          ),
        ],
        const SizedBox(height: 12),
        TCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (food.isDish)
              Text('Calcolato su ${fG(g)} g di ${food.base} + condimento', style: TS.muted(t))
            else
              Row(children: [
                Expanded(child: Text('Calcolato su ${fG(g)} $u', style: TS.muted(t))),
                Text('${fInt(food.kcal)} kcal / 100 $u', style: TS.muted(t, 12)),
              ]),
            const SizedBox(height: 2),
            BigNumber(fInt(m.kcal), unit: 'kcal', size: 38),
            const SizedBox(height: 12),
            Row(children: [
              _Tile('P', '${fDec(m.p, 1)} g', TC.prot),
              const SizedBox(width: 10),
              _Tile('C', '${fDec(m.c, 1)} g', TC.carb),
              const SizedBox(width: 10),
              _Tile('G', '${fDec(m.f, 1)} g', TC.fat),
            ]),
            if (food.isDish) ...[
              const SizedBox(height: 12),
              for (final (x, gg) in food.partsFor(g, o))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    Expanded(child: Text(x.name, style: TS.body(t), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    Text('${fG(gg)} g · ${fInt(x.per(gg).kcal)} kcal', style: TS.muted(t)),
                  ]),
                ),
            ],
          ]),
        ),
        if (food.isDish && !widget.pickMode)
          const NoteBox(text: 'Inserisci il peso da crudo: il condimento è stimato in proporzione e lo regoli con Poco, Normale o Tanto.'),
        if (!widget.pickMode) ...[
          const SectionLabel('Pasto'),
          MealChips(selected: meal, onChanged: (v) => setState(() => meal = v)),
        ],
        if (food.src == 'off')
          const NoteBox(text: 'Dati da Open Food Facts (licenza ODbL), salvati sul dispositivo: la prossima volta funziona anche offline.'),
      ]),
    );
  }
}

class _Tile extends StatelessWidget {
  final String k;
  final String v;
  final Color color;
  const _Tile(this.k, this.v, this.color);
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: t.surf2, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(k, style: TextStyle(fontSize: 10.5, letterSpacing: 1.1, fontWeight: FontWeight.w700, color: color)),
          const SizedBox(height: 4),
          Text(v, style: TS.num(t, 17, w: FontWeight.w700)),
        ]),
      ),
    );
  }
}
