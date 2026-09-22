import 'package:flutter/material.dart';

import '../core/fmt.dart';
import '../core/ids.dart';
import '../core/theme.dart';
import '../data/app_state.dart';
import '../data/models.dart';
import 'add_hub.dart';
import 'food_search.dart';
import 'shell.dart';
import 'widgets.dart';

class RecipesScreen extends StatelessWidget {
  final String date;
  final String meal;
  const RecipesScreen({super.key, required this.date, required this.meal});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final list = app.recipes;
    return SubPage(
      title: 'Le mie ricette',
      bottom: BottomActions(children: [
        PrimaryButton('Nuova ricetta', icon: Icons.add_rounded, onTap: () async {
          final e = await push<LogEntry>(context, RecipeEditorScreen(date: date, meal: meal));
          if (e != null && context.mounted) Navigator.pop(context, e);
        }),
      ]),
      body: PageBody(children: [
        if (list.isEmpty)
          const EmptyState(
            emoji: '🍲',
            title: 'Nessuna ricetta',
            body: 'Salva una volta i piatti che cucini spesso: poi li aggiungi con un tap, anche a mezza porzione.',
          ),
        for (final r in list)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: RowTile(
              leading: const FoodBadge('Ricette'),
              title: r.name,
              subtitle: '${r.items.length} ingredienti · ${fInt(r.perServing.kcal)} kcal a porzione${r.servings != 1 ? ' · ${fDec(r.servings, 1, true)} porzioni' : ''}',
              onTap: () async {
                final e = await push<LogEntry>(context, RecipeAddScreen(recipe: r, date: date, meal: meal));
                if (e != null && context.mounted) Navigator.pop(context, e);
              },
              trailing: IconButton(
                icon: const Icon(Icons.edit_outlined, size: 20),
                onPressed: () => push(context, RecipeEditorScreen(recipe: r, date: date, meal: meal)),
              ),
            ),
          ),
      ]),
    );
  }
}

class RecipeEditorScreen extends StatefulWidget {
  final Recipe? recipe;
  final String date;
  final String meal;
  const RecipeEditorScreen({super.key, this.recipe, required this.date, required this.meal});
  @override
  State<RecipeEditorScreen> createState() => _RecipeEditorScreenState();
}

class _RecipeEditorScreenState extends State<RecipeEditorScreen> {
  late final name = TextEditingController(text: widget.recipe?.name ?? '');
  late double servings = widget.recipe?.servings ?? 1;
  late List<RecipeItem> items = [...?widget.recipe?.items];
  String? error;

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Recipe _build() => Recipe(id: widget.recipe?.id ?? newId(), name: name.text.trim(), servings: servings, items: items);

  bool _validate() {
    if (name.text.trim().isEmpty) {
      setState(() => error = 'Dai un nome alla ricetta.');
      return false;
    }
    if (items.isEmpty) {
      setState(() => error = 'Aggiungi almeno un ingrediente.');
      return false;
    }
    return true;
  }

  Future<void> _addIngredient() async {
    final picked = await push<PickedFood>(context, FoodSearchScreen(date: widget.date, meal: widget.meal, pickMode: true));
    if (picked != null && mounted) setState(() => items.add(RecipeItem.of(picked.food, picked.g)));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final r = _build();
    final tot = r.total;
    final per = r.perServing;
    return SubPage(
      title: widget.recipe == null ? 'Nuova ricetta' : 'Modifica ricetta',
      actions: [
        if (widget.recipe != null)
          IconButton(
            tooltip: 'Elimina ricetta',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () async {
              if (await confirm(context, title: 'Eliminare la ricetta?', body: 'Le voci già nel diario restano.', ok: 'Elimina', danger: true)) {
                app.deleteRecipe(widget.recipe!.id);
                if (context.mounted) Navigator.pop(context);
              }
            },
          ),
      ],
      bottom: BottomActions(children: [
        GhostButton('Salva', onTap: () {
          if (!_validate()) return;
          app.saveRecipe(r);
          Navigator.pop(context);
        }),
        PrimaryButton('Salva e aggiungi a ${mealLabels[widget.meal]!.toLowerCase()}', dense: true, onTap: () {
          if (!_validate()) return;
          app.saveRecipe(r);
          final e = app.entryFromRecipe(r, 1, date: widget.date, meal: widget.meal);
          app.addEntry(e);
          Navigator.pop(context, e);
        }),
      ]),
      body: PageBody(children: [
        TCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Label('Nome'),
            TextField(
              controller: name,
              textCapitalization: TextCapitalization.sentences,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: t.ink),
              decoration: const InputDecoration(hintText: 'es. Pasta al pomodoro', filled: false, border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, contentPadding: EdgeInsets.symmetric(vertical: 8)),
              onChanged: (_) => setState(() {}),
            ),
            Row(children: [
              Expanded(child: Text('Porzioni che ottieni', style: TS.muted(t))),
              SmallButton('−', onTap: servings <= 0.5 ? null : () => setState(() => servings -= 0.5)),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text(fDec(servings, 1, true), style: TS.num(t, 18))),
              SmallButton('+', onTap: () => setState(() => servings += 0.5)),
            ]),
          ]),
        ),
        const SectionLabel('Ingredienti'),
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: RowTile(
              title: items[i].name,
              subtitle: '${fG(items[i].g)} ${items[i].unit} · tocca per cambiare',
              onTap: () async {
                final v = await askNumber(context, title: items[i].name, initial: items[i].g, unit: items[i].unit, decimals: 0, max: 10000);
                if (v != null) setState(() => items[i] = items[i].withGrams(v));
              },
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(fInt(items[i].macro.kcal), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: t.ink, fontFeatures: tabular)),
                IconButton(icon: Icon(Icons.close_rounded, size: 18, color: t.dim), onPressed: () => setState(() => items.removeAt(i))),
              ]),
            ),
          ),
        GhostButton('+ Aggiungi ingrediente', onTap: _addIngredient),
        const SizedBox(height: 14),
        TCard(
          borderColor: TC.accent.withValues(alpha: 0.35),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('Totale ricetta', style: TS.muted(t))),
              Text('${fG(r.totalGrams)} g', style: TS.muted(t, 12)),
            ]),
            BigNumber(fInt(tot.kcal), unit: 'kcal', size: 34),
            const SizedBox(height: 8),
            Text.rich(TextSpan(style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, fontFeatures: tabular), children: [
              TextSpan(text: 'P ${fInt(tot.p)} g   ', style: const TextStyle(color: TC.prot)),
              TextSpan(text: 'C ${fInt(tot.c)} g   ', style: const TextStyle(color: TC.carb)),
              TextSpan(text: 'G ${fInt(tot.f)} g', style: const TextStyle(color: TC.fat)),
            ])),
            if (servings != 1) ...[
              const SizedBox(height: 8),
              Text('A porzione: ${fInt(per.kcal)} kcal · P ${fInt(per.p)} · C ${fInt(per.c)} · G ${fInt(per.f)}', style: TS.muted(t, 12.5)),
            ],
          ]),
        ),
        if (error != null) NoteBox(icon: Icons.error_outline_rounded, text: error),
      ]),
    );
  }
}

