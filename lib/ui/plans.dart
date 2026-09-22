import 'package:flutter/material.dart';

import '../core/ids.dart';
import '../core/theme.dart';
import '../data/app_state.dart';
import '../data/models.dart';
import 'plan_editor.dart';
import 'shell.dart';
import 'training.dart';
import 'widgets.dart';

String planSubtitle(Plan p) {
  final days = p.days.map((d) => d.name).join(' / ');
  return [
    '${p.days.length} ${p.days.length == 1 ? 'giorno' : 'giorni'}${p.cycle > 1 ? ' · ciclo di ${p.cycle} settimane' : ''}',
    if (days.isNotEmpty) days,
  ].join('\n');
}

/// Elimina una o più schede, con conferma. Se tra queste c'è quella attiva
/// chiede quale attivare al suo posto. Ritorna true se ha eliminato.
Future<bool> deletePlansFlow(BuildContext context, List<String> ids) async {
  final app = context.appRead;
  final plans = ids.map(app.plan).whereType<Plan>().toList();
  if (plans.isEmpty) return false;
  final activeId = app.activePlan?.id;
  final ok = await confirm(
    context,
    title: plans.length == 1 ? 'Eliminare "${plans.single.name}"?' : 'Eliminare ${plans.length} schede?',
    body: 'Le sessioni già fatte restano nello storico e nei progressi.',
    ok: 'Elimina',
    danger: true,
  );
  if (!ok || !context.mounted) return false;
  String? activate;
  final rest = app.plans.where((p) => !ids.contains(p.id)).toList();
  if (ids.contains(activeId) && rest.isNotEmpty) {
    activate = rest.length == 1
        ? rest.single.id
        : await showModalBottomSheet<String>(
            context: context,
            isScrollControlled: true,
            builder: (c) => SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * 0.7),
                child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 0, 20, 16), children: [
                  Text('Quale scheda usi adesso?', style: TS.h2(c.tt)),
                  const SizedBox(height: 10),
                  for (final p in rest)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: RowTile(title: p.name, subtitle: planSubtitle(p), onTap: () => Navigator.pop(c, p.id)),
                    ),
                ]),
              ),
            ),
          );
    if (activate == null) return false; // chiuso senza scegliere: non elimino nulla
  }
  app.store.batch(() {
    for (final id in ids) {
      app.deletePlan(id, activate: activate);
    }
  });
  if (context.mounted) toast(context, plans.length == 1 ? 'Scheda eliminata' : '${plans.length} schede eliminate');
  return true;
}

/// "Le mie schede": attiva, modifica, duplica ed elimina (anche più di una insieme).
class PlansScreen extends StatefulWidget {
  const PlansScreen({super.key});
  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  Set<String>? selected; // null = modalità normale

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final activeId = app.activePlan?.id;
    final plans = [...app.plans]..sort((a, b) => a.id == activeId ? -1 : (b.id == activeId ? 1 : a.name.toLowerCase().compareTo(b.name.toLowerCase())));
    final sel = selected;

    Future<void> onMenu(Plan p, String v) async {
      switch (v) {
        case 'use':
          app.savePlan(p, activate: true);
          toast(context, 'Ora usi "${p.name}"');
        case 'edit':
          push(context, PlanEditorScreen(planId: p.id));
        case 'rename':
          final n = await askText(context, title: 'Nome della scheda', initial: p.name);
          if (n != null && n.isNotEmpty) app.savePlan(p.copyWith(name: n));
        case 'dup':
          app.savePlan(p.duplicate(newId(), newId));
        case 'del':
          await deletePlansFlow(context, [p.id]);
      }
    }

    return SubPage(
      title: sel == null ? 'Le mie schede' : '${sel.length} selezionate',
      actions: [
        if (plans.length > 1)
          TextButton(
            onPressed: () => setState(() => selected = sel == null ? <String>{} : null),
            child: Text(sel == null ? 'Seleziona' : 'Annulla', style: TextStyle(color: t.accentInk, fontWeight: FontWeight.w700)),
          ),
      ],
      bottom: BottomActions(children: [
        if (sel == null)
          PrimaryButton('Nuova scheda', icon: Icons.add_rounded, onTap: () => chooseTemplate(context, templatesOnly: true))
        else
          PrimaryButton(
            sel.isEmpty ? 'Scegli le schede' : 'Elimina ${sel.length}',
            onTap: sel.isEmpty
                ? null
                : () async {
                    if (await deletePlansFlow(context, sel.toList()) && mounted) setState(() => selected = null);
                  },
          ),
      ]),
      body: PageBody(children: [
        if (plans.isEmpty) const EmptyState(emoji: '📋', title: 'Nessuna scheda', body: 'Crea una scheda da un modello o da zero.'),
        for (final p in plans)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: RowTile(
              title: p.name,
              subtitle: planSubtitle(p),
              borderColor: p.id == activeId ? TC.accent : null,
              onTap: sel == null
                  ? () => push(context, PlanEditorScreen(planId: p.id))
                  : () => setState(() => sel.contains(p.id) ? sel.remove(p.id) : sel.add(p.id)),
              onLongPress: sel == null && plans.length > 1 ? () => setState(() => selected = {p.id}) : null,
              trailing: sel != null
                  ? Checkbox(value: sel.contains(p.id), onChanged: (_) => setState(() => sel.contains(p.id) ? sel.remove(p.id) : sel.add(p.id)))
                  : Row(mainAxisSize: MainAxisSize.min, children: [
                      if (p.id == activeId) StatusPill('Attiva', bg: TC.accent.withValues(alpha: 0.15), fg: t.accentInk),
                      PopupMenuButton<String>(
                        icon: Icon(Icons.more_vert_rounded, color: t.dim),
                        onSelected: (v) => onMenu(p, v),
                        itemBuilder: (_) => [
                          if (p.id != activeId) const PopupMenuItem(value: 'use', child: Text('Usa questa scheda')),
                          const PopupMenuItem(value: 'edit', child: Text('Modifica')),
                          const PopupMenuItem(value: 'rename', child: Text('Rinomina')),
                          const PopupMenuItem(value: 'dup', child: Text('Duplica')),
                          const PopupMenuItem(value: 'del', child: Text('Elimina', style: TextStyle(color: TC.danger))),
                        ],
                      ),
                    ]),
            ),
          ),
        if (plans.length > 1 && sel == null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Tieni premuto su una scheda per selezionarne più di una.', style: TS.muted(t, 12)),
          ),
      ]),
    );
  }
}
