import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/fmt.dart';
import '../core/ids.dart';
import '../data/app_state.dart';
import '../data/models.dart';
import '../logic/score.dart';
import '../logic/supplements.dart';
import '../logic/training.dart';

class _Planned {
  final int id;
  final DateTime at;
  final String title;
  final String body;
  const _Planned(this.id, this.at, this.title, this.body);
}

/// Promemoria locali. Android: pianificati per i prossimi 7 giorni (saltando
/// quelli già inutili oggi). Windows: controllo ogni 30 s mentre l'app è
/// aperta o nel tray.
class NotificationService {
  final AppState app;
  NotificationService(this.app);

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  Timer? _ticker;
  Timer? _debounce;
  final _firedToday = <String>{};
  String _firedDay = '';

  static const _channel = AndroidNotificationDetails(
    'promemoria',
    'Promemoria',
    channelDescription: 'Pasti, acqua, allenamento e peso',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
  );
  static const _timerChannel = AndroidNotificationDetails(
    'timer',
    'Timer di recupero',
    channelDescription: 'Avviso di fine recupero tra le serie',
    importance: Importance.high,
    priority: Priority.high,
    category: AndroidNotificationCategory.alarm,
  );
  static const _restId = 900;

  NotificationDetails get _details => const NotificationDetails(android: _channel);

