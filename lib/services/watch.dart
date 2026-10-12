import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:health/health.dart';

import '../core/fmt.dart';
import '../data/app_state.dart';
import '../logic/watch.dart';

/// Cosa Tigert legge dall'orologio, con il nome mostrato nelle impostazioni.
const watchKinds = {'steps': 'Passi', 'sleep': 'Sonno', 'workouts': 'Allenamenti', 'weight': 'Peso'};

/// Da dove arrivano i dati dell'orologio (Health Connect su Android; finto nei test).
abstract class WatchSource {
  /// 'ok', 'install' (Health Connect manca o va aggiornato) oppure 'no'.
  Future<String> status();
  Future<void> install();

  /// Permessi concessi, per chiave di [watchKinds].
  Future<Map<String, bool>> permissions();

  /// Apre la schermata dei permessi di Health Connect.
  Future<void> request();
  Future<List<WatchDay>> read(DateTime from, DateTime to);
}

/// Health Connect: ci scrivono Fitbit, Pixel Watch, Samsung Health, Garmin...
class HealthConnectSource implements WatchSource {
  final _h = Health();
  bool _ready = false;

  static const _types = {
    'steps': [HealthDataType.STEPS],
    'sleep': [HealthDataType.SLEEP_SESSION],
    // la lettura di un allenamento guarda anche calorie, distanza e passi nel suo intervallo
    'workouts': [HealthDataType.WORKOUT, HealthDataType.TOTAL_CALORIES_BURNED, HealthDataType.DISTANCE_DELTA, HealthDataType.STEPS],
    'weight': [HealthDataType.WEIGHT],
  };

  Future<void> _init() async {
    if (_ready) return;
    await _h.configure();
    _ready = true;
  }

  @override
  Future<String> status() async {
    await _init();
    return switch (await _h.getHealthConnectSdkStatus()) {
      HealthConnectSdkStatus.sdkAvailable => 'ok',
      HealthConnectSdkStatus.sdkUnavailableProviderUpdateRequired => 'install',
      _ => 'no',
    };
  }

  @override
  Future<void> install() async {
    await _init();
    await _h.installHealthConnect();
  }

  @override
  Future<Map<String, bool>> permissions() async {
    await _init();
    final out = <String, bool>{};
    for (final e in _types.entries) {
      out[e.key] = await _h.hasPermissions(e.value, permissions: [for (final _ in e.value) HealthDataAccess.READ]) ?? false;
    }
    return out;
  }

  @override
  Future<void> request() async {
    await _init();
    final all = [for (final l in _types.values) ...l];
    await _h.requestAuthorization(all, permissions: [for (final _ in all) HealthDataAccess.READ]);
  }

  static (DateTime, DateTime) _span(HealthDataPoint p) => (p.dateFrom, p.dateTo);

  /// Un tipo che non si riesce a leggere non blocca gli altri.
  Future<List<HealthDataPoint>> _get(bool allowed, List<HealthDataType> types, DateTime from, DateTime to) async {
    if (!allowed) return [];
    try {
      return await _h.getHealthDataFromTypes(types: types, startTime: from, endTime: to);
    } catch (e) {
      debugPrint('Health Connect: $types non letti ($e)');
      return [];
    }
  }

