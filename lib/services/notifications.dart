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
import '../logic/balance.dart';
import '../logic/nutrition.dart';
import '../logic/score.dart';
import '../logic/supplements.dart';
import '../logic/training.dart';
import '../logic/week_report.dart';

/// Due promemoria dell'acqua al giorno: a un terzo e a due terzi della fascia scelta.
List<DateTime> waterTimes(DateTime from, DateTime to) {
  final span = to.difference(from).inMinutes;
  if (span <= 0) return [from];
  return [from.add(Duration(minutes: span ~/ 3)), from.add(Duration(minutes: span * 2 ~/ 3))];
}

const _waterBody = 'A che punto sei con l\'acqua?';
const _weightBody = 'Pesata di oggi: conta la media dei 7 giorni, non il numero che leggi.';

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
      final day = addDays(today(), d);
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
        final times = waterTimes(at(r.waterFrom), at(r.waterTo));
        for (var i = 0; i < times.length; i++) {
          out.add(_Planned(200 + d * 10 + i, times[i], 'Acqua', '$_waterBody Obiettivo ${fDec(p.waterMl / 1000, 1, true)} L.'));
        }
      }
      if (r.trainingOn && (p.trainingDays.contains(day.weekday) || app.habit(key).moved != null) && !app.habit(key).isOff && !(isToday && (app.sessionsByDate[key]?.isNotEmpty ?? false))) {
        out.add(_Planned(300 + d, at(r.trainingTime), 'Allenamento', trainingReminderBody(app, day)));
      }
      if (r.weightOn && weighDays.contains(day.weekday) && !(isToday && app.weightOn(key) != null)) {
        out.add(_Planned(400 + d, at(r.weightTime), 'Peso', _weightBody));
      }
      if (r.eveningOn) {
        // oggi parte solo se manca qualcosa, e dice cosa
        final tips = isToday ? app.score(key).tips : const <Tip>[];
        if (!isToday || tips.isNotEmpty) {
          out.add(_Planned(500 + d, at(r.eveningTime), 'Chiudi la giornata',
              tips.isEmpty ? 'Controlla il voto e cosa manca per salire.' : tips.take(2).map((x) => x.text).join(' ')));
        }
      }
      if (r.reportOn && day.weekday == reportWeekday) {
        out.add(_Planned(700 + d, at(r.reportTime), 'Bilancio della settimana', balanceNotificationBody(app, day)));
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
      final start = DateTime(now.year, now.month, now.day, int.tryParse(from[0]) ?? 9, int.tryParse(from.length > 1 ? from[1] : '0') ?? 0);
      final end = DateTime(now.year, now.month, now.day, int.tryParse(to[0]) ?? 21, int.tryParse(to.length > 1 ? to[1] : '0') ?? 0);
      final times = waterTimes(start, end);
      for (var i = 0; i < times.length; i++) {
        check('water-$i', hhmm(times[i]), 'Acqua', '$_waterBody Obiettivo ${fDec(p.waterMl / 1000, 1, true)} L.', () => app.habit(k).water < p.waterMl);
      }
    }
    if (r.trainingOn && (p.trainingDays.contains(now.weekday) || app.habit(k).moved != null) && !app.habit(k).isOff) {
      check('train', r.trainingTime, 'Allenamento', trainingReminderBody(app, now), () => app.sessionsByDate[k]?.isEmpty ?? true);
    }
    if (r.weightOn && weighDays.contains(now.weekday)) {
      check('weight', r.weightTime, 'Peso', _weightBody, () => app.weightOn(k) == null);
    }
    if (r.suppOn) {
      final supps = pendingSupplements(p, app.habit(k));
      if (supps.isNotEmpty) check('supp', r.suppTime, 'Integratori', _suppBody(supps), () => pendingSupplements(p, app.habit(k)).isNotEmpty);
    }
    if (r.reportOn && now.weekday == reportWeekday) {
      check('report', r.reportTime, 'Bilancio della settimana', balanceNotificationBody(app, now), () => true);
    }
    if (r.eveningOn) {
      final sc = app.score(k);
      check('evening', r.eveningTime, 'Chiudi la giornata', 'Voto attuale ${fDec(sc.v)}. ${sc.tips.take(2).map((x) => x.text).join(' ')}', () => app.score(k).tips.isNotEmpty);
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
