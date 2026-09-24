import '../core/fmt.dart';

double _d(Object? v, [double def = 0]) => v is num ? v.toDouble() : (v is String ? (parseNum(v) ?? def) : def);
int _i(Object? v, [int def = 0]) => v is num ? v.round() : def;
int? _in(Object? v) => v is num ? v.round() : null;
String _s(Object? v, [String def = '']) => v is String ? v : def;

// =================================================================== macro

class Macro {
  final double kcal, p, c, f;
  const Macro(this.kcal, this.p, this.c, this.f);
  static const zero = Macro(0, 0, 0, 0);
  Macro operator +(Macro o) => Macro(kcal + o.kcal, p + o.p, c + o.c, f + o.f);
  Macro scale(double k) => Macro(kcal * k, p * k, c * k, f * k);
  Map<String, dynamic> toMap() => {'kcal': kcal, 'p': p, 'c': c, 'f': f};
}

// =================================================================== profilo

enum Goal { bulk, cut, maintain }

extension GoalX on Goal {
  String get label => switch (this) { Goal.bulk => 'Massa', Goal.cut => 'Definizione', Goal.maintain => 'Mantenimento' };
  String get key => name;
}

Goal goalFrom(String? s) => Goal.values.firstWhere((g) => g.name == s, orElse: () => Goal.maintain);

/// Fase per il voto delle calorie: quanto puoi scostarti dal target senza perdere punti.
/// Non cambia il target, solo la tolleranza.
enum Phase { maintain, lean, heavy, cut }

extension PhaseX on Phase {
  String get label => switch (this) {
        Phase.maintain => 'Mantenimento',
        Phase.lean => 'Massa pulita',
        Phase.heavy => 'Bulk pesante',
        Phase.cut => 'Definizione',
      };

  /// Scostamenti dal target (frazioni): voto pieno fino a [underFull]/[overFull],
  /// poi scende fino a 0 a [underZero]/[overZero].
  ({double underFull, double underZero, double overFull, double overZero}) get tol => switch (this) {
        Phase.maintain => (underFull: 0.10, underZero: 0.30, overFull: 0.10, overZero: 0.30),
        Phase.lean => (underFull: 0.10, underZero: 0.30, overFull: 0.15, overZero: 0.40),
        Phase.heavy => (underFull: 0.10, underZero: 0.30, overFull: 0.30, overZero: 0.70),
        Phase.cut => (underFull: 0.15, underZero: 0.40, overFull: 0.10, overZero: 0.30),
      };

  String get tolText {
    final x = tol;
    String pc(double v) => '${(v * 100).round()}%';
    return x.underFull == x.overFull ? 'voto calorie pieno entro ±${pc(x.overFull)} dal target' : 'voto calorie pieno da −${pc(x.underFull)} a +${pc(x.overFull)} del target';
  }
}

Phase phaseFrom(String? s) => Phase.values.firstWhere((g) => g.name == s, orElse: () => Phase.maintain);

class PhaseChange {
  final String date;
  final Phase from, to;
  const PhaseChange(this.date, this.from, this.to);
  Map<String, dynamic> toMap() => {'date': date, 'from': from.name, 'to': to.name};
  factory PhaseChange.fromMap(Map m) => PhaseChange(_s(m['date']), phaseFrom(m['from'] as String?), phaseFrom(m['to'] as String?));
}

/// Attrezzi che hai a casa, per la seduta extra del report settimanale.
class HomeGym {
  final bool bar; // sbarra per trazioni
  final bool dip; // parallele
  final bool bench; // panca piana
  final bool incline; // panca inclinabile
  final double dbKg; // peso massimo di un manubrio, 0 = niente manubri
  const HomeGym({this.bar = false, this.dip = false, this.bench = false, this.incline = false, this.dbKg = 0});
  Map<String, dynamic> toMap() => {'bar': bar, 'dip': dip, 'bench': bench, 'incline': incline, 'dbKg': dbKg};
  factory HomeGym.fromMap(Map m) => HomeGym(bar: m['bar'] == true, dip: m['dip'] == true, bench: m['bench'] == true, incline: m['incline'] == true, dbKg: _d(m['dbKg']));
  HomeGym copyWith({bool? bar, bool? dip, bool? bench, bool? incline, double? dbKg}) =>
      HomeGym(bar: bar ?? this.bar, dip: dip ?? this.dip, bench: bench ?? this.bench, incline: incline ?? this.incline, dbKg: dbKg ?? this.dbKg);
  bool has(String k) => switch (k) { 'bar' => bar, 'dip' => dip, 'bench' => bench || incline, 'incline' => incline, 'db' => dbKg > 0, _ => false };
  String get summary {
    final l = [
      if (bar) 'sbarra',
      if (dip) 'parallele',
      if (incline) 'panca inclinabile' else if (bench) 'panca',
      if (dbKg > 0) 'manubri fino a ${fDec(dbKg, 1, true)} kg',
    ];
    return l.isEmpty ? 'Solo corpo libero' : l.join(' · ');
  }
}

const activityLevels = <String, (String, double)>{
  'sedentario': ('Sedentario', 1.2),
  'leggero': ('Leggero', 1.375),
  'moderato': ('Moderato', 1.55),
  'attivo': ('Attivo', 1.725),
  'molto_attivo': ('Molto attivo', 1.9),
};

const activityDescriptions = <String, String>{
  'sedentario': 'Lavoro seduto, pochi passi, niente sport oltre alla palestra leggera',
  'leggero': 'Lavoro seduto + 2-3 allenamenti a settimana',
  'moderato': '3-5 allenamenti a settimana, 6-8 mila passi',
  'attivo': 'Allenamenti quasi quotidiani o lavoro in piedi',
  'molto_attivo': 'Lavoro fisico pesante + allenamenti intensi',
};

class Reminder {
  final String id;
  final String label;
  final String time; // "HH:mm"
  final bool on;
  const Reminder(this.id, this.label, this.time, this.on);
  Map<String, dynamic> toMap() => {'id': id, 'label': label, 'time': time, 'on': on};
  factory Reminder.fromMap(Map m) => Reminder(_s(m['id']), _s(m['label']), _s(m['time'], '08:00'), m['on'] != false);
  Reminder copyWith({String? time, bool? on, String? label}) => Reminder(id, label ?? this.label, time ?? this.time, on ?? this.on);
  int get hour => int.tryParse(time.split(':').first) ?? 8;
  int get minute => int.tryParse(time.split(':').last) ?? 0;
}

