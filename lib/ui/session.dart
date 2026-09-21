import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/fmt.dart';
import '../core/ids.dart';
import '../core/theme.dart';
import '../data/app_state.dart';
import '../data/models.dart';
import '../logic/training.dart';
import '../services/services.dart';
import 'exercise_picker.dart';
import 'plan_editor.dart';
import 'session_summary.dart';
import 'shell.dart';
import 'widgets.dart';

class SessionScreen extends StatefulWidget {
  final String sessionId;
  const SessionScreen({super.key, required this.sessionId});
  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  Timer? _tick;
  int? _pausedLeft; // secondi rimasti se in pausa
  bool _alerted = false;

  @override
  void initState() {
    super.initState();
    if (isMobile) WakelockPlus.enable();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  @override
  void dispose() {
    _tick?.cancel();
    if (isMobile) WakelockPlus.disable();
    super.dispose();
  }

  AppState get app => context.appRead;

  int? get _endsAt => app.prefs.restEndsAt;
  int get _left {
    if (_pausedLeft != null) return _pausedLeft!;
    final e = _endsAt;
    if (e == null) return 0;
    return ((e - DateTime.now().millisecondsSinceEpoch) / 1000).ceil().clamp(0, 3600);
  }

  bool get _running => _pausedLeft == null && _endsAt != null && _left > 0;

  void _onTick() {
    if (!mounted) return;
    final e = _endsAt;
    if (_pausedLeft == null && e != null && !_alerted && DateTime.now().millisecondsSinceEpoch >= e) {
      _alerted = true;
      HapticFeedback.heavyImpact();
      SystemSound.play(SystemSoundType.alert);
      if (isDesktop) Services.notif.show('Recupero finito', 'Pronto per la prossima serie 💪', urgent: true);
      app.prefs.restEndsAt = null;
    }
    setState(() {});
  }

  void _startRest(int seconds) {
    if (seconds <= 0) return;
    _pausedLeft = null;
    _alerted = false;
    app.prefs.restEndsAt = DateTime.now().millisecondsSinceEpoch + seconds * 1000;
    setState(() {});
  }

  void _toggleTimer(int defaultRest) {
    if (_pausedLeft != null) {
      _startRest(_pausedLeft!);
    } else if (_running) {
      setState(() => _pausedLeft = _left);
      app.prefs.restEndsAt = null;
    } else {
      _startRest(defaultRest);
    }
  }

  void _addTime(int s) {
    if (_pausedLeft != null) {
      setState(() => _pausedLeft = (_pausedLeft! + s).clamp(0, 3600));
    } else if (_running) {
      app.prefs.restEndsAt = _endsAt! + s * 1000;
    } else if (s > 0) {
      _startRest(s);
    }
  }

  void _save(Session s) => app.saveSession(s);

  Session _updateSet(Session s, int ei, int si, SetLog v) {
    final items = [...s.items];
    final sets = [...items[ei].sets];
    sets[si] = v;
    items[ei] = items[ei].copyWith(sets: sets);
    return s.copyWith(items: items);
  }

  void _markDone(Session s, int ei, int si, {bool done = true}) {
    final e = s.items[ei];
    var ns = _updateSet(s, ei, si, e.sets[si].copyWith(done: done));
    _save(ns);
    if (done) {
      HapticFeedback.mediumImpact();
      final allDone = ns.items[ei].sets.every((x) => x.done);
      if (!allDone || ei < ns.items.length - 1) _startRest(e.target.rest);
    }
  }

  Future<void> _editSet(Session s, int ei, int si) async {
    final e = s.items[ei];
    final ex = app.exercise(e.ex);
    final r = await showModalBottomSheet<(SetLog, bool)>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SetSheet(set: e.sets[si], index: si, ex: ex, target: e.target),
    );
    if (r == null) return;
    final (v, markDone) = r;
    var ns = s;
    final old = e.sets[si];
    ns = _updateSet(ns, ei, si, v.copyWith(done: markDone ? true : v.done));
    // propaga carico e ripetizioni alle serie successive non ancora fatte
    for (var j = si + 1; j < e.sets.length; j++) {
      final o = e.sets[j];
      if (o.done) continue;
      ns = _updateSet(ns, ei, j, o.copyWith(kg: o.kg == old.kg ? v.kg : o.kg, reps: o.reps == old.reps ? v.reps : o.reps));
    }
    _save(ns);
    if (markDone && !old.done) {
      HapticFeedback.mediumImpact();
      _startRest(e.target.rest);
    }
  }

