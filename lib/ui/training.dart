import 'package:flutter/material.dart';

import '../core/fmt.dart';
import '../core/theme.dart';
import '../data/app_state.dart';
import '../data/catalog.dart';
import '../data/models.dart';
import '../logic/day_off.dart';
import '../logic/progression.dart';
import '../logic/training.dart';
import 'coach.dart';
import 'day_off.dart';
import 'hevy_import.dart';
import 'plan_editor.dart';
import 'plans.dart';
import 'session.dart';
import 'session_summary.dart';
import 'shell.dart';
import 'volume.dart';
import 'week_report.dart';
import 'widgets.dart';

/// Avvia (o riprende) una sessione per un giorno della scheda.
/// [offPlan]: seduta fuori dal giro della scheda (l'alternativa di un giorno giustificato).
/// [date]: seduta di un giorno passato, compilata a posteriori.
Future<void> startSession(BuildContext context, {PlanDay? day, bool free = false, bool offPlan = false, String? date}) async {
  final app = context.appRead;
  final active = app.activeSession;
  if (active != null) {
    final resume = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Hai una sessione in corso'),
        content: Text('${active.name}: ${active.doneSets}/${active.plannedSets} serie fatte. Vuoi riprenderla o chiuderla e iniziarne una nuova?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Chiudi e nuova')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Riprendi')),
        ],
      ),
    );
    if (resume == null || !context.mounted) return;
    if (resume) {
      await push(context, SessionScreen(sessionId: active.id));
      return;
    }
    if (active.doneSets == 0) {
      app.deleteSession(active.id);
    } else {
      app.saveSession(active.copyWith(status: 'done', end: sessionEnd(active)));
    }
  }
  final plan = app.activePlan;
  final s = buildSession(app, plan: free || offPlan ? null : plan, day: free ? null : day, name: free ? 'Allenamento libero' : null, date: date);
  app.saveSession(s);
  if (context.mounted) await push(context, SessionScreen(sessionId: s.id));
}

/// Seduta di un giorno passato: scegli quale hai fatto e la compili adesso.
Future<void> logPastSession(BuildContext context, String date, WeekSlot? slot) async {
  final app = context.appRead;
  final t = context.tt;
  final planned = slot?.queued ?? slot?.day;
  final days = [?planned, ...?app.activePlan?.days.where((x) => x.id != planned?.id)];
  final pick = await showModalBottomSheet<Object>(
    context: context,
    isScrollControlled: true,
    builder: (c) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * 0.8),
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(8, 18, 8, 12), children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('Che seduta hai fatto ${relDay(fromKey(date)).toLowerCase()}?', style: TS.title(t)),
          ),
          for (final x in days)
            ListTile(
              leading: Icon(Icons.fitness_center_rounded, color: x == planned ? t.accentInk : t.dim),
              title: Text(x.name),
              subtitle: Text(x == planned ? 'In programma · ${x.totalSets} serie' : '${x.totalSets} serie'),
              onTap: () => Navigator.pop(c, x),
            ),
          ListTile(
            leading: Icon(Icons.add_rounded, color: t.dim),
            title: const Text('Allenamento libero'),
            subtitle: const Text('Scegli tu gli esercizi'),
            onTap: () => Navigator.pop(c, 'free'),
          ),
        ]),
      ),
    ),
  );
  if (pick == null || !context.mounted) return;
  await startSession(context, day: pick is PlanDay ? pick : null, free: pick == 'free', date: date);
}

class TrainingScreen extends StatelessWidget {
  const TrainingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final p = app.profile!;
    final plan = app.activePlan;
    if (plan == null || plan.days.isEmpty) {
      return PageBody(children: [
        Text('Allenamento', style: TS.h1(t).copyWith(fontSize: 24)),
        EmptyState(
          emoji: '🏋️',
          title: 'Nessuna scheda',
          body: 'Scegli uno split pronto e modificalo come vuoi, oppure parti da una scheda vuota.',
          action: PrimaryButton('Scegli una scheda', onTap: () => chooseTemplate(context)),
        ),
      ]);
    }
    final slots = weekSchedule(app);
    final vol = weekVolume(app);
    final next = nextSlot(app);
    final active = app.activeSession;
    // oggi giustificato per un dolore: seduta alternativa al posto di quella prevista
    final off = slots.where((x) => x.status == SlotStatus.off && x.date == today() && x.day != null && x.off!.avoid.isNotEmpty).firstOrNull;
    final alt = off == null || active != null ? null : alternativeFor(app, off.date, off.day!, off.off!.avoid);

