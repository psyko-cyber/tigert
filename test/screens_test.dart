// Giro di tutte le schermate a misura telefono e desktop: fallisce se una
// schermata lancia eccezioni o ha errori di layout (overflow, vincoli infiniti…).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigert/core/fmt.dart';
import 'package:tigert/core/ids.dart';
import 'package:tigert/core/theme.dart';
import 'package:tigert/data/app_state.dart';
import 'package:tigert/data/catalog.dart';
import 'package:tigert/data/local_prefs.dart';
import 'package:tigert/data/models.dart';
import 'package:tigert/data/store.dart';
import 'package:tigert/logic/day_off.dart';
import 'package:tigert/logic/training.dart';
import 'package:tigert/services/drive_backup.dart';
import 'package:tigert/services/gemini.dart';
import 'package:tigert/services/notifications.dart';
import 'package:tigert/services/services.dart';
import 'package:tigert/services/sync.dart';
import 'package:tigert/ui/achievements_screen.dart';
import 'package:tigert/ui/add_hub.dart';
import 'package:tigert/ui/barcode.dart';
import 'package:tigert/ui/day_off.dart';
import 'package:tigert/ui/diary.dart';
import 'package:tigert/ui/exercise_picker.dart';
import 'package:tigert/ui/food_amount.dart';
import 'package:tigert/ui/food_editor.dart';
import 'package:tigert/ui/food_search.dart';
import 'package:tigert/ui/hevy_import.dart';
import 'package:tigert/ui/onboarding.dart';
import 'package:tigert/ui/photo_estimate.dart';
import 'package:tigert/ui/plan_editor.dart';
import 'package:tigert/ui/plans.dart';
import 'package:tigert/ui/profile.dart';
import 'package:tigert/ui/progress.dart';
import 'package:tigert/ui/quick_add.dart';
import 'package:tigert/ui/recipes.dart';
import 'package:tigert/ui/reorder.dart';
import 'package:tigert/ui/score_detail.dart';
import 'package:tigert/ui/session.dart';
import 'package:tigert/ui/session_summary.dart';
import 'package:tigert/ui/settings/drive_settings.dart';
import 'package:tigert/ui/settings/gemini_settings.dart';
import 'package:tigert/ui/settings/home_gym_settings.dart';
import 'package:tigert/ui/settings/misc_settings.dart';
import 'package:tigert/ui/settings/profile_settings.dart';
import 'package:tigert/ui/settings/reminders_settings.dart';
import 'package:tigert/ui/settings/sync_settings.dart';
import 'package:tigert/ui/today.dart';
import 'package:tigert/ui/shell.dart';
import 'package:tigert/ui/training.dart';
import 'package:tigert/ui/update_dialog.dart';
import 'package:tigert/services/updates.dart';
import 'package:tigert/ui/volume.dart';
import 'package:tigert/ui/week_report.dart';
import 'package:tigert/ui/widgets.dart';

late AppState app;
late String activeSessionId;
late String doneSessionId;
late Food chicken;

Future<void> _loadFonts() async {
  final loader = FontLoader('Archivo');
  for (final w in [400, 500, 600, 700, 800]) {
    loader.addFont(rootBundle.load('assets/fonts/Archivo-$w.ttf'));
  }
  await loader.load();
  // icone Material vere negli screenshot (altrimenti quadratini)
  final icons = File('${Platform.environment['FLUTTER_ROOT'] ?? r'C:\srclutter'}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    final l = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
    await l.load();
  }
}

/// `flutter test test/screens_test.dart --dart-define=SHOTS=true --update-goldens`
/// salva uno screenshot di ogni schermata in test/shots/ (per controllo visivo).
const _shots = bool.fromEnvironment('SHOTS');

