import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/fmt.dart';
import '../../core/ids.dart';
import '../../core/theme.dart';
import '../../data/app_state.dart';
import '../../services/services.dart';
import '../../services/sync.dart';
import '../barcode.dart';
import '../shell.dart';
import '../widgets.dart';

class SyncSettingsScreen extends StatelessWidget {
  final bool fromOnboarding;
  const SyncSettingsScreen({super.key, this.fromOnboarding = false});

  @override
  Widget build(BuildContext context) {
    return SubPage(
      title: 'Sincronizzazione Wi-Fi',
      body: ListenableBuilder(
        listenable: Services.sync,
        builder: (context, _) => isDesktop ? const _ServerView() : _ClientView(fromOnboarding: fromOnboarding),
      ),
    );
  }
}

// =================================================================== PC (server)

class _ServerView extends StatelessWidget {
  const _ServerView();

  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    final app = context.app;
    final s = Services.sync;
    final peers = app.prefs.peers.entries.toList()
      ..sort((a, b) => ((b.value as Map)['at'] as num? ?? 0).compareTo((a.value as Map)['at'] as num? ?? 0));

    return PageBody(children: [
      Text(
        'Il PC fa da "casa" dei dati: il telefono si collega qui quando siete sulla stessa rete Wi-Fi. '
        'Niente cloud, niente account: i dati passano solo sulla tua rete.',
        style: TS.soft(t, 13),
      ),
      const SizedBox(height: 12),
      TCard(
        padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
        child: SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: s.serverRunning,
          title: Text('Sincronizzazione attiva', style: TS.body(t).copyWith(fontWeight: FontWeight.w600)),
          subtitle: Text(
            s.serverRunning ? 'In ascolto sulla porta ${SyncService.port}' : 'Il telefono non potrà sincronizzarsi',
            style: TS.muted(t, 12),
          ),
          onChanged: (v) async {
            app.prefs.serverEnabled = v;
            v ? await s.startServer() : await s.stopServer();
          },
        ),
      ),
      if (s.serverError != null) NoteBox(icon: Icons.error_outline_rounded, child: Text(s.serverError!, style: const TextStyle(color: TC.danger))),
      if (s.serverRunning) ...[
        const SectionLabel('Abbina il telefono'),
        TCard(
          child: LayoutBuilder(builder: (context, c) {
            final wide = c.maxWidth > 520;
            final qr = Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
              child: QrImageView(
                data: s.pairingPayload(),
                size: 210,
                backgroundColor: Colors.white,
                eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF10130A)),
                dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Color(0xFF10130A)),
              ),
            );
            final info = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final (i, step) in const [
                'Installa Tigert sul telefono.',
                'Al primo avvio tocca "Ho già Tigert sul PC", oppure vai in Profilo → Sincronizzazione Wi-Fi.',
                'Inquadra questo QR.',
              ].indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('${i + 1}. $step', style: TS.body(t).copyWith(fontSize: 13)),
                ),
              const SizedBox(height: 8),
              const Label('Oppure a mano'),
              const SizedBox(height: 4),
              Text(s.localIps.isEmpty ? 'Nessuna rete trovata' : s.localIps.join('  ·  '), style: TS.num(t, 15, w: FontWeight.w700)),
              const SizedBox(height: 2),
              Row(children: [
                Text('Codice ', style: TS.muted(t, 12.5)),
                SelectableText(SyncService.prettyKey(s.serverKey), style: TS.num(t, 15, w: FontWeight.w700)),
                IconButton(
                  tooltip: 'Copia codice',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.copy_rounded, size: 17, color: t.dim),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: s.serverKey));
                    toast(context, 'Codice copiato');
                  },
                ),
              ]),
            ]);
            return wide
                ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [qr, const SizedBox(width: 20), Expanded(child: info)])
                : Column(children: [Center(child: qr), const SizedBox(height: 16), info]);
          }),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: GhostButton('Aggiorna indirizzi', dense: true, icon: Icons.refresh_rounded, onTap: s.refreshIps)),
          const SizedBox(width: 10),
          Expanded(
            child: GhostButton('Nuovo codice', dense: true, icon: Icons.key_rounded, onTap: () async {
              final go = await confirm(
                context,
                title: 'Generare un nuovo codice?',
                body: 'I telefoni già abbinati non potranno più sincronizzarsi finché non li abbini di nuovo.',
                ok: 'Genera',
              );
              if (go) await s.regenerateKey();
            }),
          ),
        ]),
        SectionLabel('Dispositivi collegati · ${peers.length}'),
        if (peers.isEmpty)
          Text('Ancora nessuno: abbina il telefono con il QR qui sopra.', style: TS.muted(t, 12.5))
        else
          for (final e in peers)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: RowTile(
                leading: Icon(Icons.smartphone_rounded, color: t.dim),
                title: '${(e.value as Map)['name'] ?? 'Telefono'}',
                subtitle: _ago((e.value as Map)['at'] as num?),
              ),
            ),
        const NoteBox(
          icon: Icons.shield_outlined,
          text: 'Se il telefono non trova il PC: controlla che siano sulla stessa rete Wi-Fi e che Windows la consideri "Rete privata". '
              'L\'installer di Tigert apre già la porta nel firewall per le reti private.',
        ),
      ],
    ]);
  }

  String _ago(num? at) {
    if (at == null) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(at.toInt());
    return 'Ultima sincronizzazione ${relDay(d).toLowerCase()} alle ${hhmm(d)}';
  }
}