class Reminders {
  final List<Reminder> meals;
  final bool waterOn;
  final int waterEvery; // minuti
  final String waterFrom, waterTo;
  final bool trainingOn;
  final String trainingTime;
  final bool weightOn;
  final String weightTime;
  final bool eveningOn; // riepilogo serale se mancano dati
  final String eveningTime;
  final bool coachOn; // consigli di carico nel promemoria di allenamento
  final bool suppOn; // integratori non ancora spuntati
  final String suppTime;
  final bool reportOn; // report settimanale dei muscoli, il sabato
  final String reportTime;

  const Reminders({
    required this.meals,
    this.waterOn = true,
    this.waterEvery = 120,
    this.waterFrom = '09:00',
    this.waterTo = '21:00',
    this.trainingOn = true,
    this.trainingTime = '17:30',
    this.weightOn = true,
    this.weightTime = '07:30',
    this.eveningOn = true,
    this.eveningTime = '21:30',
    this.coachOn = true,
    this.suppOn = true,
    this.suppTime = '20:00',
    this.reportOn = true,
    this.reportTime = '09:00',
  });

  static Reminders defaults() => const Reminders(meals: [
        Reminder('colazione', 'Colazione', '08:00', true),
        Reminder('pranzo', 'Pranzo', '13:00', true),
        Reminder('cena', 'Cena', '20:00', true),
      ]);

  Map<String, dynamic> toMap() => {
        'meals': meals.map((e) => e.toMap()).toList(),
        'waterOn': waterOn,
        'waterEvery': waterEvery,
        'waterFrom': waterFrom,
        'waterTo': waterTo,
        'trainingOn': trainingOn,
        'trainingTime': trainingTime,
        'weightOn': weightOn,
        'weightTime': weightTime,
        'eveningOn': eveningOn,
        'eveningTime': eveningTime,
        'coachOn': coachOn,
        'suppOn': suppOn,
        'suppTime': suppTime,
        'reportOn': reportOn,
        'reportTime': reportTime,
      };

  factory Reminders.fromMap(Map? m) {
    if (m == null) return defaults();
    return Reminders(
      meals: ((m['meals'] as List?) ?? const []).map((e) => Reminder.fromMap(e as Map)).toList(),
      waterOn: m['waterOn'] != false,
      waterEvery: _i(m['waterEvery'], 120),
      waterFrom: _s(m['waterFrom'], '09:00'),
      waterTo: _s(m['waterTo'], '21:00'),
      trainingOn: m['trainingOn'] != false,
      trainingTime: _s(m['trainingTime'], '17:30'),
      weightOn: m['weightOn'] != false,
      weightTime: _s(m['weightTime'], '07:30'),
      eveningOn: m['eveningOn'] != false,
      eveningTime: _s(m['eveningTime'], '21:30'),
      coachOn: m['coachOn'] != false,
      suppOn: m['suppOn'] != false,
      suppTime: _s(m['suppTime'], '20:00'),
      reportOn: m['reportOn'] != false,
      reportTime: _s(m['reportTime'], '09:00'),
    );
  }

  Reminders copyWith({
    List<Reminder>? meals,
    bool? waterOn,
    int? waterEvery,
    String? waterFrom,
    String? waterTo,
    bool? trainingOn,
    String? trainingTime,
    bool? weightOn,
    String? weightTime,
    bool? eveningOn,
    String? eveningTime,
    bool? coachOn,
    bool? suppOn,
    String? suppTime,
    bool? reportOn,
    String? reportTime,
  }) =>
      Reminders(
        meals: meals ?? this.meals,
        waterOn: waterOn ?? this.waterOn,
        waterEvery: waterEvery ?? this.waterEvery,
        waterFrom: waterFrom ?? this.waterFrom,
        waterTo: waterTo ?? this.waterTo,
        trainingOn: trainingOn ?? this.trainingOn,
        trainingTime: trainingTime ?? this.trainingTime,
        weightOn: weightOn ?? this.weightOn,
        weightTime: weightTime ?? this.weightTime,
        eveningOn: eveningOn ?? this.eveningOn,
        eveningTime: eveningTime ?? this.eveningTime,
        coachOn: coachOn ?? this.coachOn,
        suppOn: suppOn ?? this.suppOn,
        suppTime: suppTime ?? this.suppTime,
        reportOn: reportOn ?? this.reportOn,
        reportTime: reportTime ?? this.reportTime,
      );
}

class TargetChange {
  final String date;
  final int from, to;
  final String reason;
  const TargetChange(this.date, this.from, this.to, this.reason);
  Map<String, dynamic> toMap() => {'date': date, 'from': from, 'to': to, 'reason': reason};
  factory TargetChange.fromMap(Map m) => TargetChange(_s(m['date']), _i(m['from']), _i(m['to']), _s(m['reason']));
}

class Profile {
  final String name;
  final String sex; // 'm' | 'f'
  final int birthYear;
  final double heightCm;
  final double startWeight;
  final String startDate;
  final Goal goal;
  final double targetWeight;
  final double rate; // kg/settimana (valore assoluto)
  final bool heavy; // in massa: bulk pesante (più tolleranza sopra il target)
  final List<PhaseChange> phases; // cambi di fase: i giorni passati tengono la loro
  final String activity;
  final int kcal, protein, carbs, fat;
  final int kcalStart;
  final bool autoAdjust;
  final String? lastAdjust;
  final List<TargetChange> changes;
  final int waterMl, steps, sleepMin;
  final Map<String, bool> habits; // water, sleep, steps, alcohol, supp (integratori, fuori dal voto)
  final List<String> supplements; // integratori da spuntare ogni giorno
  final List<int> trainingDays; // 1 = lunedì
  final String? planId;
  final Reminders reminders;
  final HomeGym? home; // null = non ancora indicata

