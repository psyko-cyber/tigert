import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/fmt.dart';
import '../../core/theme.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../logic/nutrition.dart';
import '../widgets.dart';

// =================================================================== dati personali

class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key});
  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  late final Profile p0 = context.appRead.profile!;
  late final nameCtl = TextEditingController(text: p0.name);
  late final ageCtl = TextEditingController(text: '${p0.age}');
  late final heightCtl = TextEditingController(text: fDec(p0.heightCm, 0));
  late final targetCtl = TextEditingController(text: fDec(p0.targetWeight, 1, true));
  late String sex = p0.sex;
  late Goal goal = p0.goal;
  late bool heavy = p0.heavy;
  late double rate = p0.rate <= 0 ? (p0.goal == Goal.cut ? 0.5 : 0.25) : p0.rate;
  late String activity = p0.activity;
  String? error;

  @override
  void dispose() {
    for (final c in [nameCtl, ageCtl, heightCtl, targetCtl]) {
      c.dispose();
    }
    super.dispose();
  }

  List<(double, String)> get rateOptions => goal == Goal.bulk
      ? const [(0.15, 'Lento'), (0.25, 'Consigliato'), (0.4, 'Veloce')]
      : const [(0.25, 'Lento'), (0.5, 'Consigliato'), (0.75, 'Veloce')];

  Future<void> _save() async {
    final app = context.appRead;
    final age = parseNum(ageCtl.text)?.round();
    final h = parseNum(heightCtl.text);
    final w = app.currentWeight;
    var tg = goal == Goal.maintain ? w : parseNum(targetCtl.text);
    String? e;
    if (age == null || age < 14 || age > 90) {
      e = 'Inserisci un\'età tra 14 e 90 anni.';
    } else if (h == null || h < 120 || h > 230) {
      e = 'Inserisci l\'altezza in cm (120-230).';
    } else if (tg == null || tg < 35 || tg > 250) {
      e = 'Inserisci il peso obiettivo in kg.';
    } else if (goal == Goal.bulk && tg <= w) {
      e = 'Per la massa il peso obiettivo deve essere più alto della media attuale (${fDec(w, 1)} kg).';
    } else if (goal == Goal.cut && tg >= w) {
      e = 'Per la definizione il peso obiettivo deve essere più basso della media attuale (${fDec(w, 1)} kg).';
    }
    setState(() => error = e);
    if (e != null) {
      HapticFeedback.heavyImpact();
      return;
    }
    tg = tg!;
    final r = goal == Goal.maintain ? 0.0 : rate;
    // Nuovo obiettivo (tipo o peso) = nuovo percorso che parte da oggi.
    final newPath = goal != p0.goal || (tg - p0.targetWeight).abs() >= 0.1;
    var p = p0.copyWith(
      name: nameCtl.text.trim(),
      sex: sex,
      birthYear: DateTime.now().year - age!,
      heightCm: h,
      goal: goal,
      targetWeight: tg,
      rate: r,
      heavy: goal == Goal.bulk && heavy,
      activity: activity,
      startWeight: newPath ? w : null,
      startDate: newPath ? todayKey() : null,
    );
    p = p.copyWith(phases: p0.phasesFor(p, todayKey()));
    final t = computeTargets(sex: sex, age: age, heightCm: h!, weight: w, activity: activity, goal: goal, rate: r);
    final changed = (t.kcal - p0.kcal).abs() >= 30 || newPath;
    if (changed) {
      final apply = await confirm(
        context,
        title: 'Aggiorno i target?',
        body: 'Con i nuovi dati il target consigliato è ${fInt(t.kcal)} kcal '
            '(P ${t.protein} g · C ${t.carbs} g · G ${t.fat} g), ora sei a ${fInt(p0.kcal)} kcal.',
        ok: 'Aggiorna',
      );
      if (!mounted) return;
      if (apply) {
        p = p.copyWith(
          kcal: t.kcal,
          protein: t.protein,
          carbs: t.carbs,
          fat: t.fat,
          kcalStart: newPath ? t.kcal : null,
          waterMl: t.water,
          lastAdjust: todayKey(),
          changes: [...p0.changes, TargetChange(todayKey(), p0.kcal, t.kcal, 'Dati aggiornati')],
        );
      }
    }
    app.saveProfile(p);
    if (mounted) {
      toast(context, 'Dati salvati');
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    final app = context.app;
    return SubPage(
      title: 'Dati personali',
      bottom: BottomActions(children: [PrimaryButton('Salva', onTap: _save)]),
      body: PageBody(children: [
        _field('Nome (facoltativo)', nameCtl, number: false),
        const SizedBox(height: 14),
        const Label('Sesso'),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _choice('Uomo', sex == 'm', () => setState(() => sex = 'm'))),
          const SizedBox(width: 8),
          Expanded(child: _choice('Donna', sex == 'f', () => setState(() => sex = 'f'))),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _field('Età', ageCtl, suffix: 'anni')),
          const SizedBox(width: 10),
          Expanded(child: _field('Altezza', heightCtl, suffix: 'cm')),
        ]),
        NoteBox(
          icon: Icons.info_outline_rounded,
          text: 'Il peso non si modifica qui: si registra dalla schermata Oggi. I calcoli usano la media degli ultimi 7 giorni '
              '(ora ${fDec(app.currentWeight, 1)} kg).',
        ),
        const SectionLabel('Obiettivo'),
        Row(children: [
          for (final g in Goal.values) ...[
            if (g != Goal.values.first) const SizedBox(width: 8),
            Expanded(
              child: _choice(g.label, goal == g, () {
                setState(() {
                  goal = g;
                  if (!rateOptions.any((o) => o.$1 == rate)) rate = rateOptions[1].$1;
                });
              }),
            ),
          ],
        ]),
        if (goal != Goal.maintain) ...[
          const SizedBox(height: 14),
          _field('Peso obiettivo', targetCtl, suffix: 'kg'),
          const SizedBox(height: 14),
          const Label('Ritmo'),
          const SizedBox(height: 8),
          Row(children: [
            for (final (v, l) in rateOptions) ...[
              if (v != rateOptions.first.$1) const SizedBox(width: 8),
              Expanded(child: _choice('$l\n${goal == Goal.bulk ? '+' : '−'}${fDec(v, 2, true)} kg/sett', rate == v, () => setState(() => rate = v))),
            ],
          ]),
        ],
        if (goal == Goal.bulk) ...[
          const SizedBox(height: 14),
          const Label('Fase'),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _choice(Phase.lean.label, !heavy, () => setState(() => heavy = false))),
            const SizedBox(width: 8),
            Expanded(child: _choice(Phase.heavy.label, heavy, () => setState(() => heavy = true))),
          ]),
        ],
        Builder(builder: (context) {
          final ph = goal == Goal.bulk ? (heavy ? Phase.heavy : Phase.lean) : (goal == Goal.cut ? Phase.cut : Phase.maintain);
          return NoteBox(
            icon: Icons.tune_rounded,
            text: '${ph.label}: ${ph.tolText}, poi il voto scende piano. '
                '${ph == Phase.heavy ? 'Andare sotto il target resta penalizzato: in bulk è quello il problema. ' : ''}'
                'Il target non cambia; la fase vale da oggi, i giorni passati tengono la loro.',
          );
        }),
        const SectionLabel('Livello di attività'),
        for (final e in activityLevels.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: TCard(
              radius: 14,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              borderColor: activity == e.key ? TC.accent : null,
              onTap: () => setState(() => activity = e.key),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(e.value.$1, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: t.ink)),
                    const SizedBox(height: 2),
                    Text(activityDescriptions[e.key] ?? '', style: TS.muted(t, 12)),
                  ]),
                ),
                if (activity == e.key) Icon(Icons.check_circle_rounded, color: t.accentInk, size: 20),
              ]),
            ),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(error!, style: const TextStyle(color: TC.danger, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
      ]),
    );
  }

  Widget _field(String label, TextEditingController c, {String? suffix, bool number = true}) => TextField(
        controller: c,
        keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
        textCapitalization: number ? TextCapitalization.none : TextCapitalization.words,
        inputFormatters: number ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))] : null,
        decoration: InputDecoration(labelText: label, suffixText: suffix),
      );

  Widget _choice(String label, bool on, VoidCallback onTap) {
    final t = context.tt;
    return Material(
      color: on ? TC.accent : t.surf2,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, height: 1.35, color: on ? TC.onAccent : t.soft)),
        ),
      ),
    );
  }
}

