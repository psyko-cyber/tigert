import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/fmt.dart';
import '../data/app_state.dart';
import '../data/models.dart';

// =================================================================== modello

class HevySet {
  final String type; // normal | warmup | dropset | failure
  final double? kg;
  final int? reps;
  final double? rpe;
  final int? seconds;
  final double? meters;
  final int? repStart, repEnd; // solo nelle routine
  const HevySet({this.type = 'normal', this.kg, this.reps, this.rpe, this.seconds, this.meters, this.repStart, this.repEnd});
  bool get warmup => type == 'warmup' || type == '2';
  bool get drop => type == 'dropset';
  /// Tipo di serie in Tigert: avvicinamento, dropset o allenante (anche "failure").
  String get tigertType => warmup ? setWarmup : (drop ? setDrop : setWork);
}

class HevyExerciseLog {
  final String key; // template id (API) oppure "t:<titolo>" (CSV)
  final String title;
  final String notes;
  final List<HevySet> sets;
  final int restSeconds;
  const HevyExerciseLog({required this.key, required this.title, this.notes = '', this.sets = const [], this.restSeconds = 0});
}

class HevyWorkout {
  final String id;
  final String title;
  final String description;
  final DateTime start;
  final DateTime? end;
  final String? routineId;
  final List<HevyExerciseLog> exercises;
  const HevyWorkout({required this.id, required this.title, this.description = '', required this.start, this.end, this.routineId, this.exercises = const []});
}

class HevyTemplate {
  final String key;
  final String title;
  final String type; // weight_reps, reps_only, duration, ...
  final String? muscle; // primary_muscle_group di Hevy
  final String? equipment;
  final bool custom;
  const HevyTemplate({required this.key, required this.title, this.type = 'weight_reps', this.muscle, this.equipment, this.custom = false});
}

class HevyRoutine {
  final String id;
  final String title;
  final int? folderId;
  final List<HevyExerciseLog> exercises;
  const HevyRoutine({required this.id, required this.title, this.folderId, this.exercises = const []});
}

class HevyFolder {
  final int id;
  final int index;
  final String title;
  const HevyFolder(this.id, this.index, this.title);
}

class HevyData {
  final List<HevyWorkout> workouts;
  final Map<String, HevyTemplate> templates;
  final List<HevyRoutine> routines;
  final List<HevyFolder> folders;
  final Map<String, double> weights; // data → kg
  final bool fromApi;
  HevyData({this.workouts = const [], this.templates = const {}, this.routines = const [], this.folders = const [], this.weights = const {}, this.fromApi = false});

  HevyData merge(HevyData o) => HevyData(
        workouts: [...workouts, ...o.workouts],
        templates: {...templates, ...o.templates},
        routines: [...routines, ...o.routines],
        folders: [...folders, ...o.folders],
        weights: {...weights, ...o.weights},
        fromApi: fromApi || o.fromApi,
      );

  bool get isEmpty => workouts.isEmpty && routines.isEmpty && weights.isEmpty;

  /// Tutti gli esercizi usati (storico + routine), con frequenza d'uso.
  List<HevyExerciseUse> exerciseUses() {
    final m = <String, HevyExerciseUse>{};
    void add(HevyExerciseLog e, int ts, {bool inRoutine = false}) {
      final u = m.putIfAbsent(e.key, () => HevyExerciseUse(e.key, e.title, templates[e.key]));
      u.times += inRoutine ? 0 : 1;
      u.inRoutine |= inRoutine;
      if (ts > u.lastUsed) u.lastUsed = ts;
    }

    for (final w in workouts) {
      for (final e in w.exercises) {
        add(e, w.start.millisecondsSinceEpoch);
      }
    }
    for (final r in routines) {
      for (final e in r.exercises) {
        add(e, 0, inRoutine: true);
      }
    }
    final l = m.values.toList()..sort((a, b) => b.times.compareTo(a.times));
    return l;
  }
}

class HevyExerciseUse {
  final String key;
  final String title;
  final HevyTemplate? template;
  int times = 0;
  int lastUsed = 0;
  bool inRoutine = false;
  HevyExerciseUse(this.key, this.title, this.template);
}

class HevyException implements Exception {
  final String message;
  const HevyException(this.message);
  @override
  String toString() => message;
}

// =================================================================== API (Hevy Pro)

const _api = 'https://api.hevyapp.com';