Future<void> _seed() async {
  final dir = Directory.systemTemp.createTempSync('tigert_test_');
  final store = Store();
  await store.init(dir: dir);
  final prefs = LocalPrefs();
  await prefs.init(dir);
  final catalog = await Catalog.load();
  app = AppState(store, prefs, catalog);
  Services.app = app;
  Services.sync = SyncService(app);
  Services.notif = NotificationService(app);
  Services.drive = DriveBackup(app);
  DriveBackup.debugAvailable = true;

  final plan = templateByKey('ulpp').toPlan();
  final today = todayKey();
  app.store.put('plans', plan.id, plan.toMap());
  // seconda scheda con un ciclo di 2 settimane
  app.savePlan(Plan(id: 'cyc', name: 'Split su 2 settimane', startDate: today, cycle: 2, days: [
    for (var i = 0; i < plan.days.length; i++) plan.days[i].copyWith(week: i < 2 ? 1 : 2),
  ]));
  app.saveProfile(Profile(
    name: 'Luca',
    sex: 'm',
    birthYear: 1996,
    heightCm: 178,
    startWeight: 78,
    startDate: addDaysKey(today, -40),
    goal: Goal.cut,
    targetWeight: 72,
    rate: 0.5,
    activity: 'moderato',
    kcal: 2140,
    protein: 168,
    carbs: 230,
    fat: 61,
    kcalStart: 2140,
    waterMl: 3250,
    trainingDays: const [1, 2, 4, 5],
    planId: plan.id,
    reminders: Reminders.defaults(),
    home: const HomeGym(bar: true, dip: true, bench: true, dbKg: 10),
  ));
  chicken = catalog.foods.firstWhere((f) => fold(f.name).contains('petto di pollo'));
  final pasta = catalog.foods.firstWhere((f) => fold(f.name).startsWith('pasta'));
  for (var d = -35; d <= 0; d++) {
    final k = addDaysKey(today, d);
    app.setWeight(k, 78 - (d + 35) * 0.1);
    app.addEntry(app.entryFromFood(chicken, 200, date: k, meal: 'pranzo'));
    app.addEntry(app.entryFromFood(pasta, 90, date: k, meal: 'cena'));
    app.saveHabit(HabitDay(date: k, water: 2500, sleep: 440, steps: 9000, alcohol: 0, supp: d < 0 && d > -6 ? const ['Creatina'] : const []));
  }
  final juice = catalog.foods.firstWhere((f) => fold(f.name).startsWith('spremuta'));
  app.addEntry(app.entryFromFood(juice, 200, date: today, meal: 'colazione'));
  app.saveHabit(app.habit(today).copyWith(extra: const [ExtraActivity(kind: 'calcetto', name: 'Calcetto', min: 60, kcal: 560)]));
  // una sessione conclusa (ieri) e una in corso (oggi)
  final done = buildSession(app, plan: plan, day: plan.days.first);
  final finished = done.copyWith(
    status: 'done',
    end: done.start + 3600 * 1000,
    items: [
      for (final (i, e) in done.items.indexed)
        e.copyWith(sets: [
          if (i == 0) const SetLog(t: setWarmup, kg: 20, reps: 10, done: true),
          for (final s in e.sets) s.copyWith(done: true, kg: s.kg == 0 ? 40 : s.kg, reps: 10, rpe: 8),
          if (i == 0) const SetLog(t: setDrop, kg: 25, reps: 8, done: true),
        ]),
    ],
  );
  final y = Session.fromMap({...finished.toMap(), 'id': 'done1', 'date': addDaysKey(today, -1)});
  app.saveSession(y);
  doneSessionId = y.id;
  final active = buildSession(app, plan: plan, day: plan.days[1]);
  app.saveSession(active);
  activeSessionId = active.id;
  await app.store.flush();
}

Widget _wrap(Widget child, {bool dark = true}) => AppScope(
      state: app,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(dark ? TT.darkT : TT.lightT),
        locale: const Locale('it', 'IT'),
        supportedLocales: const [Locale('it', 'IT')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(body: child),
      ),
    );

/// Nessun bottone deve "esplodere" in altezza (es. Center senza heightFactor).
void _checkButtons(WidgetTester tester) {
  for (final type in [PrimaryButton, GhostButton]) {
    for (final el in find.byType(type).evaluate()) {
      final h = tester.getSize(find.byWidget(el.widget)).height;
      expect(h, lessThan(120), reason: '$type alto ${h.toStringAsFixed(0)} px');
    }
  }
}

