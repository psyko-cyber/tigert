import 'package:flutter/material.dart';

import '../core/fmt.dart';
import '../core/theme.dart';
import '../data/app_state.dart';
import '../data/models.dart';
import 'barcode.dart';
import 'diary.dart';
import 'food_amount.dart';
import 'food_search.dart';
import 'photo_estimate.dart';
import 'quick_add.dart';
import 'recipes.dart';
import 'shell.dart';
import 'widgets.dart';

String catEmoji(String cat) => switch (cat) {
      'Cereali e pasta' => '🌾',
      'Pane e prodotti da forno' => '🍞',
      'Legumi e proteine vegetali' => '🫘',
      'Verdure' => '🥦',
      'Frutta' => '🍎',
      'Frutta secca e semi' => '🥜',
      'Carne' => '🍗',
      'Salumi' => '🥓',
      'Pesce' => '🐟',
      'Uova' => '🥚',
      'Latte e yogurt' => '🥛',
      'Formaggi' => '🧀',
      'Oli, grassi e condimenti' => '🫒',
      'Dolci e snack' => '🍫',
      'Bevande' => '🥤',
      'Integratori' => '💪',
      'Piatti pronti' => '🍝',
      'Prodotti' => '🏷️',
      'Ricette' => '🍲',
      _ => '🍽️',
    };

class FoodBadge extends StatelessWidget {
  final String cat;
  const FoodBadge(this.cat, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(color: context.tt.surf2, borderRadius: BorderRadius.circular(10)),
        alignment: Alignment.center,
        child: Text(catEmoji(cat), style: const TextStyle(fontSize: 18)),
      );
}

/// Selettore del pasto (Colazione, Spuntino, ...).
class MealChips extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;
  const MealChips({super.key, required this.selected, required this.onChanged});
  @override
  Widget build(BuildContext context) => Wrap(spacing: 8, runSpacing: 8, children: [
        for (final m in mealKeys) PillChip(mealLabels[m]!, selected: selected == m, onTap: () => onChanged(m)),
      ]);
}

/// Mostra conferma dopo un'aggiunta con possibilità di annullare.
void confirmAdded(BuildContext context, LogEntry e) {
  final app = context.appRead;
  // la stima da foto crea più voci: l'id è "id1|id2|..."
  toast(context, 'Aggiunto a ${mealLabels[e.meal]!.toLowerCase()} · ${fInt(e.kcal)} kcal', action: 'Annulla', onAction: () {
    app.store.batch(() {
      for (final id in e.id.split('|')) {
        app.deleteEntry(id);
      }
    });
  });
}

class AddHubScreen extends StatefulWidget {
  final bool embedded;
  final String? date;
  final String? meal;
  const AddHubScreen({super.key, this.embedded = false, this.date, this.meal});
  @override
  State<AddHubScreen> createState() => _AddHubScreenState();
}

class _AddHubScreenState extends State<AddHubScreen> {
  late String meal = widget.meal ?? mealForNow();
  String get date => widget.date ?? todayKey();

  @override
  void initState() {
    super.initState();
    if (widget.embedded) ShellNav.tab.addListener(_onTab);
  }

  @override
  void dispose() {
    if (widget.embedded) ShellNav.tab.removeListener(_onTab);
    super.dispose();
  }

  void _onTab() {
    if (ShellNav.tab.value == 2 && mounted) setState(() => meal = mealForNow());
  }

  Future<void> _open(Widget page) async {
    final r = await push<LogEntry>(context, page);
    if (r != null && mounted) {
      confirmAdded(context, r);
      if (!widget.embedded) Navigator.pop(context, r);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final d = fromKey(date);
    final fav = app.favorites;
    final recents = app.recentFoods(limit: 10);
    final favFoods = fav.map(app.food).whereType<Food>().toList();
    final favRecipes = fav.where((id) => id.startsWith('r:')).map((id) => app.recipe(id.substring(2))).whereType<Recipe>().toList();
    final shown = <String>{};
    final rows = <Widget>[];
    void addFoodRow(Food f, double g) {
      if (shown.contains(f.id)) return;
      shown.add(f.id);
      final m = f.per(g);
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: RowTile(
          leading: FoodBadge(f.cat),
          title: f.displayName,
          subtitle: '${fG(g)} g · ${fInt(m.kcal)} kcal${fav.contains(f.id) ? ' · ★' : ''}',
          onTap: () => _open(FoodAmountScreen(food: f, date: date, meal: meal, initialG: g)),
          trailing: PlusBadge(onTap: () {
            final e = app.entryFromFood(f, g, date: date, meal: meal);
            app.addEntry(e);
            confirmAdded(context, e);
          }),
        ),
      ));
    }

