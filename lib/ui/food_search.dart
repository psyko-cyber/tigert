import 'dart:async';

import 'package:flutter/material.dart';

import '../core/fmt.dart';
import '../data/app_state.dart';
import '../data/models.dart';
import '../services/off_api.dart';
import 'add_hub.dart';
import 'food_amount.dart';
import 'food_editor.dart';
import 'recipes.dart';
import 'shell.dart';
import 'widgets.dart';

/// Risultato della modalità "scegli un alimento" (per ricette e foto).
class PickedFood {
  final Food food;
  final double g;
  const PickedFood(this.food, this.g);
}

class FoodSearchScreen extends StatefulWidget {
  final String date;
  final String meal;
  final bool pickMode;
  final bool focusSearch;
  const FoodSearchScreen({super.key, required this.date, required this.meal, this.pickMode = false, this.focusSearch = true});
  @override
  State<FoodSearchScreen> createState() => _FoodSearchScreenState();
}

class _FoodSearchScreenState extends State<FoodSearchScreen> {
  final ctl = TextEditingController();
  String filter = 'tutti';
  List<Food> online = [];
  bool loadingOnline = false;
  String? onlineError;
  Timer? _deb;
  String query = '';

  @override
  void dispose() {
    ctl.dispose();
    _deb?.cancel();
    super.dispose();
  }

  void _onChanged(String v) {
    _deb?.cancel();
    _deb = Timer(const Duration(milliseconds: 150), () {
      if (mounted) {
        setState(() {
          query = v;
          online = [];
          onlineError = null;
        });
      }
    });
  }

  Future<void> _searchOnline() async {
    final q = ctl.text.trim();
    if (q.length < 2) return;
    setState(() {
      loadingOnline = true;
      onlineError = null;
    });
    try {
      final r = await OffApi.search(q);
      if (!mounted) return;
      setState(() {
        online = r;
        if (r.isEmpty) onlineError = 'Nessun prodotto trovato su Open Food Facts.';
      });
    } catch (e) {
      if (mounted) setState(() => onlineError = 'Ricerca online non riuscita: controlla la connessione.');
    } finally {
      if (mounted) setState(() => loadingOnline = false);
    }
  }

  Future<void> _openFood(Food f) async {
    final app = context.appRead;
    // i prodotti online vengono salvati in locale al primo uso
    if (f.src == 'off' && app.food(f.id) == null) app.saveFood(f);
    if (widget.pickMode) {
      final g = await push<double>(context, FoodAmountScreen(food: f, date: widget.date, meal: widget.meal, pickMode: true));
      if (g != null && mounted) Navigator.pop(context, PickedFood(f, g));
      return;
    }
    final r = await push<LogEntry>(context, FoodAmountScreen(food: f, date: widget.date, meal: widget.meal));
    if (r != null && mounted) Navigator.pop(context, r);
  }

  Future<void> _quickAdd(Food f) async {
    final app = context.appRead;
    if (f.src == 'off' && app.food(f.id) == null) app.saveFood(f);
    final g = f.portions.isNotEmpty ? f.portions.first.g : 100.0;
    if (widget.pickMode) {
      Navigator.pop(context, PickedFood(f, g));
      return;
    }
    final e = app.entryFromFood(f, g, date: widget.date, meal: widget.meal);
    app.addEntry(e);
    confirmAdded(context, e);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final results = filter == 'ricette' ? const <Food>[] : app.searchFoods(query, onlyFav: filter == 'preferiti', onlyBrands: filter == 'marche');
    final recipes = filter == 'ricette' || (filter == 'tutti' && query.trim().isNotEmpty && !widget.pickMode)
        ? app.recipes.where((r) => fold(r.name).contains(fold(query.trim()))).toList()
        : const <Recipe>[];

    Widget foodRow(Food f) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: RowTile(
            leading: FoodBadge(f.cat, name: f.name),
            title: f.displayName,
            subtitle: '${fInt(f.kcal)} kcal/100 g · P ${fDec(f.p, 1, true)} · C ${fDec(f.c, 1, true)} · G ${fDec(f.f, 1, true)}',
            onTap: () => _openFood(f),
            trailing: PlusBadge(onTap: () => _quickAdd(f)),
          ),
        );

