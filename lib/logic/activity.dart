import 'dart:math' as math;

import '../data/models.dart';

/// Sport per le attività extra: chiave, nome, MET a intensità normale
/// (Compendium of Physical Activities, valori arrotondati).
const sports = <(String, String, double)>[
  ('calcetto', 'Calcetto', 8.0),
  ('calcio', 'Calcio', 7.0),
  ('beach', 'Beach volley', 8.0),
  ('pallavolo', 'Pallavolo', 4.0),
  ('padel', 'Padel', 6.0),
  ('tennis', 'Tennis', 7.3),
  ('basket', 'Basket', 6.5),
  ('corsa', 'Corsa', 9.0),
  ('bici', 'Bici', 7.5),
  ('nuoto', 'Nuoto', 6.0),
  ('escursione', 'Escursione', 6.0),
  ('boxe', 'Boxe / arti marziali', 7.0),
  ('arrampicata', 'Arrampicata', 6.0),
  ('ballo', 'Ballo', 5.0),
  ('sci', 'Sci', 5.5),
  ('yoga', 'Yoga / pilates', 3.0),
  ('altro', 'Altro', 5.5),
];

const intensityLevels = ['Leggera', 'Normale', 'Intensa'];
const _levelFactor = [0.75, 1.0, 1.25];

double sportMet(String kind) => sports.firstWhere((s) => s.$1 == kind, orElse: () => sports.last).$3;

/// Kcal nette: (MET − 1) × kg × ore. Il consumo a riposo è già nel target, quindi si toglie.
int activityKcal(String kind, int minutes, double kg, [int lvl = 1]) {
  final met = sportMet(kind) * _levelFactor[lvl.clamp(0, 2)];
  final k = math.max(0.0, met - 1) * kg * minutes / 60;
  return (k / 5).round() * 5;
}

/// Calorie che contano per il voto: mangiate meno quelle bruciate con le attività extra.
double netKcal(Macro eaten, HabitDay h) => eaten.kcal - h.burned;
