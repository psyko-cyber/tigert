import 'dart:convert';

import 'package:flutter/services.dart';

import '../core/fmt.dart';
import '../core/ids.dart';
import 'models.dart';

/// Dati di partenza inclusi nell'app: alimenti ed esercizi.
class Catalog {
  final List<Food> foods;
  final Map<String, Food> foodById;
  final List<Exercise> exercises;
  final Map<String, Exercise> exById;
  final Map<String, String> foldedNames;

  Catalog._(this.foods, this.exercises)
      : foodById = {for (final f in foods) f.id: f},
        exById = {for (final e in exercises) e.id: e},
        foldedNames = {for (final f in foods) f.id: fold(f.name)};

  static Future<Catalog> load() async {
    final foodsJson = jsonDecode(await rootBundle.loadString('assets/data/foods.json')) as List;
    final exJson = jsonDecode(await rootBundle.loadString('assets/data/exercises.json')) as List;
    return Catalog._(
      foodsJson.map((e) => Food.fromMap(e as Map, src: 'seed')).toList(),
      exJson.map((e) => Exercise.fromMap(e as Map)).toList(),
    );
  }
}

// =================================================================== split pronti

class SplitTemplate {
  final String key;
  final String name;
  final String desc;
  final int idealDays;
  final List<(String, List<PlanItem>)> days;
  const SplitTemplate(this.key, this.name, this.desc, this.idealDays, this.days);

  Plan toPlan({String? name}) => Plan(
        id: newId(),
        name: name ?? this.name,
        template: key,
        startDate: todayKey(),
        days: [for (final d in days) PlanDay(id: newId(), name: d.$1, items: d.$2)],
      );
}

PlanItem _it(String ex, int sets, int rMin, int rMax, {double rpe = 9, int rest = 120}) =>
    PlanItem(ex: ex, sets: sets, rMin: rMin, rMax: rMax, rpe: rpe, rest: rest);

