import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tigert/core/fmt.dart';
import 'package:tigert/data/app_state.dart';
import 'package:tigert/data/catalog.dart';
import 'package:tigert/data/local_prefs.dart';
import 'package:tigert/data/models.dart';
import 'package:tigert/data/store.dart';
import 'package:tigert/logic/progression.dart';
import 'package:tigert/logic/training.dart';
import 'package:tigert/services/hevy.dart';

late Catalog catalog;

Future<AppState> newApp() async {
  final dir = Directory.systemTemp.createTempSync('tigert_hevy_');
  final store = Store();
  await store.init(dir: dir);
  final prefs = LocalPrefs();
  await prefs.init(dir);
  final app = AppState(store, prefs, catalog);
  final plan = templateByKey('ulpp').toPlan();
  store.put('plans', plan.id, plan.toMap());
  app.saveProfile(Profile(
    name: '',
    sex: 'm',
    birthYear: 1996,
    heightCm: 178,
    startWeight: 75,
    startDate: todayKey(),
    goal: Goal.bulk,
    targetWeight: 80,
    rate: 0.25,
    activity: 'moderato',
    kcal: 2800,
    protein: 150,
    carbs: 380,
    fat: 75,
    kcalStart: 2800,
    waterMl: 3000,
    trainingDays: const [1, 3, 5],
    planId: plan.id,
    reminders: Reminders.defaults(),
  ));
  return app;
}

/// Una sessione conclusa `daysAgo` giorni fa con un solo esercizio.
Session done(String exId, int daysAgo, List<(double, int)> sets, {double? rpe}) {
  final d = DateTime.now().subtract(Duration(days: daysAgo));
  return Session(
    id: 's$exId$daysAgo',
    date: dayKey(d),
    name: 'Test',
    start: d.millisecondsSinceEpoch,
    end: d.millisecondsSinceEpoch + 3600000,
    status: 'done',
    items: [
      SessionEx(ex: exId, name: exId, type: 'c', target: PlanItem(ex: exId, sets: sets.length), sets: [
        for (final (kg, r) in sets) SetLog(kg: kg, reps: r, rpe: rpe, done: true),
      ]),
    ],
  );
}