    return PageBody(children: [
      Row(children: [
        Expanded(child: Text('Settimana ${planWeek(plan)}', style: TS.h1(t).copyWith(fontSize: 24))),
        PopupMenuButton<String>(
          icon: Icon(Icons.more_horiz_rounded, color: t.ink),
          onSelected: (v) {
            switch (v) {
              case 'edit':
                push(context, PlanEditorScreen(planId: plan.id));
              case 'change':
                chooseTemplate(context);
              case 'plans':
                push(context, const PlansScreen());
              case 'free':
                startSession(context, free: true);
              case 'history':
                push(context, const SessionHistoryScreen());
              case 'hevy':
                push(context, const HevyImportScreen());
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit', child: Text('Modifica scheda')),
            PopupMenuItem(value: 'change', child: Text('Cambia scheda')),
            PopupMenuItem(value: 'plans', child: Text('Le mie schede')),
            PopupMenuItem(value: 'free', child: Text('Allenamento libero')),
            PopupMenuItem(value: 'history', child: Text('Storico sessioni')),
            PopupMenuItem(value: 'hevy', child: Text('Importa da Hevy')),
          ],
        ),
      ]),
      Text(
        [
          if (plan.cycle > 1 && next?.day != null) 'Ciclo: settimana ${weekLetter(next!.day!.week)} di ${plan.cycle}',
          '${plan.name} · ${p.trainingDays.length} giorni',
        ].join(' · '),
        style: TS.muted(t),
      ),
      const SizedBox(height: 16),
      if (slots.isEmpty) const NoteBox(text: 'Nessun giorno di allenamento impostato: sceglili in Profilo → Giorni di allenamento.'),
      for (final s in slots)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _SlotRow(slot: s),
        ),
      // seduta rimandata vicino a un'altra con gli stessi muscoli: un consiglio, la scheda non cambia
      for (final s in slots)
        if (s.movedFrom != null && s.day != null && s.session == null && !s.date.isBefore(today()))
          if (moveAdvice(app, s.day!, s.date, from: s.movedFrom) case final a?)
            NoteBox(
              icon: Icons.tips_and_updates_outlined,
              margin: const EdgeInsets.only(bottom: 12),
              text: '${moveAdviceText(a, s.day!.name, s.date)} Per cambiare giorno tocca ${giorni[fromKey(s.movedFrom!).weekday - 1].toLowerCase()}.',
            ),
      TCard(
        margin: const EdgeInsets.only(top: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Label('Volume settimanale'),
          const SizedBox(height: 10),
          Row(children: [
            _Kpi('${vol.done}', 'serie fatte'),
            _Kpi('${vol.planned}', 'previste'),
            _Kpi('${vol.prs}', 'record', accent: vol.prs > 0),
          ]),
        ]),
      ),
      const SizedBox(height: 14),
      const VolumeCard(),
      const WeekReportCard(),
      if (alt != null)
        AlternativeCard(slot: off!, alt: alt)
      else if (active == null && next?.day != null)
        CoachCard(day: next!.day!),
      if (active != null)
        PrimaryButton('Riprendi ${active.name}', icon: Icons.play_arrow_rounded, onTap: () => push(context, SessionScreen(sessionId: active.id)))
      else if (alt != null)
        PrimaryButton('Inizia la seduta alternativa · oggi', onTap: () => startSession(context, day: alt.day, offPlan: true))
      else if (next?.day != null) ...[
        PrimaryButton(
          'Inizia ${next!.day!.name} · ${next.date == today() ? 'oggi' : giorni[next.date.weekday - 1].toLowerCase()}',
          onTap: () => startSession(context, day: next.day),
        ),
        Center(
          child: Tap(
            radius: 8,
            onTap: () => showDayOffSheet(context, next),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
              child: Text('Non riesci a farla${next.date == today() ? ' oggi' : ''}?', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: t.accentInk)),
            ),
          ),
        ),
      ],
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: GhostButton('Modifica scheda', dense: true, onTap: () => push(context, PlanEditorScreen(planId: plan.id)))),
        const SizedBox(width: 10),
        Expanded(child: GhostButton('Storico', dense: true, onTap: () => push(context, const SessionHistoryScreen()))),
      ]),
      const SectionLabel('Sedute della scheda'),
      for (final d in plan.days)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: RowTile(
            title: d.name,
            subtitle: '${plan.cycle > 1 ? 'Settimana ${weekLetter(d.week)} · ' : ''}${d.items.length} esercizi · ${d.totalSets} serie',
            onTap: () => showDayPreview(context, d),
            trailing: Icon(Icons.chevron_right_rounded, color: t.dim),
          ),
        ),
    ]);
  }
}

