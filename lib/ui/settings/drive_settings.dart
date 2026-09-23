import 'package:flutter/material.dart';

import '../../core/fmt.dart';
import '../../core/ids.dart';
import '../../core/theme.dart';
import '../../data/app_state.dart';
import '../../services/drive_backup.dart';
import '../../services/services.dart';
import '../widgets.dart';

String _size(int bytes) => bytes < 1048576 ? '${fInt((bytes / 1024).ceil())} KB' : '${fDec(bytes / 1048576, 1, true)} MB';

/// Stato breve per la lista delle impostazioni.
String driveSummary() {
  final d = Services.drive;
  if (!DriveBackup.available) return 'Non disponibile';
  if (!d.on) return 'Spento';
  if (d.error != null) return 'Da ricontrollare';
  final l = d.lastBackup;
  return l == null ? 'Collegato' : 'Ultimo ${relDay(l).toLowerCase()} ${hhmm(l)}';
}

/// Backup su Google Drive: collega l'account con un tocco, poi va da solo.
class DriveSettingsScreen extends StatefulWidget {
  final bool fromOnboarding;
  const DriveSettingsScreen({super.key, this.fromOnboarding = false});
  @override
  State<DriveSettingsScreen> createState() => _DriveSettingsScreenState();
}

class _DriveSettingsScreenState extends State<DriveSettingsScreen> {
  DriveBackup get d => Services.drive;

  Future<void> _connect() async {
    try {
      await d.connect();
      if (isDesktop) await Services.desktop?.showWindow();
      if (!mounted) return;
      if (d.error != null) return toast(context, d.error!);
      if (!context.appRead.hasProfile) {
        await _restore();
      } else {
        toast(context, 'Google Drive collegato: primo backup fatto');
      }
    } catch (e) {
      if (isDesktop) await Services.desktop?.showWindow();
      if (mounted) toast(context, '$e');
    }
  }

  Future<void> _backup() async {
    await d.backupNow();
    if (mounted) toast(context, d.error ?? 'Backup fatto');
  }

