import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../core/fmt.dart';
import '../core/ids.dart';
import '../logic/nutrition.dart';
import '../logic/score.dart';
import 'catalog.dart';
import 'local_prefs.dart';
import 'models.dart';
import 'store.dart';

/// Stato centrale: dati tipizzati + cache derivate invalidate a ogni modifica.
class AppState extends ChangeNotifier {
  final Store store;
  final LocalPrefs prefs;
  final Catalog catalog;

  AppState(this.store, this.prefs, this.catalog) {
    store.addListener(_onStore);
    prefs.addListener(notifyListeners);
  }

  final Map<String, Object?> _cache = {};

  void _onStore() {
    _cache.clear();
    notifyListeners();
  }

  /// Svuota le cache (es. cambio di giorno a mezzanotte).
  void refresh() {
    _cache.clear();
    notifyListeners();
  }

  /// Cache pubblica per la logica derivata (invalidata a ogni modifica).
  T memo<T>(String key, T Function() fn) => _memo(key, fn);

  T _memo<T>(String key, T Function() fn) {
    if (_cache.containsKey(key)) return _cache[key] as T;
    final v = fn();
    _cache[key] = v;
    return v;
  }

  // ================================================================ profilo

  Profile? get profile => _memo('profile', () {
        final m = store.get('profile', 'me');
        return m == null ? null : Profile.fromMap(m);
      });

  bool get hasProfile => profile != null;

  void saveProfile(Profile p) => store.put('profile', 'me', p.toMap());

  /// Applica un nuovo target calorico registrando la modifica.
  void applyKcal(int newKcal, String reason, {bool fromAuto = false}) {
    final p = profile;
    if (p == null) return;
    final (pr, c, f) = macrosFor(newKcal, p.protein, p.fat);
    saveProfile(p.copyWith(
      kcal: newKcal,
      protein: pr,
      carbs: c,
      fat: f,
      lastAdjust: todayKey(),
      changes: [...p.changes, TargetChange(todayKey(), p.kcal, newKcal, reason)],
    ));
  }

  // ================================================================ alimenti

  Map<String, Food> get userFoods => _memo('userFoods', () {
        return {for (final m in store.all('foods')) m['id'] as String: Food.fromMap(m)};
      });

  Food? food(String? id) => id == null ? null : (userFoods[id] ?? catalog.foodById[id]);

  /// Unità della quantità di una voce del diario (le voci vecchie la prendono dall'alimento).
  String entryUnit(LogEntry e) => e.ml || (e.refType == 'food' && food(e.refId)?.ml == true) ? 'ml' : 'g';

  Food? foodByEan(String ean) {
    for (final f in userFoods.values) {
      if (f.ean == ean) return f;
    }
    return null;
  }

  void saveFood(Food f) => store.put('foods', f.id, f.toMap());
  void deleteFood(String id) => store.remove('foods', id);

  Set<String> get favorites => _memo('fav', () => store.all('fav').map((m) => m['id'] as String).toSet());

  void toggleFav(String id) {
    if (favorites.contains(id)) {
      store.remove('fav', id);
    } else {
      store.put('fav', id, {});
    }
  }