class _Kpi extends StatelessWidget {
  final String v;
  final String k;
  final bool accent;
  const _Kpi(this.v, this.k, {this.accent = false});
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    return Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(v, style: TS.num(t, 22, color: accent ? t.accentInk : null)),
        Text(k, style: TS.muted(t, 11)),
      ]),
    );
  }
}

class _SlotRow extends StatelessWidget {
  final WeekSlot slot;
  const _SlotRow({required this.slot});
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    final app = context.app;
    final s = slot;
    final isToday = s.status == SlotStatus.today;
    final done = s.status == SlotStatus.done || s.status == SlotStatus.extra;
    final off = s.status == SlotStatus.off;
    final name = s.session?.name ?? s.day?.name ?? 'Seduta saltata';
    final sub = s.session != null
        ? '${s.session!.doneSets}/${s.session!.plannedSets} serie · ${fInt(s.session!.volume)} kg'
        : off
            ? [
                (offReasons[s.off!.off] ?? 'Giustificato').split(' ').first,
                if (s.off!.postponed) 'la fai ${whenLabel(fromKey(s.off!.moveTo!), long: true)}',
                if (s.off!.avoid.isNotEmpty) 'niente ${s.off!.avoid.map((z) => z.toLowerCase()).join(', ')}',
                'non penalizza il voto',
              ].join(' · ')
            : [
                if (s.movedFrom != null) 'Rimandata da ${giorni[fromKey(s.movedFrom!).weekday - 1].toLowerCase()}',
                s.day != null
                    ? '${s.day!.items.take(4).map((i) => app.exerciseName(i.ex).split(' ').first).join(', ')} · ${s.day!.totalSets} serie'
                    : 'La seduta resta in coda · tocca per giustificare',
              ].join(' · ');
    return TCard(
      borderColor: isToday ? TC.accent : null,
      padding: const EdgeInsets.all(14),
      onTap: () {
        if (s.session != null) {
          if (s.session!.isActive) {
            push(context, SessionScreen(sessionId: s.session!.id));
          } else {
            push(context, SessionSummaryScreen(sessionId: s.session!.id));
          }
        } else if (off || s.status == SlotStatus.missed) {
          showDayOffSheet(context, s);
        } else if (s.day != null) {
          showDayPreview(context, s.day!, slot: s);
        }
      },
      child: Row(children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(color: done ? TC.accent : t.surf2, borderRadius: BorderRadius.circular(12)),
          alignment: Alignment.center,
          child: Text(giorniSigla[s.date.weekday - 1], style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: done ? TC.onAccent : t.ink)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: s.status == SlotStatus.missed || off ? t.dim : t.ink)),
            const SizedBox(height: 2),
            Text(sub, style: TS.muted(t, 12), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
        StatusPill(
          s.statusLabel,
          bg: done ? TC.accent.withValues(alpha: 0.15) : (isToday ? TC.accent : null),
          fg: done ? t.accentInk : (isToday ? TC.onAccent : (s.status == SlotStatus.missed ? TC.danger : null)),
        ),
      ]),
    );
  }
}

/// Anteprima di una seduta con i carichi suggeriti.
/// [slot]: la seduta in calendario, per poterla giustificare. [offPlan]: seduta fuori dal giro.
Future<void> showDayPreview(BuildContext context, PlanDay day, {WeekSlot? slot, bool offPlan = false}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (c) {
      final app = c.app;
      final t = c.tt;
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.92,
        builder: (c, sc) => ListView(controller: sc, padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
          Text(day.name, style: TS.h1(t).copyWith(fontSize: 22)),
          Text('${day.items.length} esercizi · ${day.totalSets} serie', style: TS.muted(t)),
          const SizedBox(height: 12),
          for (final it in day.items) ...[
            Builder(builder: (c) {
              final sug = suggestFor(app, it);
              final ex = app.exercise(it.ex);
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: RowTile(
                  title: ex?.name ?? it.ex,
                  subtitle: '${it.scheme} ${ex?.repsLabel ?? 'rip'} · RPE ${fDec(it.rpe, 1, true)} · recupero ${fMinutes((it.rest / 60).round()).replaceAll(' min', "'")}'
                      '${sug.kg > 0 ? '\n${sug.kind == AdviceKind.increase ? '↑ ' : (sug.kind == AdviceKind.lighter || sug.kind == AdviceKind.deload ? '↓ ' : '')}${fKg(sug.kg)} kg × ${sug.reps}' : ''}',
                ),
              );
            }),
          ],
          const SizedBox(height: 8),
          PrimaryButton(offPlan ? 'Inizia la seduta alternativa' : 'Inizia ${day.name}', onTap: () {
            Navigator.pop(c);
            startSession(context, day: day, offPlan: offPlan);
          }),
          if (slot != null) ...[
            const SizedBox(height: 10),
            GhostButton('Non riesco a farla', onTap: () {
              Navigator.pop(c);
              showDayOffSheet(context, slot);
            }),
          ],
        ]),
      );
    },
  );
}

