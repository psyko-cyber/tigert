import 'package:flutter/material.dart';

import '../core/fmt.dart';
import '../core/theme.dart';
import '../data/app_state.dart';
import '../data/models.dart';
import 'add_hub.dart';
import 'food_amount.dart';
import 'quick_add.dart';
import 'recipes.dart';
import 'shell.dart';
import 'widgets.dart';

class DiaryScreen extends StatefulWidget {
  final String date;
  const DiaryScreen({super.key, required this.date});
  @override
  State<DiaryScreen> createState() => _DiaryScreenState();
}

class _DiaryScreenState extends State<DiaryScreen> {
  late String date = widget.date;

  void _shift(int d) => setState(() => date = addDaysKey(date, d));

  Future<void> _add(String meal) async {
    final e = await push<LogEntry>(context, AddHubScreen(date: date, meal: meal));
    if (e != null && mounted) confirmAdded(context, e);
  }

  Future<void> _edit(LogEntry e) async {
    final app = context.appRead;
    final food = e.refType == 'food' ? app.food(e.refId) : null;
    final recipe = e.refType == 'recipe' ? app.recipe(e.refId) : null;
    if (food != null) {
      await push(context, FoodAmountScreen(food: food, date: e.date, meal: e.meal, editEntry: e));
    } else if (recipe != null) {
      await push(context, RecipeAddScreen(recipe: recipe, date: e.date, meal: e.meal, editEntry: e));
    } else if (e.g != null && e.g! > 0) {
      await showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => _GramsSheet(entry: e));
    } else {
      await push(context, QuickAddScreen(date: e.date, meal: e.meal, editEntry: e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final p = app.profile!;
    final entries = app.entries(date);
    final tot = app.totals(date);
    final d = fromKey(date);
    final yesterday = addDaysKey(date, -1);
    final byMeal = <String, List<LogEntry>>{};
    for (final e in entries) {
      (byMeal[e.meal] ??= []).add(e);
    }
    final meals = [
      for (final m in mealKeys)
        if (byMeal.containsKey(m) || m == 'colazione' || m == 'pranzo' || m == 'cena') m,
    ];

    return SubPage(
      title: 'Diario',
      actions: [
        IconButton(
          tooltip: 'Scegli data',
          icon: const Icon(Icons.calendar_month_rounded),
          onPressed: () async {
            final r = await showDatePicker(context: context, initialDate: d, firstDate: DateTime(2020), lastDate: today().add(const Duration(days: 30)));
            if (r != null) setState(() => date = dayKey(r));
          },
        ),
      ],
      body: PageBody(children: [
        Row(children: [
          SmallButton('‹', onTap: () => _shift(-1)),
          Expanded(
            child: Column(children: [
              Text(relDay(d), style: TS.title(t)),
              Text(longDate(d), style: TS.muted(t, 12)),
            ]),
          ),
          SmallButton('›', onTap: () => _shift(1)),
        ]),
        if (entries.isEmpty)
          EmptyState(
            emoji: '🍽️',
            title: date == todayKey() ? 'Ancora niente oggi' : 'Nessun pasto registrato',
            body: app.entries(yesterday).isEmpty
                ? 'Parti dalla colazione: dopo i primi giorni i tuoi alimenti abituali saranno a un tap.'
                : 'Puoi partire copiando i pasti di ieri e poi correggere le quantità.',
            action: Column(children: [
              PrimaryButton('Aggiungi il primo pasto', onTap: () => _add(date == todayKey() ? mealForNow() : 'colazione')),
              if (app.entries(yesterday).isNotEmpty) ...[
                const SizedBox(height: 8),
                GhostButton('Copia tutta la giornata di ieri', onTap: () {
                  app.store.batch(() {
                    for (final m in mealKeys) {
                      app.copyMeal(yesterday, m, date);
                    }
                  });
                }),
              ],
            ]),
          )
        else ...[
          const SizedBox(height: 14),
          TCard(
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Totale giornata', style: TS.muted(t, 12)),
                  Text('${fInt(tot.kcal)} kcal', style: TS.num(t, 28)),
                  Text('Obiettivo ${fInt(p.kcal)} kcal', style: TS.muted(t, 12)),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('P ${fInt(tot.p)} / ${p.protein} g', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: TC.prot, fontFeatures: tabular)),
                Text('C ${fInt(tot.c)} / ${p.carbs} g', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: TC.carb, fontFeatures: tabular)),
                Text('G ${fInt(tot.f)} / ${p.fat} g', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: TC.fat, fontFeatures: tabular)),
              ]),
            ]),
          ),
        ],
        const SizedBox(height: 12),
        for (final m in meals) ...[
          _MealCard(
            meal: m,
            entries: byMeal[m] ?? const [],
            onAdd: () => _add(m),
            onEdit: _edit,
            onCopyYesterday: app.entries(yesterday).any((e) => e.meal == m) && !(byMeal[m]?.isNotEmpty ?? false)
                ? () => app.copyMeal(yesterday, m, date)
                : null,
          ),
          const SizedBox(height: 10),
        ],
      ]),
    );
  }
}