/// Scarica schede, cartelle, esercizi, allenamenti e pesate dall'API di Hevy.
Future<HevyData> fetchHevy(String apiKey, {void Function(String)? onProgress, http.Client? httpClient}) async {
  final key = apiKey.trim();
  if (key.isEmpty) throw const HevyException('Incolla la chiave API di Hevy.');
  final client = httpClient ?? http.Client();
  try {
    Future<Map<String, dynamic>> get(String path, Map<String, String> q) async {
      final uri = Uri.parse('$_api$path').replace(queryParameters: q);
      http.Response r;
      var attempt = 0;
      while (true) {
        try {
          r = await client.get(uri, headers: {'api-key': key, 'accept': 'application/json'}).timeout(const Duration(seconds: 30));
        } on TimeoutException {
          throw const HevyException('Hevy non risponde: controlla la connessione e riprova.');
        } catch (e) {
          throw HevyException('Connessione a Hevy non riuscita: $e');
        }
        if (r.statusCode == 429 && attempt < 5) {
          attempt++;
          await Future<void>.delayed(Duration(seconds: 2 * attempt));
          continue;
        }
        break;
      }
      if (r.statusCode == 401 || r.statusCode == 403) {
        throw const HevyException('Chiave API non valida. Serve Hevy Pro: la chiave si trova su hevy.com → Impostazioni → Developer.');
      }
      if (r.statusCode == 404) return const {};
      if (r.statusCode != 200) throw HevyException('Hevy ha risposto con errore ${r.statusCode}.');
      return (jsonDecode(utf8.decode(r.bodyBytes)) as Map).cast<String, dynamic>();
    }

    Future<List<Map<String, dynamic>>> all(String path, String field, int pageSize, String label) async {
      final out = <Map<String, dynamic>>[];
      var page = 1, pages = 1;
      do {
        onProgress?.call(pages > 1 ? '$label · pagina $page di $pages' : label);
        final j = await get(path, {'page': '$page', 'pageSize': '$pageSize'});
        if (j.isEmpty) break;
        pages = (j['page_count'] as num?)?.toInt() ?? 1;
        out.addAll(((j[field] as List?) ?? const []).cast<Map>().map((e) => e.cast<String, dynamic>()));
        page++;
      } while (page <= pages);
      return out;
    }

    final tpl = await all('/v1/exercise_templates', 'exercise_templates', 100, 'Esercizi');
    final folders = await all('/v1/routine_folders', 'routine_folders', 10, 'Cartelle');
    final routines = await all('/v1/routines', 'routines', 10, 'Schede');
    final workouts = await all('/v1/workouts', 'workouts', 10, 'Allenamenti');
    List<Map<String, dynamic>> body = const [];
    try {
      body = await all('/v1/body_measurements', 'body_measurements', 10, 'Pesate');
    } on HevyException {
      body = const [];
    }

    final templates = <String, HevyTemplate>{
      for (final t in tpl)
        '${t['id']}': HevyTemplate(
          key: '${t['id']}',
          title: '${t['title'] ?? ''}',
          type: '${t['type'] ?? 'weight_reps'}',
          muscle: t['primary_muscle_group'] as String?,
          equipment: t['equipment'] as String?,
          custom: t['is_custom'] == true,
        ),
    };
    HevyExerciseLog ex(Map e) => HevyExerciseLog(
          key: '${e['exercise_template_id'] ?? 't:${e['title']}'}',
          title: '${e['title'] ?? ''}',
          notes: '${e['notes'] ?? ''}',
          restSeconds: (e['rest_seconds'] as num?)?.toInt() ?? 0,
          sets: [
            for (final s in ((e['sets'] as List?) ?? const []).cast<Map>())
              HevySet(
                type: '${s['type'] ?? 'normal'}',
                kg: (s['weight_kg'] as num?)?.toDouble(),
                reps: (s['reps'] as num?)?.toInt(),
                rpe: (s['rpe'] as num?)?.toDouble(),
                seconds: (s['duration_seconds'] as num?)?.toInt(),
                meters: (s['distance_meters'] as num?)?.toDouble(),
                repStart: ((s['rep_range'] as Map?)?['start'] as num?)?.toInt(),
                repEnd: ((s['rep_range'] as Map?)?['end'] as num?)?.toInt(),
              ),
          ],
        );
    List<HevyExerciseLog> exs(Map o) {
      final l = ((o['exercises'] as List?) ?? const []).cast<Map>().toList()..sort((a, b) => ((a['index'] as num?) ?? 0).compareTo((b['index'] as num?) ?? 0));
      return l.map(ex).toList();
    }

    return HevyData(
      fromApi: true,
      templates: templates,
      folders: [
        for (final f in folders) HevyFolder((f['id'] as num).toInt(), (f['index'] as num?)?.toInt() ?? 0, '${f['title'] ?? 'Cartella'}'),
      ]..sort((a, b) => a.index.compareTo(b.index)),
      routines: [
        for (final r in routines) HevyRoutine(id: '${r['id']}', title: '${r['title'] ?? 'Scheda'}', folderId: (r['folder_id'] as num?)?.toInt(), exercises: exs(r)),
      ],
      workouts: [
        for (final w in workouts)
          if (DateTime.tryParse('${w['start_time']}') != null)
            HevyWorkout(
              id: '${w['id']}',
              title: '${w['title'] ?? 'Allenamento'}',
              description: '${w['description'] ?? ''}',
              start: DateTime.parse('${w['start_time']}').toLocal(),
              end: DateTime.tryParse('${w['end_time']}')?.toLocal(),
              routineId: w['routine_id'] as String?,
              exercises: exs(w),
            ),
      ],
      weights: {
        for (final b in body)
          if (b['weight_kg'] is num && b['date'] is String) '${b['date']}'.substring(0, 10): (b['weight_kg'] as num).toDouble(),
      },
    );
  } finally {
    client.close();
  }
}

// =================================================================== CSV (gratis)

/// Legge workout_data.csv (allenamenti) o measurement_data.csv (pesate).
HevyData parseHevyCsv(String text) {
  final rows = parseCsv(text.startsWith('﻿') ? text.substring(1) : text);
  if (rows.isEmpty) throw const HevyException('Il file è vuoto.');
  final head = rows.first.map((h) => h.trim().toLowerCase()).toList();
  int col(String n) => head.indexOf(n);
  String cell(List<String> r, int i) => i >= 0 && i < r.length ? r[i].trim() : '';
  double? num0(List<String> r, int i) => parseNum(cell(r, i));

  final iEx = col('exercise_title');
  if (iEx < 0) {
    // measurement_data.csv
    final iDate = col('date');
    final iKg = col('weight_kg'), iLb = col('weight_lbs');
    if (iDate < 0 || (iKg < 0 && iLb < 0)) {
      throw const HevyException('Non riconosco il file: serve workout_data.csv (o measurement_data.csv) esportato da Hevy.');
    }
    final w = <String, double>{};
    for (final r in rows.skip(1)) {
      final d = parseHevyDate(cell(r, iDate));
      var kg = num0(r, iKg);
      if (kg == null && iLb >= 0) kg = (num0(r, iLb) ?? 0) * 0.45359237;
      if (d != null && kg != null && kg > 20) w[dayKey(d)] = double.parse(kg.toStringAsFixed(2));
    }
    return HevyData(weights: w);
  }

  final iTitle = col('title'), iStart = col('start_time'), iEnd = col('end_time'), iDesc = col('description');
  final iNotes = col('exercise_notes'), iType = col('set_type'), iKg = col('weight_kg'), iLb = col('weight_lbs');
  final iReps = col('reps'), iRpe = col('rpe'), iSec = col('duration_seconds'), iKm = col('distance_km'), iMi = col('distance_miles');
  if (iStart < 0 || iTitle < 0) throw const HevyException('Il CSV non ha le colonne attese (title, start_time, exercise_title…).');

  // un allenamento = stesse (title, start_time); gli esercizi in ordine di apparizione
  final order = <String>[];
  final meta = <String, (String, String, DateTime, DateTime?)>{};
  final exOrder = <String, List<String>>{};
  final sets = <String, Map<String, List<HevySet>>>{};
  final notes = <String, Map<String, String>>{};
  var bad = 0;
  for (final r in rows.skip(1)) {
    if (r.length < 3) continue;
    final start = parseHevyDate(cell(r, iStart));
    if (start == null) {
      bad++;
      continue;
    }
    final title = cell(r, iTitle);
    final wk = '$title|${start.millisecondsSinceEpoch}';
    if (!meta.containsKey(wk)) {
      order.add(wk);
      meta[wk] = (title, cell(r, iDesc), start, parseHevyDate(cell(r, iEnd)));
      exOrder[wk] = [];
      sets[wk] = {};
      notes[wk] = {};
    }
    final exTitle = cell(r, iEx);
    if (exTitle.isEmpty) continue;
    if (!sets[wk]!.containsKey(exTitle)) {
      exOrder[wk]!.add(exTitle);
      sets[wk]![exTitle] = [];
      notes[wk]![exTitle] = cell(r, iNotes);
    }
    var kg = num0(r, iKg);
    if (kg == null && iLb >= 0) {
      final lb = num0(r, iLb);
      if (lb != null) kg = lb * 0.45359237;
    }
    var meters = iKm >= 0 ? (num0(r, iKm) == null ? null : num0(r, iKm)! * 1000) : null;
    if (meters == null && iMi >= 0 && num0(r, iMi) != null) meters = num0(r, iMi)! * 1609.344;
    sets[wk]![exTitle]!.add(HevySet(
      type: cell(r, iType).isEmpty ? 'normal' : cell(r, iType).toLowerCase(),
      kg: kg,
      reps: num0(r, iReps)?.round(),
      rpe: num0(r, iRpe),
      seconds: num0(r, iSec)?.round(),
      meters: meters,
    ));
  }
  if (order.isEmpty) {
    throw HevyException(bad > 0 ? 'Non riesco a leggere le date del file ($bad righe).' : 'Nel file non ci sono allenamenti.');
  }
  return HevyData(workouts: [
    for (final wk in order)
      HevyWorkout(
        id: 'csv${_hash(wk)}',
        title: meta[wk]!.$1.isEmpty ? 'Allenamento' : meta[wk]!.$1,
        description: meta[wk]!.$2,
        start: meta[wk]!.$3,
        end: meta[wk]!.$4,
        exercises: [
          for (final t in exOrder[wk]!) HevyExerciseLog(key: 't:$t', title: t, notes: notes[wk]![t] ?? '', sets: sets[wk]![t]!),
        ],
      ),
  ]..sort((a, b) => a.start.compareTo(b.start)));
}