  const Profile({
    required this.name,
    required this.sex,
    required this.birthYear,
    required this.heightCm,
    required this.startWeight,
    required this.startDate,
    required this.goal,
    required this.targetWeight,
    required this.rate,
    this.heavy = false,
    this.phases = const [],
    required this.activity,
    required this.kcal,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.kcalStart,
    this.autoAdjust = true,
    this.lastAdjust,
    this.changes = const [],
    required this.waterMl,
    this.steps = 8000,
    this.sleepMin = 450,
    this.habits = const {'water': true, 'sleep': true, 'steps': true, 'alcohol': true},
    this.supplements = const ['Creatina'],
    required this.trainingDays,
    this.planId,
    required this.reminders,
    this.home,
  });

  int get age => DateTime.now().year - birthYear;
  bool habitOn(String k) => habits[k] ?? true;

  Phase get phase => switch (goal) { Goal.bulk => heavy ? Phase.heavy : Phase.lean, Goal.cut => Phase.cut, Goal.maintain => Phase.maintain };

  /// La fase in vigore in quel giorno.
  Phase phaseOn(String date) {
    if (phases.isEmpty) return phase;
    if (date.compareTo(phases.first.date) < 0) return phases.first.from;
    var out = phases.first.to;
    for (final c in phases) {
      if (c.date.compareTo(date) <= 0) out = c.to;
    }
    return out;
  }

  /// [phases] con il cambio di oggi se la fase di [next] è diversa da questa.
  List<PhaseChange> phasesFor(Profile next, String date) {
    final from = phaseOn(date), to = next.phase;
    final kept = [for (final c in phases) if (c.date != date) c];
    // stesso giorno: resta la fase che c'era prima di oggi
    final start = phases.where((c) => c.date == date).firstOrNull?.from ?? from;
    if (start == to) return kept;
    return [...kept, PhaseChange(date, start, to)];
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'sex': sex,
        'birthYear': birthYear,
        'heightCm': heightCm,
        'startWeight': startWeight,
        'startDate': startDate,
        'goal': goal.key,
        'targetWeight': targetWeight,
        'rate': rate,
        'heavy': heavy,
        'phases': phases.map((e) => e.toMap()).toList(),
        'activity': activity,
        'kcal': kcal,
        'protein': protein,
        'carbs': carbs,
        'fat': fat,
        'kcalStart': kcalStart,
        'autoAdjust': autoAdjust,
        'lastAdjust': lastAdjust,
        'changes': changes.map((e) => e.toMap()).toList(),
        'waterMl': waterMl,
        'steps': steps,
        'sleepMin': sleepMin,
        'habits': habits,
        'supplements': supplements,
        'trainingDays': trainingDays,
        'planId': planId,
        'reminders': reminders.toMap(),
        if (home != null) 'home': home!.toMap(),
      };

  factory Profile.fromMap(Map m) => Profile(
        name: _s(m['name']),
        sex: _s(m['sex'], 'm'),
        birthYear: _i(m['birthYear'], 2000),
        heightCm: _d(m['heightCm'], 175),
        startWeight: _d(m['startWeight'], 70),
        startDate: _s(m['startDate'], todayKey()),
        goal: goalFrom(m['goal'] as String?),
        targetWeight: _d(m['targetWeight'], 70),
        rate: _d(m['rate'], 0.25),
        heavy: m['heavy'] == true,
        phases: ((m['phases'] as List?) ?? const []).map((e) => PhaseChange.fromMap(e as Map)).toList(),
        activity: _s(m['activity'], 'moderato'),
        kcal: _i(m['kcal'], 2200),
        protein: _i(m['protein'], 120),
        carbs: _i(m['carbs'], 250),
        fat: _i(m['fat'], 70),
        kcalStart: _i(m['kcalStart'], _i(m['kcal'], 2200)),
        autoAdjust: m['autoAdjust'] != false,
        lastAdjust: m['lastAdjust'] as String?,
        changes: ((m['changes'] as List?) ?? const []).map((e) => TargetChange.fromMap(e as Map)).toList(),
        waterMl: _i(m['waterMl'], 2500),
        steps: _i(m['steps'], 8000),
        sleepMin: _i(m['sleepMin'], 450),
        habits: ((m['habits'] as Map?) ?? const {'water': true, 'sleep': true, 'steps': true, 'alcohol': true})
            .map((k, v) => MapEntry(k as String, v == true)),
        supplements: ((m['supplements'] as List?) ?? const ['Creatina']).map((e) => e.toString()).toList(),
        trainingDays: ((m['trainingDays'] as List?) ?? const [1, 3, 5]).map((e) => _i(e)).toList()..sort(),
        planId: m['planId'] as String?,
        reminders: Reminders.fromMap(m['reminders'] as Map?),
        home: m['home'] is Map ? HomeGym.fromMap(m['home'] as Map) : null,
      );

  Profile copyWith({
    String? name,
    String? sex,
    int? birthYear,
    double? heightCm,
    double? startWeight,
    String? startDate,
    Goal? goal,
    double? targetWeight,
    double? rate,
    bool? heavy,
    List<PhaseChange>? phases,
    String? activity,
    int? kcal,
    int? protein,
    int? carbs,
    int? fat,
    int? kcalStart,
    bool? autoAdjust,
    String? lastAdjust,
    List<TargetChange>? changes,
    int? waterMl,
    int? steps,
    int? sleepMin,
    Map<String, bool>? habits,
    List<String>? supplements,
    List<int>? trainingDays,
    String? planId,
    Reminders? reminders,
    HomeGym? home,
  }) =>
      Profile(
        name: name ?? this.name,
        sex: sex ?? this.sex,
        birthYear: birthYear ?? this.birthYear,
        heightCm: heightCm ?? this.heightCm,
        startWeight: startWeight ?? this.startWeight,
        startDate: startDate ?? this.startDate,
        goal: goal ?? this.goal,
        targetWeight: targetWeight ?? this.targetWeight,
        rate: rate ?? this.rate,
        heavy: heavy ?? this.heavy,
        phases: phases ?? this.phases,
        activity: activity ?? this.activity,
        kcal: kcal ?? this.kcal,
        protein: protein ?? this.protein,
        carbs: carbs ?? this.carbs,
        fat: fat ?? this.fat,
        kcalStart: kcalStart ?? this.kcalStart,
        autoAdjust: autoAdjust ?? this.autoAdjust,
        lastAdjust: lastAdjust ?? this.lastAdjust,
        changes: changes ?? this.changes,
        waterMl: waterMl ?? this.waterMl,
        steps: steps ?? this.steps,
        sleepMin: sleepMin ?? this.sleepMin,
        habits: habits ?? this.habits,
        supplements: supplements ?? this.supplements,
        trainingDays: trainingDays ?? this.trainingDays,
        planId: planId ?? this.planId,
        reminders: reminders ?? this.reminders,
        home: home ?? this.home,
      );
}