class _MealCard extends StatelessWidget {
  final String meal;
  final List<LogEntry> entries;
  final VoidCallback onAdd;
  final ValueChanged<LogEntry> onEdit;
  final VoidCallback? onCopyYesterday;
  const _MealCard({required this.meal, required this.entries, required this.onAdd, required this.onEdit, this.onCopyYesterday});

  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    final app = context.app;
    final tot = entries.fold(Macro.zero, (a, e) => a + e.macro);
    return TCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(mealLabels[meal]!, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: t.ink))),
          if (entries.isNotEmpty) Text('${fInt(tot.kcal)} kcal', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: t.ink, fontFeatures: tabular)),
          const SizedBox(width: 6),
        ]),
        const SizedBox(height: 6),
        for (final e in entries)
          Tap(
            radius: 8,
            onTap: () => onEdit(e),
            onLongPress: () async {
              if (await confirm(context, title: 'Eliminare "${e.name}"?', body: '${fInt(e.kcal)} kcal da ${mealLabels[e.meal]!.toLowerCase()}.', ok: 'Elimina', danger: true)) {
                app.deleteEntry(e.id);
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
              child: Row(children: [
                if (e.photoId != null && app.store.hasBlob(e.photoId!)) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.file(app.store.blobFile(e.photoId!), width: 28, height: 28, fit: BoxFit.cover, cacheWidth: 84),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    e.g == null ? e.name : '${e.name} ${e.refType == 'recipe' ? '· ${fDec(e.servings, 2, true)} porz.' : '${fG(e.g!)} g'}',
                    style: TextStyle(fontSize: 13, color: t.soft),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(fInt(e.kcal), style: TextStyle(fontSize: 13, color: t.soft, fontFeatures: tabular)),
                const SizedBox(width: 6),
              ]),
            ),
          ),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(
            child: entries.isEmpty
                ? Text('Niente di registrato', style: TS.muted(t, 12))
                : Text('P ${fInt(tot.p)} g · C ${fInt(tot.c)} g · G ${fInt(tot.f)} g', style: TextStyle(fontSize: 12, color: t.dim, fontFeatures: tabular)),
          ),
          if (onCopyYesterday != null) ...[
            TextButton(onPressed: onCopyYesterday, child: Text('Come ieri', style: TextStyle(color: t.soft, fontSize: 12.5))),
          ],
          TextButton.icon(
            onPressed: onAdd,
            icon: Icon(Icons.add_rounded, size: 18, color: t.accentInk),
            label: Text('Aggiungi', style: TextStyle(color: t.accentInk, fontWeight: FontWeight.w700, fontSize: 13)),
          ),
        ]),
      ]),
    );
  }
}

/// Modifica rapida di una voce da foto: grammi (valori ricalcolati), pasto, elimina.
class _GramsSheet extends StatefulWidget {
  final LogEntry entry;
  const _GramsSheet({required this.entry});
  @override
  State<_GramsSheet> createState() => _GramsSheetState();
}

class _GramsSheetState extends State<_GramsSheet> {
  late double g = widget.entry.g ?? 100;
  late String meal = widget.entry.meal;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final e = app.rescaleEntry(widget.entry, g: g);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(widget.entry.name, style: TS.h2(t)),
        const SizedBox(height: 12),
        Stepper2(
          value: '${fG(g)} g',
          onMinus: () => setState(() => g = (g - 10).clamp(0, 5000)),
          onPlus: () => setState(() => g = (g + 10).clamp(0, 5000)),
          onTapValue: () async {
            final v = await askNumber(context, title: 'Grammi', initial: g, unit: 'g', decimals: 0, max: 5000);
            if (v != null) setState(() => g = v);
          },
        ),
        const SizedBox(height: 10),
        Text('${fInt(e.kcal)} kcal · P ${fDec(e.p, 1)} · C ${fDec(e.c, 1)} · G ${fDec(e.f, 1)}', textAlign: TextAlign.center, style: TS.muted(t)),
        const SizedBox(height: 14),
        MealChips(selected: meal, onChanged: (m) => setState(() => meal = m)),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(
            child: GhostButton('Elimina', color: TC.danger, onTap: () {
              app.deleteEntry(widget.entry.id);
              Navigator.pop(context);
            }),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: PrimaryButton('Salva', onTap: () {
              app.updateEntry(e.copyWith(meal: meal));
              Navigator.pop(context);
            }),
          ),
        ]),
      ]),
    );
  }
}
