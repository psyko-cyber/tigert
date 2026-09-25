import 'package:flutter/material.dart';

import '../core/fmt.dart';
import '../core/theme.dart';
import '../data/app_state.dart';
import '../logic/score.dart';
import 'shell.dart';
import 'widgets.dart';

class ScoreDetailScreen extends StatefulWidget {
  final String date;
  const ScoreDetailScreen({super.key, required this.date});
  @override
  State<ScoreDetailScreen> createState() => _ScoreDetailScreenState();
}

class _ScoreDetailScreenState extends State<ScoreDetailScreen> {
  late String date = widget.date;

  Color _tone(TT t, Tone x) => switch (x) {
        Tone.good => t.accentInk,
        Tone.warn => TC.warn,
        Tone.bad => TC.danger,
        Tone.dim => t.dim,
      };

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final s = app.score(date);
    final week = app.weekAverageScore(end: fromKey(date));
    final d = fromKey(date);
    return SubPage(
      title: date == todayKey() ? 'Voto di oggi' : 'Voto · ${shortDate(d)}',
      body: PageBody(children: [
        DayBar(date: date, onChanged: (k) => setState(() => date = k)),
        const SizedBox(height: 14),
        TCard(
          child: Row(children: [
            ScoreGauge(value: s.v, hasData: s.hasData),
            const SizedBox(width: 18),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.label, style: TS.soft(t)),
                if (week != null) ...[
                  const SizedBox(height: 8),
                  Text.rich(TextSpan(style: TS.muted(t, 12), children: [
                    const TextSpan(text: 'Media 7 giorni '),
                    TextSpan(text: fDec(week), style: TextStyle(fontWeight: FontWeight.w800, color: t.ink)),
                    const TextSpan(text: ' · pesa più dei singoli giorni'),
                  ])),
                ],
              ]),
            ),
          ]),
        ),
        // manca qualcosa (sonno, passi, un pasto)? si entra nella giornata e si sistema
        if (date != todayKey()) ...[
          const SizedBox(height: 10),
          PrimaryButton('Modifica questa giornata', icon: Icons.edit_calendar_rounded, onTap: () => DayNav.open(context, date)),
        ],
        for (final part in s.parts)
          TCard(
            margin: const EdgeInsets.only(top: 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(part.name, style: TS.title(t).copyWith(fontSize: 14))),
                Text(part.max <= 0 ? '—' : '${fDec(part.points)} / ${fDec(part.max)}', style: TS.num(t, 14, w: FontWeight.w700)),
              ]),
              const SizedBox(height: 8),
              BarTrack(pct: part.ratio, color: part.max <= 0 ? t.dim : scoreColor(part.ratio * 10)),
              const SizedBox(height: 10),
              for (final r in part.rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    Expanded(child: Text(r.k, style: TS.soft(t, 12.5))),
                    Text(r.v, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: _tone(t, r.tone), fontFeatures: tabular)),
                  ]),
                ),
            ]),
          ),
        if (s.tips.isNotEmpty)
          TipCard(
            title: date == todayKey() ? 'Cosa manca per salire' : 'Cosa è mancato',
            child: Column(children: [
              for (final tip in s.tips)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 44, child: Text('+${fDec(tip.gain)}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: t.accentInk, fontFeatures: tabular))),
                    Expanded(child: Text(tip.text, style: TextStyle(fontSize: 13, color: t.ink, height: 1.4))),
                  ]),
                ),
            ]),
          ),
        const SectionLabel('Regola del voto'),
        Text(
          'Nutrizione 50% (calorie vicine al target e proteine sopra il target) · Allenamento 35% (sessione e serie completate) · '
          'Abitudini 15% (acqua, sonno, passi, alcol). Nei giorni di riposo il 35% si redistribuisce su nutrizione e abitudini. '
          'Quanto puoi stare sopra o sotto il target dipende dalla fase. Le attività extra tolgono le calorie bruciate da quelle mangiate.',
          style: TS.muted(t, 12.5),
        ),
      ]),
    );
  }
}