// =================================================================== target manuali

class TargetsEditScreen extends StatefulWidget {
  const TargetsEditScreen({super.key});
  @override
  State<TargetsEditScreen> createState() => _TargetsEditScreenState();
}

class _TargetsEditScreenState extends State<TargetsEditScreen> {
  late final Profile p0 = context.appRead.profile!;
  late final kcalCtl = TextEditingController(text: '${p0.kcal}');
  late final pCtl = TextEditingController(text: '${p0.protein}');
  late final cCtl = TextEditingController(text: '${p0.carbs}');
  late final fCtl = TextEditingController(text: '${p0.fat}');
  late final waterCtl = TextEditingController(text: '${p0.waterMl}');
  String? error;

  @override
  void dispose() {
    for (final c in [kcalCtl, pCtl, cCtl, fCtl, waterCtl]) {
      c.dispose();
    }
    super.dispose();
  }

  int? _v(TextEditingController c) => parseNum(c.text)?.round();

  /// Cambiando le calorie ricalcolo i carboidrati tenendo fissi proteine e grassi.
  void _onKcal(String _) {
    final k = _v(kcalCtl), p = _v(pCtl), f = _v(fCtl);
    if (k == null || p == null || f == null || k < 800) return;
    final (_, c, _) = macrosFor(k, p, f);
    cCtl.text = '$c';
    setState(() {});
  }

