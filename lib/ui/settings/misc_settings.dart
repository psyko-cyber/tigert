import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/fmt.dart';
import '../../core/ids.dart';
import '../../core/theme.dart';
import '../../data/app_state.dart';
import '../../services/desktop.dart';
import '../../services/files.dart';
import '../../services/services.dart';
import '../widgets.dart';

// =================================================================== abitudini

class HabitsSettingsScreen extends StatelessWidget {
  const HabitsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final p = app.profile!;

    void toggle(String k, bool v) => app.saveProfile(p.copyWith(habits: {...p.habits, k: v}));

    Widget item(String k, String title, String sub, {String? target, VoidCallback? onTarget}) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: TCard(
            radius: 14,
            padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.habitOn(k) ? t.ink : t.dim)),
                  Text(sub, style: TS.muted(t, 11.5)),
                ]),
              ),
              if (target != null) Opacity(opacity: p.habitOn(k) ? 1 : 0.4, child: SmallButton(target, onTap: onTarget)),
              const SizedBox(width: 4),
              Switch(value: p.habitOn(k), onChanged: (v) => toggle(k, v)),
            ]),
          ),
        );

    return SubPage(
      title: 'Abitudini nel voto',
      body: PageBody(children: [
        Text(
          'Le abitudini valgono il 15% del voto giornaliero. Quelle spente non contano e non compaiono nella schermata Oggi.',
          style: TS.soft(t, 13),
        ),
        const SizedBox(height: 14),
        item('water', 'Acqua', 'Obiettivo giornaliero', target: '${fDec(p.waterMl / 1000, 2, true)} L', onTarget: () async {
          final v = await askNumber(context, title: 'Obiettivo acqua', initial: p.waterMl / 1000, unit: 'L', decimals: 2, min: 0.5, max: 6);
          if (v != null) app.saveProfile(p.copyWith(waterMl: (v * 1000 / 50).round() * 50));
        }),
        item('sleep', 'Sonno', 'Ore dormite la notte prima', target: fMinutes(p.sleepMin), onTarget: () async {
          final v = await askNumber(context, title: 'Obiettivo sonno', initial: p.sleepMin / 60, unit: 'ore', decimals: 1, min: 4, max: 12);
          if (v != null) app.saveProfile(p.copyWith(sleepMin: (v * 60 / 15).round() * 15));
        }),
        item('steps', 'Passi', 'Inseriti a mano la sera', target: fInt(p.steps), onTarget: () async {
          final v = await askNumber(context, title: 'Obiettivo passi', initial: p.steps.toDouble(), decimals: 0, min: 1000, max: 40000);
          if (v != null) app.saveProfile(p.copyWith(steps: (v / 500).round() * 500));
        }),
        item('alcohol', 'Alcol', '0 bicchieri = punteggio pieno, poi scende'),
        const SectionLabel('Integratori'),
        Text('Da spuntare ogni giorno in Oggi, con i giorni di fila. Non contano nel voto.', style: TS.soft(t, 13)),
        const SizedBox(height: 10),
        item('supp', p.supplements.isEmpty ? 'Nessun integratore' : p.supplements.join(', '), 'Separali con una virgola, es. Creatina, Vitamina D',
            target: 'Modifica', onTarget: () async {
          final v = await askText(context, title: 'Integratori da seguire', initial: p.supplements.join(', '), hint: 'es. Creatina, Vitamina D');
          if (v != null) {
            final list = v.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList();
            app.saveProfile(p.copyWith(supplements: list));
          }
        }),
      ]),
    );
  }
}

// =================================================================== Windows

class DesktopSettingsScreen extends StatefulWidget {
  const DesktopSettingsScreen({super.key});
  @override
  State<DesktopSettingsScreen> createState() => _DesktopSettingsScreenState();
}

class _DesktopSettingsScreenState extends State<DesktopSettingsScreen> {
  bool? autostart;

  @override
  void initState() {
    super.initState();
    DesktopService.isAutostart().then((v) {
      if (mounted) setState(() => autostart = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    final app = context.app;
    return SubPage(
      title: 'Windows',
      body: PageBody(children: [
        TCard(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
          child: Column(children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: autostart ?? false,
              title: Text('Avvia con Windows', style: TS.body(t).copyWith(fontWeight: FontWeight.w600)),
              subtitle: Text('Parte nascosto nell\'area di notifica: promemoria e sincronizzazione sempre pronti', style: TS.muted(t, 12)),
              onChanged: autostart == null
                  ? null
                  : (v) async {
                      final ok = await DesktopService.setAutostart(v);
                      if (!mounted) return;
                      setState(() => autostart = ok ? v : autostart);
                      if (!ok) toast(this.context, 'Non sono riuscito a cambiare l\'avvio automatico');
                    },
            ),
            Divider(color: t.line, height: 1),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: app.prefs.trayEnabled,
              title: Text('Chiudi nell\'area di notifica', style: TS.body(t).copyWith(fontWeight: FontWeight.w600)),
              subtitle: Text(
                app.prefs.trayEnabled
                    ? 'La X nasconde la finestra: Tigert resta attivo vicino all\'orologio. Per uscire: tasto destro sull\'icona → Esci.'
                    : 'La X chiude Tigert: niente promemoria né sincronizzazione finché non lo riapri.',
                style: TS.muted(t, 12),
              ),
              onChanged: (v) => app.prefs.trayEnabled = v,
            ),
          ]),
        ),
        const SizedBox(height: 12),
        if (Services.desktop != null) GhostButton('Esci da Tigert', icon: Icons.power_settings_new_rounded, onTap: () => Services.desktop!.quit()),
      ]),
    );
  }
}