    for (final f in favFoods) {
      final last = recents.where((r) => r.$1.id == f.id);
      addFoodRow(f, last.isEmpty ? (f.portions.isEmpty ? 100 : f.portions.first.g) : last.first.$2);
    }
    for (final r in favRecipes) {
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: RowTile(
          leading: const FoodBadge('Ricette'),
          title: r.name,
          subtitle: '1 porzione · ${fInt(r.perServing.kcal)} kcal · ★',
          onTap: () => _open(RecipeAddScreen(recipe: r, date: date, meal: meal)),
          trailing: PlusBadge(onTap: () {
            final e = app.entryFromRecipe(r, 1, date: date, meal: meal);
            app.addEntry(e);
            confirmAdded(context, e);
          }),
        ),
      ));
    }
    for (final (f, g) in recents) {
      addFoodRow(f, g);
    }

    final wide = MediaQuery.sizeOf(context).width >= 700;
    final tiles = [
      _Tile(Icons.qr_code_scanner_rounded, 'Codice a barre', 'Inquadra o incolla l\'EAN', () => _open(BarcodeScreen(date: date, meal: meal))),
      _Tile(Icons.photo_camera_rounded, 'Foto del piatto', 'Stima con Gemini', () => _open(PhotoScreen(date: date, meal: meal))),
      _Tile(Icons.search_rounded, 'Cerca', 'Database locale', () => _open(FoodSearchScreen(date: date, meal: meal))),
      _Tile(Icons.functions_rounded, 'Solo calorie', 'Un numero e via', () => _open(QuickAddScreen(date: date, meal: meal))),
      _Tile(Icons.scale_rounded, 'Quantità a mano', 'Scegli e pesa', () => _open(FoodSearchScreen(date: date, meal: meal, focusSearch: true))),
      _Tile(Icons.menu_book_rounded, 'Le mie ricette', app.recipes.isEmpty ? 'Crea la prima' : app.recipes.first.name, () => _open(RecipesScreen(date: date, meal: meal)), accent: true),
    ];

    final content = PageBody(children: [
      if (widget.embedded) ...[
        Text('Aggiungi cibo', style: TS.h1(t).copyWith(fontSize: 24)),
        const SizedBox(height: 4),
      ],
      Text('Due tap e sei a posto. ${mealLabels[meal]} · ${relDay(d).toLowerCase()}', style: TS.muted(t)),
      const SizedBox(height: 14),
      MealChips(selected: meal, onChanged: (m) => setState(() => meal = m)),
      const SizedBox(height: 16),
      GridView.count(
        crossAxisCount: wide ? 3 : 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: wide ? 1.9 : 1.45,
        children: tiles,
      ),
      SectionLabel('Preferiti e recenti',
          trailing: Tap(
            onTap: () => push(context, DiaryScreen(date: date)),
            radius: 8,
            child: Padding(padding: const EdgeInsets.all(4), child: Text('Diario ›', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: t.accentInk))),
          )),
      if (rows.isEmpty) Text('Gli alimenti che usi compariranno qui per aggiungerli con un tap.', style: TS.muted(t)) else ...rows,
    ]);

    if (widget.embedded) return content;
    return SubPage(title: 'Aggiungi a ${mealLabels[meal]!.toLowerCase()}', body: content);
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String sub;
  final VoidCallback onTap;
  final bool accent;
  const _Tile(this.icon, this.title, this.sub, this.onTap, {this.accent = false});
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    return TCard(
      onTap: onTap,
      borderColor: accent ? TC.accent.withValues(alpha: 0.7) : null,
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Icon(icon, size: 24, color: t.accentInk),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: t.ink)),
          const SizedBox(height: 2),
          Text(sub, style: TextStyle(fontSize: 11.5, color: t.dim, height: 1.3), maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
      ]),
    );
  }
}