  List<Food> searchFoods(String q, {bool onlyFav = false, bool onlyBrands = false}) {
    final qq = fold(q.trim());
    final words = qq.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final fav = favorites;
    final pool = [...userFoods.values, ...catalog.foods];
    final scored = <(Food, int)>[];
    for (final f in pool) {
      if (onlyFav && !fav.contains(f.id)) continue;
      if (onlyBrands && (f.brand == null || f.brand!.isEmpty)) continue;
      final name = fold('${f.name} ${f.brand ?? ''}');
      var score = 0;
      if (words.isEmpty) {
        score = 1;
      } else {
        var ok = true;
        for (final w in words) {
          if (!name.contains(w)) {
            ok = false;
            break;
          }
        }
        if (!ok) continue;
        if (name.startsWith(qq)) {
          score += 100;
        } else if (name.startsWith(words.first)) {
          score += 60;
        } else if (RegExp('\\b${RegExp.escape(words.first)}').hasMatch(name)) {
          score += 30;
        }
        score += 40 - name.length.clamp(0, 40);
      }
      if (fav.contains(f.id)) score += 50;
      if (!f.isSeed) score += 20;
      scored.add((f, score));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return scored.take(80).map((e) => e.$1).toList();
  }

  /// Ultimi alimenti usati (unici) con l'ultima quantità.
  List<(Food, double)> recentFoods({int limit = 12}) => _memo('recent$limit', () {
        final entries = store.all('log').map(LogEntry.fromMap).where((e) => e.refType == 'food' && e.refId != null).toList()
          ..sort((a, b) => b.ts.compareTo(a.ts));
        final out = <(Food, double)>[];
        final seen = <String>{};
        for (final e in entries) {
          if (seen.contains(e.refId)) continue;
          final f = food(e.refId);
          if (f == null) continue;
          seen.add(e.refId!);
          out.add((f, e.g ?? 100));
          if (out.length >= limit) break;
        }
        return out;
      });

  // ================================================================ ricette

  List<Recipe> get recipes => _memo('recipes', () {
        final l = store.all('recipes').map(Recipe.fromMap).toList()..sort((a, b) => a.name.compareTo(b.name));
        return l;
      });

  Recipe? recipe(String? id) {
    if (id == null) return null;
    final m = store.get('recipes', id);
    return m == null ? null : Recipe.fromMap(m);
  }

  void saveRecipe(Recipe r) => store.put('recipes', r.id, r.toMap());
  void deleteRecipe(String id) => store.remove('recipes', id);

  // ================================================================ diario

  Map<String, List<LogEntry>> get logByDate => _memo('logByDate', () {
        final m = <String, List<LogEntry>>{};
        for (final d in store.all('log')) {
          final e = LogEntry.fromMap(d);
          (m[e.date] ??= []).add(e);
        }
        for (final l in m.values) {
          l.sort((a, b) => a.ts.compareTo(b.ts));
        }
        return m;
      });

  List<LogEntry> entries(String date) => logByDate[date] ?? const [];

  Map<String, Macro> get totalsByDate => _memo('totalsByDate', () {
        return logByDate.map((k, v) => MapEntry(k, v.fold(Macro.zero, (a, e) => a + e.macro)));
      });

  Macro totals(String date) => totalsByDate[date] ?? Macro.zero;

  void addEntry(LogEntry e) => store.put('log', e.id, e.toMap());
  void updateEntry(LogEntry e) => store.put('log', e.id, e.toMap());
  void deleteEntry(String id) => store.remove('log', id);

  LogEntry entryFromFood(Food f, double g, {required String date, required String meal}) {
    final m = f.per(g);
    return LogEntry(
      id: newId(),
      date: date,
      meal: meal,
      name: f.displayName,
      g: g,
      ml: f.ml,
      kcal: m.kcal,
      p: m.p,
      c: m.c,
      f: m.f,
      refType: 'food',
      refId: f.id,
      ts: DateTime.now().millisecondsSinceEpoch,
    );
  }

  LogEntry entryFromRecipe(Recipe r, double servings, {required String date, required String meal}) {
    final m = r.perServing.scale(servings);
    return LogEntry(
      id: newId(),
      date: date,
      meal: meal,
      name: r.name,
      g: r.totalGrams / (r.servings <= 0 ? 1 : r.servings) * servings,
      servings: servings,
      kcal: m.kcal,
      p: m.p,
      c: m.c,
      f: m.f,
      refType: 'recipe',
      refId: r.id,
      ts: DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Ricalcola una voce con una nuova quantità mantenendo la densità.
  LogEntry rescaleEntry(LogEntry e, {double? g, double? servings}) {
    if (e.refType == 'recipe' && servings != null) {
      final k = servings / (e.servings <= 0 ? 1 : e.servings);
      return e.copyWith(servings: servings, g: (e.g ?? 0) * k, kcal: e.kcal * k, p: e.p * k, c: e.c * k, f: e.f * k);
    }
    if (g != null && e.g != null && e.g! > 0) {
      final k = g / e.g!;
      return e.copyWith(g: g, kcal: e.kcal * k, p: e.p * k, c: e.c * k, f: e.f * k);
    }
    return e;
  }

  void copyMeal(String fromDate, String meal, String toDate) {
    store.batch(() {
      var ts = DateTime.now().millisecondsSinceEpoch;
      for (final e in entries(fromDate).where((e) => e.meal == meal)) {
        final n = LogEntry(
          id: newId(),
          date: toDate,
          meal: meal,
          name: e.name,
          g: e.g,
          ml: e.ml,
          servings: e.servings,
          kcal: e.kcal,
          p: e.p,
          c: e.c,
          f: e.f,
          refType: e.refType,
          refId: e.refId,
          ts: ts++,
        );
        addEntry(n);
      }
    });
  }

  // ================================================================ peso

  List<WeightEntry> get weights => _memo('weights', () {
        final l = store.all('weights').map((m) => WeightEntry(m['id'] as String, (m['kg'] as num).toDouble())).toList()
          ..sort((a, b) => a.date.compareTo(b.date));
        return l;
      });

  WeightStats get weightStats => _memo('weightStats', () => WeightStats(weights));

  double? get latestWeight => weights.isEmpty ? null : weights.last.kg;

  /// Peso "attuale" per i calcoli: media 7 giorni, altrimenti ultimo, altrimenti peso iniziale.
  double get currentWeight => weightStats.trend ?? latestWeight ?? profile?.startWeight ?? 70;

  double? weightOn(String date) {
    final m = store.get('weights', date);
    return m == null ? null : (m['kg'] as num).toDouble();
  }

  void setWeight(String date, double kg) => store.put('weights', date, {'kg': kg});
  void deleteWeight(String date) => store.remove('weights', date);

  // ================================================================ abitudini

  HabitDay habit(String date) {
    final m = store.get('habits', date);
    return m == null ? HabitDay(date: date) : HabitDay.fromMap(m);
  }

  Map<String, HabitDay> get habitsByDate => _memo('habitsByDate', () {
        return {for (final m in store.all('habits')) m['id'] as String: HabitDay.fromMap(m)};
      });

  void saveHabit(HabitDay h) => store.put('habits', h.date, h.toMap());

  void addWater(String date, int ml) {
    final h = habit(date);
    saveHabit(h.copyWith(water: (h.water + ml).clamp(0, 10000)));
  }

  // ================================================================ esercizi

  Map<String, Exercise> get exercises => _memo('exercises', () {
        final m = <String, Exercise>{...catalog.exById};
        for (final d in store.all('exercises')) {
          final e = Exercise.fromMap(d, custom: true);
          m[e.id] = e;
        }
        return m;
      });

  Exercise? exercise(String id) => exercises[id];

  String exerciseName(String id) => exercises[id]?.name ?? 'Esercizio';

  void saveExercise(Exercise e) => store.put('exercises', e.id, e.toMap());

  // ================================================================ schede

  List<Plan> get plans => _memo('plans', () => store.all('plans').map(Plan.fromMap).toList());

  Plan? get activePlan => _memo('activePlan', () {
        final id = profile?.planId;
        if (id == null) return plans.isEmpty ? null : plans.first;
        final m = store.get('plans', id);
        return m == null ? (plans.isEmpty ? null : plans.first) : Plan.fromMap(m);
      });

  Plan? plan(String? id) {
    if (id == null) return null;
    final m = store.get('plans', id);
    return m == null ? null : Plan.fromMap(m);
  }

  void savePlan(Plan p, {bool activate = false}) {
    p = p.normalized();
    store.batch(() {
      store.put('plans', p.id, p.toMap());
      final pr = profile;
      if (activate && pr != null) saveProfile(pr.copyWith(planId: p.id));
    });
  }

  /// Elimina una scheda. Se era quella attiva ne attiva un'altra ([activate]) o la prima rimasta.
  void deletePlan(String id, {String? activate}) {
    store.batch(() {
      final wasActive = activePlan?.id == id;
      store.remove('plans', id);
      final pr = profile;
      if (wasActive && pr != null && activate != null) saveProfile(pr.copyWith(planId: activate));
    });
  }

  // ================================================================ sessioni

  List<Session> get sessions => _memo('sessions', () {
        final l = store.all('sessions').map(Session.fromMap).toList()..sort((a, b) => a.start.compareTo(b.start));
        return l;
      });

  List<Session> get doneSessions => _memo('doneSessions', () => sessions.where((s) => !s.isActive).toList());

  Session? get activeSession {
    for (final s in sessions.reversed) {
      if (s.isActive) return s;
    }
    return null;
  }

  Session? session(String id) {
    final m = store.get('sessions', id);
    return m == null ? null : Session.fromMap(m);
  }

  Map<String, List<Session>> get sessionsByDate => _memo('sessionsByDate', () {
        final m = <String, List<Session>>{};
        for (final s in sessions) {
          (m[s.date] ??= []).add(s);
        }
        return m;
      });

  void saveSession(Session s) => store.put('sessions', s.id, s.toMap());
  void deleteSession(String id) => store.remove('sessions', id);

  /// Ultima sessione conclusa che contiene l'esercizio, con almeno una serie fatta.
  (Session, SessionEx)? lastPerformance(String exId, {int? beforeTs}) {
    for (final s in doneSessions.reversed) {
      if (beforeTs != null && s.start >= beforeTs) continue;
      for (final e in s.items) {
        if (e.ex == exId && e.workDone.isNotEmpty) return (s, e);
      }
    }
    return null;
  }

  // ================================================================ foto

  List<ProgressPhoto> get photos => _memo('photos', () {
        final l = store.all('photos').map(ProgressPhoto.fromMap).toList()..sort((a, b) => a.date.compareTo(b.date));
        return l;
      });

  Future<void> addPhoto(Uint8List bytes, {required String date, String pose = 'fronte'}) async {
    final blob = await store.putBlob(bytes);
    final id = newId();
    store.put('photos', id, ProgressPhoto(id: id, date: date, blob: blob, pose: pose).toMap());
  }

  void deletePhoto(String id) => store.remove('photos', id);

  // ================================================================ voto

  DayScore score(String date) => _memo('score:$date', () => computeScore(this, date));

  /// Giorni con dati (per statistiche).
  Set<String> get activeDates => _memo('activeDates', () {
        return {...logByDate.keys, ...habitsByDate.keys.where((k) => habitsByDate[k]!.water > 0), ...sessionsByDate.keys};
      });

  double? weekAverageScore({DateTime? end}) {
    final e = dateOnly(end ?? DateTime.now());
    final vs = <double>[];
    for (var i = 0; i < 7; i++) {
      final k = dayKey(e.subtract(Duration(days: i)));
      if (!activeDates.contains(k)) continue;
      vs.add(score(k).v);
    }
    if (vs.isEmpty) return null;
    return vs.reduce((a, b) => a + b) / vs.length;
  }
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  static AppState of(BuildContext c) => c.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
  static AppState read(BuildContext c) => c.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}

extension AppX on BuildContext {
  AppState get app => AppScope.of(this);
  AppState get appRead => AppScope.read(this);
}