  @override
  Future<List<WatchDay>> read(DateTime from, DateTime to) async {
    await _init();
    final perms = await permissions();
    final start = dateOnly(from);
    // la notte che finisce il primo giorno comincia la sera prima
    final sleepFrom = start.subtract(const Duration(hours: 12));

    final sleepOk = perms['sleep'] == true;
    final sessions = (await _get(sleepOk, [HealthDataType.SLEEP_SESSION], sleepFrom, to)).map(_span).toList();
    final awake = (await _get(sleepOk, [HealthDataType.SLEEP_AWAKE, HealthDataType.SLEEP_AWAKE_IN_BED, HealthDataType.SLEEP_OUT_OF_BED], sleepFrom, to))
        .map(_span)
        .toList();
    final workouts = await _get(perms['workouts'] == true, [HealthDataType.WORKOUT], start, to);
    final weights = [...await _get(perms['weight'] == true, [HealthDataType.WEIGHT], start, to)]..sort((a, b) => a.dateFrom.compareTo(b.dateFrom));

    final days = <WatchDay>[];
    for (var d = start; !d.isAfter(to); d = DateTime(d.year, d.month, d.day + 1)) {
      final k = dayKey(d);
      final next = DateTime(d.year, d.month, d.day + 1);
      int? steps;
      if (perms['steps'] == true) {
        try {
          steps = await _h.getTotalStepsInInterval(d, next.isAfter(to) ? to : next);
        } catch (e) {
          debugPrint('Health Connect: passi del $k non letti ($e)');
        }
      }
      // il peso del giorno è la prima pesata (di solito la mattina)
      final w = weights.where((p) => dayKey(p.dateFrom) == k).firstOrNull?.value;
      days.add(WatchDay(
        date: k,
        steps: steps,
        sleep: sleepOn(k, sessions, awake),
        kg: w is NumericHealthValue ? w.numericValue.toDouble() : null,
        workouts: [
          for (final p in workouts)
            if (dayKey(p.dateFrom) == k && p.value is WorkoutHealthValue)
              WatchWorkout(
                id: p.uuid,
                type: (p.value as WorkoutHealthValue).workoutActivityType.name,
                start: p.dateFrom,
                end: p.dateTo,
                kcal: (p.value as WorkoutHealthValue).totalEnergyBurned?.toDouble(),
              ),
        ],
      ));
    }
    return days;
  }
}

/// Tiene Tigert allineato all'orologio: legge all'apertura, quando torni
/// sull'app e ogni pochi minuti mentre è aperta.
class WatchService extends ChangeNotifier {
  final AppState app;
  final WatchSource? source;
  WatchService(this.app, this.source);

  /// Giorni riletti a ogni giro: oggi e i precedenti (l'orologio può sincronizzare tardi).
  static const days = 7;
  static const _every = Duration(minutes: 5);

  bool busy = false;
  String? error;
  Map<String, bool> granted = const {};
  Timer? _timer;

  bool get available => source != null;
  bool get enabled => available && app.prefs.watchOn;
  DateTime? get lastAt => app.prefs.watchLast == 0 ? null : DateTime.fromMillisecondsSinceEpoch(app.prefs.watchLast);

  void startAuto() {
    _timer?.cancel();
    if (!enabled) return;
    _timer = Timer.periodic(_every, (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) sync();
    });
  }

  /// Chiede i permessi e fa la prima lettura. Ritorna false se non ne è stato dato nessuno.
  Future<bool> connect() async {
    final s = source;
    if (s == null) return false;
    error = null;
    try {
      await s.request();
      granted = await s.permissions();
    } catch (e) {
      error = 'Health Connect non risponde: $e';
      notifyListeners();
      return false;
    }
    final ok = granted.values.any((v) => v);
    app.prefs.watchOn = ok;
    startAuto();
    notifyListeners();
    if (ok) await sync(force: true);
    return ok;
  }

  void disconnect() {
    _timer?.cancel();
    app.prefs.watchOn = false;
    notifyListeners();
  }

  Future<void> refreshPermissions() async {
    final s = source;
    if (s == null) return;
    try {
      granted = await s.permissions();
      notifyListeners();
    } catch (_) {}
  }

  /// Legge gli ultimi giorni e li unisce ai dati: ritorna quanti valori sono cambiati.
  Future<int> sync({bool force = false}) async {
    final s = source;
    if (s == null || !app.prefs.watchOn || busy || !app.hasProfile) return 0;
    final now = DateTime.now();
    if (!force && now.millisecondsSinceEpoch - app.prefs.watchLast < 60000) return 0;
    busy = true;
    notifyListeners();
    var n = 0;
    try {
      final read = await s.read(addDays(dateOnly(now), -(days - 1)), now);
      n = applyWatch(app, read);
      app.prefs.watchLast = now.millisecondsSinceEpoch;
      error = null;
    } catch (e) {
      error = 'Lettura non riuscita: $e';
    }
    busy = false;
    notifyListeners();
    return n;
  }
}
