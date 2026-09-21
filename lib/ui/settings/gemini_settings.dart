import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../data/app_state.dart';
import '../../services/gemini.dart';
import '../widgets.dart';

class GeminiSettingsScreen extends StatefulWidget {
  const GeminiSettingsScreen({super.key});
  @override
  State<GeminiSettingsScreen> createState() => _GeminiSettingsScreenState();
}

class _GeminiSettingsScreenState extends State<GeminiSettingsScreen> {
  late final keyCtl = TextEditingController(text: context.appRead.prefs.geminiKey);
  late final modelCtl = TextEditingController(text: context.appRead.prefs.geminiModel);
  bool hidden = true;
  bool busy = false;
  String? result;
  bool ok = false;

  @override
  void dispose() {
    keyCtl.dispose();
    modelCtl.dispose();
    super.dispose();
  }

  void _save() {
    final prefs = context.appRead.prefs;
    prefs.geminiKey = keyCtl.text;
    prefs.geminiModel = modelCtl.text;
  }

  Future<void> _test() async {
    _save();
    setState(() {
      busy = true;
      result = null;
    });
    try {
      final key = keyCtl.text.trim();
      final reply = await testGemini(key, modelCtl.text.trim().isEmpty ? 'gemini-flash-latest' : modelCtl.text.trim());
      final best = await latestFlashModel(key);
      ok = true;
      result = 'Funziona! Gemini ha risposto "${reply.length > 30 ? '${reply.substring(0, 30)}…' : reply}".'
          '${best == null ? '' : '\nModello Flash più recente disponibile: $best'}';
    } on GeminiException catch (e) {
      ok = false;
      result = e.message;
    } catch (e) {
      ok = false;
      result = 'Test non riuscito: $e';
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    final hasKey = keyCtl.text.trim().isNotEmpty;
    return PopScope(
      onPopInvokedWithResult: (_, _) => _save(),
      child: SubPage(
        title: 'Foto con Gemini',
        body: PageBody(children: [
          Text(
            'Tigert stima le calorie del piatto con Gemini in due modi: con la chiave API (automatico, dall\'app) '
            'oppure con il copia-incolla (gratis e senza chiave: copi il prompt, carichi la foto su Gemini e incolli la risposta).',
            style: TS.soft(t, 13),
          ),
          const SectionLabel('Chiave API (facoltativa)'),
          TextField(
            controller: keyCtl,
            obscureText: hidden,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (_) => setState(() => result = null),
            decoration: InputDecoration(
              labelText: 'Chiave API Gemini',
              hintText: 'AIza…',
              suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  tooltip: 'Incolla',
                  icon: const Icon(Icons.content_paste_rounded, size: 20),
                  onPressed: () async {
                    final d = await Clipboard.getData(Clipboard.kTextPlain);
                    if (d?.text != null) setState(() => keyCtl.text = d!.text!.trim());
                  },
                ),
                IconButton(
                  tooltip: hidden ? 'Mostra' : 'Nascondi',
                  icon: Icon(hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20),
                  onPressed: () => setState(() => hidden = !hidden),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: modelCtl,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Modello', helperText: 'gemini-flash-latest usa sempre l\'ultimo Flash'),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: PrimaryButton('Salva e prova', busy: busy, onTap: hasKey ? _test : null)),
            if (hasKey) ...[
              const SizedBox(width: 10),
              Expanded(
                child: GhostButton('Rimuovi chiave', color: TC.danger, onTap: () {
                  keyCtl.clear();
                  _save();
                  setState(() => result = null);
                  toast(context, 'Chiave rimossa: resta il copia-incolla');
                }),
              ),
            ],
          ]),
          if (result != null)
            NoteBox(
              icon: ok ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded,
              child: Text(result!, style: TextStyle(color: ok ? t.ink : TC.danger)),
            ),
          const SectionLabel('Come ottenere la chiave (gratis)'),
          TCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final (i, s) in const [
                'Apri Google AI Studio e accedi con il tuo account Google.',
                'Premi "Get API key" → "Create API key".',
                'Copia la chiave (inizia con AIza) e incollala qui sopra.',
                'Il piano gratuito basta per l\'uso quotidiano: se superi il limite, Tigert ti propone il copia-incolla.',
              ].indexed)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      width: 22,
                      height: 22,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: t.accentTint, shape: BoxShape.circle),
                      child: Text('${i + 1}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: t.accentInk)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(s, style: TS.body(t).copyWith(fontSize: 13))),
                  ]),
                ),
              const SizedBox(height: 10),
              SmallButton('Apri aistudio.google.com', icon: Icons.open_in_new_rounded, onTap: () {
                launchUrl(Uri.parse('https://aistudio.google.com/apikey'), mode: LaunchMode.externalApplication);
              }),
            ]),
          ),
          const NoteBox(
            icon: Icons.lock_outline_rounded,
            text: 'La chiave resta solo su questo dispositivo: non viene sincronizzata né inviata ad altri che a Google. '
                'Le foto inviate a Gemini seguono i termini di Google AI Studio.',
          ),
          const SectionLabel('Prompt usato'),
          TCard(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(geminiPrompt(), maxLines: 8, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: t.soft, height: 1.45)),
              const SizedBox(height: 10),
              SmallButton('Copia prompt', icon: Icons.copy_rounded, onTap: () {
                Clipboard.setData(ClipboardData(text: geminiPrompt()));
                toast(context, 'Prompt copiato');
              }),
            ]),
          ),
        ]),
      ),
    );
  }
}