// =================================================================== alimenti

class Portion {
  final String label;
  final double g;
  const Portion(this.label, this.g);
  Map<String, dynamic> toMap() => {'l': label, 'g': g};
  factory Portion.fromMap(Map m) => Portion(_s(m['l']), _d(m['g']));
}

/// Ingrediente di un piatto composto: [r] grammi per ogni grammo della base
/// (la prima parte è la base, con r = 1). Valori per 100 g.
/// [opt]: facoltativo (es. parmigiano), escluso dai valori di default del piatto.
class DishPart {
  final String name;
  final double r;
  final double kcal, p, c, f;
  final bool opt;
  const DishPart(this.name, this.r, this.kcal, this.p, this.c, this.f, {this.opt = false});
  Macro per(double g) => Macro(kcal, p, c, f).scale(g / 100);
  Map<String, dynamic> toMap() => {'n': name, 'r': r, 'k': kcal, 'p': p, 'c': c, 'f': f, if (opt) 'o': true};
  factory DishPart.fromMap(Map m) => DishPart(_s(m['n']), _d(m['r'], 1), _d(m['k']), _d(m['p']), _d(m['c']), _d(m['f']), opt: m['o'] == true);
}

/// Quanto condimento: la stima del piatto moltiplicata per il fattore.
const sauceLevels = [(0.6, 'Poco'), (1.0, 'Normale'), (1.5, 'Tanto')];

/// Cottura degli alimenti con [Food.cook]: '' senza olio, 'olio' con olio, 'fritto'.
const cookLabels = {'': 'Senza olio', 'olio': 'Con olio', 'fritto': 'Fritto'};

/// Olio assorbito, in grammi per grammo di alimento crudo.
double cookOil(String cat, String cook) {
  final veg = cat == 'Verdure';
  return switch (cook) {
    'olio' => veg ? 0.08 : 0.05,
    'fritto' => veg ? 0.15 : 0.10,
    _ => 0,
  };
}

/// Olio extravergine per 100 g.
const _oil = Macro(899, 0, 0, 99.9);

/// Scelte fatte sulla scheda alimento: condimento, formaggio, cottura.
class FoodOpts {
  final double sauce;
  final bool extra;
  final String cook;
  const FoodOpts({this.sauce = 1, this.extra = false, this.cook = ''});
  static const none = FoodOpts();
}

/// Scelte in breve per il diario, es. " · fritto" o " · tanto condimento".
String optsLabel(FoodOpts o) => [
      if (o.cook.isNotEmpty && cookLabels.containsKey(o.cook)) cookLabels[o.cook]!.toLowerCase(),
      if (o.sauce < 1) 'poco condimento' else if (o.sauce > 1) 'tanto condimento',
      if (o.extra) 'con formaggio',
    ].map((s) => ' · $s').join();

class Food {
  final String id;
  final String name;
  final String? brand;
  final String? ean;
  final String cat;
  final double kcal, p, c, f, fiber;
  final List<Portion> portions;
  final String src; // seed | user | off | photo
  final bool ml; // liquido: quantità in ml (1 ml = 1 g, valori per 100 ml)
  /// Piatto composto: la quantità è il peso da crudo della base (es. "pasta cruda")
  /// e i valori sono per 100 g di base, condimento stimato compreso ([parts]).
  final String? base;
  final List<DishPart> parts;
  final bool cook; // si cuoce: scelta senza olio / con olio / fritto

  const Food({
    required this.id,
    required this.name,
    this.brand,
    this.ean,
    this.cat = '',
    required this.kcal,
    required this.p,
    required this.c,
    required this.f,
    this.fiber = 0,
    this.portions = const [],
    this.src = 'user',
    this.ml = false,
    this.base,
    this.parts = const [],
    this.cook = false,
  });

  Macro per(double grams) => Macro(kcal, p, c, f).scale(grams / 100);

  /// Valori con le scelte della scheda (condimento, formaggio, olio di cottura).
  Macro macroFor(double grams, [FoodOpts o = FoodOpts.none]) {
    if (isDish) {
      return partsFor(grams, o).fold(Macro.zero, (a, e) => a + e.$1.per(e.$2));
    }
    final oil = cook ? cookOil(cat, o.cook) * grams : 0.0;
    return per(grams) + _oil.scale(oil / 100);
  }

  /// Grammi di olio di cottura stimati per [grams] di alimento.
  double oilFor(double grams, String cookMode) => cook ? cookOil(cat, cookMode) * grams : 0;

  /// Tiene solo le scelte che valgono per questo alimento.
  FoodOpts cleanOpts(FoodOpts o) => FoodOpts(
        sauce: isDish ? o.sauce : 1,
        extra: isDish && extraPart != null && o.extra,
        cook: cook ? o.cook : '',
      );
  String get displayName => brand == null || brand!.isEmpty ? name : '$name · $brand';
  bool get isSeed => src == 'seed';
  String get unit => ml ? 'ml' : 'g';
  bool get isDish => base != null && parts.isNotEmpty;

  /// Unità della quantità, es. "g", "ml" o "g pasta cruda".
  String get qtyUnit => base == null ? unit : '$unit $base';

  /// Parte facoltativa del piatto (es. parmigiano), se c'è.
  DishPart? get extraPart => parts.where((x) => x.opt).firstOrNull;

