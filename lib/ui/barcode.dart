import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/ids.dart';
import '../core/theme.dart';
import '../data/app_state.dart';
import '../data/models.dart';
import '../services/off_api.dart';
import 'food_amount.dart';
import 'food_editor.dart';
import 'shell.dart';
import 'widgets.dart';

/// Vista fotocamera riutilizzabile (codici a barre e QR di abbinamento).
class ScannerView extends StatefulWidget {
  final List<BarcodeFormat> formats;
  final ValueChanged<String> onCode;
  final String hint;
  const ScannerView({super.key, required this.formats, required this.onCode, this.hint = ''});
  @override
  State<ScannerView> createState() => _ScannerViewState();
}

class _ScannerViewState extends State<ScannerView> {
  late final MobileScannerController ctl = MobileScannerController(formats: widget.formats, detectionSpeed: DetectionSpeed.noDuplicates);
  bool handled = false;

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: AspectRatio(
        aspectRatio: 3 / 4,
        child: Stack(fit: StackFit.expand, children: [
          MobileScanner(
            controller: ctl,
            onDetect: (cap) {
              if (handled) return;
              for (final b in cap.barcodes) {
                final v = b.rawValue;
                if (v != null && v.isNotEmpty) {
                  handled = true;
                  HapticFeedback.mediumImpact();
                  widget.onCode(v);
                  Future.delayed(const Duration(seconds: 2), () => handled = false);
                  break;
                }
              }
            },
            errorBuilder: (context, error) => Container(
              color: Colors.black,
              padding: const EdgeInsets.all(24),
              alignment: Alignment.center,
              child: Text('Fotocamera non disponibile.\nControlla i permessi di Tigert nelle impostazioni del telefono.',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: 0.8))),
            ),
          ),
          IgnorePointer(
            child: Center(
              child: FractionallySizedBox(
                widthFactor: 0.72,
                heightFactor: widget.formats.contains(BarcodeFormat.qrCode) ? 0.5 : 0.28,
                child: Container(decoration: BoxDecoration(border: Border.all(color: TC.accent, width: 3), borderRadius: BorderRadius.circular(16))),
              ),
            ),
          ),
          if (widget.hint.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 16,
              child: Text(widget.hint, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, shadows: [Shadow(blurRadius: 8)])),
            ),
          Positioned(
            right: 10,
            top: 10,
            child: IconButton.filledTonal(onPressed: () => ctl.toggleTorch(), icon: const Icon(Icons.flashlight_on_rounded)),
          ),
        ]),
      ),
    );
  }
}

class BarcodeScreen extends StatefulWidget {
  final String date;
  final String meal;
  const BarcodeScreen({super.key, required this.date, required this.meal});
  @override
  State<BarcodeScreen> createState() => _BarcodeScreenState();
}

class _BarcodeScreenState extends State<BarcodeScreen> {
  final ctl = TextEditingController();
  bool manual = !isMobile;
  bool loading = false;
  String? notFound;
  String? error;

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  Future<void> _lookup(String raw) async {
    final code = raw.replaceAll(RegExp(r'\D'), '');
    if (code.length < 6) {
      setState(() => error = 'Il codice deve avere almeno 8 cifre (EAN-8 o EAN-13).');
      return;
    }
    final app = context.appRead;
    setState(() {
      loading = true;
      error = null;
      notFound = null;
    });
    Food? food = app.foodByEan(code) ?? app.food('off:$code');
    if (food == null) {
      try {
        food = await OffApi.byBarcode(code);
        if (food != null) app.saveFood(food);
      } on TimeoutException {
        error = 'Open Food Facts non risponde. Riprova o crea l\'alimento dall\'etichetta.';
      } catch (_) {
        error = 'Nessuna connessione: posso cercare solo tra i prodotti già salvati.';
      }
    }
    if (!mounted) return;
    setState(() => loading = false);
    if (food == null) {
      if (error == null) setState(() => notFound = code);
      return;
    }
    await _open(food);
  }

  Future<void> _open(Food food) async {
    final e = await push<LogEntry>(context, FoodAmountScreen(food: food, date: widget.date, meal: widget.meal, productStyle: true));
    if (e != null && mounted) Navigator.pop(context, e);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    return SubPage(
      title: 'Codice a barre',
      body: PageBody(children: [
        if (!manual && isMobile && notFound == null) ...[
          ScannerView(
            formats: const [BarcodeFormat.ean13, BarcodeFormat.ean8, BarcodeFormat.upcA, BarcodeFormat.upcE],
            hint: 'Inquadra il codice a barre',
            onCode: (c) => _lookup(c),
          ),
          const SizedBox(height: 12),
          GhostButton('Inserisci il codice a mano', icon: Icons.keyboard_rounded, onTap: () => setState(() => manual = true)),
        ],
        if (manual && notFound == null) ...[
          TextField(
            controller: ctl,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: TS.num(t, 24),
            decoration: const InputDecoration(labelText: 'Codice EAN', hintText: 'Incolla o digita il codice'),
            onSubmitted: _lookup,
          ),
          const SizedBox(height: 12),
          PrimaryButton('Cerca prodotto', icon: Icons.search_rounded, busy: loading, onTap: () => _lookup(ctl.text)),
          if (isMobile) ...[
            const SizedBox(height: 10),
            GhostButton('Usa la fotocamera', icon: Icons.qr_code_scanner_rounded, onTap: () => setState(() => manual = false)),
          ],
        ],
        if (loading && !manual) const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())),
        if (notFound != null) ...[
          Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.fromLTRB(20, 26, 20, 22),
            decoration: BoxDecoration(
              color: TC.warn.withValues(alpha: t.dark ? 0.08 : 0.14),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: TC.warn.withValues(alpha: 0.35)),
            ),
            child: Column(children: [
              const Text('⚠︎', style: TextStyle(fontSize: 30, color: TC.warn)),
              const SizedBox(height: 8),
              Text('Codice non trovato', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: t.ink)),
              const SizedBox(height: 6),
              Text('$notFound non è né sul dispositivo né su Open Food Facts. Inseriscilo una volta e resterà salvato per sempre.',
                  textAlign: TextAlign.center, style: TS.soft(t)),
            ]),
          ),
          const SizedBox(height: 14),
          PrimaryButton('Crea alimento da etichetta', onTap: () async {
            final f = await push<Food>(context, FoodEditorScreen(ean: notFound));
            if (f != null && mounted) await _open(f);
          }),
          const SizedBox(height: 10),
          GhostButton('Riprova la scansione', onTap: () => setState(() {
                notFound = null;
                ctl.clear();
              })),
        ],
        if (error != null) NoteBox(icon: Icons.wifi_off_rounded, text: error),
        NoteBox(
          text: isMobile
              ? 'I prodotti trovati restano salvati: la prossima volta funzionano anche offline e si sincronizzano col PC.'
              : 'Sul PC il codice si incolla da tastiera: stessa scheda prodotto, nessuna fotocamera. Molti lettori USB di codici a barre funzionano come una tastiera.',
        ),
      ]),
    );
  }
}