/// CSV con virgolette, virgole e a capo nei campi.
List<List<String>> parseCsv(String s) {
  final rows = <List<String>>[];
  var row = <String>[];
  final f = StringBuffer();
  var q = false;
  // separatore: virgola, oppure punto e virgola se la prima riga non ha virgole
  final firstLine = s.split('\n').first;
  final sep = !firstLine.contains(',') && firstLine.contains(';') ? ';' : ',';
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (q) {
      if (c == '"') {
        if (i + 1 < s.length && s[i + 1] == '"') {
          f.write('"');
          i++;
        } else {
          q = false;
        }
      } else {
        f.write(c);
      }
    } else if (c == '"') {
      q = true;
    } else if (c == sep) {
      row.add(f.toString());
      f.clear();
    } else if (c == '\n' || c == '\r') {
      if (c == '\r' && i + 1 < s.length && s[i + 1] == '\n') i++;
      row.add(f.toString());
      f.clear();
      if (row.any((x) => x.isNotEmpty)) rows.add(row);
      row = <String>[];
    } else {
      f.write(c);
    }
  }
  if (f.isNotEmpty || row.isNotEmpty) {
    row.add(f.toString());
    if (row.any((x) => x.isNotEmpty)) rows.add(row);
  }
  return rows;
}

const _months = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6, 'jul': 7, 'aug': 8, 'sep': 9, 'sept': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  'gen': 1, 'mag': 5, 'giu': 6, 'lug': 7, 'ago': 8, 'set': 9, 'ott': 10, 'dic': 12,
};

/// "15 Jul 2026, 09:52", "15 lug 2026, 09:52", "Jul 15, 2026, 9:52 AM", ISO.
DateTime? parseHevyDate(String s) {
  final t = s.trim();
  if (t.isEmpty) return null;
  final iso = DateTime.tryParse(t);
  if (iso != null) return iso.isUtc ? iso.toLocal() : iso;
  int h(String hh, String? ap) {
    var v = int.parse(hh);
    final a = ap?.trim().toLowerCase();
    if (a == 'pm' && v < 12) v += 12;
    if (a == 'am' && v == 12) v = 0;
    return v;
  }

  var m = RegExp(r'^(\d{1,2})\s+([A-Za-zÀ-ú]+)\.?\s+(\d{4})(?:,?\s+(\d{1,2}):(\d{2})(?::\d{2})?\s*([AaPp][Mm])?)?').firstMatch(t);
  if (m != null) {
    final mo = _months[fold(m.group(2)!).substring(0, 3)] ?? _months[fold(m.group(2)!)];
    if (mo == null) return null;
    return DateTime(int.parse(m.group(3)!), mo, int.parse(m.group(1)!), m.group(4) == null ? 12 : h(m.group(4)!, m.group(6)), int.parse(m.group(5) ?? '0'));
  }
  m = RegExp(r'^([A-Za-z]+)\.?\s+(\d{1,2}),?\s+(\d{4})(?:,?\s+(\d{1,2}):(\d{2})(?::\d{2})?\s*([AaPp][Mm])?)?').firstMatch(t);
  if (m != null) {
    final mo = _months[m.group(1)!.toLowerCase().substring(0, 3)];
    if (mo == null) return null;
    return DateTime(int.parse(m.group(3)!), mo, int.parse(m.group(2)!), m.group(4) == null ? 12 : h(m.group(4)!, m.group(6)), int.parse(m.group(5) ?? '0'));
  }
  m = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})(?:,?\s+(\d{1,2}):(\d{2}))?').firstMatch(t);
  if (m != null) {
    return DateTime(int.parse(m.group(3)!), int.parse(m.group(2)!), int.parse(m.group(1)!), int.parse(m.group(4) ?? '12'), int.parse(m.group(5) ?? '0'));
  }
  return null;
}

String _hash(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h.toRadixString(36);
}

// =================================================================== abbinamento esercizi

class _Rule {
  final String id;
  final List<String> all; // ogni voce: alternative separate da |
  final List<String> not;
  const _Rule(this.id, this.all, [this.not = const []]);
  bool matches(String t) =>
      all.every((a) => a.split('|').any((x) => _has(t, x))) && !not.any((n) => _has(t, n));
}

bool _has(String t, String w) => ' $t '.contains(' $w ');