  Future<void> _finish(Session s) async {
    final undone = s.plannedSets - s.doneSets;
    if (undone > 0) {
      final ok = await confirm(context,
          title: 'Terminare la sessione?',
          body: 'Mancano $undone serie: nel voto conteranno come non fatte. Puoi anche tornare indietro e completarle.',
          ok: 'Termina');
      if (!ok) return;
    }
    app.prefs.restEndsAt = null;
    await Services.notif.cancelRestEnd();
    final done = s.copyWith(status: 'done', end: DateTime.now().millisecondsSinceEpoch);
    _save(done);
    if (mounted) Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => SessionSummaryScreen(sessionId: s.id, fresh: true)));
  }

  Future<void> _discard(Session s) async {
    final ok = await confirm(context, title: 'Annullare la sessione?', body: 'Le serie registrate in questa sessione verranno eliminate.', ok: 'Annulla sessione', danger: true);
    if (!ok) return;
    app.prefs.restEndsAt = null;
    app.deleteSession(s.id);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _addExercise(Session s) async {
    final id = await push<String>(context, const ExercisePickerScreen());
    if (id == null) return;
    final item = buildSessionEx(app, defaultItemFor(app.exercise(id), id));
    _save(s.copyWith(items: [...s.items, item], current: s.items.length));
  }

  @override
  Widget build(BuildContext context) {
    final a = context.app;
    final t = context.tt;
    final s = a.session(widget.sessionId);
    if (s == null) {
      return const SubPage(title: 'Sessione', body: Center(child: Text('Sessione non trovata')));
    }
    if (s.items.isEmpty) {
      return SubPage(
        title: s.name,
        body: PageBody(children: [
          EmptyState(
            emoji: '🏋️',
            title: 'Allenamento libero',
            body: 'Aggiungi gli esercizi che fai oggi: Tigert ricorda carichi e ripetizioni per la prossima volta.',
            action: PrimaryButton('Aggiungi esercizio', onTap: () => _addExercise(s)),
          ),
          const SizedBox(height: 10),
          GhostButton('Annulla sessione', onTap: () => _discard(s)),
        ]),
      );
    }
    final ei = s.current.clamp(0, s.items.length - 1);
    final e = s.items[ei];
    final ex = a.exercise(e.ex);
    final cardio = e.type == 'k';
    final prev = a.lastPerformance(e.ex, beforeTs: s.start);
    final sug = suggestFor(a, e.target, beforeTs: s.start);
    final live = liveTip(a, e);
    final nextIdx = e.sets.indexWhere((x) => !x.done);
    final left = _left;
    final restDefault = e.target.rest > 0 ? e.target.rest : 90;

    String primaryLabel;
    VoidCallback primaryAction;
    if (nextIdx >= 0) {
      primaryLabel = 'Serie ${nextIdx + 1} fatta';
      primaryAction = () => _markDone(s, ei, nextIdx);
    } else if (ei < s.items.length - 1) {
      primaryLabel = 'Prossimo esercizio';
      primaryAction = () => _save(s.copyWith(current: ei + 1));
    } else {
      primaryLabel = 'Termina sessione';
      primaryAction = () => _finish(s);
    }

    return SubPage(
      title: s.name,
      actions: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: t.surf2, borderRadius: BorderRadius.circular(99)),
          child: Text(fDuration(s.duration), style: TS.num(t, 14, w: FontWeight.w700)),
        ),
        PopupMenuButton<String>(
          onSelected: (v) {
            switch (v) {
              case 'add':
                _addExercise(s);
              case 'finish':
                _finish(s);
              case 'discard':
                _discard(s);
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'add', child: Text('Aggiungi esercizio')),
            PopupMenuItem(value: 'finish', child: Text('Termina sessione')),
            PopupMenuItem(value: 'discard', child: Text('Annulla sessione')),
          ],
        ),
      ],
      bottom: BottomActions(children: [
        GhostButton('Esercizio prec.', onTap: ei == 0 ? null : () => _save(s.copyWith(current: ei - 1))),
        PrimaryButton(primaryLabel, onTap: primaryAction),
      ]),
      body: PageBody(children: [
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: s.items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (_, i) {
              final it = s.items[i];
              final complete = it.sets.isNotEmpty && it.sets.every((x) => x.done);
              return PillChip(
                '${i + 1}. ${_short(it.name)}',
                selected: i == ei,
                icon: complete ? Icons.check_rounded : null,
                onTap: () => _save(s.copyWith(current: i)),
              );
            },
          ),
        ),
        const SizedBox(height: 14),
        Label('Esercizio ${ei + 1} di ${s.items.length} · ${ex?.muscle ?? ''}'),
        const SizedBox(height: 2),
        Text(e.name, style: TS.h1(t).copyWith(fontSize: 22)),
        NoteBox(
          child: Text.rich(TextSpan(children: [
            TextSpan(text: '${e.target.scheme} ${ex?.repsLabel ?? 'rip'}'),
            TextSpan(text: ' · RPE target ${fDec(e.target.rpe, 1, true)}'),
            if (e.target.rest > 0) TextSpan(text: ' · recupero ${fMinutes((e.target.rest / 60).ceil())}'),
            TextSpan(text: '\n${sug.title}: ', style: const TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: sug.text),
          ])),
        ),
        const SizedBox(height: 12),
        // ---------------------------------------------------- tabella serie
        TCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.line))),
              child: Row(children: [
                SizedBox(width: 34, child: Text('#', style: TS.label(t))),
                if (!cardio) Expanded(child: Text('KG', style: TS.label(t))),
                Expanded(child: Text((ex?.repsLabel ?? 'rip').toUpperCase(), style: TS.label(t))),
                Expanded(child: Text('RPE', style: TS.label(t))),
                SizedBox(width: 72, child: Text('SCORSA', textAlign: TextAlign.right, style: TS.label(t))),
              ]),
            ),
            for (var i = 0; i < e.sets.length; i++)
              _SetRow(
                index: i,
                set: e.sets[i],
                cardio: cardio,
                isNext: i == nextIdx,
                prev: prev != null && i < prev.$2.sets.length ? prevLabel(prev.$2.sets[i], ex) : '—',
                onTap: () => _editSet(s, ei, i),
                onToggle: () => _markDone(s, ei, i, done: !e.sets[i].done),
              ),
          ]),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: SmallButton('+ Serie', onTap: () {
              final last = e.sets.isEmpty ? const SetLog() : e.sets.last;
              final items = [...s.items];
              items[ei] = e.copyWith(sets: [...e.sets, SetLog(kg: last.kg, reps: last.reps)]);
              _save(s.copyWith(items: items));
            }),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SmallButton('− Serie', onTap: e.sets.length <= 1 || e.sets.last.done
                ? null
                : () {
                    final items = [...s.items];
                    items[ei] = e.copyWith(sets: e.sets.sublist(0, e.sets.length - 1));
                    _save(s.copyWith(items: items));
                  }),
          ),
        ]),
        if (live != null)
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: t.accentTint, borderRadius: BorderRadius.circular(18), border: Border.all(color: t.accentLine)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(live.title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: t.accentInk)),
              const SizedBox(height: 4),
              Text(live.text, style: TS.soft(t, 12.5)),
            ]),
          ),
        // ---------------------------------------------------- timer
        TCard(
          margin: const EdgeInsets.only(top: 12),
          borderColor: _running ? TC.accent : null,
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Label('Recupero'),
                const SizedBox(height: 4),
                Text(
                  fDuration(Duration(seconds: _running || _pausedLeft != null ? left : restDefault)),
                  style: TS.num(t, 40, color: _running ? t.accentInk : (_pausedLeft != null ? TC.warn : t.dim)),
                ),
              ]),
            ),
            Column(children: [
              SmallButton(_running ? 'Pausa' : (_pausedLeft != null ? 'Riprendi' : 'Avvia'), accent: !_running, onTap: () => _toggleTimer(restDefault)),
              const SizedBox(height: 8),
              Row(children: [
                SmallButton('−15s', onTap: () => _addTime(-15)),
                const SizedBox(width: 6),
                SmallButton('+1 min', onTap: () => _addTime(60)),
              ]),
            ]),
          ]),
        ),
        const SizedBox(height: 12),
        Text('${s.doneSets}/${s.plannedSets} serie · ${fInt(s.volume)} kg sollevati', textAlign: TextAlign.center, style: TS.muted(t, 12)),
      ]),
    );
  }
}

