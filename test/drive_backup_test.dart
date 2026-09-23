import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tigert/core/fmt.dart';
import 'package:tigert/data/app_state.dart';
import 'package:tigert/data/catalog.dart';
import 'package:tigert/data/local_prefs.dart';
import 'package:tigert/data/models.dart';
import 'package:tigert/data/store.dart';
import 'package:tigert/services/drive_backup.dart';

late Catalog catalog;

/// Google Drive finto, in memoria: token, appDataFolder, upload riprendibile, download, cancellazione.
class FakeDrive {
  final files = <String, (String name, List<int> bytes, DateTime modified)>{};
  var tokenOk = true;
  var uploads = 0;
  var _n = 0;
  final _pending = <String, String>{};

  void add(String name, DateTime modified, [List<int> bytes = const [1]]) => files['f${_n++}'] = (name, bytes, modified);
  List<String> get names => [for (final f in files.values) f.$1]..sort();

  late final client = MockClient((req) async {
    final u = req.url;
    if (u.host == 'oauth2.googleapis.com') {
      return tokenOk
          ? http.Response(jsonEncode({'access_token': 'at', 'expires_in': 3600}), 200)
          : http.Response(jsonEncode({'error': 'invalid_grant'}), 400);
    }
    if (req.headers['Authorization'] != 'Bearer at') return http.Response('{}', 401);
    if (u.host == 'upload.test') {
      final id = 'f${_n++}';
      files[id] = (_pending.remove(u.path)!, (req as http.Request).bodyBytes, DateTime.now());
      uploads++;
      return http.Response(jsonEncode({'id': id}), 200);
    }
    if (u.path == '/upload/drive/v3/files') {
      final meta = jsonDecode((req as http.Request).body) as Map;
      expect(meta['parents'], ['appDataFolder']);
      final path = '/s${_n++}';
      _pending[path] = meta['name'] as String;
      return http.Response('', 200, headers: {'location': 'https://upload.test$path'});
    }
    if (u.path == '/drive/v3/about') return http.Response(jsonEncode({'user': {'emailAddress': 'luca@example.com'}}), 200);
    if (u.path == '/drive/v3/files' && req.method == 'GET') {
      expect(u.queryParameters['spaces'], 'appDataFolder');
      return http.Response(
          jsonEncode({
            'files': [
              for (final e in files.entries)
                {'id': e.key, 'name': e.value.$1, 'size': '${e.value.$2.length}', 'modifiedTime': e.value.$3.toUtc().toIso8601String()},
            ],
          }),
          200);
    }
    final id = u.pathSegments.last;
    if (req.method == 'DELETE') return http.Response(files.remove(id) == null ? '{}' : '', files.containsKey(id) ? 404 : 204);
    if (u.queryParameters['alt'] == 'media') return http.Response.bytes(files[id]!.$2, 200);
    return http.Response('{}', 404);
  });
}

Future<AppState> newApp() async {
  final dir = Directory.systemTemp.createTempSync('tigert_drive_');
  final store = Store();
  await store.init(dir: dir);
  final prefs = LocalPrefs();
  await prefs.init(dir);
  return AppState(store, prefs, catalog);
}

