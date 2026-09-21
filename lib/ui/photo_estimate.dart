import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/fmt.dart';
import '../core/ids.dart';
import '../core/theme.dart';
import '../data/app_state.dart';
import '../data/models.dart';
import '../services/files.dart';
import '../services/gemini.dart';
import 'add_hub.dart';
import 'food_search.dart';
import 'settings/gemini_settings.dart';
import 'shell.dart';
import 'widgets.dart';

class PhotoScreen extends StatefulWidget {
  final String date;
  final String meal;
  const PhotoScreen({super.key, required this.date, required this.meal});
  @override
  State<PhotoScreen> createState() => _PhotoScreenState();
}

class _PhotoScreenState extends State<PhotoScreen> {
  Uint8List? photo;
  final extra = TextEditingController();
  final answer = TextEditingController();
  bool busy = false;
  String? error;
  late final AppLifecycleListener _life;
  bool _askedClipboard = false;

  @override
  void initState() {
    super.initState();
    _life = AppLifecycleListener(onResume: _checkClipboard);
  }

  @override
  void dispose() {
    _life.dispose();
    extra.dispose();
    answer.dispose();
    super.dispose();
  }

  /// Tornando da Gemini, se negli appunti c'è la risposta propongo di usarla.
  Future<void> _checkClipboard() async {
    if (_askedClipboard || !mounted) return;
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    final txt = d?.text ?? '';
    if (!txt.contains('"alimenti"') || answer.text == txt) return;
    _askedClipboard = true;
    if (!mounted) return;
    final ok = await confirm(context, title: 'Risposta di Gemini trovata', body: 'Negli appunti c\'è una risposta con gli alimenti. Vuoi usarla?', ok: 'Usa');
    if (ok) {
      answer.text = txt;
      _parse();
    }
  }

  Future<void> _pick(bool camera) async {
    try {
      final b = await pickPhoto(camera: camera);
      if (b != null) setState(() => photo = b);
    } catch (e) {
      setState(() => error = 'Non riesco ad aprire la ${camera ? 'fotocamera' : 'galleria'}: $e');
    }
  }

