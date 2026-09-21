import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/fmt.dart';
import '../core/ids.dart';
import '../data/app_state.dart';

// =================================================================== foto

/// Scatta o sceglie una foto e la riduce a max 1600 px (JPEG).
Future<Uint8List?> pickPhoto({required bool camera}) async {
  final picker = ImagePicker();
  final x = await picker.pickImage(
    source: camera && isMobile ? ImageSource.camera : ImageSource.gallery,
    maxWidth: 1600,
    maxHeight: 1600,
    imageQuality: 82,
  );
  if (x == null) return null;
  final bytes = await x.readAsBytes();
  if (isMobile && bytes.length < 2500000) return bytes;
  return compute(_shrink, bytes);
}

Uint8List _shrink(Uint8List bytes) {
  final im = img.decodeImage(bytes);
  if (im == null) return bytes;
  final big = im.width > 1600 || im.height > 1600;
  final out = big ? img.copyResize(im, width: im.width >= im.height ? 1600 : null, height: im.height > im.width ? 1600 : null) : im;
  return Uint8List.fromList(img.encodeJpg(out, quality: 82));
}

// =================================================================== CSV

String _csvCell(Object? v) {
  final s = v == null ? '' : v.toString();
  if (s.contains(';') || s.contains('"') || s.contains('\n')) return '"${s.replaceAll('"', '""')}"';
  return s;
}

String _csv(List<String> header, List<List<Object?>> rows) {
  final b = StringBuffer('﻿');
  b.writeln(header.map(_csvCell).join(';'));
  for (final r in rows) {
    b.writeln(r.map(_csvCell).join(';'));
  }
  return b.toString();
}

String _n(num? v, [int d = 1]) => v == null ? '' : fDec(v, d, true).replaceAll('.', '');

Map<String, String> buildCsvFiles(AppState app) {
  final log = [for (final l in app.logByDate.values) ...l]..sort((a, b) => '${a.date}${a.ts}'.compareTo('${b.date}${b.ts}'));
  final diario = _csv(['data', 'pasto', 'alimento', 'grammi', 'kcal', 'proteine', 'carboidrati', 'grassi'], [
    for (final e in log) [e.date, e.meal, e.name, _n(e.g, 0), _n(e.kcal, 0), _n(e.p), _n(e.c), _n(e.f)],
  ]);
  final peso = _csv(['data', 'kg'], [for (final w in app.weights) [w.date, _n(w.kg, 2)]]);
  final allenamenti = _csv(['data', 'sessione', 'esercizio', 'serie', 'kg', 'ripetizioni', 'rpe', 'fatta'], [
    for (final s in app.doneSessions)
      for (final e in s.items)
        for (var i = 0; i < e.sets.length; i++)
          [s.date, s.name, e.name, i + 1, _n(e.sets[i].kg, 2), e.sets[i].reps, _n(e.sets[i].rpe), e.sets[i].done ? 'sì' : 'no'],
  ]);
  final habits = app.habitsByDate.values.toList()..sort((a, b) => a.date.compareTo(b.date));
  final abitudini = _csv(['data', 'acqua_ml', 'sonno_min', 'passi', 'alcol'], [
    for (final h in habits) [h.date, h.water, h.sleep, h.steps, h.alcohol],
  ]);
  final dates = app.activeDates.toList()..sort();
  final voti = _csv(['data', 'voto', 'kcal', 'proteine'], [
    for (final d in dates) [d, _n(app.score(d).v), _n(app.totals(d).kcal, 0), _n(app.totals(d).p, 0)],
  ]);
  return {
    'tigert-diario.csv': diario,
    'tigert-peso.csv': peso,
    'tigert-allenamenti.csv': allenamenti,
    'tigert-abitudini.csv': abitudini,
    'tigert-voti.csv': voti,
  };
}

/// Esporta i CSV. Ritorna una descrizione di dove sono finiti (o null se annullato).
Future<String?> exportCsv(AppState app) async {
  final files = buildCsvFiles(app);
  if (isDesktop) {
    final dir = await getDirectoryPath(confirmButtonText: 'Esporta qui');
    if (dir == null) return null;
    for (final e in files.entries) {
      await File('$dir${Platform.pathSeparator}${e.key}').writeAsString(e.value, encoding: utf8);
    }
    return dir;
  }
  final tmp = await getTemporaryDirectory();
  final xs = <XFile>[];
  for (final e in files.entries) {
    final f = File('${tmp.path}${Platform.pathSeparator}${e.key}');
    await f.writeAsString(e.value, encoding: utf8);
    xs.add(XFile(f.path, mimeType: 'text/csv'));
  }
  await SharePlus.instance.share(ShareParams(files: xs, subject: 'Dati Tigert'));
  return 'condivisione';
}

// =================================================================== backup

Future<String?> exportBackup(AppState app) async {
  await app.store.flush();
  final data = jsonEncode(app.store.exportAll());
  final name = 'tigert-backup-${todayKey()}.json';
  if (isDesktop) {
    final loc = await getSaveLocation(
      suggestedName: name,
      acceptedTypeGroups: const [XTypeGroup(label: 'Backup Tigert', extensions: ['json'])],
      confirmButtonText: 'Salva',
    );
    if (loc == null) return null;
    await File(loc.path).writeAsString(data, encoding: utf8);
    return loc.path;
  }
  final tmp = await getTemporaryDirectory();
  final f = File('${tmp.path}${Platform.pathSeparator}$name');
  await f.writeAsString(data, encoding: utf8);
  await SharePlus.instance.share(ShareParams(files: [XFile(f.path, mimeType: 'application/json')], subject: 'Backup Tigert'));
  return 'condivisione';
}

/// Importa un backup (unione: vince la modifica più recente). Ritorna i record importati.
Future<int?> importBackup(AppState app) async {
  final x = await openFile(acceptedTypeGroups: const [
    XTypeGroup(label: 'Backup Tigert', extensions: ['json'], mimeTypes: ['application/json', 'text/plain', 'application/octet-stream']),
  ]);
  if (x == null) return null;
  final txt = utf8.decode(await x.readAsBytes());
  final j = jsonDecode(txt);
  if (j is! Map) throw const FormatException('File non valido');
  return app.store.importAll(Map<String, dynamic>.from(j));
}
