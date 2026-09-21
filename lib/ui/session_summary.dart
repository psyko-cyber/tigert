import 'package:flutter/material.dart';

import '../core/fmt.dart';
import '../core/theme.dart';
import '../data/app_state.dart';
import '../logic/training.dart';
import 'session.dart';
import 'shell.dart';
import 'widgets.dart';

class SessionSummaryScreen extends StatelessWidget {
  final String sessionId;
  final bool fresh;
  const SessionSummaryScreen({super.key, required this.sessionId, this.fresh = false});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final s = app.session(sessionId);
    if (s == null) return const SubPage(title: 'Sessione', body: Center(child: Text('Sessione eliminata')));
    final prs = sessionPrs(app, s);
    final rpe = s.avgRpe;
    return SubPage(
      title: fresh ? 'Ottimo lavoro' : shortDateY(fromKey(s.date)),
      actions: [
        PopupMenuButton<String>(
          onSelected: (v) async {
            if (v == 'reopen') {
              app.saveSession(s.copyWith(status: 'active'));
              Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => SessionScreen(sessionId: s.id)));
            } else if (v == 'delete') {
              if (await confirm(context, title: 'Eliminare la sessione?', body: 'Serie, volume e record di questa sessione verranno rimossi.', ok: 'Elimina', danger: true)) {
                app.deleteSession(s.id);
                if (context.mounted) Navigator.pop(context);
              }
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'reopen', child: Text('Riapri e modifica')),
            PopupMenuItem(value: 'delete', child: Text('Elimina sessione')),
          ],
        ),
      ],
      bottom: BottomActions(children: [
        PrimaryButton(fresh ? 'Chiudi e torna a Oggi' : 'Chiudi', onTap: () {
          if (fresh) ShellNav.go(0);
          Navigator.pop(context);
        }),
      ]),
      body: PageBody(children: [
        const Label('Sessione conclusa'),
        const SizedBox(height: 2),
        Text('${s.name} · ${s.duration.inMinutes} min', style: TS.h1(t)),
        const SizedBox(height: 14),
        Row(children: [
          _Kpi('${s.doneSets}', 'serie'),
          const SizedBox(width: 10),
          _Kpi(fInt(s.volume), 'kg volume'),
          const SizedBox(width: 10),
          _Kpi(rpe == null ? '—' : fDec(rpe, 1), 'RPE medio'),
        ]),
        for (final pr in prs)
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: TC.accent, borderRadius: BorderRadius.circular(18)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('NUOVO RECORD', style: TS.label(t, TC.onAccent.withValues(alpha: 0.75))),
              const SizedBox(height: 2),
              Text(
                pr.set.kg > 0 ? '${pr.exName.split(' ').take(3).join(' ')} ${fKg(pr.set.kg)} kg × ${pr.set.reps}' : '${pr.exName} × ${pr.set.reps}',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: TC.onAccent),
              ),
              if (pr.prev != null)
                Text(
                  pr.set.kg > 0 ? '1RM stimato ${fDec(pr.e1rm, 1)} kg · +${fDec(pr.pct, 1)}% sul precedente' : 'Precedente ${fInt(pr.prev!)} ripetizioni',
                  style: TextStyle(fontSize: 13, color: TC.onAccent.withValues(alpha: 0.8)),
                ),
            ]),
          ),
        const SectionLabel('Esercizi'),
        for (final e in s.items)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Builder(builder: (context) {
              final tag = compareTag(app, s, e);
              final done = e.sets.where((x) => x.done).toList();
              final good = tag.startsWith('+') || tag == 'nuovo';
              final bad = tag.startsWith('−') || tag == 'saltato';
              return RowTile(
                title: e.name,
                subtitle: done.isEmpty
                    ? 'Nessuna serie fatta'
                    : done.map((x) => e.type == 'k' ? '${x.reps} min' : (x.kg > 0 ? '${fKg(x.kg)}×${x.reps}' : '${x.reps}')).join(' · '),
                trailing: StatusPill(
                  prs.any((p) => p.exId == e.ex) ? 'PR' : tag,
                  bg: prs.any((p) => p.exId == e.ex) || good ? TC.accent.withValues(alpha: 0.15) : (bad ? TC.danger.withValues(alpha: 0.12) : null),
                  fg: prs.any((p) => p.exId == e.ex) || good ? t.accentInk : (bad ? TC.danger : null),
                ),
              );
            }),
          ),
      ]),
    );
  }
}

class _Kpi extends StatelessWidget {
  final String v;
  final String k;
  const _Kpi(this.v, this.k);
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    return Expanded(
      child: TCard(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(v, style: TS.num(t, 24)),
          const SizedBox(height: 2),
          Text(k, style: TS.muted(t, 11)),
        ]),
      ),
    );
  }
}
