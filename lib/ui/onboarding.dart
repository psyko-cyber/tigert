import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/fmt.dart';
import '../core/ids.dart';
import '../core/theme.dart';
import '../data/app_state.dart';
import '../data/catalog.dart';
import '../data/models.dart';
import '../logic/nutrition.dart';
import '../services/services.dart';
import 'settings/sync_settings.dart';
import 'shell.dart';
import 'widgets.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int step = 0;
  static const steps = 5;

  final nameCtl = TextEditingController();
  final ageCtl = TextEditingController();
  final heightCtl = TextEditingController();
  final weightCtl = TextEditingController();
  final targetCtl = TextEditingController();
  String sex = 'm';
  Goal goal = Goal.bulk;
  double rate = 0.25;
  String activity = 'moderato';
  Set<int> days = {1, 2, 4, 5};
  String templateKey = 'ulpp';
  bool templateTouched = false;
  String? error;

  @override
  void dispose() {
    for (final c in [nameCtl, ageCtl, heightCtl, weightCtl, targetCtl]) {
      c.dispose();
    }
    super.dispose();
  }

  double? get weight => parseNum(weightCtl.text);
  double? get height => parseNum(heightCtl.text);
  int? get age => parseNum(ageCtl.text)?.round();
  double? get target => parseNum(targetCtl.text);

  Targets get targets => computeTargets(
        sex: sex,
        age: age ?? 30,
        heightCm: height ?? 175,
        weight: weight ?? 70,
        activity: activity,
        goal: goal,
        rate: goal == Goal.maintain ? 0 : rate,
      );

  List<(double, String)> get rateOptions => goal == Goal.bulk
      ? const [(0.15, 'Lento'), (0.25, 'Consigliato'), (0.4, 'Veloce')]
      : const [(0.25, 'Lento'), (0.5, 'Consigliato'), (0.75, 'Veloce')];

  String? _validate() {
    switch (step) {
      case 1:
        if (age == null || age! < 14 || age! > 90) return 'Inserisci un\'età tra 14 e 90 anni.';
        if (height == null || height! < 120 || height! > 230) return 'Inserisci l\'altezza in cm (120-230).';
        if (weight == null || weight! < 35 || weight! > 250) return 'Inserisci il peso in kg (35-250).';
      case 2:
        if (goal != Goal.maintain) {
          final tg = target;
          if (tg == null || tg < 35 || tg > 250) return 'Inserisci il peso obiettivo in kg.';
          if (goal == Goal.bulk && tg <= weight!) return 'Per la massa il peso obiettivo deve essere più alto di quello attuale.';
          if (goal == Goal.cut && tg >= weight!) return 'Per la definizione il peso obiettivo deve essere più basso di quello attuale.';
        }
      case 3:
        if (days.isEmpty) return 'Scegli almeno un giorno di allenamento.';
    }
    return null;
  }

  void _next() {
    final e = _validate();
    setState(() => error = e);
    if (e != null) {
      HapticFeedback.heavyImpact();
      return;
    }
    if (step == 2 && goal == Goal.maintain) targetCtl.text = fDec(weight!, 1, true);
    if (step < steps - 1) {
      setState(() => step++);
    } else {
      _finish();
    }
  }

  Future<void> _finish() async {
    final app = context.appRead;
    final tg = targets;
    final tpl = templateByKey(templateKey);
    final plan = tpl.toPlan();
    final w = weight!;
    final profile = Profile(
      name: nameCtl.text.trim(),
      sex: sex,
      birthYear: DateTime.now().year - (age ?? 30),
      heightCm: height!,
      startWeight: w,
      startDate: todayKey(),
      goal: goal,
      targetWeight: goal == Goal.maintain ? w : target!,
      rate: goal == Goal.maintain ? 0 : rate,
      activity: activity,
      kcal: tg.kcal,
      protein: tg.protein,
      carbs: tg.carbs,
      fat: tg.fat,
      kcalStart: tg.kcal,
      waterMl: tg.water,
      trainingDays: days.toList()..sort(),
      planId: plan.id,
      reminders: Reminders.defaults(),
    );
    app.prefs.seenBadges = [];
    app.prefs.badgesInitialized = true;
    app.store.batch(() {
      app.store.put('plans', plan.id, plan.toMap());
      app.setWeight(todayKey(), w);
      app.saveProfile(profile);
    });
    ShellNav.go(0);
    await Services.notif.requestPermission();
    Services.notif.reschedule(delay: const Duration(seconds: 1));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
                child: Row(children: [
                  for (var i = 0; i < steps; i++) ...[
                    if (i > 0) const SizedBox(width: 6),
                    Expanded(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        height: 3,
                        decoration: BoxDecoration(color: i <= step ? TC.accent : t.surf2, borderRadius: BorderRadius.circular(99)),
                      ),
                    ),
                  ],
                ]),
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: ListView(
                    key: ValueKey(step),
                    padding: const EdgeInsets.fromLTRB(22, 26, 22, 16),
                    children: [..._stepContent(t), if (error != null) NoteBox(icon: Icons.error_outline_rounded, text: error)],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 4, 22, 16),
                child: Column(children: [
                  PrimaryButton(step == 0 ? 'Inizia' : (step == steps - 1 ? 'Inizia con Tigert' : 'Avanti'), onTap: _next),
                  const SizedBox(height: 10),
                  if (step == 0)
                    GhostButton(isMobile ? 'Ho già Tigert sul PC: collegati' : 'Ho già Tigert sul telefono',
                        onTap: () => push(context, const SyncSettingsScreen(fromOnboarding: true)))
                  else
                    GhostButton('Indietro', onTap: () => setState(() {
                          step--;
                          error = null;
                        })),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _art(Widget child) => Align(
        alignment: Alignment.centerLeft,
        child: Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(color: TC.accent, borderRadius: BorderRadius.circular(28)),
          alignment: Alignment.center,
          child: child,
        ),
      );

  Widget _title(String s) => Padding(
        padding: const EdgeInsets.only(top: 26),
        child: Text(s, style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.9, height: 1.1, color: context.tt.ink)),
      );

  Widget _body(String s) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(s, style: TextStyle(fontSize: 15, color: context.tt.dim, height: 1.5)),
      );

  Widget _row(String k, String v) {
    final t = context.tt;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(color: t.surf, border: Border.all(color: t.line), borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Expanded(child: Text(k, style: TextStyle(fontSize: 13, color: t.dim))),
        Text(v, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: t.ink, fontFeatures: tabular)),
      ]),
    );
  }

  Widget _field(String label, TextEditingController c, {String? suffix, bool number = true, String? hint}) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: TextField(
        controller: c,
        keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.name,
        textCapitalization: number ? TextCapitalization.none : TextCapitalization.words,
        inputFormatters: number ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))] : null,
        decoration: InputDecoration(labelText: label, suffixText: suffix, hintText: hint),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  List<Widget> _stepContent(TT t) {
    switch (step) {
      case 0:
        return [
          _art(const TigertMark(size: 64, color: TC.onAccent)),
          _title('La forza di una tigre, la mira di un bersaglio.'),
          _body('Tigert tiene insieme allenamento e cucina in un unico numero: il voto del giorno. Ogni giorno sai cosa manca per salire.'),
          const SizedBox(height: 12),
          _row('Nutrizione', '50%'),
          _row('Allenamento', '35%'),
          _row('Abitudini', '15%'),
        ];
      case 1:
        return [
          _art(const Icon(Icons.person_rounded, size: 46, color: TC.onAccent)),
          _title('Partiamo da te'),
          _body('Servono per calcolare il tuo fabbisogno. Restano solo sui tuoi dispositivi.'),
          _field('Come ti chiami?', nameCtl, number: false, hint: 'Nome'),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _choice('Uomo', sex == 'm', () => setState(() => sex = 'm'))),
            const SizedBox(width: 10),
            Expanded(child: _choice('Donna', sex == 'f', () => setState(() => sex = 'f'))),
          ]),
          _field('Età', ageCtl, suffix: 'anni'),
          _field('Altezza', heightCtl, suffix: 'cm'),
          _field('Peso attuale', weightCtl, suffix: 'kg'),
        ];
      case 2:
        final eta = goal == Goal.maintain || target == null || weight == null
            ? null
            : today().add(Duration(days: ((target! - weight!).abs() / rate * 7).round()));
        return [
          _art(const Icon(Icons.track_changes_rounded, size: 48, color: TC.onAccent)),
          _title('Qual è il tuo obiettivo?'),
          const SizedBox(height: 16),
          for (final g in Goal.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _optionCard(
                g.label,
                switch (g) {
                  Goal.bulk => 'Aumentare peso e muscoli con un surplus controllato.',
                  Goal.cut => 'Perdere grasso mantenendo la forza.',
                  Goal.maintain => 'Restare stabile e migliorare la composizione.',
                },
                goal == g,
                () => setState(() {
                  goal = g;
                  rate = g == Goal.bulk ? 0.25 : 0.5;
                }),
              ),
            ),
          if (goal != Goal.maintain) ...[
            _field('Peso obiettivo', targetCtl, suffix: 'kg'),
            const SizedBox(height: 16),
            const Label('Ritmo'),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (r, l) in rateOptions) PillChip('$l · ${goal == Goal.bulk ? '+' : '−'}${fDec(r, 2, true)} kg/sett', selected: rate == r, onTap: () => setState(() => rate = r)),
            ]),
            if (eta != null) NoteBox(text: 'Con questo ritmo arrivi a ${fDec(target!, 1, true)} kg verso ${mesi[eta.month - 1]} ${eta.year}. I target si adattano da soli se il peso si ferma.'),
          ],
        ];
      case 3:
        final suggested = suggestTemplate(days.length);
        if (!templateTouched) templateKey = suggested.key;
        return [
          _art(const Icon(Icons.calendar_month_rounded, size: 46, color: TC.onAccent)),
          _title('Attività e allenamento'),
          const SizedBox(height: 18),
          const Label('Quanto ti muovi?'),
          const SizedBox(height: 8),
          for (final e in activityLevels.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _optionCard(e.value.$1, activityDescriptions[e.key] ?? '', activity == e.key, () => setState(() => activity = e.key), dense: true),
            ),
          const SizedBox(height: 10),
          const Label('Giorni di allenamento'),
          const SizedBox(height: 8),
          Row(children: [
            for (var d = 1; d <= 7; d++) ...[
              if (d > 1) const SizedBox(width: 6),
              Expanded(
                child: _dayChip(giorniBrevi[d - 1], days.contains(d), () => setState(() {
                      days.contains(d) ? days.remove(d) : days.add(d);
                    })),
              ),
            ],
          ]),
          const SizedBox(height: 16),
          Label('Scheda · ${days.length} ${days.length == 1 ? 'giorno' : 'giorni'}'),
          const SizedBox(height: 8),
          for (final tpl in splitTemplates)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _optionCard(
                '${tpl.name}${tpl.key == suggested.key ? '  · consigliata' : ''}',
                '${tpl.desc} ${tpl.days.map((d) => d.$1).join(' · ')}',
                templateKey == tpl.key,
                () => setState(() {
                  templateKey = tpl.key;
                  templateTouched = true;
                }),
                dense: true,
              ),
            ),
          NoteBox(text: 'Potrai modificare esercizi, serie e ripetizioni quando vuoi. Se cambi i giorni, la scheda si riadatta a rotazione.'),
        ];
      default:
        final tg = targets;
        final delta = tg.kcal - tg.tdee;
        return [
          _art(const Icon(Icons.bolt_rounded, size: 50, color: TC.onAccent)),
          _title('${fInt(tg.kcal)} kcal al giorno'),
          _body(switch (goal) {
            Goal.bulk => 'Surplus controllato di circa ${fInt(delta)} kcal sul tuo dispendio stimato (${fInt(tg.tdee)} kcal). Ogni 2 settimane Tigert controlla il peso e alza i target se si ferma.',
            Goal.cut => 'Deficit di circa ${fInt(-delta)} kcal sul tuo dispendio stimato (${fInt(tg.tdee)} kcal). Proteine alte per proteggere i muscoli.',
            Goal.maintain => 'In linea con il tuo dispendio stimato. Tigert corregge il tiro se il peso si sposta.',
          }),
          const SizedBox(height: 8),
          _row('Calorie', '${fInt(tg.kcal)} kcal'),
          _row('Proteine', '${tg.protein} g'),
          _row('Carboidrati', '${tg.carbs} g'),
          _row('Grassi', '${tg.fat} g'),
          _row('Acqua', '${fDec(tg.water / 1000, 2, true)} L'),
          NoteBox(text: 'Sono stime di partenza: dopo 2 settimane di dati Tigert calcola il tuo dispendio reale e li ricalibra.'),
        ];
    }
  }

  Widget _choice(String label, bool on, VoidCallback onTap) {
    final t = context.tt;
    return Material(
      color: on ? TC.accent : t.surf,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: on ? TC.accent : t.line)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(height: 48, child: Center(child: Text(label, style: TextStyle(fontWeight: FontWeight.w700, color: on ? TC.onAccent : t.ink)))),
      ),
    );
  }

  Widget _dayChip(String label, bool on, VoidCallback onTap) {
    final t = context.tt;
    return Material(
      color: on ? TC.accent : t.surf2,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: SizedBox(height: 42, child: Center(child: Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: on ? TC.onAccent : t.dim)))),
      ),
    );
  }

  Widget _optionCard(String title, String sub, bool on, VoidCallback onTap, {bool dense = false}) {
    final t = context.tt;
    return TCard(
      onTap: onTap,
      radius: 14,
      borderColor: on ? TC.accent : null,
      color: on ? t.accentTint : null,
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: dense ? 11 : 14),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: t.ink)),
            if (sub.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(sub, style: TextStyle(fontSize: 12.5, color: t.dim, height: 1.35)),
            ],
          ]),
        ),
        const SizedBox(width: 10),
        Icon(on ? Icons.check_circle_rounded : Icons.circle_outlined, color: on ? t.accentInk : t.dim, size: 22),
      ]),
    );
  }
}