  Future<void> _analyze() async {
    final app = context.appRead;
    if (photo == null) return setState(() => error = 'Prima scatta o scegli una foto.');
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final est = await analyzeWithGemini(apiKey: app.prefs.geminiKey, model: app.prefs.geminiModel, jpeg: photo!, extra: extra.text);
      if (!mounted) return;
      await _openEstimate(est);
    } on GeminiException catch (e) {
      setState(() => error = e.message);
    } catch (e) {
      setState(() => error = 'Analisi non riuscita: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _parse() {
    try {
      final est = parseEstimate(answer.text);
      setState(() => error = null);
      _openEstimate(est);
    } on FormatException catch (e) {
      setState(() => error = e.message);
    }
  }

  Future<void> _openEstimate(PhotoEstimate est) async {
    final r = await push<LogEntry>(context, EstimateScreen(estimate: est, photo: photo, date: widget.date, meal: widget.meal));
    if (r != null && mounted) Navigator.pop(context, r);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final hasKey = app.prefs.geminiKey.isNotEmpty;
    return SubPage(
      title: 'Stima dalla foto',
      body: PageBody(children: [
        // ------------------------------------------------------ foto
        Container(
          height: 220,
          decoration: BoxDecoration(color: t.surf2, borderRadius: BorderRadius.circular(18), border: Border.all(color: t.line)),
          clipBehavior: Clip.antiAlias,
          child: photo == null
              ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.restaurant_rounded, size: 40, color: t.dim),
                  const SizedBox(height: 8),
                  Text('Foto del piatto', style: TS.muted(t)),
                  const SizedBox(height: 14),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    if (isMobile) ...[SmallButton('Scatta', icon: Icons.photo_camera_rounded, accent: true, onTap: () => _pick(true)), const SizedBox(width: 8)],
                    SmallButton(isMobile ? 'Galleria' : 'Scegli foto', icon: Icons.photo_library_rounded, onTap: () => _pick(false)),
                  ]),
                ])
              : Stack(fit: StackFit.expand, children: [
                  Image.memory(photo!, fit: BoxFit.cover),
                  Positioned(
                    right: 10,
                    top: 10,
                    child: IconButton.filledTonal(onPressed: () => setState(() => photo = null), icon: const Icon(Icons.close_rounded)),
                  ),
                ]),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: extra,
          textCapitalization: TextCapitalization.sentences,
          maxLines: 2,
          minLines: 1,
          decoration: const InputDecoration(labelText: 'Dettagli (facoltativo)', hintText: 'es. con un cucchiaio d\'olio, porzione abbondante'),
        ),
        // ------------------------------------------------------ API
        if (hasKey) ...[
          const SizedBox(height: 14),
          PrimaryButton('Analizza con Gemini', icon: Icons.auto_awesome_rounded, busy: busy, onTap: photo == null ? null : _analyze),
        ],
        // ------------------------------------------------------ copia-incolla
        SectionLabel(hasKey ? 'Oppure copia-incolla' : 'Copia-incolla con Gemini'),
        TCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _Step(n: '1', text: 'Copia il prompt di Tigert.', action: SmallButton('Copia prompt', icon: Icons.copy_rounded, accent: true, onTap: () async {
              await Clipboard.setData(ClipboardData(text: geminiPrompt(extra.text)));
              _askedClipboard = false;
              if (context.mounted) toast(context, 'Prompt copiato');
            })),
            _Step(n: '2', text: 'Apri Gemini, allega la foto del piatto e incolla il prompt.', action: SmallButton('Apri Gemini', icon: Icons.open_in_new_rounded, onTap: () {
              launchUrl(Uri.parse('https://gemini.google.com/app'), mode: LaunchMode.externalApplication);
            })),
            _Step(n: '3', text: 'Copia la risposta di Gemini e incollala qui sotto.', action: SmallButton('Incolla', icon: Icons.content_paste_rounded, onTap: () async {
              final d = await Clipboard.getData(Clipboard.kTextPlain);
              if (d?.text != null) {
                answer.text = d!.text!;
                _parse();
              }
            })),
            const SizedBox(height: 8),
            TextField(
              controller: answer,
              minLines: 3,
              maxLines: 8,
              style: const TextStyle(fontSize: 12.5, fontFamily: 'monospace'),
              decoration: const InputDecoration(hintText: '{ "tigert": 1, "piatto": ... }'),
            ),
            const SizedBox(height: 10),
            GhostButton('Leggi la risposta', dense: true, onTap: _parse),
          ]),
        ),
        if (error != null) NoteBox(icon: Icons.error_outline_rounded, text: error),
        if (!hasKey)
          NoteBox(
            child: Row(children: [
              const Expanded(child: Text('Vuoi l\'analisi automatica? Inserisci la chiave API gratuita di Gemini.')),
              SmallButton('Imposta', onTap: () => push(context, const GeminiSettingsScreen())),
            ]),
          ),
      ]),
    );
  }
}

class _Step extends StatelessWidget {
  final String n;
  final String text;
  final Widget action;
  const _Step({required this.n, required this.text, required this.action});
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(color: t.surf2, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Text(n, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: t.accentInk)),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: t.soft, height: 1.35))),
        const SizedBox(width: 8),
        action,
      ]),
    );
  }
}

// =================================================================== correzione stima

class EstimateScreen extends StatefulWidget {
  final PhotoEstimate estimate;
  final Uint8List? photo;
  final String date;
  final String meal;
  const EstimateScreen({super.key, required this.estimate, this.photo, required this.date, required this.meal});
  @override
  State<EstimateScreen> createState() => _EstimateScreenState();
}

class _EstimateScreenState extends State<EstimateScreen> {
  late final est = widget.estimate;
  late String meal = widget.meal;
  bool keepPhoto = true;
  bool saving = false;

  Future<void> _addMissing() async {
    final picked = await push<PickedFood>(context, FoodSearchScreen(date: widget.date, meal: meal, pickMode: true));
    if (picked == null) return;
    final f = picked.food;
    setState(() => est.items.add(EstimateItem(
          name: f.name,
          g: picked.g,
          gMin: picked.g,
          gMax: picked.g,
          kcal100: f.kcal,
          p100: f.p,
          c100: f.c,
          f100: f.f,
          confirmed: true,
        )));
  }