class RecipeAddScreen extends StatefulWidget {
  final Recipe recipe;
  final String date;
  final String meal;
  final LogEntry? editEntry;
  const RecipeAddScreen({super.key, required this.recipe, required this.date, required this.meal, this.editEntry});
  @override
  State<RecipeAddScreen> createState() => _RecipeAddScreenState();
}

class _RecipeAddScreenState extends State<RecipeAddScreen> {
  late double servings = widget.editEntry?.servings ?? 1;
  late String meal = widget.editEntry?.meal ?? widget.meal;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final r = app.recipe(widget.recipe.id) ?? widget.recipe;
    final m = r.perServing.scale(servings);
    final favKey = 'r:${r.id}';
    final fav = app.favorites.contains(favKey);
    final edit = widget.editEntry != null;
    return SubPage(
      title: r.name,
      actions: [
        IconButton(
          icon: Icon(fav ? Icons.star_rounded : Icons.star_border_rounded, color: fav ? TC.accent : null),
          onPressed: () => app.toggleFav(favKey),
        ),
        IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => push(context, RecipeEditorScreen(recipe: r, date: widget.date, meal: meal))),
      ],
      bottom: BottomActions(children: [
        if (edit)
          GhostButton('Elimina', color: TC.danger, onTap: () {
            app.deleteEntry(widget.editEntry!.id);
            Navigator.pop(context);
          }),
        PrimaryButton(edit ? 'Salva' : 'Aggiungi a ${mealLabels[meal]!.toLowerCase()}', onTap: () {
          if (edit) {
            app.updateEntry(app.rescaleEntry(widget.editEntry!, servings: servings).copyWith(meal: meal));
            Navigator.pop(context);
            return;
          }
          final e = app.entryFromRecipe(r, servings, date: widget.date, meal: meal);
          app.addEntry(e);
          Navigator.pop(context, e);
        }),
      ]),
      body: PageBody(children: [
        TCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Label('Porzioni'),
            const SizedBox(height: 6),
            Text(fDec(servings, 2, true), style: TS.num(t, 44)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final v in [0.5, 1.0, 1.5, 2.0]) PillChip(fDec(v, 1, true), selected: servings == v, onTap: () => setState(() => servings = v)),
              PillChip('Altro…', onTap: () async {
                final v = await askNumber(context, title: 'Porzioni', initial: servings, decimals: 2, max: 20);
                if (v != null && v > 0) setState(() => servings = v);
              }),
            ]),
          ]),
        ),
        const SizedBox(height: 12),
        TCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            BigNumber(fInt(m.kcal), unit: 'kcal', size: 38),
            const SizedBox(height: 8),
            Text('P ${fDec(m.p, 1)} g · C ${fDec(m.c, 1)} g · G ${fDec(m.f, 1)} g', style: TextStyle(fontSize: 13, color: t.soft, fontFeatures: tabular)),
          ]),
        ),
        const SectionLabel('Ingredienti (ricetta intera)'),
        for (final it in r.items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Expanded(child: Text(it.name, style: TS.body(t))),
              Text('${fG(it.g)} ${it.unit} · ${fInt(it.macro.kcal)} kcal', style: TS.muted(t)),
            ]),
          ),
        const SectionLabel('Pasto'),
        MealChips(selected: meal, onChanged: (v) => setState(() => meal = v)),
      ]),
    );
  }
}