  void _recompute() {
    final app = context.appRead;
    final t = computeTargets(
      sex: p0.sex,
      age: p0.age,
      heightCm: p0.heightCm,
      weight: app.currentWeight,
      activity: p0.activity,
      goal: p0.goal,
      rate: p0.goal == Goal.maintain ? 0 : p0.rate,
    );
    kcalCtl.text = '${t.kcal}';
    pCtl.text = '${t.protein}';
    cCtl.text = '${t.carbs}';
    fCtl.text = '${t.fat}';
    waterCtl.text = '${t.water}';
    setState(() {});
    toast(context, 'Valori consigliati per ${fDec(app.currentWeight, 1)} kg: premi Salva per applicarli');
  }

  void _save() {
    final k = _v(kcalCtl), p = _v(pCtl), c = _v(cCtl), f = _v(fCtl), w = _v(waterCtl);
    String? e;
    if (k == null || k < 1000 || k > 6000) {
      e = 'Calorie tra 1.000 e 6.000.';
    } else if (p == null || p < 30 || p > 400) {
      e = 'Proteine tra 30 e 400 g.';
    } else if (c == null || c < 0 || c > 900) {
      e = 'Carboidrati tra 0 e 900 g.';
    } else if (f == null || f < 20 || f > 300) {
      e = 'Grassi tra 20 e 300 g.';
    } else if (w == null || w < 500 || w > 6000) {
      e = 'Acqua tra 500 e 6.000 ml.';
    }
    setState(() => error = e);
    if (e != null) return;
    final app = context.appRead;
    app.saveProfile(p0.copyWith(
      kcal: k,
      protein: p,
      carbs: c,
      fat: f,
      waterMl: w,
      lastAdjust: todayKey(),
      changes: k != p0.kcal ? [...p0.changes, TargetChange(todayKey(), p0.kcal, k!, 'Modifica manuale')] : null,
    ));
    toast(context, 'Target aggiornati');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    final k = _v(kcalCtl) ?? 0, p = _v(pCtl) ?? 0, c = _v(cCtl) ?? 0, f = _v(fCtl) ?? 0;
    final fromMacro = p * 4 + c * 4 + f * 9;
    final diff = fromMacro - k;
    final changes = p0.changes.reversed.take(8).toList();
    return SubPage(
      title: 'Target',
      bottom: BottomActions(children: [
        GhostButton('Ricalcola', onTap: _recompute),
        PrimaryButton('Salva', onTap: _save),
      ]),
      body: PageBody(children: [
        _num('Calorie', kcalCtl, 'kcal', onChanged: _onKcal),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _num('Proteine', pCtl, 'g', color: TC.prot)),
          const SizedBox(width: 8),
          Expanded(child: _num('Carboidrati', cCtl, 'g', color: TC.carb)),
          const SizedBox(width: 8),
          Expanded(child: _num('Grassi', fCtl, 'g', color: TC.fat)),
        ]),
        const SizedBox(height: 8),
        Text(
          diff.abs() <= 40
              ? 'I macro corrispondono a ${fInt(fromMacro)} kcal ✓'
              : 'I macro fanno ${fInt(fromMacro)} kcal (${diff > 0 ? '+' : '−'}${fInt(diff.abs())} rispetto al target): modifica le calorie per ricalcolare i carboidrati.',
          style: TextStyle(fontSize: 12.5, color: diff.abs() <= 40 ? t.dim : TC.warn),
        ),
        const SizedBox(height: 14),
        _num('Acqua', waterCtl, 'ml'),
        if (p0.autoAdjust)
          const NoteBox(
            icon: Icons.autorenew_rounded,
            text: 'L\'adeguamento automatico è attivo: ogni 2 settimane Tigert potrà proporti di cambiare le calorie in base al peso reale.',
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(error!, style: const TextStyle(color: TC.danger, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        if (changes.isNotEmpty) ...[
          const SectionLabel('Storico modifiche'),
          for (final ch in changes)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                SizedBox(width: 92, child: Text(shortDateY(fromKey(ch.date)), style: TS.muted(t, 12))),
                Expanded(child: Text(ch.reason, style: TS.soft(t, 12.5))),
                Text('${fInt(ch.from)} → ${fInt(ch.to)}', style: TS.num(t, 13, w: FontWeight.w700)),
              ]),
            ),
        ],
      ]),
    );
  }

  Widget _num(String label, TextEditingController c, String suffix, {Color? color, ValueChanged<String>? onChanged}) => TextField(
        controller: c,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: TS.num(context.tt, 18, w: FontWeight.w700),
        onChanged: onChanged ?? (_) => setState(() {}),
        decoration: InputDecoration(labelText: label, suffixText: suffix, labelStyle: color == null ? null : TextStyle(color: color)),
      );
}