// =================================================================== telefono (client)

class _ClientView extends StatefulWidget {
  final bool fromOnboarding;
  const _ClientView({required this.fromOnboarding});
  @override
  State<_ClientView> createState() => _ClientViewState();
}

class _ClientViewState extends State<_ClientView> {
  final ipCtl = TextEditingController();
  final keyCtl = TextEditingController();
  bool busy = false;
  bool manual = false;
  String? error;

  @override
  void dispose() {
    ipCtl.dispose();
    keyCtl.dispose();
    super.dispose();
  }

  Future<void> _pair(Map<String, dynamic> pairing) async {
    setState(() {
      busy = true;
      error = null;
    });
    final err = await Services.sync.pair(pairing);
    if (!mounted) return;
    setState(() {
      busy = false;
      error = err;
    });
    if (err == null) {
      HapticFeedback.mediumImpact();
      toast(context, 'Abbinato a ${pairing['name'] ?? 'PC'} ✓');
      if (widget.fromOnboarding && context.appRead.hasProfile) {
        ShellNav.go(0);
        Navigator.of(context).popUntil((r) => r.isFirst);
      }
    }
  }

  Future<void> _scan() async {
    final code = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const _QrScanPage()));
    if (code == null || !mounted) return;
    final p = SyncService.parsePairing(code);
    if (p == null) {
      setState(() => error = 'Questo QR non è un codice di abbinamento Tigert.');
      return;
    }
    await _pair(p);
  }

  Future<void> _manual() async {
    final key = keyCtl.text.toUpperCase().replaceAll(RegExp(r'[^0-9A-Z]'), '');
    if (key.length != 12) {
      setState(() => error = 'Il codice ha 12 caratteri (lo trovi sul PC in Profilo → Sincronizzazione Wi-Fi).');
      return;
    }
    final ip = ipCtl.text.trim();
    await _pair({
      'hosts': [if (ip.isNotEmpty) ip],
      'port': SyncService.port,
      'key': key,
      'name': 'PC',
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    final s = Services.sync;
    final app = context.app;

    if (s.paired && !busy) {
      final pairing = app.prefs.pairing!;
      final hosts = ((pairing['hosts'] as List?) ?? const []).cast<String>();
      return PageBody(children: [
        TCard(
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: t.accentTint, borderRadius: BorderRadius.circular(12)),
              child: Icon(Icons.desktop_windows_rounded, color: t.accentInk),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${pairing['name'] ?? 'PC'}', style: TS.title(t)),
                Text(hosts.isEmpty ? 'Abbinato' : 'Abbinato · ${hosts.first}', style: TS.muted(t, 12)),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: Text(
              s.syncing
                  ? 'Sincronizzazione in corso…'
                  : (s.lastSyncAt == null ? 'Mai sincronizzato' : 'Ultima sincronizzazione ${relDay(s.lastSyncAt!).toLowerCase()} alle ${hhmm(s.lastSyncAt!)}'),
              style: TS.soft(t, 13),
            ),
          ),
        ]),
        if (s.lastError != null) NoteBox(icon: Icons.wifi_off_rounded, child: Text(s.lastError!, style: const TextStyle(color: TC.danger))),
        const SizedBox(height: 14),
        PrimaryButton('Sincronizza ora', icon: Icons.sync_rounded, busy: s.syncing, onTap: () async {
          final err = await s.syncNow();
          if (context.mounted) toast(context, err ?? 'Sincronizzato ✓');
        }),
        const SizedBox(height: 10),
        GhostButton('Scollega dal PC', color: TC.danger, onTap: () async {
          final go = await confirm(
            context,
            title: 'Scollegare il telefono?',
            body: 'I dati restano su entrambi i dispositivi, ma smetteranno di sincronizzarsi.',
            ok: 'Scollega',
            danger: true,
          );
          if (go) s.unpair();
        }),
        const NoteBox(
          icon: Icons.info_outline_rounded,
          text: 'La sincronizzazione parte da sola quando apri l\'app, dopo ogni modifica e ogni 3 minuti se il PC è raggiungibile. '
              'Se modifichi lo stesso dato su entrambi, vince la modifica più recente.',
        ),
      ]);
    }

    return PageBody(children: [
      Text(
        widget.fromOnboarding
            ? 'Collega il telefono a Tigert sul PC: profilo, diario, schede e progressi arriveranno qui in pochi secondi.'
            : 'Collega il telefono a Tigert sul PC per avere gli stessi dati su entrambi. Serve essere sulla stessa rete Wi-Fi.',
        style: TS.soft(t, 13),
      ),
      const SizedBox(height: 16),
      PrimaryButton('Inquadra il QR del PC', icon: Icons.qr_code_scanner_rounded, busy: busy && !manual, onTap: busy ? null : _scan),
      const SizedBox(height: 8),
      Text('Sul PC: Profilo → Sincronizzazione Wi-Fi.', textAlign: TextAlign.center, style: TS.muted(t, 12)),
      const SizedBox(height: 18),
      if (!manual)
        Center(child: TextButton(onPressed: () => setState(() => manual = true), child: Text('Inserisci il codice a mano', style: TextStyle(color: t.soft))))
      else ...[
        const SectionLabel('A mano'),
        TextField(
          controller: keyCtl,
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          decoration: const InputDecoration(labelText: 'Codice (12 caratteri)', hintText: 'ABCD-EFGH-JKLM'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: ipCtl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autocorrect: false,
          decoration: const InputDecoration(labelText: 'Indirizzo del PC (facoltativo)', hintText: '192.168.1.20', helperText: 'Se lo lasci vuoto lo cerco io sulla rete'),
        ),
        const SizedBox(height: 12),
        PrimaryButton('Collega', busy: busy && manual, onTap: busy ? null : _manual),
      ],
      if (busy)
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Text('Cerco il PC e scarico i dati…', textAlign: TextAlign.center, style: TS.muted(t, 12.5)),
        ),
      if (error != null) NoteBox(icon: Icons.error_outline_rounded, child: Text(error!, style: const TextStyle(color: TC.danger))),
    ]);
  }
}

class _QrScanPage extends StatelessWidget {
  const _QrScanPage();
  @override
  Widget build(BuildContext context) {
    return SubPage(
      title: 'Inquadra il QR',
      body: PageBody(children: [
        ScannerView(
          formats: const [BarcodeFormat.qrCode],
          hint: 'Il QR è sul PC in Profilo → Sincronizzazione',
          onCode: (c) {
            if (Navigator.canPop(context)) Navigator.pop(context, c);
          },
        ),
      ]),
    );
  }
}