  /// Grammi di ogni ingrediente per [g] grammi di base (i facoltativi solo se scelti).
  List<(DishPart, double)> partsFor(double g, [FoodOpts o = FoodOpts.none]) => [
        for (var i = 0; i < parts.length; i++)
          if (!parts[i].opt || o.extra) (parts[i], g * parts[i].r * (i == 0 || parts[i].opt ? 1 : o.sauce)),
      ];

  Map<String, dynamic> toMap() => {
        'n': name,
        'brand': brand,
        'ean': ean,
        'cat': cat,
        'k': kcal,
        'p': p,
        'c': c,
        'f': f,
        'fi': fiber,
        'por': portions.map((e) => e.toMap()).toList(),
        'src': src,
        'ml': ml,
        if (base != null) 'base': base,
        if (parts.isNotEmpty) 'parts': parts.map((e) => e.toMap()).toList(),
        if (cook) 'ck': true,
      };

  factory Food.fromMap(Map m, {String? src}) => Food(
        id: _s(m['id']),
        name: _s(m['n']),
        brand: m['brand'] as String?,
        ean: m['ean'] as String?,
        cat: _s(m['cat']),
        kcal: _d(m['k']),
        p: _d(m['p']),
        c: _d(m['c']),
        f: _d(m['f']),
        fiber: _d(m['fi']),
        portions: ((m['por'] as List?) ?? const []).map((e) => Portion.fromMap(e as Map)).toList(),
        src: src ?? _s(m['src'], 'user'),
        ml: m['ml'] is bool ? m['ml'] as bool : isLiquidFood(_s(m['n']), _s(m['cat'])),
        base: m['base'] as String?,
        parts: ((m['parts'] as List?) ?? const []).map((e) => DishPart.fromMap(e as Map)).toList(),
        cook: m['ck'] == true,
      );

  Food copyWith({String? id, String? name, String? brand, String? ean, double? kcal, double? p, double? c, double? f, List<Portion>? portions, String? src, String? cat, bool? ml}) => Food(
        id: id ?? this.id,
        name: name ?? this.name,
        brand: brand ?? this.brand,
        ean: ean ?? this.ean,
        cat: cat ?? this.cat,
        kcal: kcal ?? this.kcal,
        p: p ?? this.p,
        c: c ?? this.c,
        f: f ?? this.f,
        fiber: fiber,
        portions: portions ?? this.portions,
        src: src ?? this.src,
        ml: ml ?? this.ml,
        base: base,
        parts: parts,
        cook: cook,
      );
}

/// Alimenti che di default si misurano in ml (bevande, latte, bevande vegetali, succhi).
bool isLiquidFood(String name, String cat) =>
    cat == 'Bevande' || RegExp(r'^(latte\b|bevanda\b|acqua\b|succo\b|spremuta\b)|\(succo\)', caseSensitive: false).hasMatch(name.trim());

class RecipeItem {
  final String foodId;
  final String name;
  final double g;
  final double kcal, p, c, f; // per 100 g (istantanea)
  final bool ml;
  const RecipeItem(this.foodId, this.name, this.g, this.kcal, this.p, this.c, this.f, {this.ml = false});
  Macro get macro => Macro(kcal, p, c, f).scale(g / 100);
  String get unit => ml ? 'ml' : 'g';
  Map<String, dynamic> toMap() => {'food': foodId, 'n': name, 'g': g, 'k': kcal, 'p': p, 'c': c, 'f': f, if (ml) 'ml': true};
  factory RecipeItem.fromMap(Map m) =>
      RecipeItem(_s(m['food']), _s(m['n']), _d(m['g']), _d(m['k']), _d(m['p']), _d(m['c']), _d(m['f']), ml: m['ml'] == true);
  factory RecipeItem.of(Food food, double g) => RecipeItem(food.id, food.name, g, food.kcal, food.p, food.c, food.f, ml: food.ml);
  RecipeItem withGrams(double g) => RecipeItem(foodId, name, g, kcal, p, c, f, ml: ml);
}

class Recipe {
  final String id;
  final String name;
  final double servings;
  final List<RecipeItem> items;
  final String note;
  const Recipe({required this.id, required this.name, this.servings = 1, this.items = const [], this.note = ''});

  Macro get total => items.fold(Macro.zero, (a, b) => a + b.macro);
  Macro get perServing => total.scale(1 / (servings <= 0 ? 1 : servings));
  double get totalGrams => items.fold(0.0, (a, b) => a + b.g);

  Map<String, dynamic> toMap() => {'n': name, 'servings': servings, 'items': items.map((e) => e.toMap()).toList(), 'note': note};
  factory Recipe.fromMap(Map m) => Recipe(
        id: _s(m['id']),
        name: _s(m['n']),
        servings: _d(m['servings'], 1),
        items: ((m['items'] as List?) ?? const []).map((e) => RecipeItem.fromMap(e as Map)).toList(),
        note: _s(m['note']),
      );
  Recipe copyWith({String? name, double? servings, List<RecipeItem>? items}) =>
      Recipe(id: id, name: name ?? this.name, servings: servings ?? this.servings, items: items ?? this.items, note: note);
}

// =================================================================== diario

const mealKeys = ['colazione', 'spuntino', 'pranzo', 'merenda', 'cena', 'post'];
const mealLabels = {
  'colazione': 'Colazione',
  'spuntino': 'Spuntino',
  'pranzo': 'Pranzo',
  'merenda': 'Merenda',
  'cena': 'Cena',
  'post': 'Post-workout',
};

String mealForNow([DateTime? t]) {
  final n = t ?? DateTime.now();
  final m = n.hour * 60 + n.minute;
  if (m < 10 * 60 + 30) return 'colazione';
  if (m < 12 * 60) return 'spuntino';
  if (m < 15 * 60 + 30) return 'pranzo';
  if (m < 18 * 60 + 30) return 'merenda';
  return 'cena';
}

class LogEntry {
  final String id;
  final String date;
  final String meal;
  final String name;
  final double? g; // grammi (null per "solo calorie")
  final bool ml; // la quantità g è in ml (bevande)
  final double servings; // per le ricette
  final double kcal, p, c, f;
  final String refType; // food | recipe | quick | photo
  final String? refId;
  final String? photoId;
  final int ts;
  final FoodOpts opts; // condimento, formaggio e cottura scelti (alimenti)

