// Percorso reale del PC: primo avvio senza profilo, i dati arrivano dal
// telefono via sync, poi si usano i tasti della schermata Oggi.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigert/app.dart';
import 'package:tigert/core/fmt.dart';
import 'package:tigert/data/app_state.dart';
import 'package:tigert/data/catalog.dart';
import 'package:tigert/data/local_prefs.dart';
import 'package:tigert/data/models.dart';
import 'package:tigert/data/store.dart';
import 'package:tigert/services/drive_backup.dart';
import 'package:tigert/services/notifications.dart';
import 'package:tigert/services/resume_guard.dart';
import 'package:tigert/services/services.dart';
import 'package:tigert/services/sync.dart';

Future<AppState> _newApp(Catalog catalog) async {
  final dir = Directory.systemTemp.createTempSync('tigert_pc_');
  final store = Store();
  await store.init(dir: dir);
  final prefs = LocalPrefs();
  await prefs.init(dir);
  prefs.lastUpdateCheck = DateTime.now().millisecondsSinceEpoch; // niente rete nei test
  return AppState(store, prefs, catalog);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('PC: dopo la sync dal telefono i tasti di Oggi aggiornano la schermata', (tester) async {
    tester.view.physicalSize = const bool.fromEnvironment('NARROW') ? const Size(400, 860) : const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    late AppState pc, phone;
    await tester.runAsync(() async {
      final loader = FontLoader('Archivo')..addFont(rootBundle.load('assets/fonts/Archivo-400.ttf'));
      await loader.load();
      final catalog = await Catalog.load();
      pc = await _newApp(catalog);
      phone = await _newApp(catalog);
    });
    Services.app = pc;
    Services.sync = SyncService(pc);
    Services.notif = NotificationService(pc);
    Services.drive = DriveBackup(pc);

    // telefono: onboarding fatto + un pasto (sblocca il badge "Primo pasto")
    final plan = templateByKey('fb3').toPlan();
    phone.store.put('plans', plan.id, plan.toMap());
    phone.saveProfile(Profile(
      name: 'Luca',
      sex: 'm',
      birthYear: 1996,
      heightCm: 175,
      startWeight: 62,
      startDate: todayKey(),
      goal: Goal.bulk,
      targetWeight: 70,
      rate: 0.25,
      activity: 'moderato',
      kcal: 2790,
      protein: 124,
      carbs: 398,
      fat: 78,
      kcalStart: 2790,
      waterMl: 2750,
      trainingDays: const [1, 3, 5],
      planId: plan.id,
      reminders: Reminders.defaults(),
    ));
    phone.setWeight(todayKey(), 62);
    phone.prefs.badgesInitialized = true;
    final food = phone.catalog.foods.first;
    phone.addEntry(phone.entryFromFood(food, 100, date: todayKey(), meal: 'pranzo'));

    const direct = bool.fromEnvironment('DIRECT');
    if (direct) pc.store.applyRemote(phone.store.changesSince(0));
    await tester.pumpWidget(TigertApp(app: pc));
    await tester.pump(const Duration(milliseconds: 500));
    if (!direct) expect(find.text('Inizia'), findsOneWidget); // onboarding

    // arriva la sync dal telefono
    if (!direct) pc.store.applyRemote(phone.store.changesSince(0));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    // eventuale finestra "badge sbloccato"
    if (find.text('Continua').evaluate().isNotEmpty) {
      await tester.tap(find.text('Continua'));
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.text('+ 250 ml'), findsOneWidget);
    expect(tester.takeException(), isNull);

    installResumeGuard();
    const hide = String.fromEnvironment('HIDE', defaultValue: 'inactive,hidden');
    if (hide.isNotEmpty) {
      // la finestra va nel tray e poi viene riaperta
      for (final st in hide.split(',')) {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.values.byName(st));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
    await tester.tap(find.text('+ 250 ml'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(pc.habit(todayKey()).water, 250, reason: 'il dato deve essere salvato');
    expect(find.textContaining('0,25 /'), findsOneWidget, reason: 'la schermata deve mostrare 0,25 L');

    await tester.tap(find.text('2'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(pc.habit(todayKey()).alcohol, 2);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}
