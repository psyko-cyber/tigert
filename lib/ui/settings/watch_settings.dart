import 'package:flutter/material.dart';

import '../../core/fmt.dart';
import '../../core/theme.dart';
import '../../services/services.dart';
import '../../services/watch.dart';
import '../widgets.dart';

/// Riga del Profilo: stato del collegamento con l'orologio.
String watchSummary(WatchService w) {
  if (!w.enabled) return 'Non collegato';
  final at = w.lastAt;
  return at == null ? 'Collegato' : 'Letto ${relDay(at).toLowerCase()} ${hhmm(at)}';
}

class WatchSettingsScreen extends StatefulWidget {
  const WatchSettingsScreen({super.key});
  @override
  State<WatchSettingsScreen> createState() => _WatchSettingsScreenState();
}

class _WatchSettingsScreenState extends State<WatchSettingsScreen> {
  WatchService get w => Services.watch!;
  String status = 'ok';
  bool working = false;
  late final AppLifecycleListener _life;

  @override
  void initState() {
    super.initState();
    // tornando dalla schermata dei permessi rileggo cosa è stato concesso
    _life = AppLifecycleListener(onResume: _load);
    _load();
  }

  @override
  void dispose() {
    _life.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await w.source!.status();
      if (mounted) setState(() => status = s);
    } catch (_) {
      if (mounted) setState(() => status = 'no');
    }
    await w.refreshPermissions();
  }

  Future<void> _connect() async {
    setState(() => working = true);
    final ok = await w.connect();
    if (!mounted) return;
    setState(() => working = false);
    toast(context, ok ? 'Orologio collegato' : (w.error ?? 'Nessun permesso concesso: Tigert non può leggere i dati.'));
  }

  Future<void> _read() async {
    final n = await w.sync(force: true);
    if (!mounted) return;
    toast(context, w.error ?? (n == 0 ? 'Niente di nuovo dall\'orologio' : (n == 1 ? '1 dato aggiornato' : '$n dati aggiornati')));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    return ListenableBuilder(
      listenable: w,
      builder: (context, _) => SubPage(
        title: 'Orologio e salute',
        body: PageBody(children: [
          Text(
            'Tigert legge passi, sonno, peso e allenamenti da Health Connect, dove li scrive l\'app del tuo orologio '
            '(Fitbit, Pixel Watch, Samsung Health, Garmin...). Li trovi già compilati quando apri l\'app.',
            style: TS.soft(t, 13.5),
          ),
          const SizedBox(height: 14),
          if (status != 'ok')
            TCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(status == 'install' ? 'Health Connect va installato o aggiornato' : 'Health Connect non è disponibile su questo telefono', style: TS.body(t)),
                if (status == 'install') ...[
                  const SizedBox(height: 10),
                  PrimaryButton('Apri il Play Store', dense: true, onTap: () => w.source!.install()),
                ],
              ]),
            )
          else ...[
            TCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.watch_rounded, size: 20, color: w.enabled ? t.accentInk : t.dim),
                  const SizedBox(width: 10),
                  Expanded(child: Text(w.enabled ? 'Collegato' : 'Non collegato', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: t.ink))),
                  if (w.enabled && w.lastAt != null) Text('${relDay(w.lastAt!).toLowerCase()} ${hhmm(w.lastAt!)}', style: TS.muted(t, 12.5)),
                ]),
                if (w.enabled) ...[
                  const SizedBox(height: 12),
                  for (final e in watchKinds.entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(children: [
                        Icon(w.granted[e.key] == true ? Icons.check_circle_rounded : Icons.remove_circle_outline_rounded,
                            size: 16, color: w.granted[e.key] == true ? t.accentInk : t.dim),
                        const SizedBox(width: 8),
                        Text(e.value, style: TextStyle(fontSize: 13.5, color: t.soft)),
                        const Spacer(),
                        if (w.granted[e.key] != true) Text('permesso non dato', style: TS.muted(t, 12)),
                      ]),
                    ),
                ],
                const SizedBox(height: 10),
                if (!w.enabled)
                  PrimaryButton('Collega', icon: Icons.link_rounded, dense: true, busy: working, onTap: _connect)
                else
                  Row(children: [
                    Expanded(child: PrimaryButton('Leggi ora', dense: true, busy: w.busy, onTap: _read)),
                    const SizedBox(width: 10),
                    Expanded(child: GhostButton('Permessi', dense: true, onTap: _connect)),
                  ]),
              ]),
            ),
            if (w.error != null) NoteBox(icon: Icons.error_outline_rounded, text: w.error),
            if (w.enabled) ...[
              const SizedBox(height: 10),
              GhostButton('Scollega', onTap: () {
                w.disconnect();
                toast(context, 'Orologio scollegato: i dati già letti restano');
              }),
            ],
          ],
          const SectionLabel('Come funziona'),
          const NoteBox(
            margin: EdgeInsets.zero,
            child: Text(
              '• Passi e sonno si aggiornano da soli. Se li scrivi a mano, quel giorno vale il tuo valore.\n'
              '• Il peso entra solo nei giorni in cui non l\'hai già registrato.\n'
              '• Corsa, camminata, bici e gli altri sport diventano attività extra con le calorie dell\'orologio. '
              'Gli allenamenti con i pesi no: sono già le tue sedute.\n'
              '• Tigert legge quando lo apri e ogni 5 minuti mentre è aperto. Vede solo quello che l\'app dell\'orologio '
              'ha già passato a Health Connect: se un dato manca, apri prima quella app.',
            ),
          ),
          const NoteBox(
            icon: Icons.lock_outline_rounded,
            text: 'I dati restano sul telefono e sul tuo PC abbinato. Tigert legge soltanto: non scrive nulla in Health Connect.',
          ),
        ]),
      ),
    );
  }
}
