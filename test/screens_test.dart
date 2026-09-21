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
import 'package:tigert/logic/training.dart';
import 'package:tigert/services/gemini.dart';
import 'package:tigert/services/notifications.dart';
import 'package:tigert/services/services.dart';
import 'package:tigert/services/sync.dart';
import 'package:tigert/ui/achievements_screen.dart';
import 'package:tigert/ui/add_hub.dart';
import 'package:tigert/ui/barcode.dart';
import 'package:tigert/ui/diary.dart';
import 'package:tigert/ui/exercise_picker.dart';
import 'package:tigert/ui/food_amount.dart';
import 'package:tigert/ui/food_editor.dart';
import 'package:tigert/ui/food_search.dart';
import 'package:tigert/ui/onboarding.dart';
import 'package:tigert/ui/photo_estimate.dart';
import 'package:tigert/ui/plan_editor.dart';
import 'package:tigert/ui/profile.dart';
import 'package:tigert/ui/progress.dart';
import 'package:tigert/ui/quick_add.dart';
import 'package:tigert/ui/recipes.dart';
import 'package:tigert/ui/score_detail.dart';
import 'package:tigert/ui/session.dart';
import 'package:tigert/ui/session_summary.dart';
import 'package:tigert/ui/settings/gemini_settings.dart';
import 'package:tigert/ui/settings/misc_settings.dart';
import 'package:tigert/ui/settings/profile_settings.dart';
import 'package:tigert/ui/settings/reminders_settings.dart';
import 'package:tigert/ui/settings/sync_settings.dart';
import 'package:tigert/ui/today.dart';
import 'package:tigert/ui/training.dart';
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

  final plan = templateByKey('ulpp').toPlan();
  final today = todayKey();
  app.store.put('plans', plan.id, plan.toMap());
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
  ));
  chicken = catalog.foods.firstWhere((f) => fold(f.name).contains('petto di pollo'));
  final pasta = catalog.foods.firstWhere((f) => fold(f.name).startsWith('pasta'));
  for (var d = -35; d <= 0; d++) {
    final k = addDaysKey(today, d);
    app.setWeight(k, 78 - (d + 35) * 0.1);
    app.addEntry(app.entryFromFood(chicken, 200, date: k, meal: 'pranzo'));
    app.addEntry(app.entryFromFood(pasta, 90, date: k, meal: 'cena'));
    app.saveHabit(HabitDay(date: k, water: 2500, sleep: 440, steps: 9000, alcohol: 0));
  }
  // una sessione conclusa (ieri) e una in corso (oggi)
  final done = buildSession(app, plan: plan, day: plan.days.first);
  final finished = done.copyWith(
    status: 'done',
    end: done.start + 3600 * 1000,
    items: [
      for (final e in done.items) e.copyWith(sets: [for (final s in e.sets) s.copyWith(done: true, kg: s.kg == 0 ? 40 : s.kg, reps: 10, rpe: 8)]),
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
    'Aggiungi': () => const AddHubScreen(embedded: true),
    'Cerca': () => FoodSearchScreen(date: todayKey(), meal: 'pranzo', focusSearch: false),
    'Quantità': () => FoodAmountScreen(food: chicken, date: todayKey(), meal: 'pranzo'),
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
    'Storico sessioni': () => const SessionHistoryScreen(),
    'Editor scheda': () => PlanEditorScreen(planId: app.activePlan!.id),
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
    'Informazioni': () => const AboutScreen(),
  };

  const sizes = {'telefono': Size(390, 844), 'desktop': Size(1280, 800)};

  for (final s in sizes.entries) {
    for (final e in screens.entries) {
      testWidgets('${e.key} · ${s.key}', (tester) async {
        tester.view.physicalSize = s.value;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
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

  test('dispositivo di test', () => expect(isDesktop, isTrue));
}