  Future<void> _save() async {
    final app = context.appRead;
    if (est.items.isEmpty) return;
    setState(() => saving = true);
    String? blob;
    if (keepPhoto && widget.photo != null) blob = await app.store.putBlob(widget.photo!);
    final ids = <String>[];
    var ts = DateTime.now().millisecondsSinceEpoch;
    var total = 0.0;
    app.store.batch(() {
      for (final it in est.items) {
        final m = it.macro;
        final e = LogEntry(
          id: newId(),
          date: widget.date,
          meal: meal,
          name: it.name,
          g: it.g,
          kcal: m.kcal,
          p: m.p,
          c: m.c,
          f: m.f,
          refType: 'photo',
          photoId: ids.isEmpty ? blob : null,
          ts: ts++,
        );
        ids.add(e.id);
        total += m.kcal;
        app.addEntry(e);
      }
    });
    if (!mounted) return;
    // voce "gruppo" solo per il messaggio di conferma (annulla elimina tutte)
    Navigator.pop(
      context,
      LogEntry(id: ids.join('|'), date: widget.date, meal: meal, name: est.dish, kcal: total, p: 0, c: 0, f: 0, ts: ts),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    final tot = est.total;
    final lo = est.kcalMin, hi = est.kcalMax;
    final allConfirmed = est.items.every((i) => i.confirmed);
    final conf = allConfirmed ? 'alta' : est.confidence;
    return SubPage(
      title: est.dish,
      bottom: BottomActions(children: [
        GhostButton('Annulla', onTap: () => Navigator.pop(context)),
        PrimaryButton('Salva stima', busy: saving, onTap: est.items.isEmpty ? null : _save),
      ]),
      body: PageBody(children: [
        if (widget.photo != null)
          Container(
            height: 170,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(18)),
            child: Stack(fit: StackFit.expand, children: [
              Image.memory(widget.photo!, fit: BoxFit.cover),
              Positioned(
                left: 12,
                top: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(color: TC.warn, borderRadius: BorderRadius.circular(6)),
                  child: const Text('STIMA', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: TC.onAccent)),
                ),
              ),
            ]),
          ),
        const SizedBox(height: 12),
        TCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Intervallo calorie', style: TS.muted(t)),
            const SizedBox(height: 2),
            BigNumber((hi - lo).abs() < 15 ? fInt(tot.kcal) : '${fInt(lo)}–${fInt(hi)}', unit: 'kcal', size: 34),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: (conf == 'alta' ? TC.accent : conf == 'media' ? TC.warn : TC.danger).withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Affidabilità $conf${allConfirmed ? ' · quantità confermate' : ' · correggi gli alimenti per stringere il range'}',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: t.soft),
              ),
            ),
            const SizedBox(height: 10),
            Text('Stima attuale ${fInt(tot.kcal)} kcal · P ${fInt(tot.p)} · C ${fInt(tot.c)} · G ${fInt(tot.f)}', style: TS.muted(t, 12.5)),
          ]),
        ),
        const SectionLabel('Alimenti riconosciuti'),
        for (var i = 0; i < est.items.length; i++) _itemCard(i),
        GhostButton('+ Manca un alimento', onTap: _addMissing),
        if (est.note.trim().isNotEmpty) NoteBox(icon: Icons.info_outline_rounded, text: est.note),
        const SectionLabel('Pasto'),
        MealChips(selected: meal, onChanged: (v) => setState(() => meal = v)),
        if (widget.photo != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: keepPhoto,
              onChanged: (v) => setState(() => keepPhoto = v),
              title: Text('Salva la foto nel diario', style: TS.body(t)),
            ),
          ),
      ]),
    );
  }

  Widget _itemCard(int i) {
    final t = context.tt;
    final it = est.items[i];
    final lo = math.max(0.0, math.min(it.gMin * 0.5, it.g));
    final hi = math.max(it.gMax * 1.5, it.g);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TCard(
        radius: 14,
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 6),
        borderColor: it.confirmed ? TC.accent.withValues(alpha: 0.5) : null,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Tap(
                radius: 6,
                onTap: () async {
                  final n = await askText(context, title: 'Nome alimento', initial: it.name);
                  if (n != null && n.isNotEmpty) setState(() => it.name = n);
                },
                child: Text(it.name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: t.ink)),
              ),
            ),
            Tap(
              radius: 6,
              onTap: () async {
                final v = await askNumber(context, title: it.name, initial: it.g, unit: 'g', decimals: 0, max: 5000);
                if (v != null) {
                  setState(() {
                    it.g = v;
                    it.confirmed = true;
                  });
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text('${fG(it.g)} g · ${fInt(it.macro.kcal)} kcal', style: TextStyle(fontSize: 13, color: t.dim, fontFeatures: tabular)),
              ),
            ),
            IconButton(icon: Icon(Icons.close_rounded, size: 18, color: t.dim), onPressed: () => setState(() => est.items.removeAt(i))),
          ]),
          Slider(
            value: it.g.clamp(lo, hi),
            min: lo,
            max: hi <= lo ? lo + 1 : hi,
            onChanged: (v) => setState(() {
              it.g = (v / 5).round() * 5.0;
              it.confirmed = true;
            }),
          ),
        ]),
      ),
    );
  }
}