  const LogEntry({
    required this.id,
    required this.date,
    required this.meal,
    required this.name,
    this.g,
    this.ml = false,
    this.servings = 1,
    required this.kcal,
    required this.p,
    required this.c,
    required this.f,
    this.refType = 'food',
    this.refId,
    this.photoId,
    required this.ts,
    this.opts = FoodOpts.none,
  });

  Macro get macro => Macro(kcal, p, c, f);

  Map<String, dynamic> toMap() => {
        'date': date,
        'meal': meal,
        'n': name,
        'g': g,
        if (ml) 'ml': true,
        'sv': servings,
        'k': kcal,
        'p': p,
        'c': c,
        'f': f,
        'rt': refType,
        'ref': refId,
        'photo': photoId,
        'ts': ts,
        if (opts.sauce != 1) 'sx': opts.sauce,
        if (opts.extra) 'ex': true,
        if (opts.cook.isNotEmpty) 'ck': opts.cook,
      };

  factory LogEntry.fromMap(Map m) => LogEntry(
        id: _s(m['id']),
        date: _s(m['date']),
        meal: _s(m['meal'], 'pranzo'),
        name: _s(m['n']),
        g: m['g'] is num ? (m['g'] as num).toDouble() : null,
        ml: m['ml'] == true,
        servings: _d(m['sv'], 1),
        kcal: _d(m['k']),
        p: _d(m['p']),
        c: _d(m['c']),
        f: _d(m['f']),
        refType: _s(m['rt'], 'food'),
        refId: m['ref'] as String?,
        photoId: m['photo'] as String?,
        ts: _i(m['ts']),
        opts: FoodOpts(sauce: _d(m['sx'], 1), extra: m['ex'] == true, cook: _s(m['ck'])),
      );

  LogEntry copyWith({String? meal, String? date, double? g, double? servings, double? kcal, double? p, double? c, double? f, String? name, FoodOpts? opts}) => LogEntry(
        id: id,
        date: date ?? this.date,
        meal: meal ?? this.meal,
        name: name ?? this.name,
        g: g ?? this.g,
        ml: ml,
        servings: servings ?? this.servings,
        kcal: kcal ?? this.kcal,
        p: p ?? this.p,
        c: c ?? this.c,
        f: f ?? this.f,
        refType: refType,
        refId: refId,
        photoId: photoId,
        ts: ts,
        opts: opts ?? this.opts,
      );
}

/// Motivi per cui un giorno di allenamento è giustificato (non penalizza il voto).
const offReasons = {'dolore': 'Dolore o infortunio', 'malattia': 'Malattia', 'impegno': 'Impegno', 'altro': 'Altro'};

class HabitDay {
  final String date;
  final int water; // ml
  final int? sleep; // minuti
  final int? steps;
  final int? alcohol; // bicchieri
  final List<String> supp; // integratori presi
  // giorno di allenamento giustificato: motivo (offReasons), seduta saltata, zone da evitare
  // e, se la seduta è solo rimandata, il giorno in cui si fa (moveTo)
  final String off;
  final String? offDay;
  final List<String> avoid;
  final String? moveTo;
  // giorno di allenamento in più: qui arriva la seduta rimandata dal giorno [moved]
  final String? moved;
  const HabitDay({
    required this.date,
    this.water = 0,
    this.sleep,
    this.steps,
    this.alcohol,
    this.supp = const [],
    this.off = '',
    this.offDay,
    this.avoid = const [],
    this.moveTo,
    this.moved,
  });
  Map<String, dynamic> toMap() => {
        'date': date,
        'water': water,
        'sleep': sleep,
        'steps': steps,
        'alcohol': alcohol,
        'supp': supp,
        if (off.isNotEmpty) 'off': off,
        if (off.isNotEmpty && offDay != null) 'offDay': offDay,
        if (off.isNotEmpty && avoid.isNotEmpty) 'avoid': avoid,
        if (off.isNotEmpty && moveTo != null) 'moveTo': moveTo,
        if (moved != null) 'moved': moved,
      };
  factory HabitDay.fromMap(Map m) => HabitDay(
        date: _s(m['date']),
        water: _i(m['water']),
        sleep: _in(m['sleep']),
        steps: _in(m['steps']),
        alcohol: _in(m['alcohol']),
        supp: ((m['supp'] as List?) ?? const []).map((e) => e.toString()).toList(),
        off: _s(m['off']),
        offDay: m['offDay'] as String?,
        avoid: ((m['avoid'] as List?) ?? const []).map((e) => e.toString()).toList(),
        moveTo: m['moveTo'] as String?,
        moved: m['moved'] as String?,
      );
  HabitDay copyWith({int? water, int? sleep, int? steps, int? alcohol, bool clearAlcohol = false, List<String>? supp}) => HabitDay(
        date: date,
        water: water ?? this.water,
        sleep: sleep ?? this.sleep,
        steps: steps ?? this.steps,
        alcohol: clearAlcohol ? null : (alcohol ?? this.alcohol),
        supp: supp ?? this.supp,
        off: off,
        offDay: offDay,
        avoid: avoid,
        moveTo: moveTo,
        moved: moved,
      );
  HabitDay withOff(String reason, {String? dayId, List<String> avoid = const [], String? moveTo}) => HabitDay(
      date: date, water: water, sleep: sleep, steps: steps, alcohol: alcohol, supp: supp, off: reason, offDay: dayId, avoid: avoid, moveTo: moveTo, moved: moved);
  HabitDay withMoved(String? from) => HabitDay(
      date: date, water: water, sleep: sleep, steps: steps, alcohol: alcohol, supp: supp, off: off, offDay: offDay, avoid: avoid, moveTo: moveTo, moved: from);
  bool get isOff => off.isNotEmpty;

  /// Seduta rimandata a un altro giorno (non saltata: resta nel giro).
  bool get postponed => isOff && moveTo != null;
  bool took(String name) => supp.contains(name);
  HabitDay toggleSupp(String name) => copyWith(supp: took(name) ? supp.where((e) => e != name).toList() : [...supp, name]);
}

class WeightEntry {
  final String date;
  final double kg;
  const WeightEntry(this.date, this.kg);
}