    return SubPage(
      title: widget.pickMode ? 'Scegli alimento' : 'Cerca',
      actions: [
        IconButton(
          tooltip: 'Crea alimento',
          icon: const Icon(Icons.add_box_outlined),
          onPressed: () async {
            final f = await push<Food>(context, FoodEditorScreen(initialName: ctl.text.trim()));
            if (f != null && mounted) _openFood(f);
          },
        ),
      ],
      body: Column(children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
              child: Column(children: [
                TextField(
                  controller: ctl,
                  autofocus: widget.focusSearch,
                  textInputAction: TextInputAction.search,
                  onChanged: _onChanged,
                  onSubmitted: (_) {
                    if (results.isEmpty) _searchOnline();
                  },
                  decoration: InputDecoration(
                    hintText: 'Cerca un alimento, es. petto di pollo',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: ctl.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () {
                              ctl.clear();
                              _onChanged('');
                            }),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 36,
                  child: ListView(scrollDirection: Axis.horizontal, children: [
                    for (final (k, l) in [('tutti', 'Tutti'), ('preferiti', 'Preferiti'), if (!widget.pickMode) ('ricette', 'Ricette'), ('marche', 'Prodotti')]) ...[
                      PillChip(l, selected: filter == k, onTap: () => setState(() => filter = k)),
                      const SizedBox(width: 6),
                    ],
                  ]),
                ),
              ]),
            ),
          ),
        ),
        Expanded(
          child: PageBody(padding: const EdgeInsets.fromLTRB(18, 4, 18, 28), children: [
            for (final r in recipes)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: RowTile(
                  leading: const FoodBadge('Ricette'),
                  title: r.name,
                  subtitle: 'Ricetta · ${fInt(r.perServing.kcal)} kcal a porzione',
                  onTap: () async {
                    final e = await push<LogEntry>(context, RecipeAddScreen(recipe: r, date: widget.date, meal: widget.meal));
                    if (e != null && context.mounted) Navigator.pop(context, e);
                  },
                ),
              ),
            if (filter == 'ricette' && recipes.isEmpty)
              EmptyState(
                emoji: '🍲',
                title: 'Nessuna ricetta',
                body: 'Crea una ricetta una volta e riusala con un tap.',
                action: PrimaryButton('Nuova ricetta', onTap: () => push(context, RecipeEditorScreen(date: widget.date, meal: widget.meal))),
              ),
            ...results.map(foodRow),
            if (filter != 'ricette' && query.trim().length >= 2) ...[
              const SizedBox(height: 8),
              if (online.isEmpty)
                GhostButton(loadingOnline ? 'Cerco su Open Food Facts…' : 'Non lo trovi? Cerca su Open Food Facts', icon: Icons.public_rounded, onTap: loadingOnline ? null : _searchOnline),
              if (onlineError != null) NoteBox(text: onlineError),
              if (online.isNotEmpty) ...[
                const SectionLabel('Open Food Facts'),
                ...online.map(foodRow),
              ],
            ],
            if (results.isEmpty && query.trim().isNotEmpty && online.isEmpty) ...[
              const SizedBox(height: 10),
              PrimaryButton('Crea "${query.trim()}"', icon: Icons.add_rounded, onTap: () async {
                final f = await push<Food>(context, FoodEditorScreen(initialName: query.trim()));
                if (f != null && mounted) _openFood(f);
              }),
            ],
            NoteBox(
              text: 'Database locale con ${app.catalog.foods.length + app.userFoods.length} alimenti: cresce con i tuoi prodotti e le tue ricette. Tocca + per aggiungere subito una porzione standard.',
            ),
          ]),
        ),
      ]),
    );
  }
}
