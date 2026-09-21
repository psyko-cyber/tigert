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
  final String activity;
  final int kcal, protein, carbs, fat;
  final int kcalStart;
  final bool autoAdjust;
  final String? lastAdjust;
  final List<TargetChange> changes;
  final int waterMl, steps, sleepMin;
  final Map<String, bool> habits; // water, sleep, steps, alcohol
  final List<int> trainingDays; // 1 = lunedì
  final String? planId;
  final Reminders reminders;

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
    required this.trainingDays,
    this.planId,
    required this.reminders,
  });

  int get age => DateTime.now().year - birthYear;
  bool habitOn(String k) => habits[k] ?? true;

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
        'trainingDays': trainingDays,
        'planId': planId,
        'reminders': reminders.toMap(),
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
        trainingDays: ((m['trainingDays'] as List?) ?? const [1, 3, 5]).map((e) => _i(e)).toList()..sort(),
        planId: m['planId'] as String?,
        reminders: Reminders.fromMap(m['reminders'] as Map?),
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
    List<int>? trainingDays,
    String? planId,
    Reminders? reminders,
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
        trainingDays: trainingDays ?? this.trainingDays,
        planId: planId ?? this.planId,
        reminders: reminders ?? this.reminders,
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

class Food {
  final String id;
  final String name;
  final String? brand;
  final String? ean;
  final String cat;
  final double kcal, p, c, f, fiber;
  final List<Portion> portions;
  final String src; // seed | user | off | photo

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
  });

  Macro per(double grams) => Macro(kcal, p, c, f).scale(grams / 100);
  String get displayName => brand == null || brand!.isEmpty ? name : '$name · $brand';
  bool get isSeed => src == 'seed';

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
      );

  Food copyWith({String? id, String? name, String? brand, String? ean, double? kcal, double? p, double? c, double? f, List<Portion>? portions, String? src, String? cat}) => Food(
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
      );
}

class RecipeItem {
  final String foodId;
  final String name;
  final double g;
  final double kcal, p, c, f; // per 100 g (istantanea)
  const RecipeItem(this.foodId, this.name, this.g, this.kcal, this.p, this.c, this.f);
  Macro get macro => Macro(kcal, p, c, f).scale(g / 100);
  Map<String, dynamic> toMap() => {'food': foodId, 'n': name, 'g': g, 'k': kcal, 'p': p, 'c': c, 'f': f};
  factory RecipeItem.fromMap(Map m) =>
      RecipeItem(_s(m['food']), _s(m['n']), _d(m['g']), _d(m['k']), _d(m['p']), _d(m['c']), _d(m['f']));
  factory RecipeItem.of(Food food, double g) => RecipeItem(food.id, food.name, g, food.kcal, food.p, food.c, food.f);
  RecipeItem withGrams(double g) => RecipeItem(foodId, name, g, kcal, p, c, f);
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
  final double servings; // per le ricette
  final double kcal, p, c, f;
  final String refType; // food | recipe | quick | photo
  final String? refId;
  final String? photoId;
  final int ts;

  const LogEntry({
    required this.id,
    required this.date,
    required this.meal,
    required this.name,
    this.g,
    this.servings = 1,
    required this.kcal,
    required this.p,
    required this.c,
    required this.f,
    this.refType = 'food',
    this.refId,
    this.photoId,
    required this.ts,
  });

  Macro get macro => Macro(kcal, p, c, f);

  Map<String, dynamic> toMap() => {
        'date': date,
        'meal': meal,
        'n': name,
        'g': g,
        'sv': servings,
        'k': kcal,
        'p': p,
        'c': c,
        'f': f,
        'rt': refType,
        'ref': refId,
        'photo': photoId,
        'ts': ts,
      };

  factory LogEntry.fromMap(Map m) => LogEntry(
        id: _s(m['id']),
        date: _s(m['date']),
        meal: _s(m['meal'], 'pranzo'),
        name: _s(m['n']),
        g: m['g'] is num ? (m['g'] as num).toDouble() : null,
        servings: _d(m['sv'], 1),
        kcal: _d(m['k']),
        p: _d(m['p']),
        c: _d(m['c']),
        f: _d(m['f']),
        refType: _s(m['rt'], 'food'),
        refId: m['ref'] as String?,
        photoId: m['photo'] as String?,
        ts: _i(m['ts']),
      );

  LogEntry copyWith({String? meal, String? date, double? g, double? servings, double? kcal, double? p, double? c, double? f, String? name}) => LogEntry(
        id: id,
        date: date ?? this.date,
        meal: meal ?? this.meal,
        name: name ?? this.name,
        g: g ?? this.g,
        servings: servings ?? this.servings,
        kcal: kcal ?? this.kcal,
        p: p ?? this.p,
        c: c ?? this.c,
        f: f ?? this.f,
        refType: refType,
        refId: refId,
        photoId: photoId,
        ts: ts,
      );
}