// =================================================================== allenamento

class Exercise {
  final String id;
  final String name;
  final String muscle;
  final String equip;
  final String type; // c | i | b | k
  final double inc;
  final bool custom;
  const Exercise({
    required this.id,
    required this.name,
    required this.muscle,
    required this.equip,
    required this.type,
    required this.inc,
    this.custom = false,
  });
  bool get isCardio => type == 'k';
  bool get isBodyweight => type == 'b';
  String get repsLabel => isCardio ? 'min' : (name.contains('(secondi)') ? 'sec' : 'rip');
  Map<String, dynamic> toMap() => {'n': name, 'm': muscle, 'e': equip, 't': type, 'inc': inc};
  factory Exercise.fromMap(Map m, {bool custom = false}) => Exercise(
        id: _s(m['id']),
        name: _s(m['n']),
        muscle: _s(m['m'], 'Altro'),
        equip: _s(m['e'], 'Altro'),
        type: _s(m['t'], 'c'),
        inc: _d(m['inc'], 2.5),
        custom: custom,
      );
}

const muscleGroups = [
  'Petto', 'Dorso', 'Spalle', 'Bicipiti', 'Tricipiti', 'Quadricipiti', 'Femorali', 'Glutei',
  'Polpacci', 'Addome', 'Avambracci', 'Total body', 'Cardio',
];

class PlanItem {
  final String ex;
  final int sets, rMin, rMax;
  final double rpe;
  final int rest; // secondi
  final String note;
  final int warm; // serie di avvicinamento da precompilare prima di quelle allenanti
  const PlanItem({required this.ex, this.sets = 3, this.rMin = 8, this.rMax = 12, this.rpe = 9, this.rest = 120, this.note = '', this.warm = 0});
  Map<String, dynamic> toMap() => {'ex': ex, 'sets': sets, 'rMin': rMin, 'rMax': rMax, 'rpe': rpe, 'rest': rest, 'note': note, if (warm > 0) 'warm': warm};
  factory PlanItem.fromMap(Map m) => PlanItem(
        ex: _s(m['ex']),
        sets: _i(m['sets'], 3),
        rMin: _i(m['rMin'], 8),
        rMax: _i(m['rMax'], 12),
        rpe: _d(m['rpe'], 9),
        rest: _i(m['rest'], 120),
        note: _s(m['note']),
        warm: _i(m['warm']),
      );
  PlanItem copyWith({String? ex, int? sets, int? rMin, int? rMax, double? rpe, int? rest, String? note, int? warm}) => PlanItem(
        ex: ex ?? this.ex,
        sets: sets ?? this.sets,
        rMin: rMin ?? this.rMin,
        rMax: rMax ?? this.rMax,
        rpe: rpe ?? this.rpe,
        rest: rest ?? this.rest,
        note: note ?? this.note,
        warm: warm ?? this.warm,
      );
  String get scheme => rMin == rMax ? '$sets×$rMin' : '$sets×$rMin-$rMax';
}

class PlanDay {
  final String id;
  final String name;
  final List<PlanItem> items;
  final int week; // settimana del ciclo (1 = A), conta solo se la scheda ha più settimane
  const PlanDay({required this.id, required this.name, this.items = const [], this.week = 1});
  int get totalSets => items.fold(0, (a, b) => a + b.sets);
  Map<String, dynamic> toMap() => {'id': id, 'name': name, 'items': items.map((e) => e.toMap()).toList(), if (week > 1) 'week': week};
  factory PlanDay.fromMap(Map m) => PlanDay(
        id: _s(m['id']),
        name: _s(m['name']),
        items: ((m['items'] as List?) ?? const []).map((e) => PlanItem.fromMap(e as Map)).toList(),
        week: _i(m['week'], 1).clamp(1, 8),
      );
  PlanDay copyWith({String? name, List<PlanItem>? items, int? week}) =>
      PlanDay(id: id, name: name ?? this.name, items: items ?? this.items, week: week ?? this.week);
}

/// Lettera della settimana del ciclo: 1 → A, 2 → B...
String weekLetter(int w) => String.fromCharCode(64 + w.clamp(1, 26));

class Plan {
  final String id;
  final String name;
  final String template;
  final String startDate;
  final List<PlanDay> days;
  final int cycle; // settimane del ciclo (1 = scheda classica)
  const Plan({required this.id, required this.name, this.template = 'custom', required this.startDate, this.days = const [], this.cycle = 1});
  Map<String, dynamic> toMap() =>
      {'name': name, 'template': template, 'startDate': startDate, 'days': days.map((e) => e.toMap()).toList(), if (cycle > 1) 'cycle': cycle};
  factory Plan.fromMap(Map m) => Plan(
        id: _s(m['id']),
        name: _s(m['name']),
        template: _s(m['template'], 'custom'),
        startDate: _s(m['startDate'], todayKey()),
        days: ((m['days'] as List?) ?? const []).map((e) => PlanDay.fromMap(e as Map)).toList(),
        cycle: _i(m['cycle'], 1).clamp(1, 4),
      );
  Plan copyWith({String? name, List<PlanDay>? days, String? template, int? cycle}) => Plan(
        id: id,
        name: name ?? this.name,
        template: template ?? this.template,
        startDate: startDate,
        days: days ?? this.days,
        cycle: cycle ?? this.cycle,
      );

  /// Con un ciclo di più settimane i giorni ruotano in ordine di settimana (A, poi B...).
  Plan normalized() {
    if (cycle <= 1) return days.every((d) => d.week == 1) ? this : copyWith(days: [for (final d in days) d.copyWith(week: 1)]);
    final fixed = [for (final d in days) d.week > cycle ? d.copyWith(week: cycle) : d];
    return copyWith(days: [for (var w = 1; w <= cycle; w++) ...fixed.where((d) => d.week == w)]);
  }

  /// Copia con un nuovo id (e nuovi id dei giorni).
  Plan duplicate(String newPlanId, String Function() newDayId, {String? name}) => Plan(
        id: newPlanId,
        name: name ?? '${this.name} (copia)',
        template: template,
        startDate: todayKey(),
        days: [for (final d in days) PlanDay(id: newDayId(), name: d.name, items: d.items, week: d.week)],
        cycle: cycle,
      );
  PlanDay? day(String id) {
    for (final d in days) {
      if (d.id == id) return d;
    }
    return null;
  }
}