/// Nomi di Hevy (inglese) → esercizi di Tigert. L'ordine conta: prima i casi specifici.
const _rules = <_Rule>[
  // petto
  _Rule('panca-inclinata-multipower', ['incline', 'bench press|chest press|press', 'smith machine|smith']),
  _Rule('panca-multipower', ['bench press', 'smith machine|smith'], ['incline', 'decline', 'close grip']),
  _Rule('panca-stretta', ['close grip bench press|close grip bench|close grip press']),
  _Rule('panca-inclinata-manubri', ['incline', 'bench press|press', 'dumbbell'], ['fly', 'row', 'curl']),
  _Rule('panca-declinata-manubri', ['decline', 'bench press|press', 'dumbbell'], ['crunch', 'sit up']),
  _Rule('floor-press-manubri', ['floor press', 'dumbbell']),
  _Rule('floor-press', ['floor press']),
  _Rule('panca-declinata', ['decline', 'bench press|press']),
  _Rule('chest-press-inclinata', ['incline', 'chest press']),
  _Rule('panca-inclinata', ['incline bench press|incline press']),
  _Rule('panca-piana-manubri', ['bench press|press', 'dumbbell'], ['incline', 'decline', 'shoulder', 'overhead', 'arnold', 'floor']),
  _Rule('panca-piana', ['bench press'], ['incline', 'decline', 'close grip', 'dumbbell']),
  _Rule('chest-press', ['chest press']),
  _Rule('croci-inclinata-manubri', ['incline', 'fly', 'dumbbell']),
  _Rule('croci-manubri', ['fly', 'dumbbell'], ['reverse', 'rear']),
  _Rule('reverse-pec-deck', ['reverse', 'pec deck|fly', 'machine']),
  _Rule('pec-deck', ['pec deck|butterfly'], ['reverse', 'rear']),
  _Rule('croci-cavi-alto', ['high to low|high cable|high', 'fly|crossover|crossovers']),
  _Rule('croci-cavi-basso', ['low', 'fly|crossover|crossovers']),
  _Rule('croci-cavi', ['fly|crossover|crossovers', 'cable'], ['reverse', 'rear']),
  _Rule('croci-cavi', ['cable crossover|cable fly']),
  _Rule('dip-anelli', ['dip|dips', 'ring|rings']),
  _Rule('dip-sbarra', ['straight bar dip|straight bar dips']),
  _Rule('dip-macchina', ['dip|dips', 'machine'], ['assisted']),
  _Rule('dip-petto', ['chest dip|chest dips']),
  _Rule('dip-assistite', ['dip|dips', 'assisted']),
  _Rule('dip-panche', ['bench dip|bench dips']),
  _Rule('dip-tricipiti', ['dip|dips|triceps dip|tricep dip'], ['bench', 'chest', 'assisted']),
  _Rule('pike-push-up-rialzato', ['pike push up|pike push ups|pike pushup|pike pushups', 'elevated|decline']),
  _Rule('pike-push-up', ['pike push up|pike push ups|pike pushup|pike pushups']),
  _Rule('hspu', ['handstand push up|handstand push ups|handstand pushup|hspu']),
  _Rule('pseudo-planche-push-up', ['pseudo planche']),
  _Rule('push-up-diamante', ['diamond push up|diamond push ups|diamond pushup|close grip push up|close grip push ups']),
  _Rule('push-up-archer', ['archer push up|archer push ups|archer pushup']),
  _Rule('push-up-esplosivi', ['clap push up|clap push ups|plyo push up|plyometric push up|explosive push up']),
  _Rule('push-up-anelli', ['push up|push ups|pushup|pushups', 'ring|rings']),
  _Rule('push-up-declinati', ['push up|push ups|pushup|pushups', 'decline']),
  _Rule('push-up-inclinati', ['push up|push ups|pushup|pushups', 'incline']),
  _Rule('push-up-larghi', ['push up|push ups|pushup|pushups', 'wide']),
  _Rule('push-up', ['push up|push ups|pushup|pushups']),
  _Rule('pullover-cavi', ['pullover', 'cable']),
  _Rule('pullover-macchina', ['pullover', 'machine']),
  _Rule('pullover-manubrio', ['pullover']),
  _Rule('landmine-press', ['landmine press']),
  // dorso
  _Rule('trazioni-elastico', ['pull up|pull ups|pullup|pullups|chin up|chin ups', 'band|banded']),
  _Rule('muscle-up-anelli', ['muscle up|muscle ups|muscleup', 'ring|rings']),
  _Rule('muscle-up', ['muscle up|muscle ups|muscleup']),
  _Rule('trazioni-scapolari', ['scapular pull up|scapular pull ups|scap pull up|scapula pull up|scapular pulls']),
  _Rule('trazioni-negative', ['pull up|pull ups|pullup|pullups|chin up', 'negative|eccentric']),
  _Rule('trazioni-archer', ['archer pull up|archer pull ups|archer pullup']),
  _Rule('trazioni-esplosive', ['pull up|pull ups|pullup|pullups', 'explosive|chest to bar']),
  _Rule('trazioni-presa-larga', ['wide grip pull up|wide pull up|wide grip pull ups|wide pull ups|wide grip pullup']),
  _Rule('trazioni-presa-neutra', ['pull up|pull ups|pullup|pullups', 'neutral|hammer|parallel']),
  _Rule('rematore-inverso', ['inverted row|inverted rows|australian pull up|australian pull ups|bodyweight row']),
  _Rule('rematore-anelli', ['row|rows', 'ring|rings|trx|suspension']),
  _Rule('front-lever', ['front lever']),
  _Rule('back-lever', ['back lever']),
  _Rule('dead-hang', ['dead hang|bar hang|passive hang|active hang']),
  _Rule('superman', ['superman|supermans']),
  _Rule('trazioni-assistite', ['pull up|chin up|pull ups|chin ups', 'assisted']),
  _Rule('chin-up', ['chin up|chin ups|chinup']),
  _Rule('trazioni', ['pull up|pull ups|pullup|pullups']),
  _Rule('pulldown-braccia-tese', ['straight arm']),
  _Rule('lat-machine-unilaterale', ['pulldown|pull down', 'single arm|one arm|unilateral']),
  _Rule('lat-machine-stretta', ['pulldown|pull down', 'close grip|narrow|v grip|v bar']),
  _Rule('lat-machine-inversa', ['pulldown|pull down', 'reverse grip|underhand|supinated|reverse']),
  _Rule('lat-machine', ['lat pulldown|pulldown|pull down']),
  _Rule('pulley-unilaterale', ['single arm|one arm|unilateral', 'cable row|cable|row cable'], ['dumbbell']),
  _Rule('pulley', ['seated cable row|cable row|low row|seated row cable']),
  _Rule('rematore-panca-inclinata', ['chest supported|incline row|incline dumbbell row']),
  _Rule('rematore-tbar', ['t bar|tbar|t-bar']),
  _Rule('seal-row', ['seal row']),
  _Rule('rematore-macchina', ['row', 'machine|iso lateral|lever|hammer strength'], ['upright']),
  _Rule('rematore-manubrio', ['row', 'dumbbell'], ['upright']),
  _Rule('rematore-pendlay', ['pendlay']),
  _Rule('meadows-row', ['meadows']),
  _Rule('rematore-bilanciere', ['bent over row|barbell row|pendlay row|pendlay|yates row']),
  _Rule('rematore-bilanciere', ['row', 'barbell'], ['upright']),
  _Rule('stacco-rumeno-monolaterale', ['romanian deadlift|rdl', 'single leg|single-leg|one leg']),
  _Rule('stacco-rumeno-manubri', ['romanian deadlift|rdl', 'dumbbell']),
  _Rule('stacco-rumeno', ['romanian deadlift|rdl']),
  _Rule('stacco-gambe-tese', ['straight leg deadlift|stiff leg deadlift|stiff legged']),
  _Rule('stacco-sumo', ['sumo deadlift|sumo']),
  _Rule('rack-pull', ['rack pull|rack pulls']),
  _Rule('stacco-trap-bar', ['deadlift', 'trap bar|hex bar']),
  _Rule('stacco', ['deadlift'], ['single leg', 'trap bar', 'hex bar']),
  _Rule('reverse-hyper', ['reverse hyper|reverse hyperextension|reverse hyperextensions']),
  _Rule('hyperextension', ['back extension|hyperextension|hyperextensions']),
  _Rule('scrollate-manubri', ['shrug|shrugs', 'dumbbell']),
  _Rule('scrollate-bilanciere', ['shrug|shrugs']),
  // spalle
  _Rule('lento-multipower', ['shoulder press|overhead press|military press', 'smith machine|smith']),
  _Rule('z-press', ['z press']),
  _Rule('planche-lean', ['planche lean|planche leans']),
  _Rule('planche', ['planche']),
  _Rule('verticale', ['handstand']),
  _Rule('military-press-seduto', ['seated', 'overhead press|military press|shoulder press', 'barbell']),
  _Rule('shoulder-press-macchina', ['shoulder press|overhead press', 'machine']),
  _Rule('arnold-press', ['arnold']),
  _Rule('lento-manubri', ['shoulder press|overhead press', 'dumbbell']),
  _Rule('push-press', ['push press']),
  _Rule('military-press', ['overhead press|military press|shoulder press|strict press']),
  _Rule('alzate-laterali-cavi', ['lateral raise|lateral raises|side raise', 'cable']),
  _Rule('alzate-laterali-macchina', ['lateral raise|lateral raises|side raise', 'machine']),
  _Rule('alzate-laterali', ['lateral raise|lateral raises|side raise|side lateral']),
  _Rule('alzate-frontali', ['front raise|front raises']),
  _Rule('reverse-pec-deck', ['rear delt|reverse fly|reverse flye', 'machine']),
  _Rule('alzate-posteriori-cavi', ['rear delt|reverse fly|reverse flye', 'cable']),
  _Rule('alzate-posteriori', ['rear delt|reverse fly|reverse flye|bent over lateral']),
  _Rule('face-pull', ['face pull|face pulls']),
  _Rule('tirate-mento-cavi', ['upright row', 'cable']),
  _Rule('tirate-mento', ['upright row']),
  _Rule('y-raise', ['y raise|y raises']),
  // bicipiti e avambracci
  _Rule('curl-polso-inverso', ['reverse wrist curl|reverse wrist curls']),
  _Rule('wrist-roller', ['wrist roller']),
  _Rule('curl-zottman', ['zottman']),
  _Rule('drag-curl', ['drag curl|drag curls']),
  _Rule('curl-scott-manubrio', ['preacher', 'dumbbell']),
  _Rule('curl-anelli', ['curl|curls', 'ring|rings|trx|suspension'], ['leg']),
  _Rule('curl-elastico', ['curl|curls', 'band|banded'], ['leg', 'wrist']),
  _Rule('curl-polso', ['wrist curl|wrist curls']),
  _Rule('reverse-curl', ['reverse curl|reverse grip curl']),
  _Rule('curl-scott', ['preacher']),
  _Rule('curl-spider', ['spider curl|spider']),
  _Rule('curl-concentrato', ['concentration']),
  _Rule('curl-bayesiano', ['bayesian']),
  _Rule('curl-inclinata', ['incline', 'curl']),
  _Rule('curl-corda', ['hammer curl|rope curl', 'cable|rope']),
  _Rule('curl-martello', ['hammer curl|hammer curls']),
  _Rule('curl-ez', ['ez bar|ez curl|ezbar|ez', 'curl']),
  _Rule('curl-macchina', ['curl', 'machine'], ['leg']),
  _Rule('curl-cavi', ['curl', 'cable'], ['leg']),
  _Rule('curl-manubri', ['curl', 'dumbbell'], ['leg', 'wrist']),
  _Rule('curl-bilanciere', ['bicep curl|biceps curl|barbell curl|curl'], ['leg', 'wrist', 'nordic', 'hamstring']),
  // tricipiti
  _Rule('estensioni-corpo-libero', ['bodyweight', 'triceps extension|tricep extension|skull crusher|skullcrusher']),
  _Rule('pushdown-unilaterale', ['pushdown|push down|pushdowns', 'single arm|one arm|unilateral']),
  _Rule('kickback-cavi-tricipiti', ['kickback', 'triceps|tricep', 'cable']),
  _Rule('french-press-manubri', ['skullcrusher|skull crusher|skullcrushers|lying triceps extension|lying tricep extension', 'dumbbell']),
  _Rule('french-press', ['skullcrusher|skull crusher|skullcrushers|lying triceps extension|lying tricep extension|french press']),
  _Rule('pushdown-corda', ['pushdown|push down|pushdowns', 'rope']),
  _Rule('pushdown-barra', ['pushdown|push down|pushdowns']),
  _Rule('estensioni-cavi', ['overhead', 'triceps|tricep', 'cable']),
  _Rule('estensioni-manubrio', ['triceps extension|tricep extension|overhead triceps|overhead tricep']),
  _Rule('tricipiti-macchina', ['triceps|tricep', 'machine']),
  _Rule('kickback', ['triceps kickback|tricep kickback|kickback', 'dumbbell|triceps|tricep']),
  _Rule('jm-press', ['jm press']),
  // gambe
  _Rule('pistol-squat-assistito', ['pistol', 'assisted']),
  _Rule('pistol-squat', ['pistol']),
  _Rule('shrimp-squat', ['shrimp']),
  _Rule('sissy-squat', ['sissy']),
  _Rule('jump-squat', ['jump squat|jump squats|squat jump|squat jumps']),
  _Rule('cossack-squat', ['cossack']),
  _Rule('wall-sit', ['wall sit|wall sits']),
  _Rule('box-squat', ['box squat|box squats']),
  _Rule('zercher-squat', ['zercher squat|zercher squats']),
  _Rule('belt-squat', ['belt squat']),
  _Rule('squat-corpo-libero', ['air squat|air squats|bodyweight squat|bodyweight squats|squat bodyweight']),
  _Rule('bulgarian-corpo-libero', ['bulgarian|split squat', 'bodyweight']),
  _Rule('leg-press-unilaterale', ['leg press', 'single leg|one leg|unilateral']),
  _Rule('affondi-saltati', ['jump lunge|jump lunges|jumping lunge|jumping lunges|split jump|split jumps']),
  _Rule('affondi-laterali', ['lateral lunge|lateral lunges|side lunge|side lunges']),
  _Rule('bulgarian-multipower', ['bulgarian|split squat', 'smith machine|smith']),
  _Rule('bulgarian', ['bulgarian|split squat']),
  _Rule('squat-multipower', ['squat', 'smith machine|smith']),
  _Rule('front-squat', ['front squat']),
  _Rule('goblet-squat', ['goblet']),
  _Rule('hack-squat', ['hack squat|hack']),
  _Rule('pendulum-squat', ['pendulum']),
  _Rule('calf-leg-press', ['calf', 'leg press|press']),
  _Rule('leg-press-orizzontale', ['leg press', 'horizontal|seated']),
  _Rule('leg-press', ['leg press']),
  _Rule('affondi-camminati', ['walking lunge|walking lunges']),
  _Rule('affondi-inversi', ['reverse lunge|reverse lunges']),
  _Rule('affondi-bilanciere', ['lunge|lunges', 'barbell']),
  _Rule('affondi-corpo-libero', ['lunge|lunges', 'bodyweight']),
  _Rule('affondi', ['lunge|lunges']),
  _Rule('step-up', ['step up|step ups']),
  _Rule('leg-extension', ['leg extension|leg extensions']),
  _Rule('glute-ham-raise', ['glute ham raise|glute ham raises|ghr']),
  _Rule('leg-curl-scivolamento', ['sliding leg curl|slider leg curl|sliding hamstring curl|towel leg curl|slider curl']),
  _Rule('nordic-curl', ['nordic']),
  _Rule('leg-curl-seduto', ['seated leg curl|seated hamstring curl']),
  _Rule('leg-curl-in-piedi', ['standing leg curl|standing hamstring curl']),
  _Rule('leg-curl-sdraiato', ['leg curl|leg curls|hamstring curl|lying leg curl']),
  _Rule('good-morning', ['good morning']),
  _Rule('hip-thrust-monolaterale', ['hip thrust', 'single leg|one leg']),
  _Rule('hip-thrust-manubrio', ['hip thrust', 'dumbbell']),
  _Rule('glute-bridge-monolaterale', ['glute bridge|bridge', 'single leg|one leg']),
  _Rule('pull-through', ['pull through|pull throughs|pullthrough']),
  _Rule('hip-thrust-multipower', ['hip thrust', 'smith machine|smith']),
  _Rule('hip-thrust-macchina', ['hip thrust', 'machine']),
  _Rule('hip-thrust', ['hip thrust']),
  _Rule('glute-bridge', ['glute bridge|bridge']),
  _Rule('frog-pump', ['frog pump|frog pumps']),
  _Rule('abductor', ['abduction|abductor']),
  _Rule('adductor', ['adduction|adductor']),
  _Rule('kickback-macchina', ['glute kickback|kickback', 'machine']),
  _Rule('donkey-kick', ['donkey kick|donkey kicks'], ['cable', 'machine']),
  _Rule('kickback-cavi', ['glute kickback|cable kickback|donkey kick']),
  _Rule('donkey-calf', ['donkey calf']),
  _Rule('tibialis-raise', ['tibialis|tib raise|tib raises|tibia raise']),
  _Rule('calf-corpo-libero', ['calf raise|calf raises', 'bodyweight'], ['single', 'one']),
  _Rule('calf-seduto', ['seated calf']),
  _Rule('calf-multipower', ['calf', 'smith machine|smith']),
  _Rule('calf-monolaterale', ['single leg|one leg|single', 'calf']),
  _Rule('calf-in-piedi', ['calf raise|calf raises|calf']),
  _Rule('squat', ['squat'], ['front', 'goblet', 'hack', 'split', 'pendulum', 'sissy', 'jump', 'pistol', 'box', 'overhead', 'zercher']),
  // addome
  _Rule('crunch-declinato', ['decline crunch|decline crunches|decline sit up|decline sit ups']),
  _Rule('crunch-bicicletta', ['bicycle crunch|bicycle crunches|bicycle']),
  _Rule('sit-up', ['sit up|sit ups|situp|situps']),
  _Rule('v-up', ['v up|v ups|v sit up|jackknife']),
  _Rule('toes-to-bar', ['toes to bar|toe to bar|t2b']),
  _Rule('knee-raise-sbarra', ['hanging knee raise|hanging knee raises|knee raise|knee raises'], ['lying', 'captain', 'captains']),
  _Rule('l-sit', ['l sit|lsit']),
  _Rule('dragon-flag', ['dragon flag|dragon flags']),
  _Rule('human-flag', ['human flag']),
  _Rule('tergicristallo', ['windshield wiper|windshield wipers']),
  _Rule('hollow-rock', ['hollow rock|hollow rocks']),
  _Rule('sforbiciate', ['flutter kick|flutter kicks|scissor kick|scissor kicks|scissors']),
  _Rule('woodchopper', ['woodchopper|wood chopper|woodchop|wood chop|cable chop']),
  _Rule('crunch-cavi', ['crunch', 'cable']),
  _Rule('crunch-macchina', ['crunch', 'machine']),
  _Rule('crunch-inverso', ['reverse crunch']),
  _Rule('crunch', ['crunch|crunches|sit up|sit ups']),
  _Rule('plank-laterale', ['side plank']),
  _Rule('plank', ['plank']),
  _Rule('leg-raise-sbarra', ['hanging leg raise|hanging knee raise|knee raise|captains chair|toes to bar']),
  _Rule('leg-raise', ['leg raise|leg raises']),
  _Rule('russian-twist', ['russian twist']),
  _Rule('ab-wheel', ['ab wheel|ab rollout|rollout|ab roller']),
  _Rule('pallof-press', ['pallof']),
  _Rule('side-bend', ['side bend|side bends']),
  _Rule('mountain-climber', ['mountain climber|mountain climbers']),
  _Rule('hollow-hold', ['hollow']),
  _Rule('dead-bug', ['dead bug|dead bugs']),
  // total body
  _Rule('farmer-walk', ['farmer|farmers']),
  _Rule('kettlebell-swing', ['kettlebell swing|swing']),
  _Rule('slancio', ['clean and jerk|clean jerk']),
  _Rule('strappo', ['snatch'], ['deadlift', 'high pull']),
  _Rule('turkish-get-up', ['turkish get up|turkish getup|get up']),
  _Rule('girata', ['power clean|clean and jerk|hang clean|clean']),
  _Rule('thruster', ['thruster|thrusters']),
  _Rule('burpee-trazione', ['burpee pull up|burpee pullup|burpee to pull up']),
  _Rule('bear-crawl', ['bear crawl|bear crawls']),
  _Rule('burpees', ['burpee|burpees']),
  _Rule('box-jump', ['box jump|box jumps']),
  // cardio
  _Rule('camminata-inclinata', ['incline walk|incline walking|incline treadmill']),
  _Rule('tapis-roulant', ['treadmill']),
  _Rule('assault-bike', ['air bike|assault bike|airbike|echo bike']),
  _Rule('cyclette', ['cycling|bike|spinning|stationary|cycle']),
  _Rule('ellittica', ['elliptical']),
  _Rule('skierg', ['ski erg|skierg|ski']),
  _Rule('vogatore', ['rowing machine|rower|rowing|erg']),
  _Rule('stair-climber', ['stair|stairmaster|stepper|stairs']),
  _Rule('battle-rope', ['battle rope|battle ropes']),
  _Rule('jumping-jack', ['jumping jack|jumping jacks|jumping jax']),
  _Rule('sprint', ['sprint|sprints']),
  _Rule('nuoto', ['swimming|swim']),
  _Rule('camminata', ['walking|walk'], ['lunge', 'lunges', 'farmer', 'farmers', 'incline']),
  _Rule('corda', ['jump rope|skipping|rope jump']),
  _Rule('corsa', ['running|run|jogging|jog']),
  _Rule('hiit', ['hiit']),
];