class _SetRow extends StatelessWidget {
  final int index;
  final SetLog set;
  final bool cardio;
  final bool isNext;
  final String prev;
  final VoidCallback onTap;
  final VoidCallback onToggle;
  const _SetRow({required this.index, required this.set, required this.cardio, required this.isNext, required this.prev, required this.onTap, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    final st = TS.num(t, 17, w: FontWeight.w700, color: set.done ? t.ink : t.soft);
    return Material(
      color: isNext ? TC.accent.withValues(alpha: 0.06) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.line))),
          child: Row(children: [
            SizedBox(
              width: 38,
              child: InkResponse(
                onTap: onToggle,
                radius: 22,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: set.done ? TC.accent : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(color: set.done ? TC.accent : t.line, width: 1.5),
                  ),
                  alignment: Alignment.center,
                  child: set.done
                      ? const Icon(Icons.check_rounded, size: 18, color: TC.onAccent)
                      : Text('${index + 1}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: t.soft)),
                ),
              ),
            ),
            if (!cardio) Expanded(child: Text(set.kg > 0 ? fKg(set.kg) : '—', style: st)),
            Expanded(child: Text('${set.reps}', style: st)),
            Expanded(child: Text(set.rpe == null ? '—' : fDec(set.rpe!, 1, true), style: st)),
            SizedBox(width: 72, child: Text(prev, textAlign: TextAlign.right, style: TextStyle(fontSize: 12, color: t.dim, fontFeatures: tabular))),
          ]),
        ),
      ),
    );
  }
}