const _estimate = '{"tigert":1,"piatto":"Pasta al pomodoro con pollo","affidabilita":"media","alimenti":['
    '{"nome":"Pasta","grammi":90,"grammi_min":80,"grammi_max":110,"kcal_100g":357,"proteine_100g":12.5,"carboidrati_100g":72,"grassi_100g":1.5},'
    '{"nome":"Petto di pollo","grammi":120,"grammi_min":100,"grammi_max":150,"kcal_100g":110,"proteine_100g":23,"carboidrati_100g":0,"grassi_100g":1.2}],'
    '"note":"Olio stimato"}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadFonts();
    await _seed();
  });

  final screens = <String, Widget Function()>{
    'Onboarding': () => const OnboardingScreen(),
    'Oggi': () => const TodayScreen(),
    'Oggi su ieri': () {
      DayNav.set(addDaysKey(todayKey(), -1));
      return const TodayScreen();
    },
    'Oggi su 3 giorni fa': () {
      DayNav.set(addDaysKey(todayKey(), -3));
      return const TodayScreen();
    },
    'Aggiungi': () => const AddHubScreen(embedded: true),
    'Aggiungi su ieri': () {
      DayNav.set(addDaysKey(todayKey(), -1));
      return const AddHubScreen(embedded: true);
    },
    'Cerca': () => FoodSearchScreen(date: todayKey(), meal: 'pranzo', focusSearch: false),
    'Quantità': () => FoodAmountScreen(food: chicken, date: todayKey(), meal: 'pranzo'),
    'Quantità piatto': () => FoodAmountScreen(food: app.catalog.foodById['s:pasta-al-ragu']!, date: todayKey(), meal: 'cena'),
    'Editor alimento': () => const FoodEditorScreen(),
    'Solo calorie': () => QuickAddScreen(date: todayKey(), meal: 'pranzo'),
    'Ricette': () => RecipesScreen(date: todayKey(), meal: 'pranzo'),
    'Editor ricetta': () => RecipeEditorScreen(date: todayKey(), meal: 'pranzo'),
    'Barcode': () => BarcodeScreen(date: todayKey(), meal: 'pranzo'),
    'Foto': () => PhotoScreen(date: todayKey(), meal: 'pranzo'),
    'Stima': () => EstimateScreen(estimate: parseEstimate(_estimate), date: todayKey(), meal: 'pranzo'),
    'Diario': () => DiaryScreen(date: todayKey()),
    'Diario vuoto': () => DiaryScreen(date: addDaysKey(todayKey(), 1)),
    'Allena': () => const TrainingScreen(),
    'Giustifica': () => DayOffSheet(slot: WeekSlot(today(), app.activePlan!.days[1], SlotStatus.todo, null)),
    'Rimanda': () {
      final d = app.activePlan!.days[1];
      final off = HabitDay(date: todayKey()).withOff('impegno', dayId: d.id, moveTo: addDaysKey(todayKey(), 1));
      return DayOffSheet(slot: WeekSlot(today(), d, SlotStatus.off, null, off: off));
    },
    'Alternativa': () {
      final lower = app.activePlan!.days[1];
      final off = HabitDay(date: todayKey()).withOff('dolore', dayId: lower.id, avoid: const ['Gambe']);
      return PageBody(children: [
        AlternativeCard(slot: WeekSlot(today(), lower, SlotStatus.off, null, off: off), alt: alternativeFor(app, today(), lower, const ['Gambe'])),
      ]);
    },
    'Storico sessioni': () => const SessionHistoryScreen(),
    'Editor scheda': () => PlanEditorScreen(planId: app.activePlan!.id),
    'Editor scheda ciclo': () => const PlanEditorScreen(planId: 'cyc'),
    'Le mie schede': () => const PlansScreen(),
    'Volume': () => const VolumeScreen(),
    'Report settimanale': () => const WeekReportScreen(),
    'Report settimana scorsa': () => WeekReportScreen(monday: today().subtract(const Duration(days: 7))),
    'Card report': () => const PageBody(children: [WeekReportCard(), WeekReportCard(tip: true)]),
    'Attrezzatura a casa': () => const HomeGymScreen(),
    'Riordina': () => ReorderScreen(entries: [for (final e in app.session(activeSessionId)!.items) ReorderEntry(e.ex, e.name, '${e.plannedSets} serie')]),
    'Quantità bevanda': () => FoodAmountScreen(food: app.catalog.foods.firstWhere((f) => fold(f.name).startsWith('spremuta')), date: todayKey(), meal: 'colazione'),
    'Esercizi': () => const ExercisePickerScreen(),
    'Sessione': () => SessionScreen(sessionId: activeSessionId),
    'Riepilogo sessione': () => SessionSummaryScreen(sessionId: doneSessionId, fresh: true),
    'Voto': () => ScoreDetailScreen(date: addDaysKey(todayKey(), -1)),
    'Traguardi': () => const AchievementsScreen(),
    'Progressi': () => const ProgressScreen(),
    'Storico peso': () => const WeightHistoryScreen(),
    'Storico esercizio': () => ExerciseHistoryScreen(exId: app.activePlan!.days.first.items.first.ex),
    'Profilo': () => const ProfileScreen(),
    'Dati personali': () => const ProfileEditScreen(),
    'Target': () => const TargetsEditScreen(),
    'Promemoria': () => const RemindersScreen(),
    'Gemini': () => const GeminiSettingsScreen(),
    'Sync': () => const SyncSettingsScreen(),
    'Abitudini': () => const HabitsSettingsScreen(),
    'Windows': () => const DesktopSettingsScreen(),
    'Dati': () => const DataSettingsScreen(),
    'Google Drive': () {
      app.prefs.set('driveOn', null);
      return const DriveSettingsScreen();
    },
    'Google Drive collegato': () {
      app.prefs.set('driveOn', true);
      app.prefs.set('driveEmail', 'luca@gmail.com');
      app.prefs.set('driveLast', DateTime.now().millisecondsSinceEpoch);
      app.prefs.set('driveLastSize', 1840000);
      return const DriveSettingsScreen();
    },
    'Informazioni': () => const AboutScreen(),
    'Importa da Hevy': () => const HevyImportScreen(),
  };

  const sizes = {'telefono': Size(390, 844), 'desktop': Size(1280, 800), if (_shots) 'lungo': Size(390, 2200)};

  for (final s in sizes.entries) {
    for (final e in screens.entries) {
      testWidgets('${e.key} · ${s.key}', (tester) async {
        tester.view.physicalSize = s.value;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        DayNav.reset();
        await tester.pumpWidget(_wrap(e.value(), dark: s.key == 'telefono'));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 900));
        expect(tester.takeException(), isNull);
        _checkButtons(tester);
        if (_shots) {
          await expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/${s.key}/${e.key.replaceAll(' ', '_')}.png'));
        }
        // scorro fino in fondo per costruire (e verificare) anche la parte bassa
        final scrollables = find.byType(Scrollable);
        if (scrollables.evaluate().isNotEmpty) {
          await tester.drag(scrollables.first, const Offset(0, -3000), warnIfMissed: false);
          await tester.pump(const Duration(milliseconds: 600));
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  for (final s in sizes.entries.where((s) => s.key != 'lungo')) {
    testWidgets('Attività extra · ${s.key}', (tester) async {
      tester.view.physicalSize = s.value;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_wrap(const TodayScreen(), dark: s.key == 'telefono'));
      await tester.pump(const Duration(milliseconds: 500));
      final add = find.text('Attività extra');
      await tester.ensureVisible(add);
      await tester.pumpAndSettle();
      await tester.tap(add);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Beach volley'));
      await tester.tap(find.text('Intensa'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      if (_shots) await expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/${s.key}/Attività_extra.png'));
      await tester.tap(find.text('Aggiungi'));
      await tester.pumpAndSettle();
      final h = app.habit(todayKey());
      expect(h.extra.map((e) => e.name), contains('Beach volley'));
      app.saveHabit(h.copyWith(extra: h.extra.where((e) => e.kind != 'beach').toList()));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    });
  }

  testWidgets('Aggiungi a ieri', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(const AddHubScreen(embedded: true)));
    await tester.pump(const Duration(milliseconds: 300));
    final yesterday = addDaysKey(todayKey(), -1);
    final before = app.entries(yesterday).length;
    DayNav.reset();
    await tester.tap(find.byTooltip('Giorno prima'));
    await tester.pump();
    expect(DayNav.key, yesterday, reason: 'la barra sposta il giorno anche in Oggi');
    final plus = find.byType(PlusBadge).first;
    await tester.ensureVisible(plus);
    await tester.pumpAndSettle();
    await tester.tap(plus);
    await tester.pump(const Duration(milliseconds: 300));
    expect(app.entries(yesterday).length, before + 1);
    expect(find.textContaining('di ieri'), findsOneWidget, reason: 'il toast dice il giorno');
    final added = app.entries(yesterday).last;
    app.deleteEntry(added.id);
    DayNav.reset();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('Oggi su una giornata passata si modifica tutto', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final yesterday = addDaysKey(todayKey(), -1);
    DayNav.set(yesterday);
    await tester.pumpWidget(_wrap(const TodayScreen()));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('STAI MODIFICANDO'), findsOneWidget);
    expect(find.text('VOTO DI IERI'), findsOneWidget);
    expect(find.textContaining('· fatto'), findsOneWidget, reason: 'la seduta di ieri');
    final water = app.habit(yesterday).water;
    final add = find.text('+ 250 ml');
    await tester.ensureVisible(add);
    await tester.pumpAndSettle();
    await tester.tap(add);
    await tester.pump();
    expect(app.habit(yesterday).water, water + 250, reason: 'l\'acqua va su ieri');
    app.addWater(yesterday, -250);
    await tester.ensureVisible(find.text('Oggi'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Oggi'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(DayNav.isToday, isTrue);
    expect(find.text('STAI MODIFICANDO'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('Dal voto si entra nella giornata; seduta di un giorno passato', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    DayNav.reset();
    final yesterday = addDaysKey(todayKey(), -1);
    await tester.pumpWidget(_wrap(ScoreDetailScreen(date: yesterday)));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Modifica questa giornata'));
    await tester.pump();
    expect(DayNav.key, yesterday);
    // giorno senza seduta: tocco la card e scelgo quale ho fatto
    final old = addDaysKey(todayKey(), -3);
    DayNav.set(old);
    await tester.pumpWidget(_wrap(const TodayScreen()));
    await tester.pump(const Duration(milliseconds: 300));
    final card = find.textContaining('Tocca per registrar');
    expect(card, findsOneWidget);
    await tester.tap(card);
    await tester.pumpAndSettle();
    expect(find.textContaining('Che seduta hai fatto'), findsOneWidget);
    expect(find.text('Allenamento libero'), findsOneWidget);
    DayNav.reset();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    // la seduta compilata dopo sta in quel giorno, alle 18, con durata stimata
    final s = buildSession(app, plan: app.activePlan, day: app.activePlan!.days.first, date: old);
    expect(s.date, old);
    expect(DateTime.fromMillisecondsSinceEpoch(s.start).hour, 18);
    expect(sessionEnd(s) - s.start, const Duration(minutes: 20).inMilliseconds);
    expect(DateTime.fromMillisecondsSinceEpoch(buildSession(app).start).day, DateTime.now().day);
  });

  testWidgets('Popup di aggiornamento', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const u = UpdateInfo('9.9.9', 'https://github.com', 'https://github.com/Tigert-9.9.9.apk', '## Novità\n\n**Barra giorno** in Oggi', null);
    updateNotice.value = u;
    await tester.pumpWidget(_wrap(Builder(builder: (context) => Center(child: SmallButton('apri', onTap: () => offerUpdate(context, u))))));
    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
    expect(find.text('Tigert 9.9.9 disponibile'), findsOneWidget);
    expect(find.textContaining('Barra giorno in Oggi'), findsOneWidget, reason: 'note senza markdown');
    if (_shots) await expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/telefono/Aggiornamento.png'));
    await tester.tap(find.text('Più tardi'));
    await tester.pumpAndSettle();
    expect(updateSnoozed(app.prefs, u), isTrue, reason: 'riproposto dopo 20 ore');
    expect(updateNotice.value, isNull);
    app.prefs.dismissedUpdate = null;
    await tester.pumpWidget(const SizedBox());
  });

  test('dispositivo di test', () => expect(isDesktop, isTrue));
}