final splitTemplates = <SplitTemplate>[
  SplitTemplate('ulpp', 'Upper / Lower / Push / Pull', 'Quattro sedute: forza sui fondamentali e volume sui distretti.', 4, [
    ('Upper', [
      _it('panca-piana', 3, 6, 8, rest: 180),
      _it('rematore-bilanciere', 3, 8, 10, rest: 150),
      _it('lento-manubri', 3, 8, 10),
      _it('lat-machine', 3, 10, 12),
      _it('curl-manubri', 2, 10, 12, rest: 90),
      _it('pushdown-corda', 2, 10, 12, rest: 90),
    ]),
    ('Lower', [
      _it('squat', 4, 5, 7, rpe: 8.5, rest: 180),
      _it('stacco-rumeno', 3, 8, 10, rest: 150),
      _it('leg-press', 3, 10, 12),
      _it('leg-curl-seduto', 3, 10, 12, rest: 90),
      _it('calf-in-piedi', 4, 10, 15, rest: 60),
    ]),
    ('Push', [
      _it('panca-inclinata-manubri', 4, 8, 10, rest: 150),
      _it('dip-petto', 3, 8, 12),
      _it('shoulder-press-macchina', 3, 10, 12),
      _it('alzate-laterali', 4, 12, 15, rest: 60),
      _it('croci-cavi', 2, 12, 15, rest: 60),
      _it('estensioni-cavi', 3, 10, 12, rest: 90),
    ]),
    ('Pull', [
      _it('trazioni', 4, 6, 10, rest: 150),
      _it('pulley', 3, 10, 12),
      _it('rematore-manubrio', 3, 8, 10),
      _it('face-pull', 3, 12, 15, rest: 60),
      _it('curl-ez', 3, 8, 10, rest: 90),
      _it('curl-martello', 2, 10, 12, rest: 60),
    ]),
  ]),
  SplitTemplate('ul4', 'Upper / Lower', 'Due parte alta e due parte bassa, alternando forza (A) e volume (B).', 4, [
    ('Upper A', [
      _it('panca-piana', 4, 5, 7, rpe: 8.5, rest: 180),
      _it('rematore-bilanciere', 4, 6, 8, rest: 150),
      _it('military-press', 3, 6, 8, rest: 150),
      _it('lat-machine', 3, 8, 10),
      _it('curl-bilanciere', 2, 8, 10, rest: 90),
      _it('french-press', 2, 8, 10, rest: 90),
    ]),
    ('Lower A', [
      _it('squat', 4, 5, 7, rpe: 8.5, rest: 180),
      _it('stacco-rumeno', 3, 6, 8, rest: 150),
      _it('leg-press', 3, 8, 10),
      _it('leg-curl-sdraiato', 3, 10, 12, rest: 90),
      _it('calf-in-piedi', 4, 8, 12, rest: 60),
    ]),
    ('Upper B', [
      _it('panca-inclinata-manubri', 3, 8, 10, rest: 150),
      _it('trazioni', 3, 6, 10, rest: 150),
      _it('lento-manubri', 3, 8, 12),
      _it('pulley', 3, 10, 12),
      _it('alzate-laterali', 3, 12, 15, rest: 60),
      _it('curl-inclinata', 2, 10, 12, rest: 60),
      _it('pushdown-corda', 2, 10, 12, rest: 60),
    ]),
    ('Lower B', [
      _it('stacco', 3, 4, 6, rpe: 8, rest: 180),
      _it('bulgarian', 3, 8, 10),
      _it('leg-extension', 3, 10, 15, rest: 90),
      _it('leg-curl-seduto', 3, 10, 15, rest: 90),
      _it('hip-thrust', 3, 8, 12),
      _it('calf-seduto', 3, 12, 15, rest: 60),
    ]),
  ]),
  SplitTemplate('ppl', 'Push / Pull / Legs', 'Spinta, tirata e gambe. Con 6 giorni fai il giro due volte.', 3, [
    ('Push', [
      _it('panca-piana', 4, 6, 8, rest: 180),
      _it('lento-manubri', 3, 8, 10),
      _it('panca-inclinata-manubri', 3, 8, 10),
      _it('alzate-laterali', 4, 12, 15, rest: 60),
      _it('pushdown-barra', 3, 10, 12, rest: 90),
      _it('estensioni-cavi', 2, 12, 15, rest: 60),
    ]),
    ('Pull', [
      _it('trazioni', 4, 6, 10, rest: 150),
      _it('rematore-bilanciere', 3, 8, 10, rest: 150),
      _it('pulley', 3, 10, 12),
      _it('face-pull', 3, 12, 15, rest: 60),
      _it('curl-bilanciere', 3, 8, 10, rest: 90),
      _it('curl-martello', 2, 10, 12, rest: 60),
    ]),
    ('Legs', [
      _it('squat', 4, 6, 8, rpe: 8.5, rest: 180),
      _it('stacco-rumeno', 3, 8, 10, rest: 150),
      _it('leg-press', 3, 10, 12),
      _it('leg-curl-seduto', 3, 10, 12, rest: 90),
      _it('calf-in-piedi', 4, 10, 15, rest: 60),
      _it('crunch-cavi', 3, 12, 15, rest: 60),
    ]),
  ]),
  SplitTemplate('fb3', 'Full body A / B / C', 'Tutto il corpo in ogni seduta, tre varianti a rotazione.', 3, [
    ('Full body A', [
      _it('squat', 3, 6, 8, rpe: 8.5, rest: 180),
      _it('panca-piana', 3, 6, 8, rest: 180),
      _it('rematore-bilanciere', 3, 8, 10, rest: 150),
      _it('alzate-laterali', 3, 12, 15, rest: 60),
      _it('curl-manubri', 2, 10, 12, rest: 60),
    ]),
    ('Full body B', [
      _it('stacco', 3, 4, 6, rpe: 8, rest: 180),
      _it('lento-manubri', 3, 8, 10),
      _it('lat-machine', 3, 8, 10),
      _it('affondi', 3, 10, 12),
      _it('plank', 3, 30, 60, rest: 60),
    ]),
    ('Full body C', [
      _it('leg-press', 3, 10, 12),
      _it('panca-inclinata-manubri', 3, 8, 10),
      _it('pulley', 3, 10, 12),
      _it('leg-curl-seduto', 3, 10, 12, rest: 90),
      _it('pushdown-corda', 2, 10, 12, rest: 60),
      _it('calf-in-piedi', 3, 10, 15, rest: 60),
    ]),
  ]),
  SplitTemplate('fb2', 'Full body A / B', 'Due sedute complete: ideale con 2 giorni a settimana.', 2, [
    ('Full body A', [
      _it('squat', 3, 6, 8, rpe: 8.5, rest: 180),
      _it('panca-piana', 3, 6, 8, rest: 180),
      _it('rematore-manubrio', 3, 8, 10),
      _it('lento-manubri', 2, 8, 10),
      _it('curl-manubri', 2, 10, 12, rest: 60),
      _it('crunch', 3, 12, 20, rest: 60),
    ]),
    ('Full body B', [
      _it('stacco-rumeno', 3, 8, 10, rest: 150),
      _it('lat-machine', 3, 8, 10),
      _it('panca-inclinata-manubri', 3, 8, 10),
      _it('leg-press', 3, 10, 12),
      _it('alzate-laterali', 3, 12, 15, rest: 60),
      _it('pushdown-corda', 2, 10, 12, rest: 60),
    ]),
  ]),
];

SplitTemplate templateByKey(String key) => splitTemplates.firstWhere((t) => t.key == key, orElse: () => splitTemplates.first);

SplitTemplate suggestTemplate(int trainingDays) => switch (trainingDays) {
      <= 2 => templateByKey('fb2'),
      3 => templateByKey('fb3'),
      4 => templateByKey('ulpp'),
      _ => templateByKey('ppl'),
    };

Plan emptyPlan() => Plan(
      id: newId(),
      name: 'La mia scheda',
      template: 'custom',
      startDate: todayKey(),
      days: [PlanDay(id: newId(), name: 'Giorno A')],
    );
