import 'package:flutter/material.dart';

import '../../core/fmt.dart';
import '../../core/theme.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../widgets.dart';

/// Attrezzi di casa: servono al report settimanale per proporre una seduta extra.
class HomeGymScreen extends StatefulWidget {
  const HomeGymScreen({super.key});
  @override
  State<HomeGymScreen> createState() => _HomeGymScreenState();
}

class _HomeGymScreenState extends State<HomeGymScreen> {
  late HomeGym g = context.appRead.profile!.home ?? const HomeGym();

  static const _kg = [0.0, 4, 6, 8, 10, 12, 15, 20, 25];

  void _save() {
    final app = context.appRead;
    app.saveProfile(app.profile!.copyWith(home: g));
    toast(context, 'Attrezzatura salvata');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    Widget toggle(String title, String sub, bool on, ValueChanged<bool> set) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: TCard(
            radius: 14,
            onTap: () => setState(() => set(!on)),
            padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: t.ink)),
                  Text(sub, style: TS.muted(t, 11.5)),
                ]),
              ),
              Switch(value: on, onChanged: (v) => setState(() => set(v))),
            ]),
          ),
        );
    return SubPage(
      title: 'Attrezzatura a casa',
      bottom: BottomActions(children: [PrimaryButton('Salva', onTap: _save)]),
      body: PageBody(children: [
        Text('Il sabato il report settimanale ti propone una seduta a casa per i muscoli rimasti indietro, solo con quello che hai.',
            style: TS.muted(t, 12.5)),
        const SectionLabel('Attrezzi'),
        toggle('Sbarra per trazioni', 'Trazioni, sollevamento gambe', g.bar, (v) => g = g.copyWith(bar: v)),
        toggle('Parallele', 'Dip per petto e tricipiti', g.dip, (v) => g = g.copyWith(dip: v)),
        toggle('Panca piana', 'Panca e croci con manubri, rematore', g.bench, (v) => g = g.copyWith(bench: v)),
        toggle('Panca inclinabile', 'Panca inclinata, curl e rematore su panca inclinata', g.incline, (v) => g = g.copyWith(incline: v)),
        const SectionLabel('Manubri · peso massimo per manubrio'),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final k in _kg)
            PillChip(k == 0 ? 'Nessuno' : '${fDec(k, 1, true)} kg', selected: g.dbKg == k, onTap: () => setState(() => g = g.copyWith(dbKg: k.toDouble()))),
        ]),
        NoteBox(
          icon: Icons.info_outline_rounded,
          text: g.dbKg > 0 && g.dbKg < 16
              ? 'Con manubri leggeri la seduta sale di ripetizioni (12-20) e va vicino al cedimento: lo stimolo è simile a quello di serie più pesanti.'
              : 'Il corpo libero (piegamenti, glute bridge) è sempre compreso.',
        ),
      ]),
    );
  }
}