String _norm(String s) => fold(s).replaceAll(RegExp(r'[^a-z0-9]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

const _stop = {'con', 'al', 'alla', 'alle', 'ai', 'agli', 'a', 'di', 'da', 'in', 'su', 'e', 'the', 'with', 'on', 'of', 'and'};
const _itEquip = {
  'barbell': 'bilanciere', 'dumbbell': 'manubri', 'dumbbells': 'manubri', 'cable': 'cavi', 'machine': 'macchina',
  'smith': 'multipower', 'bodyweight': 'corpo libero', 'manubrio': 'manubri', 'cavo': 'cavi',
};

Set<String> _tokens(String s) {
  var t = _norm(s);
  _itEquip.forEach((k, v) => t = t.replaceAll(RegExp('\\b$k\\b'), v));
  return t.split(' ').where((w) => w.isNotEmpty && !_stop.contains(w)).toSet();
}

/// Trova l'esercizio di Tigert corrispondente a un titolo di Hevy (null = nessuno).
String? matchExercise(String title, AppState app) {
  final all = app.exercises;
  final n = _norm(title);
  // 1) stesso nome (anche esercizi personalizzati creati da un import precedente)
  for (final e in all.values) {
    if (_norm(e.name) == n) return e.id;
  }
  // 2) regole per i nomi inglesi di Hevy
  for (final r in _rules) {
    if (r.matches(n) && all.containsKey(r.id)) return r.id;
  }
  // 3) somiglianza sui nomi italiani (Hevy in italiano)
  final tt = _tokens(title);
  if (tt.isEmpty) return null;
  String? best;
  var score = 0.0;
  for (final e in all.values) {
    final et = _tokens(e.name.replaceAll('(secondi)', ''));
    if (et.isEmpty) continue;
    final inter = tt.intersection(et).length;
    final s = inter / tt.union(et).length;
    if (s > score) {
      score = s;
      best = e.id;
    }
  }
  return score >= 0.6 ? best : null;
}

const _muscleFromHevy = {
  'chest': 'Petto', 'lats': 'Dorso', 'upper_back': 'Dorso', 'traps': 'Dorso', 'lower_back': 'Dorso', 'shoulders': 'Spalle',
  'biceps': 'Bicipiti', 'triceps': 'Tricipiti', 'forearms': 'Avambracci', 'quadriceps': 'Quadricipiti', 'hamstrings': 'Femorali',
  'glutes': 'Glutei', 'abductors': 'Glutei', 'adductors': 'Glutei', 'calves': 'Polpacci', 'abdominals': 'Addome',
  'cardio': 'Cardio', 'full_body': 'Total body', 'neck': 'Total body', 'other': 'Total body',
};

const _equipFromHevy = {
  'barbell': 'Bilanciere', 'dumbbell': 'Manubri', 'kettlebell': 'Kettlebell', 'machine': 'Macchina', 'plate': 'Bilanciere',
  'resistance_band': 'Elastico', 'suspension': 'Corpo libero', 'none': 'Corpo libero', 'other': 'Altro',
};

/// Gruppo muscolare dedotto dal nome (quando Hevy non lo dice, cioè dal CSV).
String guessMuscle(String title) {
  final t = _norm(title);
  bool any(String l) => l.split('|').any((w) => _has(t, w));
  if (any('treadmill|running|run|bike|cycling|elliptical|rowing machine|stair|walk|walking|cardio|jump rope|hiit|corsa|cyclette')) return 'Cardio';
  if (any('calf|calves|polpacci')) return 'Polpacci';
  if (any('leg curl|romanian|rdl|hamstring|good morning|femorali|nordic')) return 'Femorali';
  if (any('hip|glute|glutes|abduction|adduction|abductor|adductor|kickback|glutei|bridge')) return 'Glutei';
  if (any('crunch|plank|abs|ab|leg raise|twist|core|addome|sit up|oblique')) return 'Addome';
  if (any('wrist|forearm|farmer|grip|avambracci')) return 'Avambracci';
  if (any('tricep|triceps|pushdown|skullcrusher|skull|french|tricipiti|dip|dips')) return 'Tricipiti';
  if (any('curl|bicep|biceps|bicipiti')) return 'Bicipiti';
  if (any('squat|leg press|lunge|lunges|leg extension|step up|quad|quadricipiti|affondi')) return 'Quadricipiti';
  if (any('bench|chest|fly|pec|push up|panca|petto|croci|piegamenti')) return 'Petto';
  if (any('row|pulldown|pull up|chin up|lat|deadlift|shrug|back|rematore|trazioni|stacco|pulley|dorso')) return 'Dorso';
  if (any('shoulder|overhead|lateral|raise|delt|face pull|military|arnold|spalle|alzate|lento')) return 'Spalle';
  return 'Total body';
}

String _guessEquip(String title) {
  final t = _norm(title);
  if (_has(t, 'smith')) return 'Multipower';
  if (_has(t, 'barbell') || _has(t, 'bilanciere') || _has(t, 'ez')) return 'Bilanciere';
  if (_has(t, 'dumbbell') || _has(t, 'manubri') || _has(t, 'manubrio')) return 'Manubri';
  if (_has(t, 'cable') || _has(t, 'cavi') || _has(t, 'rope')) return 'Cavi';
  if (_has(t, 'machine') || _has(t, 'macchina')) return 'Macchina';
  if (_has(t, 'kettlebell')) return 'Kettlebell';
  if (_has(t, 'band')) return 'Elastico';
  return 'Corpo libero';
}

/// Esercizio personalizzato da creare per un titolo di Hevy senza corrispondenza.
Exercise newExerciseFor(HevyExerciseUse u) {
  final tpl = u.template;
  final muscle = _muscleFromHevy[tpl?.muscle] ?? guessMuscle(u.title);
  final equip = _equipFromHevy[tpl?.equipment] ?? _guessEquip(u.title);
  final type = tpl?.type ?? 'weight_reps';
  final cardio = muscle == 'Cardio' || type == 'distance_duration';
  final bodyweight = type.startsWith('bodyweight') || type == 'reps_only' || (equip == 'Corpo libero' && type != 'weight_reps');
  final timed = !cardio && (type == 'duration' || type == 'weight_duration');
  const isolation = {'Bicipiti', 'Tricipiti', 'Polpacci', 'Addome', 'Avambracci'};
  final t = cardio ? 'k' : (bodyweight || timed ? 'b' : (isolation.contains(muscle) ? 'i' : 'c'));
  final inc = switch (equip) {
    _ when t == 'k' => 0.0,
    'Bilanciere' => 2.5,
    'Manubri' => 2.0,
    'Kettlebell' => 4.0,
    'Corpo libero' || 'Elastico' => bodyweight ? 0.0 : 2.5,
    _ => (muscle == 'Quadricipiti' || muscle == 'Glutei') ? 5.0 : 2.5,
  };
  var name = u.title.trim();
  if (timed && !name.contains('(secondi)')) name = '$name (secondi)';
  return Exercise(id: 'x:hv${_hash(fold(u.title))}', name: name, muscle: muscle, equip: equip, type: t, inc: inc, custom: true);
}

// =================================================================== bozze delle schede

class HevyItemDraft {
  final String exKey;
  final String title;
  final int sets, rMin, rMax, rest;
  final int warm;
  final double rpe;
  final String note;
  const HevyItemDraft(this.exKey, this.title, this.sets, this.rMin, this.rMax, this.rpe, this.rest, this.note, {this.warm = 0});
}

class HevyDayDraft {
  final String id;
  final String name;
  final List<HevyItemDraft> items;
  const HevyDayDraft(this.id, this.name, this.items);
}

class HevyPlanDraft {
  final String id;
  final String name;
  final List<HevyDayDraft> days;
  final int lastUsed; // ms dell'ultimo allenamento fatto con queste schede
  const HevyPlanDraft(this.id, this.name, this.days, this.lastUsed);
}

HevyItemDraft _item(HevyExerciseLog e) {
  final work = e.sets.where((s) => !s.warmup && !s.drop).toList();
  final lows = [for (final s in work) s.repStart ?? s.reps].whereType<int>().where((v) => v > 0).toList();
  final highs = [for (final s in work) s.repEnd ?? s.reps].whereType<int>().where((v) => v > 0).toList();
  var rMin = lows.isEmpty ? 8 : lows.reduce((a, b) => a < b ? a : b);
  var rMax = highs.isEmpty ? 12 : highs.reduce((a, b) => a > b ? a : b);
  if (rMin == rMax && work.every((s) => s.repStart == null)) rMax = rMin + 2; // 3×10 fatto → obiettivo 10-12
  final rpes = work.map((s) => s.rpe).whereType<double>().toList();
  return HevyItemDraft(
    e.key,
    e.title,
    work.isEmpty ? 3 : work.length.clamp(1, 10),
    rMin,
    rMax,
    rpes.isEmpty ? 9 : (rpes.reduce((a, b) => a + b) / rpes.length * 2).round() / 2,
    e.restSeconds > 0 ? e.restSeconds : 120,
    e.notes,
    warm: e.sets.where((s) => s.warmup).length.clamp(0, 5),
  );
}

/// Schede da creare: dalle routine di Hevy (API) o ricostruite dagli allenamenti (CSV).
List<HevyPlanDraft> buildPlanDrafts(HevyData d) {
  final lastByRoutine = <String, int>{};
  for (final w in d.workouts) {
    if (w.routineId != null) lastByRoutine[w.routineId!] = w.start.millisecondsSinceEpoch;
  }
  if (d.routines.isNotEmpty) {
    final out = <HevyPlanDraft>[];
    HevyPlanDraft plan(String id, String name, List<HevyRoutine> rs) => HevyPlanDraft(
          id,
          name,
          [for (final r in rs) HevyDayDraft('hv${_hash(r.id)}', r.title, r.exercises.map(_item).toList())],
          rs.map((r) => lastByRoutine[r.id] ?? 0).fold(0, (a, b) => a > b ? a : b),
        );
    for (final f in d.folders) {
      final rs = d.routines.where((r) => r.folderId == f.id).toList();
      if (rs.isNotEmpty) out.add(plan('hv-f${f.id}', f.title, rs));
    }
    final loose = d.routines.where((r) => r.folderId == null || !d.folders.any((f) => f.id == r.folderId)).toList();
    if (loose.isNotEmpty) out.add(plan('hv-routines', 'Schede da Hevy', loose));
    out.sort((a, b) => b.lastUsed.compareTo(a.lastUsed));
    return out;
  }
  if (d.workouts.isEmpty) return const [];
  // CSV: una seduta per ogni titolo usato nelle ultime 8 settimane di allenamento
  final last = d.workouts.last.start;
  final recent = d.workouts.where((w) => last.difference(w.start).inDays <= 56).toList();
  final latest = <String, HevyWorkout>{};
  for (final w in recent) {
    latest[w.title] = w;
  }
  final count = <String, int>{};
  for (final w in recent) {
    count[w.title] = (count[w.title] ?? 0) + 1;
  }
  final titles = latest.keys.where((t) => (count[t] ?? 0) >= (recent.length >= 8 ? 2 : 1)).toList()
    ..sort((a, b) => latest[a]!.start.compareTo(latest[b]!.start));
  final days = [
    for (final t in titles.take(7)) HevyDayDraft('hv${_hash(t)}', t, latest[t]!.exercises.map(_item).toList()),
  ];
  return days.isEmpty ? const [] : [HevyPlanDraft('hv-csv', 'Da Hevy', days, last.millisecondsSinceEpoch)];
}

// =================================================================== import

class HevyImportResult {
  final int sessions, exercisesCreated, plans, weights;
  const HevyImportResult(this.sessions, this.exercisesCreated, this.plans, this.weights);
}

/// [mapping]: chiave Hevy → id esercizio Tigert (null = crea personalizzato).
HevyImportResult importHevy(
  AppState app,
  HevyData d, {
  required Map<String, String?> mapping,
  required bool history,
  required bool weights,
  required List<HevyPlanDraft> plans,
  String? activatePlanId,
}) {
  final uses = {for (final u in d.exerciseUses()) u.key: u};
  final resolved = <String, Exercise>{};
  var created = 0;
  var sessions = 0, nWeights = 0;

  Exercise resolve(String key) {
    final cached = resolved[key];
    if (cached != null) return cached;
    final id = mapping[key];
    Exercise? ex = id == null ? null : app.exercise(id);
    if (ex == null) {
      ex = newExerciseFor(uses[key] ?? HevyExerciseUse(key, key.startsWith('t:') ? key.substring(2) : key, d.templates[key]));
      if (app.exercise(ex.id) == null) {
        app.saveExercise(ex);
        created++;
      }
    }
    resolved[key] = ex;
    return ex;
  }

  app.store.batch(() {
    if (history) {
      for (final w in d.workouts) {
        final items = <SessionEx>[];
        for (final e in w.exercises) {
          final ex = resolve(e.key);
          if (e.sets.every((s) => s.warmup)) continue;
          final sets = [
            for (final s in e.sets)
              SetLog(
                t: s.tigertType,
                kg: ex.isCardio ? 0 : double.parse((s.kg ?? 0).toStringAsFixed(2)),
                reps: ex.isCardio
                    ? ((s.seconds ?? 0) / 60).ceil()
                    : (s.reps ?? (ex.repsLabel == 'sec' ? s.seconds : null) ?? 0),
                rpe: s.rpe,
                done: true,
              ),
          ];
          final dr = _item(e);
          items.add(SessionEx(
            ex: ex.id,
            name: ex.name,
            type: ex.type,
            target: PlanItem(ex: ex.id, sets: dr.sets, rMin: dr.rMin, rMax: dr.rMax, rpe: dr.rpe, rest: dr.rest, warm: dr.warm),
            sets: sets,
          ));
        }
        if (items.isEmpty) continue;
        final start = w.start.millisecondsSinceEpoch;
        final end = w.end?.millisecondsSinceEpoch ?? start + 3600 * 1000;
        final s = Session(
          id: 'hv${_hash(w.id)}',
          date: dayKey(w.start),
          name: w.title,
          start: start,
          end: end > start ? end : start + 60 * 1000,
          status: 'done',
          items: items,
          note: w.description,
        );
        app.saveSession(s);
        sessions++;
      }
    }
    if (weights) {
      d.weights.forEach((date, kg) {
        if (app.weightOn(date) == null) {
          app.setWeight(date, kg);
          nWeights++;
        }
      });
    }
    for (final p in plans) {
      final plan = Plan(
        id: p.id,
        name: p.name,
        template: 'hevy',
        startDate: todayKey(),
        days: [
          for (final day in p.days)
            PlanDay(id: day.id, name: day.name, items: [
              for (final it in day.items)
                PlanItem(ex: resolve(it.exKey).id, sets: it.sets, rMin: it.rMin, rMax: it.rMax, rpe: it.rpe, rest: it.rest, note: it.note, warm: it.warm),
            ]),
        ],
      );
      app.store.put('plans', plan.id, plan.toMap());
    }
    final pr = app.profile;
    if (activatePlanId != null && pr != null) app.saveProfile(pr.copyWith(planId: activatePlanId));
  });
  return HevyImportResult(sessions, created, plans.length, nWeights);
}
