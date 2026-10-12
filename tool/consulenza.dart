// Consulenza dal PC: scrive in un file lo stesso testo di "Copia per Claude",
// leggendo una copia dei dati veri di Tigert (%APPDATA%\Tigert\Tigert\data).
// Non modifica nulla e non apre l'app.
//
//   flutter test tool/consulenza.dart
//   flutter test tool/consulenza.dart --dart-define=GIORNI=28
//
// Il testo finisce in %TEMP%\tigert-consulenza.txt.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tigert/data/app_state.dart';
import 'package:tigert/data/catalog.dart';
import 'package:tigert/data/local_prefs.dart';
import 'package:tigert/data/store.dart';
import 'package:tigert/logic/consult.dart';

const _days = int.fromEnvironment('GIORNI', defaultValue: 14);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('consulenza', () async {
    final src = Directory('${Platform.environment['APPDATA']}\\Tigert\\Tigert\\data');
    if (!src.existsSync()) fail('non trovo i dati di Tigert in ${src.path}');
    // si lavora su una copia: lo Store non deve mai aprire la cartella vera
    final dir = Directory.systemTemp.createTempSync('tigert_consulenza_');
    final data = Directory('${dir.path}\\data')..createSync();
    for (final f in src.listSync().whereType<File>()) {
      if (f.path.endsWith('.json')) f.copySync('${data.path}\\${f.uri.pathSegments.last}');
    }
    final store = Store();
    await store.init(dir: dir);
    final prefs = LocalPrefs();
    await prefs.init(dir);
    final app = AppState(store, prefs, await Catalog.load());
    final out = File('${Directory.systemTemp.path}\\tigert-consulenza.txt')..writeAsStringSync(consultText(app, days: _days));
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
    // ignore: avoid_print
    print('CONSULENZA ${out.path}');
  });
}