  Future<void> _restore() async {
    final List<DriveFile> list;
    try {
      list = await d.backups();
    } catch (e) {
      if (mounted) toast(context, '$e');
      return;
    }
    if (!mounted) return;
    if (list.isEmpty) return toast(context, 'Nessun backup su questo account Google');
    final f = await showModalBottomSheet<DriveFile>(
      context: context,
      isScrollControlled: true,
      builder: (c) {
        final t = c.tt;
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.92,
          builder: (c, sc) => ListView(controller: sc, padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
            Text('Scegli il backup', style: TS.h1(t).copyWith(fontSize: 22)),
            Text('Il più recente è in cima', style: TS.muted(t)),
            const SizedBox(height: 12),
            for (final x in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: RowTile(
                  leading: Icon(x.device == 'pc' ? Icons.desktop_windows_outlined : Icons.smartphone_rounded, color: t.dim),
                  title: '${relDay(x.modified)} alle ${hhmm(x.modified)}',
                  subtitle: '${x.device == 'pc' ? 'Dal PC' : 'Dal telefono'} · ${_size(x.size)}',
                  onTap: () => Navigator.pop(c, x),
                  trailing: Icon(Icons.chevron_right_rounded, color: t.dim),
                ),
              ),
          ]),
        );
      },
    );
    if (f == null || !mounted) return;
    final ok = await confirm(
      context,
      title: 'Ripristinare questo backup?',
      body: 'I dati del backup si uniscono a quelli di questo dispositivo: per ogni elemento vince la modifica più recente. Non si cancella niente.',
      ok: 'Ripristina',
    );
    if (!ok || !mounted) return;
    try {
      final n = await d.restore(f);
      if (!mounted) return;
      toast(context, n == 0 ? 'Niente di nuovo nel backup' : '${fInt(n)} elementi ripristinati');
      if (widget.fromOnboarding && context.appRead.hasProfile) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
  }

  Future<void> _disconnect() async {
    final ok = await confirm(
      context,
      title: 'Scollegare Google Drive?',
      body: 'Il backup automatico si ferma su questo dispositivo. I backup già fatti restano sul tuo Drive e puoi ripristinarli ricollegando l\'account.',
      ok: 'Scollega',
      danger: true,
    );
    if (ok) await d.disconnect();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    return ListenableBuilder(
      listenable: d,
      builder: (context, _) {
        final last = d.lastBackup;
        return SubPage(
          title: 'Backup su Google Drive',
          body: PageBody(children: [
            if (!DriveBackup.available)
              const NoteBox(text: 'Il backup su Google Drive non è disponibile in questa versione di Tigert.')
            else if (!d.on) ...[
              TCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(Icons.cloud_done_outlined, color: t.accentInk),
                    const SizedBox(width: 10),
                    Expanded(child: Text('I tuoi dati al sicuro', style: TS.title(t))),
                  ]),
                  const SizedBox(height: 10),
                  for (final line in [
                    'Una copia al giorno di tutti i dati, foto comprese, in automatico.',
                    'In una cartella nascosta del tuo Drive: Tigert non vede gli altri tuoi file.',
                    'Se cambi PC, accedi con lo stesso account e ripristini tutto. Il telefono prende i dati dal PC con la sincronizzazione Wi-Fi.',
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Padding(padding: const EdgeInsets.only(top: 2), child: Icon(Icons.check_rounded, size: 16, color: t.accentInk)),
                        const SizedBox(width: 8),
                        Expanded(child: Text(line, style: TS.body(t))),
                      ]),
                    ),
                ]),
              ),
              const SizedBox(height: 14),
              PrimaryButton(
                context.app.hasProfile ? 'Collega Google Drive' : 'Accedi e cerca i backup',
                icon: Icons.login_rounded,
                busy: d.busy,
                onTap: d.busy ? null : _connect,
              ),
              const NoteBox(text: 'Si apre il browser: scegli il tuo account Google e premi Continua. Poi torna qui. Serve solo la prima volta.'),
            ] else ...[
              TCard(
                borderColor: d.error != null ? TC.danger.withValues(alpha: 0.6) : null,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Label('Collegato'),
                  const SizedBox(height: 4),
                  Text(d.email ?? 'Account Google', style: TS.title(t)),
                  const SizedBox(height: 4),
                  Text(
                    d.progress ??
                        (last == null
                            ? 'Nessun backup ancora'
                            : 'Ultimo backup ${relDay(last).toLowerCase()} alle ${hhmm(last)}${d.lastSize == null ? '' : ' · ${_size(d.lastSize!)}'}'),
                    style: TS.muted(t),
                  ),
                  if (d.error != null) ...[
                    const SizedBox(height: 8),
                    Text(d.error!, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: TC.danger)),
                    if (d.error!.contains('ricollega')) ...[
                      const SizedBox(height: 10),
                      PrimaryButton('Ricollega', dense: true, busy: d.busy, onTap: d.busy ? null : _connect),
                    ],
                  ],
                ]),
              ),
              const SizedBox(height: 12),
              _Row(Icons.cloud_upload_outlined, 'Fai il backup ora', 'Di solito parte da solo una volta al giorno', d.busy ? null : _backup, busy: d.busy),
              _Row(Icons.restore_rounded, 'Ripristina da Google Drive', 'Unisce un backup ai dati attuali', d.busy ? null : _restore),
              _Row(Icons.link_off_rounded, 'Scollega', 'I backup restano sul Drive', d.busy ? null : _disconnect, danger: true),
              NoteBox(
                text: 'Il backup parte da solo una volta al giorno, quando Tigert è aperto (anche nel tray). '
                    'Sul Drive restano gli ultimi ${DriveBackup.keep} giorni. Comprende anche i dati del telefono, se è sincronizzato con il PC.',
              ),
            ],
          ]),
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String title, sub;
  final VoidCallback? onTap;
  final bool busy, danger;
  const _Row(this.icon, this.title, this.sub, this.onTap, {this.busy = false, this.danger = false});
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
        onTap: onTap,
        trailing: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(Icons.chevron_right_rounded, color: t.dim),
      ),
    );
  }
}
