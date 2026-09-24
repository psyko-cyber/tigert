import 'package:flutter/material.dart';

import '../core/fmt.dart';
import '../core/theme.dart';
import '../data/app_state.dart';
import '../data/models.dart';
import '../logic/activity.dart';
import 'widgets.dart';

IconData sportIcon(String kind) => switch (kind) {
      'calcetto' || 'calcio' => Icons.sports_soccer_rounded,
      'beach' || 'pallavolo' => Icons.sports_volleyball_rounded,
      'padel' || 'tennis' => Icons.sports_tennis_rounded,
      'basket' => Icons.sports_basketball_rounded,
      'corsa' => Icons.directions_run_rounded,
      'bici' => Icons.directions_bike_rounded,
      'nuoto' => Icons.pool_rounded,
      'escursione' => Icons.hiking_rounded,
      'boxe' => Icons.sports_mma_rounded,
      'arrampicata' => Icons.terrain_rounded,
      'ballo' => Icons.music_note_rounded,
      'sci' => Icons.downhill_skiing_rounded,
      'yoga' => Icons.self_improvement_rounded,
      _ => Icons.sports_rounded,
    };

/// Aggiunge un'attività extra al giorno [h], o modifica quella in posizione [index].
Future<void> editExtraActivity(BuildContext context, HabitDay h, [int? index]) async {
  final app = context.appRead;
  final old = index == null ? null : h.extra[index];
  final kg = app.currentWeight;
  var kind = old?.kind ?? 'calcetto';
  var min = old?.min ?? 60;
  var lvl = old?.lvl ?? 1;
  final name = TextEditingController(text: old?.kind == 'altro' ? old!.name : '');
  final r = await showModalBottomSheet<Object>(
    context: context,
    isScrollControlled: true,
    builder: (c) => StatefulBuilder(builder: (c, set) {
      final t = c.tt;
      final kcal = activityKcal(kind, min, kg, lvl);
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(c).bottom),
        child: SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * 0.85),
            child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 0, 20, 16), children: [
              Text(old == null ? 'Attività extra' : 'Modifica attività', style: TS.h2(t)),
              const SizedBox(height: 4),
              Text('Le calorie bruciate si tolgono da quelle mangiate: oggi puoi mangiare di più.', style: TS.muted(t)),
              const SizedBox(height: 14),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final (k, n, _) in sports) PillChip(n, icon: sportIcon(k), selected: kind == k, onTap: () => set(() => kind = k)),
              ]),
              if (kind == 'altro') ...[
                const SizedBox(height: 10),
                TextField(controller: name, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(hintText: 'Nome (es. rugby)')),
              ],
              const SizedBox(height: 16),
              Row(children: [
                Text('Durata', style: TextStyle(fontSize: 14, color: t.soft)),
                const Spacer(),
                SmallButton('−', onTap: min <= 15 ? null : () => set(() => min -= 15)),
                SizedBox(width: 76, child: Text(fMinutes(min), textAlign: TextAlign.center, style: TS.num(t, 18))),
                SmallButton('+', onTap: min >= 300 ? null : () => set(() => min += 15)),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Text('Intensità', style: TextStyle(fontSize: 14, color: t.soft)),
                const Spacer(),
                for (var i = 0; i < intensityLevels.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  PillChip(intensityLevels[i], selected: lvl == i, onTap: () => set(() => lvl = i)),
                ],
              ]),
              const SizedBox(height: 16),
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('−${fInt(kcal)}', style: TS.num(t, 32, color: t.accentInk)),
                Padding(padding: const EdgeInsets.only(left: 6, bottom: 5), child: Text('kcal', style: TS.muted(t))),
              ]),
              Text('Stima per ${fDec(kg, 1)} kg, senza il consumo a riposo che è già nel target.', style: TS.muted(t, 12)),
              const SizedBox(height: 16),
              Row(children: [
                if (old != null) ...[
                  Expanded(child: SmallButton('Elimina', onTap: () => Navigator.pop(c, 'del'))),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  flex: 2,
                  child: PrimaryButton(old == null ? 'Aggiungi' : 'Salva', dense: true, onTap: () {
                    final n = kind == 'altro' && name.text.trim().isNotEmpty ? name.text.trim() : sports.firstWhere((s) => s.$1 == kind).$2;
                    Navigator.pop(c, ExtraActivity(kind: kind, name: n, min: min, lvl: lvl, kcal: kcal));
                  }),
                ),
              ]),
            ]),
          ),
        ),
      );
    }),
  );
  if (r == null) return;
  final list = [...h.extra];
  if (r == 'del') {
    list.removeAt(index!);
  } else if (index == null) {
    list.add(r as ExtraActivity);
  } else {
    list[index] = r as ExtraActivity;
  }
  app.saveHabit(h.copyWith(extra: list));
}

/// Riga di un'attività in Oggi: tocca per modificarla.
class ExtraActivityRow extends StatelessWidget {
  final HabitDay day;
  final int index;
  const ExtraActivityRow({super.key, required this.day, required this.index});
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    final e = day.extra[index];
    return Material(
      color: t.surf2,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => editExtraActivity(context, day, index),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(children: [
            Icon(sportIcon(e.kind), size: 20, color: t.accentInk),
            const SizedBox(width: 10),
            Expanded(
              child: Text('${e.name} · ${fMinutes(e.min)}${e.lvl == 1 ? '' : ' · ${intensityLevels[e.lvl].toLowerCase()}'}',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: t.ink), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            Text('−${fInt(e.kcal)} kcal', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: t.accentInk, fontFeatures: tabular)),
          ]),
        ),
      ),
    );
  }
}