/// Scelta di uno split pronto (crea una nuova scheda e la attiva).
/// Cambia scheda: prima quelle già salvate, poi i modelli (che creano una scheda nuova).
Future<void> chooseTemplate(BuildContext context, {bool templatesOnly = false}) async {
  final app = context.appRead;
  final days = app.profile?.trainingDays.length ?? 3;
  final suggested = suggestTemplate(days);
  final activeId = app.activePlan?.id;
  final saved = templatesOnly ? const <Plan>[] : app.plans;
  final key = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (c) {
      final t = c.tt;
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.92,
        builder: (c, sc) => ListView(controller: sc, padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
          Text(templatesOnly ? 'Nuova scheda' : 'Scegli una scheda', style: TS.h1(t).copyWith(fontSize: 22)),
          if (saved.isNotEmpty) ...[
            const SectionLabel('Le tue schede'),
            for (final p in saved)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: RowTile(
                  title: '${p.name}${p.id == activeId ? ' · attiva' : ''}',
                  subtitle: planSubtitle(p),
                  borderColor: p.id == activeId ? TC.accent : null,
                  onTap: () => Navigator.pop(c, 'plan:${p.id}'),
                ),
              ),
            const SectionLabel('Oppure crea una scheda nuova da un modello'),
          ],
          Text('Con $days giorni a settimana ti consiglio: ${suggested.name}.', style: TS.muted(t)),
          const SizedBox(height: 12),
          for (final tpl in splitTemplates)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: RowTile(
                title: '${tpl.name}${tpl.key == suggested.key ? ' · consigliata' : ''}',
                subtitle: '${tpl.desc}\n${tpl.days.map((d) => d.$1).join(' · ')}',
                borderColor: tpl.key == suggested.key ? TC.accent : null,
                onTap: () => Navigator.pop(c, tpl.key),
              ),
            ),
          RowTile(title: 'Scheda vuota', subtitle: 'Costruisci tutto da zero con l\'editor.', onTap: () => Navigator.pop(c, 'empty')),
        ]),
      );
    },
  );
  if (key == null || !context.mounted) return;
  if (key.startsWith('plan:')) {
    final p = app.plan(key.substring(5));
    if (p != null) app.savePlan(p, activate: true);
    return;
  }
  final plan = key == 'empty' ? emptyPlan() : templateByKey(key).toPlan();
  app.savePlan(plan, activate: true);
  if (key == 'empty' && context.mounted) push(context, PlanEditorScreen(planId: plan.id));
}

class SessionHistoryScreen extends StatelessWidget {
  const SessionHistoryScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final list = app.doneSessions.reversed.toList();
    return SubPage(
      title: 'Storico sessioni',
      body: PageBody(children: [
        if (list.isEmpty) const EmptyState(emoji: '📒', title: 'Ancora nessuna sessione', body: 'Le sessioni completate appariranno qui con volume e record.'),
        for (final s in list)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: RowTile(
              leading: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: t.surf2, borderRadius: BorderRadius.circular(12)),
                alignment: Alignment.center,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('${fromKey(s.date).day}', style: TS.num(t, 16)),
                  Text(mesiBrevi[fromKey(s.date).month - 1], style: TS.muted(t, 10)),
                ]),
              ),
              title: s.name,
              subtitle: '${s.doneSets} serie · ${fInt(s.volume)} kg · ${s.duration.inMinutes} min',
              onTap: () => push(context, SessionSummaryScreen(sessionId: s.id)),
            ),
          ),
      ]),
    );
  }
}