const csv = '''title,start_time,end_time,description,exercise_title,superset_id,exercise_notes,set_index,set_type,weight_kg,reps,distance_km,duration_seconds,rpe
"Push A","15 Sep 2026, 18:02","15 Sep 2026, 19:10","Buona, ma stanco","Bench Press (Barbell)",,"",0,warmup,40,10,,,
"Push A","15 Sep 2026, 18:02","15 Sep 2026, 19:10","Buona, ma stanco","Bench Press (Barbell)",,"",1,normal,70,8,,,8
"Push A","15 Sep 2026, 18:02","15 Sep 2026, 19:10","Buona, ma stanco","Bench Press (Barbell)",,"",2,normal,70,8,,,8.5
"Push A","15 Sep 2026, 18:02","15 Sep 2026, 19:10","Buona, ma stanco","Lateral Raise (Dumbbell)",,"",0,normal,10,12,,,
"Push A","15 Sep 2026, 18:02","15 Sep 2026, 19:10","Buona, ma stanco","Zercher Carry Supreme",,"",0,normal,50,20,,,
"Push A","15 Sep 2026, 18:02","15 Sep 2026, 19:10","Buona, ma stanco","Treadmill",,"",0,normal,,,2.1,900,
"Pull A","17 Sep 2026, 07:45","17 Sep 2026, 08:50","","Lat Pulldown (Cable)",1,"presa larga",0,normal,55,10,,,
"Pull A","17 Sep 2026, 07:45","17 Sep 2026, 08:50","","Seated Cable Row - V Grip (Cable)",1,"",0,normal,50,12,,,
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => catalog = await Catalog.load());

  group('Hevy CSV', () {
    test('date nei formati di Hevy', () {
      expect(parseHevyDate('15 Jul 2026, 09:52'), DateTime(2026, 7, 15, 9, 52));
      expect(parseHevyDate('3 lug 2026, 18:05'), DateTime(2026, 7, 3, 18, 5));
      expect(parseHevyDate('Jul 15, 2026, 9:52 PM'), DateTime(2026, 7, 15, 21, 52));
      expect(parseHevyDate('2026-07-15 09:52:00'), DateTime(2026, 7, 15, 9, 52));
      expect(parseHevyDate('boh'), isNull);
    });

    test('allenamenti, serie e virgole dentro le virgolette', () {
      final d = parseHevyCsv(csv);
      expect(d.workouts, hasLength(2));
      final push = d.workouts.first;
      expect(push.title, 'Push A');
      expect(push.description, 'Buona, ma stanco');
      expect(push.exercises.map((e) => e.title), ['Bench Press (Barbell)', 'Lateral Raise (Dumbbell)', 'Zercher Carry Supreme', 'Treadmill']);
      expect(push.exercises.first.sets, hasLength(3));
      expect(push.exercises.first.sets.first.warmup, isTrue);
      expect(push.exercises.first.sets[2].rpe, 8.5);
    });

    test('libbre convertite in kg e pesate', () {
      final lbs = parseHevyCsv('title,start_time,end_time,exercise_title,set_type,weight_lbs,reps\n'
          'A,"1 Sep 2026, 10:00","1 Sep 2026, 11:00",Squat (Barbell),normal,225,5\n');
      expect(lbs.workouts.single.exercises.single.sets.single.kg, closeTo(102.06, 0.01));
      final m = parseHevyCsv('date,weight_kg,fat_percent\n"10 Sep 2026",78.4,15\n"11 Sep 2026",78.1,\n');
      expect(m.weights, {'2026-09-10': 78.4, '2026-09-11': 78.1});
    });

    test('file non riconosciuto', () {
      expect(() => parseHevyCsv('a,b\n1,2\n'), throwsA(isA<HevyException>()));
    });
  });

  group('abbinamento esercizi', () {
    test('nomi inglesi di Hevy', () async {
      final app = await newApp();
      const expected = {
        'Bench Press (Barbell)': 'panca-piana',
        'Incline Bench Press (Dumbbell)': 'panca-inclinata-manubri',
        'Bench Press (Smith Machine)': 'panca-multipower',
        'Lat Pulldown (Cable)': 'lat-machine',
        'Seated Cable Row - V Grip (Cable)': 'pulley',
        'Squat (Barbell)': 'squat',
        'Romanian Deadlift (Barbell)': 'stacco-rumeno',
        'Deadlift (Barbell)': 'stacco',
        'Lateral Raise (Dumbbell)': 'alzate-laterali',
        'Overhead Press (Barbell)': 'military-press',
        'Shoulder Press (Dumbbell)': 'lento-manubri',
        'Bicep Curl (Dumbbell)': 'curl-manubri',
        'Hammer Curl (Dumbbell)': 'curl-martello',
        'Triceps Rope Pushdown': 'pushdown-corda',
        'Leg Press (Machine)': 'leg-press',
        'Lying Leg Curl (Machine)': 'leg-curl-sdraiato',
        'Seated Leg Curl (Machine)': 'leg-curl-seduto',
        'Leg Extension (Machine)': 'leg-extension',
        'Hip Thrust (Barbell)': 'hip-thrust',
        'Standing Calf Raise (Machine)': 'calf-in-piedi',
        'Pull Up': 'trazioni',
        'Chin Up': 'chin-up',
        'Plank': 'plank',
        'Treadmill': 'tapis-roulant',
        'Butterfly (Pec Deck)': 'pec-deck',
        'Face Pull': 'face-pull',
        'Bulgarian Split Squat': 'bulgarian',
        // calisthenics
        'Push Up': 'push-up',
        'Diamond Push Up': 'push-up-diamante',
        'Decline Push Up': 'push-up-declinati',
        'Pike Pushup': 'pike-push-up',
        'Handstand Push Up': 'hspu',
        'Chest Dip': 'dip-petto',
        'Triceps Dip': 'dip-tricipiti',
        'Ring Dips': 'dip-anelli',
        'Muscle Up': 'muscle-up',
        'Wide Pull Up': 'trazioni-presa-larga',
        'Negative Pull Up': 'trazioni-negative',
        'Inverted Row': 'rematore-inverso',
        'Front Lever Hold': 'front-lever',
        'L-Sit Hold': 'l-sit',
        'Hanging Knee Raise': 'knee-raise-sbarra',
        'Hanging Leg Raise': 'leg-raise-sbarra',
        'Toes To Bar': 'toes-to-bar',
        'Pistol Squat': 'pistol-squat',
        'Squat (Bodyweight)': 'squat-corpo-libero',
        'Jump Squat': 'jump-squat',
        'Single Leg Glute Bridge': 'glute-bridge-monolaterale',
        'Reverse Hyperextension': 'reverse-hyper',
        'Back Extension (Hyperextension)': 'hyperextension',
        'Pendlay Row (Barbell)': 'rematore-pendlay',
        'Floor Press (Dumbbell)': 'floor-press-manubri',
        'Clean and Jerk': 'slancio',
        'Power Clean': 'girata',
        'Walking': 'camminata',
        'Walking Lunge (Dumbbell)': 'affondi-camminati',
        'Farmers Walk': 'farmer-walk',
        // Hevy in italiano
        'Panca piana (Bilanciere)': 'panca-piana',
        'Lat machine avanti': 'lat-machine',
      };
      expected.forEach((title, id) => expect(matchExercise(title, app), id, reason: title));
      expect(matchExercise('Zercher Carry Supreme', app), isNull);
    });

    test('esercizio personalizzato dal CSV', () {
      final u = HevyExerciseUse('t:Cable Y Raise Deluxe', 'Cable Y Raise Deluxe', null);
      final e = newExerciseFor(u);
      expect(e.id, startsWith('x:hv'));
      expect(e.muscle, 'Spalle');
      expect(e.equip, 'Cavi');
    });
  });

  group('import', () {
    test('storico, esercizi nuovi e scheda ricostruita; ripetibile senza doppioni', () async {
      final app = await newApp();
      final d = parseHevyCsv(csv);
      final uses = d.exerciseUses();
      final mapping = {for (final u in uses) u.key: matchExercise(u.title, app)};
      final drafts = buildPlanDrafts(d);
      expect(drafts.single.days.map((x) => x.name), ['Push A', 'Pull A']);
      final r = importHevy(app, d, mapping: mapping, history: true, weights: false, plans: drafts, activatePlanId: drafts.single.id);
      expect(r.sessions, 2);
      expect(r.exercisesCreated, 1); // Zercher Carry Supreme
      expect(app.activePlan!.name, 'Da Hevy');
      final push = app.doneSessions.first;
      expect(push.items.first.ex, 'panca-piana');
      // il riscaldamento arriva come serie di avvicinamento e non conta come lavoro
      expect(push.items.first.sets.map((x) => x.t), [setWarmup, setWork, setWork]);
      expect(push.items.first.workDone, hasLength(2));
      expect(push.items.first.doneSets, 2);
      expect(push.items.first.target.warm, 1);
      expect(push.items.firstWhere((e) => e.ex == 'tapis-roulant').sets.single.reps, 15, reason: '900 s = 15 min');
      // di nuovo: stessi id, nessun doppione
      importHevy(app, d, mapping: mapping, history: true, weights: false, plans: drafts);
      expect(app.doneSessions, hasLength(2));
      expect(app.exercises.values.where((e) => e.custom), hasLength(1));
    });

    test('API di Hevy Pro (risposte simulate)', () async {
      final app = await newApp();
      final client = MockClient((req) async {
        expect(req.headers['api-key'], 'chiave');
        final page = req.url.queryParameters['page'];
        Map<String, dynamic> body;
        switch (req.url.path) {
          case '/v1/exercise_templates':
            body = {'page': 1, 'page_count': 1, 'exercise_templates': [
              {'id': 'B1', 'title': 'Bench Press (Barbell)', 'type': 'weight_reps', 'primary_muscle_group': 'chest', 'is_custom': false},
              {'id': 'C9', 'title': 'Macchina Strana Mia', 'type': 'weight_reps', 'primary_muscle_group': 'lats', 'equipment': 'machine', 'is_custom': true},
            ]};
          case '/v1/routine_folders':
            body = {'page': 1, 'page_count': 1, 'routine_folders': [{'id': 7, 'index': 0, 'title': 'PPL'}]};
          case '/v1/routines':
            body = {'page': 1, 'page_count': 1, 'routines': [
              {'id': 'r1', 'title': 'Push', 'folder_id': 7, 'exercises': [
                {'index': 0, 'title': 'Bench Press (Barbell)', 'exercise_template_id': 'B1', 'rest_seconds': 150, 'sets': [
                  {'index': 0, 'type': 'normal', 'rep_range': {'start': 6, 'end': 8}},
                  {'index': 1, 'type': 'normal', 'rep_range': {'start': 6, 'end': 8}},
                  {'index': 2, 'type': 'normal', 'rep_range': {'start': 6, 'end': 8}},
                ]},
              ]},
              {'id': 'r2', 'title': 'Pull', 'folder_id': 7, 'exercises': [
                {'index': 0, 'title': 'Macchina Strana Mia', 'exercise_template_id': 'C9', 'sets': [{'index': 0, 'type': 'normal', 'reps': 10}]},
              ]},
            ]};
          case '/v1/workouts':
            // due pagine per verificare la paginazione
            body = {'page': int.parse(page!), 'page_count': 2, 'workouts': [
              {'id': 'w$page', 'title': 'Push', 'routine_id': 'r1', 'start_time': '2026-09-1${page}T17:00:00Z', 'end_time': '2026-09-1${page}T18:00:00Z', 'exercises': [
                {'index': 0, 'title': 'Bench Press (Barbell)', 'exercise_template_id': 'B1', 'sets': [
                  {'index': 0, 'type': 'normal', 'weight_kg': 80, 'reps': 8, 'rpe': 8},
                  {'index': 1, 'type': 'normal', 'weight_kg': 80, 'reps': 8, 'rpe': 8},
                  {'index': 2, 'type': 'normal', 'weight_kg': 80, 'reps': 8, 'rpe': 8.5},
                ]},
              ]},
            ]};
          case '/v1/body_measurements':
            body = {'page': 1, 'page_count': 1, 'body_measurements': [{'date': '2026-09-12', 'weight_kg': 79.5}]};
          default:
            return http.Response('{}', 404);
        }
        return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});
      });
      final d = await fetchHevy('chiave', httpClient: client);
      expect(d.workouts, hasLength(2));
      expect(d.routines, hasLength(2));
      expect(d.weights, {'2026-09-12': 79.5});
      final drafts = buildPlanDrafts(d);
      expect(drafts.single.name, 'PPL');
      final bench = drafts.single.days.first.items.single;
      expect((bench.sets, bench.rMin, bench.rMax, bench.rest), (3, 6, 8, 150));
      final mapping = {for (final u in d.exerciseUses()) u.key: matchExercise(u.title, app)};
      final r = importHevy(app, d, mapping: mapping, history: true, weights: true, plans: drafts, activatePlanId: drafts.single.id);
      expect((r.sessions, r.exercisesCreated, r.plans, r.weights), (2, 1, 1, 1));
      final custom = app.exercises.values.firstWhere((e) => e.custom);
      expect((custom.name, custom.muscle, custom.equip), ('Macchina Strana Mia', 'Dorso', 'Macchina'));
      // 3×8 a RPE ≤ 9 sul tetto del range 6-8 → il coach propone di salire
      final a = adviceFor(app, app.activePlan!.days.first.items.single);
      expect(a.kind, AdviceKind.increase);
      expect(a.kg, 82.5);
    });

    test('chiave sbagliata', () async {
      final client = MockClient((_) async => http.Response('{"error":"unauthorized"}', 401));
      expect(() => fetchHevy('x', httpClient: client), throwsA(isA<HevyException>()));
    });
  });

  group('coach di progressione', () {
    const it = PlanItem(ex: 'panca-piana', sets: 3, rMin: 8, rMax: 12, rpe: 9);

    test('tetto raggiunto → +2,5 kg e si riparte da 8', () async {
      final app = await newApp();
      app.saveSession(done('panca-piana', 3, [(60, 12), (60, 12), (60, 12)], rpe: 8.5));
      final a = adviceFor(app, it);
      expect((a.kind, a.kg, a.reps), (AdviceKind.increase, 62.5, 8));
      expect(adviceSummary([a]), '↑ Panca piana con bilanciere 62,5 kg (+2,5)');
      // la sessione nuova parte già col carico alzato
      final ex = buildSessionEx(app, it);
      expect(ex.sets.map((s) => (s.kg, s.reps)).toSet(), {(62.5, 8)});
    });

    test('RPE troppo alto al tetto → non si sale ancora', () async {
      final app = await newApp();
      app.saveSession(done('panca-piana', 3, [(60, 12), (60, 12), (60, 12)], rpe: 10));
      expect(adviceFor(app, it).kind, AdviceKind.reps);
    });

    test('in mezzo al range → una ripetizione in più', () async {
      final app = await newApp();
      app.saveSession(done('panca-piana', 3, [(60, 10), (60, 9), (60, 9)]));
      final a = adviceFor(app, it);
      expect((a.kind, a.kg, a.reps), (AdviceKind.reps, 60.0, 11));
    });

    test('sotto il minimo → carico più leggero', () async {
      final app = await newApp();
      app.saveSession(done('panca-piana', 2, [(70, 6), (70, 5), (70, 5)]));
      final a = adviceFor(app, it);
      expect((a.kind, a.kg), (AdviceKind.lighter, 67.5));
    });

    test('3 sedute ferme → scarico del 10%', () async {
      final app = await newApp();
      app.saveSession(done('panca-piana', 9, [(80, 10), (80, 9), (80, 9)]));
      app.saveSession(done('panca-piana', 5, [(80, 10), (80, 9), (80, 8)]));
      app.saveSession(done('panca-piana', 2, [(80, 9), (80, 9), (80, 8)]));
      final a = adviceFor(app, it);
      expect((a.kind, a.kg), (AdviceKind.deload, 72.5));
    });

    test('dopo più di 4 settimane → si riparte al 90%', () async {
      final app = await newApp();
      app.saveSession(done('panca-piana', 40, [(80, 10), (80, 10), (80, 10)]));
      final a = adviceFor(app, it);
      expect((a.kind, a.kg), (AdviceKind.lighter, 72.5));
    });

    test('prima volta', () async {
      final app = await newApp();
      expect(adviceFor(app, it).kind, AdviceKind.first);
    });
  });
}
