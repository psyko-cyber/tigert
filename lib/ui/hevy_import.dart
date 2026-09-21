import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/fmt.dart';
import '../core/theme.dart';
import '../data/app_state.dart';
import '../services/hevy.dart';
import 'exercise_picker.dart';
import 'shell.dart';
import 'widgets.dart';

/// Importa storico, schede ed esercizi personalizzati da Hevy.
class HevyImportScreen extends StatefulWidget {
  const HevyImportScreen({super.key});
  @override
  State<HevyImportScreen> createState() => _HevyImportScreenState();
}

enum _Step { source, loading, review, done }

class _HevyImportScreenState extends State<HevyImportScreen> {
  _Step step = _Step.source;
  final keyCtl = TextEditingController();
  bool hideKey = true;
  String progress = '';
  String? error;

  HevyData? data;
  List<HevyExerciseUse> uses = [];
  final mapping = <String, String?>{};
  List<HevyPlanDraft> drafts = [];
  final selectedPlans = <String>{};
  String? activePlan; // null = tieni la scheda attuale
  bool history = true;
  bool weights = true;
  bool onlyNew = false;
  HevyImportResult? result;

  @override
  void dispose() {
    keyCtl.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ caricamento

  Future<void> _fromApi() async {
    setState(() {
      step = _Step.loading;
      error = null;
      progress = 'Collegamento a Hevy…';
    });
    try {
      final d = await fetchHevy(keyCtl.text, onProgress: (p) {
        if (mounted) setState(() => progress = p);
      });
      _review(d);
    } on HevyException catch (e) {
      setState(() {
        step = _Step.source;
        error = e.message;
      });
    }
  }

  Future<void> _fromCsv() async {
    final files = await openFiles(acceptedTypeGroups: const [
      XTypeGroup(label: 'CSV di Hevy', extensions: ['csv'], mimeTypes: ['text/csv', 'text/comma-separated-values', 'text/plain', 'application/octet-stream']),
    ]);
    if (files.isEmpty) return;
    setState(() {
      step = _Step.loading;
      error = null;
      progress = 'Leggo ${files.length == 1 ? 'il file' : '${files.length} file'}…';
    });
    try {
      var d = HevyData();
      for (final f in files) {
        final text = utf8.decode(await f.readAsBytes(), allowMalformed: true);
        d = d.merge(parseHevyCsv(text));
      }
      if (d.isEmpty) throw const HevyException('Nei file non ci sono allenamenti né pesate.');
      _review(d);
    } on HevyException catch (e) {
      setState(() {
        step = _Step.source;
        error = e.message;
      });
    } catch (e) {
      setState(() {
        step = _Step.source;
        error = 'Non riesco a leggere il file: $e';
      });
    }
  }

  void _review(HevyData d) {
    if (!mounted) return;
    final app = context.appRead;
    final u = d.exerciseUses();
    mapping.clear();
    for (final x in u) {
      mapping[x.key] = matchExercise(x.title, app);
    }
    final pl = buildPlanDrafts(d);
    setState(() {
      data = d;
      uses = u;
      drafts = pl;
      selectedPlans
        ..clear()
        ..addAll(pl.map((p) => p.id));
      activePlan = pl.isEmpty ? null : pl.first.id;
      history = d.workouts.isNotEmpty;
      weights = d.weights.isNotEmpty;
      step = _Step.review;
    });
  }

  void _import() {
    final app = context.appRead;
    final plans = drafts.where((p) => selectedPlans.contains(p.id)).toList();
    final r = importHevy(
      app,
      data!,
      mapping: mapping,
      history: history,
      weights: weights,
      plans: plans,
      activatePlanId: activePlan != null && selectedPlans.contains(activePlan) ? activePlan : null,
    );
    HapticFeedback.mediumImpact();
    setState(() {
      result = r;
      step = _Step.done;
    });
  }

  // ------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    return SubPage(
      title: 'Importa da Hevy',
      bottom: step == _Step.review
          ? BottomActions(children: [PrimaryButton('Importa', icon: Icons.download_done_rounded, onTap: _canImport ? _import : null)])
          : null,
      body: switch (step) {
        _Step.source => _source(),
        _Step.loading => _loading(),
        _Step.review => _reviewView(),
        _Step.done => _done(),
      },
    );
  }

  bool get _canImport => history || weights || selectedPlans.isNotEmpty;

  Widget _source() {
    final t = context.tt;
    return PageBody(children: [
      Text(
        'Porta in Tigert quello che hai registrato su Hevy: gli allenamenti fatti (con carichi e ripetizioni), le schede e i tuoi esercizi personalizzati. '
        'Il coach di progressione parte subito dai tuoi ultimi carichi.',
        style: TS.soft(t, 13),
      ),
      if (error != null) NoteBox(icon: Icons.error_outline_rounded, child: Text(error!, style: const TextStyle(color: TC.danger))),
      const SectionLabel('Con Hevy Pro · tutto'),
      TCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Schede e cartelle, esercizi personalizzati con il gruppo muscolare, tutto lo storico e le pesate.', style: TS.body(t).copyWith(fontSize: 13)),
          const SizedBox(height: 12),
          TextField(
            controller: keyCtl,
            obscureText: hideKey,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Chiave API di Hevy',
              hintText: 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx',
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
                  tooltip: hideKey ? 'Mostra' : 'Nascondi',
                  icon: Icon(hideKey ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20),
                  onPressed: () => setState(() => hideKey = !hideKey),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          Text('La trovi su hevy.com → Impostazioni → Developer. Resta solo per questo import: Tigert non la salva.', style: TS.muted(t, 12)),
          const SizedBox(height: 12),
          PrimaryButton('Scarica da Hevy', icon: Icons.cloud_download_outlined, onTap: keyCtl.text.trim().isEmpty ? null : _fromApi),
          const SizedBox(height: 8),
          Center(
            child: TextButton.icon(
              onPressed: () => launchUrl(Uri.parse('https://hevy.com/settings?developer'), mode: LaunchMode.externalApplication),
              icon: Icon(Icons.open_in_new_rounded, size: 16, color: t.accentInk),
              label: Text('Apri hevy.com per copiare la chiave', style: TextStyle(color: t.accentInk, fontWeight: FontWeight.w600)),
            ),
          ),
        ]),
      ),
      const SectionLabel('Senza Pro · dal file CSV'),
      TCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final (i, s) in const [
            'Nell\'app Hevy: Profilo → ⚙ Impostazioni → Esporta e importa dati.',
            'Esporta gli allenamenti (workout_data.csv) e, se vuoi, le misurazioni (measurement_data.csv).',
            'Scegli qui i file: lo storico entra tutto, le schede le ricostruisco dagli allenamenti recenti.',
          ].indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('${i + 1}. $s', style: TS.body(t).copyWith(fontSize: 13)),
            ),
          const SizedBox(height: 6),
          GhostButton('Scegli file CSV', icon: Icons.upload_file_rounded, dense: true, onTap: _fromCsv),
        ]),
      ),
      const NoteBox(
        icon: Icons.info_outline_rounded,
        text: 'Puoi ripetere l\'import quando vuoi: gli allenamenti già importati vengono aggiornati, non duplicati. '
            'Le serie di riscaldamento non vengono importate.',
      ),
    ]);
  }

  Widget _loading() {
    final t = context.tt;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(width: 36, height: 36, child: CircularProgressIndicator(strokeWidth: 3)),
        const SizedBox(height: 16),
        Text(progress, style: TS.soft(t)),
      ]),
    );
  }

  Widget _reviewView() {
    final t = context.tt;
    final app = context.app;
    final d = data!;
    final ws = d.workouts;
    final newCount = uses.where((u) => mapping[u.key] == null).length;
    final shown = onlyNew ? uses.where((u) => mapping[u.key] == null).toList() : uses;
    return PageBody(children: [
      Row(children: [
        _Kpi('${ws.length}', 'allenamenti'),
        const SizedBox(width: 8),
        _Kpi('${uses.length}', 'esercizi'),
        const SizedBox(width: 8),
        _Kpi('${drafts.fold<int>(0, (a, p) => a + p.days.length)}', 'sedute'),
      ]),
      if (ws.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text('Dal ${shortDateY(ws.first.start)} al ${shortDateY(ws.last.start)}${d.fromApi ? '' : ' · dal file CSV'}', style: TS.muted(t, 12.5)),
      ],
      const SectionLabel('Cosa importare'),
      if (ws.isNotEmpty)
        _Toggle(
          title: 'Storico allenamenti',
          sub: '${ws.length} allenamenti: record, grafici e coach partono dai tuoi carichi',
          value: history,
          onChanged: (v) => setState(() => history = v),
        ),
      if (d.weights.isNotEmpty)
        _Toggle(
          title: 'Pesate',
          sub: '${d.weights.length} pesate (i giorni già registrati in Tigert non vengono toccati)',
          value: weights,
          onChanged: (v) => setState(() => weights = v),
        ),
      if (drafts.isNotEmpty) ...[
        SectionLabel(d.fromApi ? 'Schede' : 'Scheda ricostruita'),
        for (final p in drafts)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TCard(
              padding: const EdgeInsets.fromLTRB(6, 6, 14, 10),
              borderColor: activePlan == p.id ? TC.accent : null,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Checkbox(
                    value: selectedPlans.contains(p.id),
                    onChanged: (v) => setState(() {
                      v == true ? selectedPlans.add(p.id) : selectedPlans.remove(p.id);
                      if (v != true && activePlan == p.id) activePlan = null;
                    }),
                  ),
                  Expanded(child: Text(p.name, style: TS.title(t).copyWith(fontSize: 15))),
                  if (selectedPlans.contains(p.id))
                    PillChip(activePlan == p.id ? 'Attiva' : 'Rendi attiva', selected: activePlan == p.id, onTap: () => setState(() => activePlan = activePlan == p.id ? null : p.id)),
                ]),
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Text(
                    p.days.map((x) => '${x.name} (${x.items.length})').join(' · '),
                    style: TS.muted(t, 12),
                  ),
                ),
              ]),
            ),
          ),
        Text(
          activePlan == null
              ? 'La scheda attiva di Tigert resta ${app.activePlan?.name ?? 'quella attuale'}.'
              : 'Dopo l\'import allenerai con "${drafts.firstWhere((p) => p.id == activePlan).name}". Controlla i giorni di allenamento in Profilo.',
          style: TS.muted(t, 12),
        ),
      ],
      SectionLabel(
        'Esercizi · ${uses.length}',
        trailing: newCount == 0 ? null : PillChip(onlyNew ? 'Tutti' : 'Nuovi ($newCount)', selected: onlyNew, onTap: () => setState(() => onlyNew = !onlyNew)),
      ),
      Text(
        newCount == 0
            ? 'Tutti gli esercizi corrispondono a esercizi di Tigert. Tocca per cambiare l\'abbinamento.'
            : '$newCount esercizi verranno creati come personalizzati. Tocca un esercizio per abbinarlo a uno di Tigert.',
        style: TS.muted(t, 12),
      ),
      const SizedBox(height: 10),
      for (final u in shown)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Builder(builder: (context) {
            final id = mapping[u.key];
            final ex = id == null ? null : app.exercise(id);
            final preview = ex ?? newExerciseFor(u);
            return RowTile(
              title: preview.name,
              subtitle: '${u.title == preview.name ? '' : 'Hevy: ${u.title} · '}${preview.muscle}${u.times > 0 ? ' · ${u.times}×' : ''}',
              trailing: ex == null
                  ? StatusPill('nuovo', bg: TC.warn.withValues(alpha: 0.15), fg: TC.warn)
                  : Icon(Icons.link_rounded, size: 18, color: t.accentInk),
              onTap: () => _changeMapping(u),
            );
          }),
        ),
    ]);
  }

  Future<void> _changeMapping(HevyExerciseUse u) async {
    final t = context.tt;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text(u.title, style: TS.h2(t), textAlign: TextAlign.center),
          ),
          ListTile(leading: const Icon(Icons.search_rounded), title: const Text('Abbina a un esercizio di Tigert'), onTap: () => Navigator.pop(c, 'pick')),
          ListTile(leading: const Icon(Icons.add_circle_outline_rounded), title: const Text('Crea come esercizio personalizzato'), onTap: () => Navigator.pop(c, 'new')),
        ]),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'new') {
      setState(() => mapping[u.key] = null);
      return;
    }
    final id = await push<String>(context, ExercisePickerScreen(initialMuscle: newExerciseFor(u).muscle));
    if (id != null && mounted) setState(() => mapping[u.key] = id);
  }

  Widget _done() {
    final t = context.tt;
    final r = result!;
    return PageBody(children: [
      const SizedBox(height: 20),
      Center(
        child: Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(color: TC.accent, borderRadius: BorderRadius.circular(26)),
          child: const Icon(Icons.check_rounded, size: 46, color: TC.onAccent),
        ),
      ),
      const SizedBox(height: 16),
      Center(child: Text('Import completato', style: TS.h1(t))),
      const SizedBox(height: 16),
      TCard(
        child: Column(children: [
          _row('Allenamenti', fInt(r.sessions)),
          _row('Esercizi personalizzati creati', fInt(r.exercisesCreated)),
          _row('Schede', fInt(r.plans)),
          _row('Pesate', fInt(r.weights)),
        ]),
      ),
      const NoteBox(
        icon: Icons.trending_up_rounded,
        text: 'Il coach di progressione usa già questi dati: in Allena trovi quali carichi alzare nella prossima seduta.',
      ),
      const SizedBox(height: 16),
      PrimaryButton('Vai ad Allena', onTap: () {
        ShellNav.go(1);
        Navigator.of(context).popUntil((r) => r.isFirst);
      }),
    ]);
  }

  Widget _row(String k, String v) {
    final t = context.tt;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Expanded(child: Text(k, style: TS.soft(t, 13))),
        Text(v, style: TS.num(t, 15, w: FontWeight.w700)),
      ]),
    );
  }
}

class _Kpi extends StatelessWidget {
  final String v, k;
  const _Kpi(this.v, this.k);
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    return Expanded(
      child: TCard(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(v, style: TS.num(t, 24)),
          Text(k, style: TS.muted(t, 11.5)),
        ]),
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  final String title, sub;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _Toggle({required this.title, required this.sub, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: TCard(
        radius: 14,
        padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
        child: SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: value,
          onChanged: onChanged,
          title: Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: t.ink)),
          subtitle: Text(sub, style: TS.muted(t, 12)),
        ),
      ),
    );
  }
}