  Future<void> init() async {
    try {
      tzdata.initializeTimeZones();
      try {
        final info = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(info.identifier));
      } catch (_) {
        tz.setLocalLocation(tz.getLocation('Europe/Rome'));
      }
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@drawable/ic_stat_tigert'),
          windows: WindowsInitializationSettings(
            appName: 'Tigert',
            appUserModelId: 'Tigert.App',
            guid: 'd6f3c0a2-5b7e-4a3c-9f1e-2b8a7c4e9d10',
          ),
        ),
      );
      _ready = true;
    } catch (e) {
      debugPrint('notifiche non disponibili: $e');
    }
    if (isDesktop) {
      _ticker = Timer.periodic(const Duration(seconds: 30), (_) => _tickDesktop());
    }
  }

  Future<bool> requestPermission() async {
    if (!_ready || !isAndroid) return true;
    final a = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    return await a?.requestNotificationsPermission() ?? true;
  }

  Future<void> show(String title, String body, {bool urgent = false}) async {
    if (!_ready) return;
    try {
      await _plugin.show(
        id: DateTime.now().millisecondsSinceEpoch % 100000 + 1000,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(android: urgent ? _timerChannel : _channel),
      );
    } catch (e) {
      debugPrint('notifica non mostrata: $e');
    }
  }

  // ---------------------------------------------------------------- pianificazione

  /// Da chiamare quando cambiano dati rilevanti (con debounce).
  void reschedule({Duration delay = const Duration(seconds: 8)}) {
    if (!isAndroid) return;
    _debounce?.cancel();
    _debounce = Timer(delay, _scheduleAndroid);
  }

  Future<void> rescheduleNow() async {
    _debounce?.cancel();
    if (isAndroid) await _scheduleAndroid();
  }

  List<_Planned> _plan({int days = 7}) {
    final p = app.profile;
    if (p == null) return const [];
    final r = p.reminders;
    final now = DateTime.now();
    final out = <_Planned>[];
    for (var d = 0; d < days; d++) {
      final day = today().add(Duration(days: d));
      final key = dayKey(day);
      final isToday = d == 0;
      DateTime at(String hhmm) {
        final parts = hhmm.split(':');
        return DateTime(day.year, day.month, day.day, int.tryParse(parts[0]) ?? 8, int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0);
      }

      for (var i = 0; i < r.meals.length; i++) {
        final m = r.meals[i];
        if (!m.on) continue;
        if (isToday && app.entries(key).any((e) => e.meal == m.id)) continue;
        out.add(_Planned(100 + d * 10 + i, at(m.time), m.label, _mealBody(m.id)));
      }
      if (r.waterOn && p.habitOn('water') && !(isToday && app.habit(key).water >= p.waterMl)) {
        var t = at(r.waterFrom);
        final end = at(r.waterTo);
        var i = 0;
        while (!t.isAfter(end) && i < 10) {
          out.add(_Planned(200 + d * 10 + i, t, 'Acqua', 'Un bicchiere adesso? Obiettivo ${fDec(p.waterMl / 1000, 1, true)} L.'));
          t = t.add(Duration(minutes: r.waterEvery.clamp(30, 600)));
          i++;
        }
      }
      if (r.trainingOn && p.trainingDays.contains(day.weekday) && !app.habit(key).isOff && !(isToday && (app.sessionsByDate[key]?.isNotEmpty ?? false))) {
        out.add(_Planned(300 + d, at(r.trainingTime), 'Allenamento', trainingReminderBody(app, day)));
      }
      if (r.weightOn && !(isToday && app.weightOn(key) != null)) {
        out.add(_Planned(400 + d, at(r.weightTime), 'Peso', 'Pesati prima di colazione: la media dei 7 giorni diventa più precisa.'));
      }
      if (r.eveningOn) {
        out.add(_Planned(500 + d, at(r.eveningTime), 'Chiudi la giornata', 'Controlla il voto e cosa manca per salire.'));
      }
      final supps = pendingSupplements(p, isToday ? app.habit(key) : HabitDay(date: key));
      if (r.suppOn && supps.isNotEmpty) {
        out.add(_Planned(600 + d, at(r.suppTime), 'Integratori', _suppBody(supps)));
      }
    }
    return out.where((e) => e.at.isAfter(now)).toList();
  }

  String _mealBody(String meal) => switch (meal) {
        'colazione' => 'Registra la colazione: due tap e sei a posto.',
        'pranzo' => 'Com\'è andato il pranzo? Registralo ora che te lo ricordi.',
        'cena' => 'Registra la cena e guarda il voto di oggi.',
        _ => 'Registra il pasto.',
      };

  Future<void> _scheduleAndroid() async {
    if (!_ready) return;
    try {
      final pending = await _plugin.pendingNotificationRequests();
      for (final p in pending) {
        if (p.id < _restId) await _plugin.cancel(id: p.id);
      }
      for (final e in _plan()) {
        await _plugin.zonedSchedule(
          id: e.id,
          title: e.title,
          body: e.body,
          scheduledDate: tz.TZDateTime.from(e.at, tz.local),
          notificationDetails: _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    } catch (e) {
      debugPrint('pianificazione promemoria fallita: $e');
    }
  }

  // ---------------------------------------------------------------- desktop

  void _tickDesktop() {
    final p = app.profile;
    if (p == null || !_ready) return;
    final now = DateTime.now();
    final k = todayKey();
    if (_firedDay != k) {
      _firedDay = k;
      _firedToday.clear();
    }
    // Il ticker gira ogni 30 s: scatta tutto ciò che è scaduto nell'ultimo minuto.
    _catchUp(now, k, p);
  }

  void _catchUp(DateTime now, String k, Profile p) {
    final r = p.reminders;
    void check(String id, String hhmm, String title, String body, bool Function() still) {
      final parts = hhmm.split(':');
      final t = DateTime(now.year, now.month, now.day, int.tryParse(parts[0]) ?? 0, int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0);
      final d = now.difference(t).inSeconds;
      if (d < 0 || d > 60 || _firedToday.contains(id)) return;
      _firedToday.add(id);
      if (still()) show(title, body);
    }

    for (final m in r.meals) {
      if (!m.on) continue;
      check('meal-${m.id}', m.time, m.label, _mealBody(m.id), () => !app.entries(k).any((e) => e.meal == m.id));
    }
    if (r.waterOn && p.habitOn('water')) {
      final from = r.waterFrom.split(':'), to = r.waterTo.split(':');
      var t = DateTime(now.year, now.month, now.day, int.tryParse(from[0]) ?? 9, int.tryParse(from.length > 1 ? from[1] : '0') ?? 0);
      final end = DateTime(now.year, now.month, now.day, int.tryParse(to[0]) ?? 21, int.tryParse(to.length > 1 ? to[1] : '0') ?? 0);
      var i = 0;
      while (!t.isAfter(end) && i < 12) {
        check('water-$i', hhmm(t), 'Acqua', 'Un bicchiere adesso? Obiettivo ${fDec(p.waterMl / 1000, 1, true)} L.', () => app.habit(k).water < p.waterMl);
        t = t.add(Duration(minutes: r.waterEvery.clamp(30, 600)));
        i++;
      }
    }
    if (r.trainingOn && p.trainingDays.contains(now.weekday) && !app.habit(k).isOff) {
      check('train', r.trainingTime, 'Allenamento', trainingReminderBody(app, now), () => app.sessionsByDate[k]?.isEmpty ?? true);
    }
    if (r.weightOn) {
      check('weight', r.weightTime, 'Peso', 'Pesati prima di colazione.', () => app.weightOn(k) == null);
    }
    if (r.suppOn) {
      final supps = pendingSupplements(p, app.habit(k));
      if (supps.isNotEmpty) check('supp', r.suppTime, 'Integratori', _suppBody(supps), () => pendingSupplements(p, app.habit(k)).isNotEmpty);
    }
    if (r.eveningOn) {
      check('evening', r.eveningTime, 'Chiudi la giornata', 'Voto attuale ${fDec(app.score(k).v)}: guarda cosa manca per salire.', () => true);
    }
  }

  // ---------------------------------------------------------------- timer recupero

  Future<void> scheduleRestEnd(DateTime at) async {
    if (!_ready || !isAndroid) return;
    try {
      await _plugin.zonedSchedule(
        id: _restId,
        title: 'Recupero finito',
        body: 'Pronto per la prossima serie 💪',
        scheduledDate: tz.TZDateTime.from(at, tz.local),
        notificationDetails: const NotificationDetails(android: _timerChannel),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (e) {
      debugPrint('timer non pianificato: $e');
    }
  }

  Future<void> cancelRestEnd() async {
    if (!_ready) return;
    try {
      await _plugin.cancel(id: _restId);
    } catch (_) {}
  }

  static String _suppBody(List<String> s) => 'Hai preso ${s.join(' e ')}? Spunta in Oggi per non perdere la serie.';

  /// Per il voto serale su desktop: messaggio sintetico.
  String eveningSummary(DayScore s) => s.tips.isEmpty ? 'Giornata completa.' : s.tips.first.text;

  void dispose() {
    _ticker?.cancel();
    _debounce?.cancel();
  }
}