/// Tipo di serie: allenante (normale), avvicinamento, dropset.
const setWork = 'n', setWarmup = 'a', setDrop = 'd';

class SetLog {
  final double kg;
  final int reps;
  final double? rpe;
  final bool done;
  final String t; // n | a | d (vedi setWork, setWarmup, setDrop)
  const SetLog({this.kg = 0, this.reps = 0, this.rpe, this.done = false, this.t = setWork});
  Map<String, dynamic> toMap() => {'kg': kg, 'r': reps, 'rpe': rpe, 'done': done, if (t != setWork) 't': t};
  factory SetLog.fromMap(Map m) => SetLog(
        kg: _d(m['kg']),
        reps: _i(m['r']),
        rpe: m['rpe'] is num ? (m['rpe'] as num).toDouble() : null,
        done: m['done'] == true,
        t: const {setWarmup, setDrop}.contains(m['t']) ? m['t'] as String : setWork,
      );
  SetLog copyWith({double? kg, int? reps, double? rpe, bool? done, bool clearRpe = false, String? t}) =>
      SetLog(kg: kg ?? this.kg, reps: reps ?? this.reps, rpe: clearRpe ? null : (rpe ?? this.rpe), done: done ?? this.done, t: t ?? this.t);
  bool get isWork => t == setWork;
  bool get isWarmup => t == setWarmup;
  bool get isDrop => t == setDrop;
  /// Serie allenante completata: solo queste guidano coach e record.
  bool get counts => done && isWork;
  double get volume => kg * reps;
  /// 1RM stimato (Epley).
  double get e1rm => reps <= 0 ? 0 : (reps == 1 ? kg : kg * (1 + reps / 30));
}

class SessionEx {
  final String ex;
  final String name;
  final String type;
  final PlanItem target;
  final List<SetLog> sets;
  const SessionEx({required this.ex, required this.name, required this.type, required this.target, this.sets = const []});
  /// Serie fatte, senza gli avvicinamenti (non sono lavoro).
  int get doneSets => sets.where((s) => s.done && !s.isWarmup).length;
  int get plannedSets => sets.where((s) => !s.isWarmup).length;
  /// Serie allenanti completate.
  List<SetLog> get workDone => sets.where((s) => s.counts).toList();
  Map<String, dynamic> toMap() => {'ex': ex, 'name': name, 'type': type, 'target': target.toMap(), 'sets': sets.map((e) => e.toMap()).toList()};
  factory SessionEx.fromMap(Map m) => SessionEx(
        ex: _s(m['ex']),
        name: _s(m['name']),
        type: _s(m['type'], 'c'),
        target: PlanItem.fromMap((m['target'] as Map?) ?? const {}),
        sets: ((m['sets'] as List?) ?? const []).map((e) => SetLog.fromMap(e as Map)).toList(),
      );
  SessionEx copyWith({List<SetLog>? sets}) => SessionEx(ex: ex, name: name, type: type, target: target, sets: sets ?? this.sets);
}

class Session {
  final String id;
  final String date;
  final String? planId;
  final String? dayId;
  final String name;
  final int start;
  final int? end;
  final String status; // active | done
  final List<SessionEx> items;
  final int current; // indice esercizio corrente
  final String note;

  const Session({
    required this.id,
    required this.date,
    this.planId,
    this.dayId,
    required this.name,
    required this.start,
    this.end,
    this.status = 'active',
    this.items = const [],
    this.current = 0,
    this.note = '',
  });

  bool get isActive => status == 'active';
  int get plannedSets => items.fold(0, (a, b) => a + b.plannedSets);
  int get doneSets => items.fold(0, (a, b) => a + b.doneSets);
  double get volume => items.fold(0.0, (a, e) => a + (e.type == 'k' ? 0 : e.sets.where((s) => s.done && !s.isWarmup).fold(0.0, (x, s) => x + s.volume)));
  Duration get duration => Duration(milliseconds: (end ?? DateTime.now().millisecondsSinceEpoch) - start);
  double? get avgRpe {
    final r = [for (final e in items) for (final s in e.sets) if (s.counts && s.rpe != null) s.rpe!];
    return r.isEmpty ? null : r.reduce((a, b) => a + b) / r.length;
  }

  Map<String, dynamic> toMap() => {
        'date': date,
        'planId': planId,
        'dayId': dayId,
        'name': name,
        'start': start,
        'end': end,
        'status': status,
        'items': items.map((e) => e.toMap()).toList(),
        'current': current,
        'note': note,
      };

  factory Session.fromMap(Map m) => Session(
        id: _s(m['id']),
        date: _s(m['date']),
        planId: m['planId'] as String?,
        dayId: m['dayId'] as String?,
        name: _s(m['name'], 'Sessione'),
        start: _i(m['start']),
        end: _in(m['end']),
        status: _s(m['status'], 'done'),
        items: ((m['items'] as List?) ?? const []).map((e) => SessionEx.fromMap(e as Map)).toList(),
        current: _i(m['current']),
        note: _s(m['note']),
      );

  Session copyWith({List<SessionEx>? items, int? current, String? status, int? end, String? note, String? name}) => Session(
        id: id,
        date: date,
        planId: planId,
        dayId: dayId,
        name: name ?? this.name,
        start: start,
        end: end ?? this.end,
        status: status ?? this.status,
        items: items ?? this.items,
        current: current ?? this.current,
        note: note ?? this.note,
      );
}

class ProgressPhoto {
  final String id;
  final String date;
  final String blob;
  final String pose;
  final String note;
  const ProgressPhoto({required this.id, required this.date, required this.blob, this.pose = 'fronte', this.note = ''});
  Map<String, dynamic> toMap() => {'date': date, 'blob': blob, 'pose': pose, 'note': note};
  factory ProgressPhoto.fromMap(Map m) =>
      ProgressPhoto(id: _s(m['id']), date: _s(m['date']), blob: _s(m['blob']), pose: _s(m['pose'], 'fronte'), note: _s(m['note']));
}