Profile profile() => Profile(
      name: 'Luca',
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
      reminders: Reminders.defaults(),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => catalog = await Catalog.load());

  test('nomi dei backup e pulizia: una copia al giorno, ultimi 7 giorni', () {
    final f = DriveFile.fromMap({'id': 'x', 'name': 'tigert-2026-09-23-telefono.json.gz', 'size': '2048', 'modifiedTime': '2026-09-23T10:00:00Z'});
    expect(f.isBackup, isTrue);
    expect(f.device, 'telefono');
    expect(f.day, DateTime(2026, 9, 23));
    expect(f.size, 2048);
    expect(DriveFile.fromMap({'id': 'y', 'name': 'foto-abc.jpg'}).isBackup, isFalse);

    final today = DateTime(2026, 9, 23, 12);
    final mine = [
      for (var d = 0; d < 9; d++) DriveFile('d$d', 'tigert-${dayKey(today.subtract(Duration(days: d)))}-pc.json.gz', 10, today.subtract(Duration(days: d))),
    ];
    final del = backupsToDelete(mine, today: 'tigert-2026-09-23-pc.json.gz', keep: 7);
    // oggi (quello vecchio con lo stesso nome) + i giorni oltre il settimo
    expect(del.map((f) => f.id), ['d0', 'd7', 'd8']);
  });

  test('backup su Drive e ripristino su un dispositivo nuovo, foto comprese', () async {
    final drive = FakeDrive();
    final a = await newApp();
    a.saveProfile(profile());
    final pasta = catalog.foods.firstWhere((f) => f.id == 's:pasta-al-ragu');
    a.addEntry(a.entryFromFood(pasta, 200, date: todayKey(), meal: 'pranzo'));
    final jpg = Uint8List.fromList(List.generate(5000, (i) => i % 251));
    await a.addPhoto(jpg, date: todayKey());
    a.prefs.set('driveOn', true);
    a.prefs.set('driveRefresh', 'rt');
    // backup vecchi: 8 giorni del PC, uno di oggi già fatto e uno del telefono
    final now = DateTime.now();
    for (var d = 1; d <= 8; d++) {
      drive.add('tigert-${dayKey(now.subtract(Duration(days: d)))}-pc.json.gz', now.subtract(Duration(days: d)));
    }
    drive.add('tigert-${todayKey()}-pc.json.gz', now.subtract(const Duration(hours: 2)));
    drive.add('tigert-${todayKey()}-telefono.json.gz', now.subtract(const Duration(hours: 1)));

    final d = DriveBackup(a, client: drive.client);
    await d.backupNow();
    expect(d.error, isNull);
    expect(d.lastBackup, isNotNull);
    expect(drive.uploads, 2, reason: 'dati + una foto');
    final pcs = drive.names.where((n) => n.endsWith('-pc.json.gz')).toList();
    expect(pcs.length, DriveBackup.keep);
    expect(pcs.where((n) => n.contains(todayKey())).length, 1, reason: 'una sola copia di oggi');
    expect(drive.names, contains('tigert-${todayKey()}-telefono.json.gz'), reason: 'i backup del telefono non si toccano');

    // le foto già caricate non si ricaricano
    await d.backupNow();
    expect(drive.uploads, 3);

    // telefono nuovo: niente backup automatico finché è vuoto, poi ripristino
    final b = await newApp();
    b.prefs.set('driveOn', true);
    b.prefs.set('driveRefresh', 'rt');
    final db = DriveBackup(b, client: drive.client);
    await db.maybeAuto();
    expect(drive.uploads, 3, reason: 'un dispositivo vuoto non sovrascrive i backup');
    final list = await db.backups();
    expect(list.first.name, 'tigert-${todayKey()}-pc.json.gz');
    final n = await db.restore(list.first);
    expect(n, greaterThan(0));
    expect(b.hasProfile, isTrue);
    expect(b.profile!.name, 'Luca');
    expect(b.totals(todayKey()).kcal, closeTo(a.totals(todayKey()).kcal, 0.01));
    expect(b.photos.single.blob, a.photos.single.blob);
    expect(await b.store.blobFile(b.photos.single.blob).readAsBytes(), jpg);
  });

  test('accesso scaduto: errore chiaro e niente eccezioni', () async {
    final drive = FakeDrive()..tokenOk = false;
    final a = await newApp();
    a.saveProfile(profile());
    a.prefs.set('driveOn', true);
    a.prefs.set('driveRefresh', 'rt');
    final d = DriveBackup(a, client: drive.client);
    await d.backupNow();
    expect(d.error, 'Accesso a Google scaduto: ricollega Google Drive');
    expect(d.lastBackup, isNull);
    expect(drive.uploads, 0);
    await d.disconnect();
    expect(d.on, isFalse);
    expect(d.error, isNull);
  });
}
