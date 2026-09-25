import 'package:flutter_test/flutter_test.dart';
import 'package:tigert/core/fmt.dart';
import 'package:tigert/data/models.dart';
import 'package:tigert/logic/achievements.dart';
import 'package:tigert/logic/nutrition.dart';
import 'package:tigert/services/gemini.dart';
import 'package:tigert/services/sync.dart';
import 'package:tigert/services/updates.dart';

void main() {
  group('formattazione', () {
    test('numeri all\'italiana', () {
      expect(fInt(12345), '12.345');
      expect(fInt(-1500), '-1.500');
      expect(fDec(1.25, 1), '1,3');
      expect(fDec(70.0, 1, true), '70');
      expect(parseNum('72,5'), 72.5);
      expect(parseNum(''), isNull);
    });

    test('chiavi data', () {
      expect(addDaysKey('2026-02-28', 1), '2026-03-01');
      expect(daysBetween(fromKey('2026-01-01'), fromKey('2026-01-31')), 30);
    });

    test('dopo mezzanotte, fino alle 4, il cibo va su ieri', () {
      expect(isLateNight(DateTime(2026, 9, 25, 0, 30)), isTrue);
      expect(isLateNight(DateTime(2026, 9, 25, 3, 59)), isTrue);
      expect(isLateNight(DateTime(2026, 9, 25, 4)), isFalse);
      expect(isLateNight(DateTime(2026, 9, 24, 23, 50)), isFalse);
    });
  });

  group('target', () {
    test('definizione: deficit, proteine alte', () {
      final t = computeTargets(sex: 'm', age: 30, heightCm: 180, weight: 80, activity: 'moderato', goal: Goal.cut, rate: 0.5);
      expect(t.kcal, lessThan(t.tdee));
      expect(t.protein, 176); // 2,2 g/kg
      expect(t.kcal % 10, 0);
      final fromMacro = t.protein * 4 + t.carbs * 4 + t.fat * 9;
      expect((fromMacro - t.kcal).abs(), lessThan(15));
    });

    test('massa: surplus', () {
      final t = computeTargets(sex: 'f', age: 25, heightCm: 165, weight: 58, activity: 'leggero', goal: Goal.bulk, rate: 0.25);
      expect(t.kcal, greaterThan(t.tdee));
    });
  });

  group('risposta Gemini', () {
    test('accetta code fence, virgolette tipografiche e virgole decimali', () {
      const raw = '''Ecco la stima:
```json
{ “tigert”: 1, "piatto": "Pasta al pomodoro", "affidabilita": "media",
  "alimenti": [ {"nome": "Pasta", "grammi": 90, "grammi_min": 80, "grammi_max": 110,
     "kcal_100g": 357, "proteine_100g": 12,5, "carboidrati_100g": 72, "grassi_100g": 1.5}, ],
  "note": "" }
```''';
      final e = parseEstimate(raw);
      expect(e.dish, 'Pasta al pomodoro');
      expect(e.items, hasLength(1));
      expect(e.items.first.p100, closeTo(12.5, 0.01));
      expect(e.total.kcal, closeTo(321.3, 0.5));
    });

    test('errore chiaro se manca il JSON', () {
      expect(() => parseEstimate('non so'), throwsFormatException);
    });
  });

  group('varie', () {
    test('confronto versioni', () {
      expect(isNewer('v1.2.0', '1.1.9'), isTrue);
      expect(isNewer('1.0.0', '1.0.0'), isFalse);
      expect(isNewer('1.0.10', '1.0.9'), isTrue);
    });

    test('aggiornamento: note leggibili e controllo SHA-256', () {
      expect(plainNotes('## Novità\n\n**Barra giorno**\n- In **Oggi** la barra'), 'Novità\n\nBarra giorno\n- In Oggi la barra');
      final h = 'a' * 64, e = 'B' * 64;
      const n = 'Tigert-1.7.1.apk';
      expect(expectedSha('$h *$n\n$e *Tigert-Setup-1.7.1.exe\n', n), h);
      expect(expectedSha('$e  Tigert-Setup-1.7.1.exe', 'Tigert-Setup-1.7.1.exe'), e.toLowerCase());
      expect(expectedSha('$h *$n', 'altro.apk'), isNull);
      expect(UpdateInfo.fromMap(const UpdateInfo('1.7.1', 'p', 'd', 'n', 's').toMap())!.sumsUrl, 's');
    });

    test('QR di abbinamento', () {
      expect(SyncService.parsePairing('https://example.com'), isNull);
      expect(SyncService.prettyKey('ABCDEFGHJKLM'), 'ABCD-EFGH-JKLM');
    });

    test('livelli', () {
      expect(levelFor(0).level, 1);
      expect(levelFor(xpForLevel(3)).level, 3);
    });
  });
}
