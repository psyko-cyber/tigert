import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/fmt.dart';
import '../core/theme.dart';
import '../data/app_state.dart';
import '../data/models.dart';
import '../logic/balance.dart';
import '../logic/consult.dart';
import '../logic/score.dart' show Tone;
import 'shell.dart';
import 'week_report.dart';
import 'widgets.dart';

Color toneColor(TT t, Tone x) => switch (x) {
      Tone.good => t.accentInk,
      Tone.warn => TC.warn,
      Tone.bad => TC.danger,
      Tone.dim => t.dim,
    };

/// Le righe del bilancio: pallino colorato, voce e valore.
class BalanceRows extends StatelessWidget {
  final WeekBalance balance;
  const BalanceRows(this.balance, {super.key});
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final r in balance.rows)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: toneColor(t, r.tone), shape: BoxShape.circle)),
            const SizedBox(width: 10),
            SizedBox(width: 76, child: Text(r.k, style: TS.soft(t, 13))),
            Expanded(
              child: Text(r.v, textAlign: TextAlign.right, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: t.ink, fontFeatures: tabular)),
            ),
          ]),
        ),
      if (balance.note != null) ...[
        const SizedBox(height: 6),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.info_outline_rounded, size: 16, color: TC.warn)),
          const SizedBox(width: 8),
          Expanded(child: Text(balance.note!, style: TS.soft(t, 12.5))),
        ]),
      ],
    ]);
  }
}

/// Nel weekend in Oggi: il bilancio della settimana, con i muscoli e la consulenza a un tocco.
class BalanceCard extends StatelessWidget {
  const BalanceCard({super.key});
  @override
  Widget build(BuildContext context) => TipCard(
        title: 'Bilancio della settimana',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          BalanceRows(weekBalance(context.app, DateTime.now())),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: SmallButton('Muscoli', onTap: () => push(context, const MusclesScreen()))),
            const SizedBox(width: 8),
            Expanded(child: SmallButton('Consulenza', accent: true, onTap: () => push(context, const ConsultScreen()))),
          ]),
        ]),
      );
}

/// Le priorità dell'ultima consulenza restano in Oggi per questi giorni.
const priorityDays = 9;

Consult? currentPriorities(AppState app) {
  final c = app.lastConsult;
  return c == null || c.items.isEmpty || daysBetween(fromKey(c.id), today()) > priorityDays ? null : c;
}

/// Le priorità della consulenza, da spuntare.
class PriorityList extends StatelessWidget {
  final Consult consult;
  const PriorityList(this.consult, {super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    return Column(children: [
      for (var i = 0; i < consult.items.length; i++)
        Tap(
          radius: 10,
          onTap: () => app.saveConsult(consult.toggle(i)),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(consult.done.contains(i) ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                  size: 22, color: consult.done.contains(i) ? TC.accent : t.dim),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Text(consult.items[i],
                      style: TextStyle(fontSize: 13.5, height: 1.4, color: consult.done.contains(i) ? t.dim : t.ink)),
                ),
              ),
            ]),
          ),
        ),
    ]);
  }
}

/// In Oggi: le priorità della settimana.
class PrioritiesCard extends StatelessWidget {
  final Consult consult;
  const PrioritiesCard(this.consult, {super.key});
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    return TCard(
      margin: const EdgeInsets.only(top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Label('Priorità della settimana · ${consult.done.length}/${consult.items.length}')),
          Tap(
            radius: 6,
            onTap: () => push(context, const ConsultScreen()),
            child: Text('Consulenza ›', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: t.accentInk)),
          ),
        ]),
        const SizedBox(height: 6),
        PriorityList(consult),
      ]),
    );
  }
}

/// Consulenza: copi i dati per l'assistente, incolli la risposta e le sue
/// priorità diventano la lista della settimana.
class ConsultScreen extends StatefulWidget {
  const ConsultScreen({super.key});
  @override
  State<ConsultScreen> createState() => _ConsultScreenState();
}

class _ConsultScreenState extends State<ConsultScreen> {
  int days = 14;
  String question = '';

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: consultText(context.appRead, days: days, question: question)));
    if (mounted) toast(context, 'Copiato: incollalo in una chat con Claude');
  }

  Future<void> _paste() async {
    final app = context.appRead;
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim() ?? '';
    if (!mounted) return;
    // se negli appunti ci sono ancora i dati copiati, la risposta non è stata copiata
    if (text.isEmpty || text.startsWith('# Consulenza Tigert')) {
      toast(context, 'Copia prima la risposta di Claude, poi torna qui');
      return;
    }
    final items = parsePriorities(text);
    if (items.isEmpty) {
      toast(context, 'Non trovo le priorità numerate nella risposta');
      return;
    }
    app.saveConsult(Consult(id: todayKey(), reply: text, items: items));
    toast(context, '${items.length} priorità salvate: le trovi in Oggi');
  }

  void _showReply(Consult c) => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          maxChildSize: 0.95,
          builder: (ctx, scroll) => SingleChildScrollView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 22),
            child: SelectableText(c.reply, style: TextStyle(fontSize: 14, height: 1.5, color: ctx.tt.ink)),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final c = app.lastConsult;
    return SubPage(
      title: 'Consulenza',
      bottom: BottomActions(children: [
        GhostButton('Incolla la risposta', onTap: _paste),
        PrimaryButton('Copia per Claude', onTap: _copy),
      ]),
      body: PageBody(children: [
        Text(
          'Copia i tuoi dati, incollali in una chat con Claude e riporta qui la risposta: le sue tre priorità diventano la lista della settimana in Oggi.',
          style: TS.muted(t, 12.5),
        ),
        const SectionLabel('Bilancio di questa settimana'),
        TCard(child: BalanceRows(weekBalance(app, DateTime.now()))),
        const SectionLabel('Dati da copiare'),
        Row(children: [
          for (final d in consultDays) ...[
            PillChip('$d giorni', selected: days == d, onTap: () => setState(() => days = d)),
            const SizedBox(width: 8),
          ],
        ]),
        const SizedBox(height: 10),
        RowTile(
          leading: Icon(Icons.help_outline_rounded, size: 20, color: t.dim),
          title: question.isEmpty ? 'Aggiungi una domanda' : question,
          subtitle: question.isEmpty ? 'Facoltativa: un dubbio, un dolore, un cambio di scheda' : null,
          trailing: Icon(Icons.chevron_right_rounded, size: 18, color: t.dim),
          onTap: () async {
            final v = await askText(context, title: 'La tua domanda', initial: question, hint: 'es. Conviene passare a 2 sedute?', lines: 4);
            if (v != null) setState(() => question = v);
          },
        ),
        if (c != null && c.items.isNotEmpty) ...[
          SectionLabel(
            'Priorità · ${relDay(fromKey(c.id)).toLowerCase()}',
            trailing: Tap(
              radius: 6,
              onTap: () => _showReply(c),
              child: Text('Rileggi la risposta ›', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: t.accentInk)),
            ),
          ),
          TCard(child: PriorityList(c)),
        ],
      ]),
    );
  }
}
