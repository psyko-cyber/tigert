import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tigert/data/models.dart';
import 'package:tigert/logic/food_icons.dart';
import 'package:tigert/logic/supplements.dart';

void main() {
  test('icone per nome prima della categoria', () {
    const cases = {
      'Banana': '🍌',
      'Mela': '🍏',
      'Melanzane': '🍆',
      'Melone': '🍈',
      'Pesca': '🍑',
      'Pesce spada': '🐟',
      "Spremuta d'arancia": '🍊',
      'Limone (succo)': '🍋',
      'Tè freddo': '🍵',
      'Hamburger (panino)': '🍔',
      'Pasta al pomodoro': '🍝',
      'Yogurt alla fragola': '🥛',
      "Tonno sott'olio (sgocciolato)": '🐟',
      'Olio di cocco': '🫒',
      'Bevanda di riso': '🥛',
      'Fagiolini': '🥦',
      'Fagioli borlotti secchi': '🫘',
      'Parmigiano Reggiano': '🧀',
      'Parmigiana di melanzane': '🍆',
      'Creatina monoidrato': '💊',
    };
    const cats = {'Fagiolini': 'Verdure'};
    cases.forEach((name, emoji) => expect(foodEmoji(name, cats[name] ?? ''), emoji, reason: name));
    expect(foodEmoji('Qualcosa di strano', 'Frutta'), '🍎');
  });

  test('tutto il database locale ha un\'icona', () {
    final list = jsonDecode(File('assets/data/foods.json').readAsStringSync()) as List;
    final generic = <String>[];
    for (final m in list.cast<Map>()) {
      final e = foodEmoji(m['n'] as String, m['cat'] as String);
      expect(e, isNotEmpty);
      if (e == catEmoji(m['cat'] as String)) generic.add('${m['cat']}: ${m['n']}');
    }
    if (const bool.fromEnvironment('ICONS')) {
      // ignore: avoid_print
      print(generic.join('\n'));
    }
  });

  test('integratori: serie di giorni e ultimi 7 giorni', () {
    HabitDay d(String k, [List<String> s = const ['Creatina']]) => HabitDay(date: k, supp: s);
    final by = {
      '2026-03-27': d('2026-03-27'),
      '2026-03-28': d('2026-03-28'),
      '2026-03-29': d('2026-03-29'), // cambio dell'ora legale: giorno di 23 ore
      '2026-03-30': d('2026-03-30'),
    };
    // oggi non ancora spuntato: la serie parte da ieri
    expect(supplementStreak(by, 'Creatina', DateTime(2026, 3, 31)), 4);
    expect(supplementStreak({...by, '2026-03-31': d('2026-03-31')}, 'Creatina', DateTime(2026, 3, 31)), 5);
    expect(supplementStreak(by, 'Creatina', DateTime(2026, 4, 2)), 0);
    expect(supplementLastDays(by, 'Creatina', DateTime(2026, 3, 31)), [false, false, true, true, true, true, false]);
    final h = HabitDay(date: '2026-03-31').toggleSupp('Creatina');
    expect(h.took('Creatina'), isTrue);
    expect(h.toggleSupp('Creatina').took('Creatina'), isFalse);
    expect(HabitDay.fromMap({...h.toMap(), 'id': 'x'}).supp, ['Creatina']);
    final p = Profile.fromMap(const {});
    expect(p.supplements, ['Creatina']);
    expect(pendingSupplements(p, h), isEmpty);
    expect(pendingSupplements(p, HabitDay(date: 'x')), ['Creatina']);
    expect(pendingSupplements(p.copyWith(habits: {...p.habits, 'supp': false}), HabitDay(date: 'x')), isEmpty);
  });

  test('bevande in ml', () {
    expect(isLiquidFood("Spremuta d'arancia", 'Bevande'), isTrue);
    expect(isLiquidFood('Latte parzialmente scremato', 'Latte e yogurt'), isTrue);
    expect(isLiquidFood('Bevanda di avena', 'Latte e yogurt'), isTrue);
    expect(isLiquidFood('Yogurt greco 0%', 'Latte e yogurt'), isFalse);
    expect(isLiquidFood('Banana', 'Frutta'), isFalse);
    // un documento senza campo "ml" lo deduce, uno con il campo lo rispetta
    expect(Food.fromMap({'n': 'Cola', 'cat': 'Bevande', 'k': 42}).ml, isTrue);
    expect(Food.fromMap({'n': 'Cola', 'cat': 'Bevande', 'k': 42, 'ml': false}).ml, isFalse);
    final f = Food.fromMap({'n': 'Cola', 'cat': 'Bevande', 'k': 42});
    expect(Food.fromMap({...f.toMap(), 'id': 'x'}).unit, 'ml');
    final e = LogEntry(id: 'a', date: '2026-09-22', meal: 'pranzo', name: 'Cola', g: 330, ml: true, kcal: 139, p: 0, c: 35, f: 0, ts: 1);
    expect(LogEntry.fromMap({...e.toMap(), 'id': 'a'}).ml, isTrue);
    expect(e.copyWith(g: 200).ml, isTrue);
  });
}