// =================================================================== dati

class DataSettingsScreen extends StatefulWidget {
  const DataSettingsScreen({super.key});
  @override
  State<DataSettingsScreen> createState() => _DataSettingsScreenState();
}

class _DataSettingsScreenState extends State<DataSettingsScreen> {
  String? busy;

  Future<void> _run(String key, Future<String?> Function() job) async {
    setState(() => busy = key);
    try {
      final msg = await job();
      if (mounted && msg != null) toast(context, msg);
    } catch (e) {
      if (mounted) toast(context, 'Operazione non riuscita: $e');
    } finally {
      if (mounted) setState(() => busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    final app = context.app;
    return SubPage(
      title: 'Esporta e backup',
      body: PageBody(children: [
        const SectionLabel('Esporta'),
        _Action(
          icon: Icons.table_chart_outlined,
          title: 'Esporta in CSV',
          sub: 'Diario, peso, abitudini, allenamenti e voti: si aprono con Excel',
          busy: busy == 'csv',
          onTap: () => _run('csv', () async {
            final r = await exportCsv(app);
            if (r == null) return null;
            return isDesktop ? 'CSV salvati in $r' : null;
          }),
        ),
        const SectionLabel('Backup'),
        _Action(
          icon: Icons.save_alt_rounded,
          title: 'Crea backup',
          sub: 'Un file .json con tutti i dati (foto escluse)',
          busy: busy == 'backup',
          onTap: () => _run('backup', () async {
            final r = await exportBackup(app);
            if (r == null) return null;
            return isDesktop ? 'Backup salvato' : null;
          }),
        ),
        _Action(
          icon: Icons.restore_rounded,
          title: 'Ripristina backup',
          sub: 'Unisce il backup ai dati attuali: vince la modifica più recente',
          busy: busy == 'restore',
          onTap: () => _run('restore', () async {
            final n = await importBackup(app);
            if (n == null) return null;
            return n == 0 ? 'Niente di nuovo nel backup' : '${fInt(n)} elementi ripristinati';
          }),
        ),
        const NoteBox(
          icon: Icons.info_outline_rounded,
          text: 'Con la sincronizzazione Wi-Fi attiva il PC ha già una copia completa dei dati del telefono (foto comprese).',
        ),
        const SectionLabel('Zona pericolosa'),
        _Action(
          icon: Icons.delete_forever_outlined,
          title: 'Cancella tutti i dati',
          sub: 'Riparti da zero su questo dispositivo',
          danger: true,
          busy: busy == 'wipe',
          onTap: () async {
            final ok = await confirm(
              context,
              title: 'Cancellare tutto?',
              body: 'Profilo, diario, pesate, allenamenti e foto verranno eliminati da questo dispositivo. '
                  'Se è abbinato al PC, verrà anche scollegato. L\'operazione non si può annullare.',
              ok: 'Cancella tutto',
              danger: true,
            );
            if (!ok || !context.mounted) return;
            await _run('wipe', () async {
              Services.sync.unpair();
              app.prefs.seenBadges = [];
              app.prefs.badgesInitialized = false;
              app.prefs.restEndsAt = null;
              await app.store.wipe();
              return null;
            });
            if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
          },
        ),
        const SizedBox(height: 8),
        Text('Dati salvati in: ${app.store.root.path}', style: TS.muted(t, 11)),
      ]),
    );
  }
}

class _Action extends StatelessWidget {
  final IconData icon;
  final String title, sub;
  final VoidCallback onTap;
  final bool busy, danger;
  const _Action({required this.icon, required this.title, required this.sub, required this.onTap, this.busy = false, this.danger = false});
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RowTile(
        leading: Icon(icon, color: danger ? TC.danger : t.dim),
        title: title,
        titleStyle: danger ? const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: TC.danger) : null,
        subtitle: sub,
        onTap: busy ? null : onTap,
        trailing: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(Icons.chevron_right_rounded, color: t.dim),
      ),
    );
  }
}

// =================================================================== informazioni

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    Widget link(String label, String url) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: RowTile(
            title: label,
            subtitle: url.replaceFirst('https://', ''),
            trailing: Icon(Icons.open_in_new_rounded, size: 18, color: t.dim),
            onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
          ),
        );
    return SubPage(
      title: 'Informazioni',
      body: PageBody(children: [
        const SizedBox(height: 8),
        const Center(child: TigertMark(size: 84)),
        const SizedBox(height: 12),
        Center(child: Text('Tigert', style: TS.h1(t))),
        Center(child: Text('Versione $appVersion ($appBuild)', style: TS.muted(t, 12.5))),
        const SizedBox(height: 6),
        Center(child: Text('Forza di volontà, obiettivo nel mirino.', style: TS.soft(t, 13))),
        const SectionLabel('Progetto'),
        link('Codice e aggiornamenti', 'https://github.com/$githubRepo'),
        link('Segnala un problema', 'https://github.com/$githubRepo/issues'),
        const SectionLabel('Crediti'),
        link('Open Food Facts · dati prodotti (ODbL)', 'https://world.openfoodfacts.org'),
        link('Font Archivo (SIL Open Font License)', 'https://fonts.google.com/specimen/Archivo'),
        link('Google Gemini · stima dalle foto', 'https://ai.google.dev'),
        const NoteBox(
          icon: Icons.health_and_safety_outlined,
          text: 'Tigert dà stime e indicazioni generali su alimentazione e allenamento: non sostituisce il parere di un medico, '
              'di un nutrizionista o di un preparatore. Le calorie stimate dalle foto possono avere errori anche del 20-30%.',
        ),
      ]),
    );
  }
}