class _SetSheet extends StatefulWidget {
  final SetLog set;
  final int index;
  final Exercise? ex;
  final PlanItem target;
  const _SetSheet({required this.set, required this.index, required this.ex, required this.target});
  @override
  State<_SetSheet> createState() => _SetSheetState();
}

class _SetSheetState extends State<_SetSheet> {
  late SetLog s = widget.set;

  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    final cardio = widget.ex?.isCardio == true;
    final inc = (widget.ex?.inc ?? 2.5) > 0 ? widget.ex!.inc : 2.5;
    final unit = widget.ex?.repsLabel ?? 'rip';
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Serie ${widget.index + 1}', style: TS.h2(t)),
          Text('Obiettivo ${widget.target.rMin}-${widget.target.rMax} $unit a RPE ${fDec(widget.target.rpe, 1, true)}', style: TS.muted(t)),
          if (!cardio) ...[
            const SectionLabel('Carico (kg)'),
            Stepper2(
              value: fKg(s.kg),
              minusLabel: '−${fKg(inc)}',
              plusLabel: '+${fKg(inc)}',
              onMinus: () => setState(() => s = s.copyWith(kg: (s.kg - inc).clamp(0, 1000))),
              onPlus: () => setState(() => s = s.copyWith(kg: s.kg + inc)),
              onTapValue: () async {
                final v = await askNumber(context, title: 'Carico', initial: s.kg, unit: 'kg', decimals: 2, max: 1000);
                if (v != null) setState(() => s = s.copyWith(kg: v));
              },
            ),
          ],
          SectionLabel(unit == 'rip' ? 'Ripetizioni' : (unit == 'min' ? 'Minuti' : 'Secondi')),
          Stepper2(
            value: '${s.reps}',
            onMinus: () => setState(() => s = s.copyWith(reps: (s.reps - 1).clamp(0, 999))),
            onPlus: () => setState(() => s = s.copyWith(reps: s.reps + 1)),
            onTapValue: () async {
              final v = await askNumber(context, title: unit == 'rip' ? 'Ripetizioni' : 'Durata', initial: s.reps.toDouble(), decimals: 0, max: 999);
              if (v != null) setState(() => s = s.copyWith(reps: v.round()));
            },
          ),
          const SectionLabel('RPE (quanto era dura)'),
          Wrap(spacing: 6, runSpacing: 6, children: [
            PillChip('—', selected: s.rpe == null, onTap: () => setState(() => s = s.copyWith(clearRpe: true))),
            for (final r in [6.0, 7.0, 7.5, 8.0, 8.5, 9.0, 9.5, 10.0]) PillChip(fDec(r, 1, true), selected: s.rpe == r, onTap: () => setState(() => s = s.copyWith(rpe: r))),
          ]),
          const SizedBox(height: 6),
          Text('RPE 10 = cedimento · 9 = una ripetizione in riserva · 8 = due', style: TS.muted(t, 11.5)),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(child: GhostButton('Salva', dense: true, onTap: () => Navigator.pop(context, (s, false)))),
            const SizedBox(width: 10),
            Expanded(child: PrimaryButton(widget.set.done ? 'Salva' : 'Salva e fatta', dense: true, onTap: () => Navigator.pop(context, (s, true)))),
          ]),
        ]),
      ),
    );
  }
}

/// "Squat con bilanciere" → "Squat bilanciere", "Panca piana con manubri" → "Panca piana".
String _short(String name) {
  const filler = {'con', 'al', 'alla', 'alle', 'ai', 'agli', 'in', 'da', 'di', 'a', 'su', 'e'};
  return name.split(' ').where((w) => !filler.contains(w.toLowerCase())).take(2).join(' ');
}