class HabitDay {
  final String date;
  final int water; // ml
  final int? sleep; // minuti
  final int? steps;
  final int? alcohol; // bicchieri
  const HabitDay({required this.date, this.water = 0, this.sleep, this.steps, this.alcohol});
  Map<String, dynamic> toMap() => {'date': date, 'water': water, 'sleep': sleep, 'steps': steps, 'alcohol': alcohol};
  factory HabitDay.fromMap(Map m) =>
      HabitDay(date: _s(m['date']), water: _i(m['water']), sleep: _in(m['sleep']), steps: _in(m['steps']), alcohol: _in(m['alcohol']));
  HabitDay copyWith({int? water, int? sleep, int? steps, int? alcohol, bool clearAlcohol = false}) => HabitDay(
        date: date,
        water: water ?? this.water,
        sleep: sleep ?? this.sleep,
        steps: steps ?? this.steps,
        alcohol: clearAlcohol ? null : (alcohol ?? this.alcohol),
      );
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
  const PlanItem({required this.ex, this.sets = 3, this.rMin = 8, this.rMax = 12, this.rpe = 9, this.rest = 120, this.note = ''});
  Map<String, dynamic> toMap() => {'ex': ex, 'sets': sets, 'rMin': rMin, 'rMax': rMax, 'rpe': rpe, 'rest': rest, 'note': note};
  factory PlanItem.fromMap(Map m) => PlanItem(
        ex: _s(m['ex']),
        sets: _i(m['sets'], 3),
        rMin: _i(m['rMin'], 8),
        rMax: _i(m['rMax'], 12),
        rpe: _d(m['rpe'], 9),
        rest: _i(m['rest'], 120),
        note: _s(m['note']),
      );
  PlanItem copyWith({String? ex, int? sets, int? rMin, int? rMax, double? rpe, int? rest, String? note}) => PlanItem(
        ex: ex ?? this.ex,
        sets: sets ?? this.sets,
        rMin: rMin ?? this.rMin,
        rMax: rMax ?? this.rMax,
        rpe: rpe ?? this.rpe,
        rest: rest ?? this.rest,
        note: note ?? this.note,
      );
  String get scheme => rMin == rMax ? '$sets×$rMin' : '$sets×$rMin-$rMax';
}

class PlanDay {
  final String id;
  final String name;
  final List<PlanItem> items;
  const PlanDay({required this.id, required this.name, this.items = const []});
  int get totalSets => items.fold(0, (a, b) => a + b.sets);
  Map<String, dynamic> toMap() => {'id': id, 'name': name, 'items': items.map((e) => e.toMap()).toList()};
  factory PlanDay.fromMap(Map m) => PlanDay(
        id: _s(m['id']),
        name: _s(m['name']),
        items: ((m['items'] as List?) ?? const []).map((e) => PlanItem.fromMap(e as Map)).toList(),
      );
  PlanDay copyWith({String? name, List<PlanItem>? items}) => PlanDay(id: id, name: name ?? this.name, items: items ?? this.items);
}

class Plan {
  final String id;
  final String name;
  final String template;
  final String startDate;
  final List<PlanDay> days;
  const Plan({required this.id, required this.name, this.template = 'custom', required this.startDate, this.days = const []});
  Map<String, dynamic> toMap() => {'name': name, 'template': template, 'startDate': startDate, 'days': days.map((e) => e.toMap()).toList()};
  factory Plan.fromMap(Map m) => Plan(
        id: _s(m['id']),
        name: _s(m['name']),
        template: _s(m['template'], 'custom'),
        startDate: _s(m['startDate'], todayKey()),
        days: ((m['days'] as List?) ?? const []).map((e) => PlanDay.fromMap(e as Map)).toList(),
      );
  Plan copyWith({String? name, List<PlanDay>? days, String? template}) =>
      Plan(id: id, name: name ?? this.name, template: template ?? this.template, startDate: startDate, days: days ?? this.days);
  PlanDay? day(String id) {
    for (final d in days) {
      if (d.id == id) return d;
    }
    return null;
  }
}

class SetLog {
  final double kg;
  final int reps;
  final double? rpe;
  final bool done;
  const SetLog({this.kg = 0, this.reps = 0, this.rpe, this.done = false});
  Map<String, dynamic> toMap() => {'kg': kg, 'r': reps, 'rpe': rpe, 'done': done};
  factory SetLog.fromMap(Map m) => SetLog(
        kg: _d(m['kg']),
        reps: _i(m['r']),
        rpe: m['rpe'] is num ? (m['rpe'] as num).toDouble() : null,
        done: m['done'] == true,
      );
  SetLog copyWith({double? kg, int? reps, double? rpe, bool? done, bool clearRpe = false}) =>
      SetLog(kg: kg ?? this.kg, reps: reps ?? this.reps, rpe: clearRpe ? null : (rpe ?? this.rpe), done: done ?? this.done);
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
  int get doneSets => sets.where((s) => s.done).length;
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
  int get plannedSets => items.fold(0, (a, b) => a + b.sets.length);
  int get doneSets => items.fold(0, (a, b) => a + b.doneSets);
  double get volume => items.fold(0.0, (a, e) => a + (e.type == 'k' ? 0 : e.sets.where((s) => s.done).fold(0.0, (x, s) => x + s.volume)));
  Duration get duration => Duration(milliseconds: (end ?? DateTime.now().millisecondsSinceEpoch) - start);
  double? get avgRpe {
    final r = [for (final e in items) for (final s in e.sets) if (s.done && s.rpe != null) s.rpe!];
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
