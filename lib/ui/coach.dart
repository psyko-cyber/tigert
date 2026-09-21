import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/app_state.dart';
import '../data/models.dart';
import '../logic/progression.dart';
import 'widgets.dart';

/// Card "Coach": cosa cambia nella prossima seduta (carichi da alzare o
/// abbassare) e l'obiettivo di ripetizioni per il resto.
class CoachCard extends StatelessWidget {
  final PlanDay day;
  final String? heading;
  final EdgeInsets margin;
  const CoachCard({super.key, required this.day, this.heading, this.margin = const EdgeInsets.only(top: 4, bottom: 14)});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final list = dayAdvice(app, day);
    if (list.isEmpty) return const SizedBox.shrink();
    final changes = list.where((a) => a.isChange).toList();
    final reps = list.where((a) => a.kind == AdviceKind.reps).length;
    final first = list.where((a) => a.kind == AdviceKind.first).length;
    return Container(
      margin: margin,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: t.accentTint, borderRadius: BorderRadius.circular(18), border: Border.all(color: t.accentLine)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.trending_up_rounded, size: 18, color: t.accentInk),
          const SizedBox(width: 8),
          Expanded(child: Text((heading ?? 'Coach · ${day.name}').toUpperCase(), style: TS.label(t, t.accentInk))),
        ]),
        const SizedBox(height: 10),
        if (changes.isEmpty)
          Text(
            first == list.length
                ? 'Prima volta con questa seduta: scegli carichi con cui arrivi al range di ripetizioni indicato.'
                : 'Nessun carico da cambiare: stessi pesi della volta scorsa, punta a una ripetizione in più per serie.',
            style: TextStyle(fontSize: 13, color: t.ink, height: 1.4),
          )
        else
          for (final a in changes)
            Tap(
              radius: 10,
              onTap: () => showAdvice(context, a),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  _Arrow(up: a.kind == AdviceKind.increase),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(a.exName, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: t.ink), maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(a.title, style: TS.muted(t, 11.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  Text(a.badge.replaceFirst(RegExp(r'^[↑↓] '), ''), style: TS.num(t, 15, w: FontWeight.w800)),
                ]),
              ),
            ),
        if (changes.isNotEmpty && reps > 0) ...[
          const SizedBox(height: 6),
          Text('Altri $reps: stesso carico, una ripetizione in più.', style: TS.muted(t, 12)),
        ],
      ]),
    );
  }
}

class _Arrow extends StatelessWidget {
  final bool up;
  const _Arrow({required this.up});
  @override
  Widget build(BuildContext context) => Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(color: up ? TC.accent : TC.warn.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
        child: Icon(up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 17, color: up ? TC.onAccent : TC.warn),
      );
}

Future<void> showAdvice(BuildContext context, Advice a) {
  final t = context.tt;
  return showModalBottomSheet(
    context: context,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 4, 22, 22),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(a.exName, style: TS.h2(t)),
          const SizedBox(height: 4),
          Text(a.title, style: TS.label(t, t.accentInk)),
          const SizedBox(height: 10),
          Text(a.text, style: TextStyle(fontSize: 14.5, color: t.ink, height: 1.45)),
          const SizedBox(height: 14),
          Text(
            'Come funziona: lavori in un range di ripetizioni (es. 8-12). Quando fai tutte le serie al massimo del range senza superare '
            'l\'RPE indicato, alzi il carico del minimo incremento e riparti dal basso. Se resti fermo per 3 sedute, scarichi del 10% e risali.',
            style: TS.muted(t, 12),
          ),
        ]),
      ),
    ),
  );
}
