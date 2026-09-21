import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../core/fmt.dart';
import '../data/models.dart';

/// Un alimento riconosciuto nella foto.
class EstimateItem {
  String name;
  double g, gMin, gMax;
  double kcal100, p100, c100, f100;
  bool confirmed;
  EstimateItem({
    required this.name,
    required this.g,
    required this.gMin,
    required this.gMax,
    required this.kcal100,
    required this.p100,
    required this.c100,
    required this.f100,
    this.confirmed = false,
  });

  Macro get macro => Macro(kcal100, p100, c100, f100).scale(g / 100);
  double get kcalMin => kcal100 * (confirmed ? g : gMin) / 100;
  double get kcalMax => kcal100 * (confirmed ? g : gMax) / 100;
}

class PhotoEstimate {
  String dish;
  String confidence; // bassa | media | alta
  String note;
  List<EstimateItem> items;
  PhotoEstimate({required this.dish, required this.confidence, required this.note, required this.items});

  Macro get total => items.fold(Macro.zero, (a, b) => a + b.macro);
  double get kcalMin => items.fold(0.0, (a, b) => a + b.kcalMin);
  double get kcalMax => items.fold(0.0, (a, b) => a + b.kcalMax);
}

String geminiPrompt([String extra = '']) {
  final e = extra.trim();
  return '''Sei un nutrizionista esperto. Analizza la foto del piatto che ti allego e stima cosa contiene.

Regole:
- Elenca separatamente ogni alimento visibile, compresi i condimenti probabili (olio, sughi, formaggio grattugiato, salse).
- Per ogni alimento stima il peso in grammi così come si vede nel piatto (cotto, se cotto), con un intervallo minimo-massimo realistico.
- Indica i valori nutrizionali per 100 g dell'alimento così com'è nel piatto: kcal, proteine, carboidrati, grassi.
- Usa nomi italiani semplici (es. "Riso basmati cotto", "Petto di pollo alla piastra").
- Se nella foto c'è un riferimento (posate, mano, confezione, piatto standard da 26 cm) usalo per stimare le dimensioni.
- Valuta la tua affidabilità complessiva: "alta", "media" o "bassa".${e.isEmpty ? '' : '\n- Informazioni aggiuntive fornite da me: $e'}

Rispondi SOLO con un blocco JSON valido, senza testo prima o dopo, con esattamente questa struttura:
{
  "tigert": 1,
  "piatto": "nome breve del piatto",
  "affidabilita": "media",
  "alimenti": [
    {"nome": "Riso basmati cotto", "grammi": 180, "grammi_min": 150, "grammi_max": 220, "kcal_100g": 130, "proteine_100g": 2.7, "carboidrati_100g": 28, "grassi_100g": 0.3}
  ],
  "note": "eventuali dubbi, per esempio la quantità di olio non visibile"
}
Usa il punto come separatore decimale.''';
}

class GeminiException implements Exception {
  final String message;
  const GeminiException(this.message);
  @override
  String toString() => message;
}

// ------------------------------------------------------------------ parsing

double _num(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return parseNum(v.replaceAll(RegExp(r'[^0-9,.\-]'), '')) ?? 0;
  return 0;
}

Object? _pick(Map m, List<String> keys) {
  for (final k in keys) {
    if (m.containsKey(k) && m[k] != null) return m[k];
  }
  return null;
}

/// Legge la risposta di Gemini anche se "sporca": blocchi ```json, virgolette
/// tipografiche, virgole finali o decimali con la virgola.
PhotoEstimate parseEstimate(String raw) {
  var t = raw.trim();
  if (t.isEmpty) throw const FormatException('La risposta è vuota. Copia tutto il testo della risposta di Gemini.');
  t = t.replaceAll(RegExp(r'```[a-zA-Z]*'), '');
  final start = t.indexOf('{');
  final end = t.lastIndexOf('}');
  if (start < 0 || end <= start) {
    throw const FormatException('Non trovo i dati nella risposta. Assicurati di copiare tutta la risposta di Gemini, parentesi graffe comprese.');
  }
  var j = t.substring(start, end + 1);
  j = j
      .replaceAll('“', '"')
      .replaceAll('”', '"')
      .replaceAll('„', '"')
      .replaceAll('«', '"')
      .replaceAll('»', '"')
      .replaceAll(' ', ' ');
  j = j.replaceAllMapped(RegExp(r',\s*([}\]])'), (m) => m[1]!);
  Map<String, dynamic> m;
  try {
    m = Map<String, dynamic>.from(jsonDecode(j) as Map);
  } catch (_) {
    final fixed = j.replaceAllMapped(RegExp(r'(:\s*-?\d+),(\d+)'), (x) => '${x[1]}.${x[2]}');
    try {
      m = Map<String, dynamic>.from(jsonDecode(fixed) as Map);
    } catch (_) {
      throw const FormatException('La risposta non è nel formato previsto. Riprova su Gemini con il prompt di Tigert, senza modificarlo.');
    }
  }
  final rawItems = _pick(m, ['alimenti', 'items', 'foods', 'ingredienti']);
  if (rawItems is! List || rawItems.isEmpty) {
    throw const FormatException('Nella risposta non ci sono alimenti. Prova con una foto più nitida o aggiungi una descrizione.');
  }
  final items = <EstimateItem>[];
  for (final it in rawItems) {
    if (it is! Map) continue;
    final name = (_pick(it, ['nome', 'name', 'alimento']) ?? 'Alimento').toString();
    var g = _num(_pick(it, ['grammi', 'g', 'grams', 'peso', 'quantita']));
    var gMin = _num(_pick(it, ['grammi_min', 'g_min', 'min']));
    var gMax = _num(_pick(it, ['grammi_max', 'g_max', 'max']));
    var k100 = _num(_pick(it, ['kcal_100g', 'kcal100', 'kcal_per_100g', 'calorie_100g']));
    var p100 = _num(_pick(it, ['proteine_100g', 'proteine', 'protein_100g']));
    var c100 = _num(_pick(it, ['carboidrati_100g', 'carboidrati', 'carbs_100g']));
    var f100 = _num(_pick(it, ['grassi_100g', 'grassi', 'fat_100g']));
    // se ha dato solo i totali, li riporto a 100 g
    final kTot = _num(_pick(it, ['kcal', 'calorie', 'kcal_totali']));
    if (k100 <= 0 && kTot > 0 && g > 0) {
      k100 = kTot / g * 100;
      p100 = p100 / g * 100;
      c100 = c100 / g * 100;
      f100 = f100 / g * 100;
    }
    if (g <= 0) g = gMin > 0 && gMax > 0 ? (gMin + gMax) / 2 : 100;
    if (gMin <= 0 || gMin > g) gMin = g * 0.8;
    if (gMax <= 0 || gMax < g) gMax = g * 1.2;
    if (k100 <= 0) k100 = p100 * 4 + c100 * 4 + f100 * 9;
    items.add(EstimateItem(name: name, g: g, gMin: gMin, gMax: gMax, kcal100: k100, p100: p100, c100: c100, f100: f100));
  }
  if (items.isEmpty) throw const FormatException('Nessun alimento leggibile nella risposta.');
  var conf = (_pick(m, ['affidabilita', 'affidabilità', 'confidenza', 'confidence']) ?? 'media').toString().toLowerCase();
  if (!['alta', 'media', 'bassa'].contains(conf)) {
    conf = conf.contains('high') ? 'alta' : conf.contains('low') ? 'bassa' : 'media';
  }
  return PhotoEstimate(
    dish: (_pick(m, ['piatto', 'dish', 'nome_piatto']) ?? 'Piatto').toString(),
    confidence: conf,
    note: (_pick(m, ['note', 'nota', 'notes']) ?? '').toString(),
    items: items,
  );
}

// ------------------------------------------------------------------ API

const _base = 'https://generativelanguage.googleapis.com/v1beta';

Future<PhotoEstimate> analyzeWithGemini({
  required String apiKey,
  required String model,
  required Uint8List jpeg,
  String extra = '',
}) async {
  final text = await _generate(apiKey, model, [
    {'text': geminiPrompt(extra)},
    {
      'inlineData': {'mimeType': 'image/jpeg', 'data': base64Encode(jpeg)}
    },
  ], json: true);
  try {
    return parseEstimate(text);
  } on FormatException catch (e) {
    throw GeminiException(e.message);
  }
}

/// Verifica chiave e modello con una richiesta minima.
Future<String> testGemini(String apiKey, String model) async {
  final t = await _generate(apiKey, model, [
    {'text': 'Rispondi solo con la parola: ok'}
  ]);
  return t.trim();
}

Future<String> _generate(String apiKey, String model, List<Map<String, dynamic>> parts, {bool json = false}) async {
  if (apiKey.trim().isEmpty) throw const GeminiException('Manca la chiave API di Gemini (Profilo → Foto con Gemini).');
  final body = jsonEncode({
    'contents': [
      {'role': 'user', 'parts': parts}
    ],
    'generationConfig': {
      'temperature': 0.2,
      if (json) 'responseMimeType': 'application/json',
    },
  });
  Future<http.Response> call(String m) => http
      .post(Uri.parse('$_base/models/$m:generateContent'),
          headers: {'Content-Type': 'application/json', 'x-goog-api-key': apiKey.trim()}, body: body)
      .timeout(const Duration(seconds: 90));
  http.Response r;
  try {
    r = await call(model);
    if (r.statusCode == 404) {
      final alt = await latestFlashModel(apiKey);
      if (alt != null && alt != model) r = await call(alt);
    }
  } on TimeoutException {
    throw const GeminiException('Gemini non ha risposto in tempo. Controlla la connessione e riprova.');
  } catch (e) {
    throw GeminiException('Connessione a Gemini non riuscita: $e');
  }
  if (r.statusCode != 200) {
    String msg = '';
    try {
      msg = ((jsonDecode(r.body) as Map)['error'] as Map?)?['message']?.toString() ?? '';
    } catch (_) {}
    throw GeminiException(switch (r.statusCode) {
      400 when msg.toLowerCase().contains('api key') => 'La chiave API non è valida. Controllala in Profilo → Foto con Gemini.',
      403 => 'La chiave API non ha i permessi per Gemini ($msg).',
      429 => 'Hai superato il limite gratuito di Gemini per ora. Riprova tra poco o usa la modalità copia-incolla.',
      _ => 'Errore Gemini ${r.statusCode}${msg.isEmpty ? '' : ': $msg'}',
    });
  }
  final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map;
  final cands = j['candidates'] as List?;
  if (cands == null || cands.isEmpty) {
    final block = (j['promptFeedback'] as Map?)?['blockReason'];
    throw GeminiException(block != null ? 'Gemini ha bloccato la richiesta ($block).' : 'Gemini non ha restituito risposte.');
  }
  final ps = ((cands.first as Map)['content'] as Map?)?['parts'] as List? ?? const [];
  return ps.map((p) => (p as Map)['text'] ?? '').join();
}

/// Trova il modello Flash più recente disponibile per la chiave.
Future<String?> latestFlashModel(String apiKey) async {
  try {
    final r = await http.get(Uri.parse('$_base/models?pageSize=200'), headers: {'x-goog-api-key': apiKey.trim()}).timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) return null;
    final models = ((jsonDecode(r.body) as Map)['models'] as List? ?? const []).cast<Map>();
    final names = <String>[];
    for (final m in models) {
      final name = (m['name'] as String? ?? '').replaceFirst('models/', '');
      final methods = (m['supportedGenerationMethods'] as List? ?? const []).cast<String>();
      if (!methods.contains('generateContent')) continue;
      if (!name.contains('flash')) continue;
      if (RegExp(r'lite|image|tts|live|audio|preview|exp|embedding').hasMatch(name)) continue;
      names.add(name);
    }
    if (names.isEmpty) return null;
    double ver(String n) => double.tryParse(RegExp(r'(\d+(\.\d+)?)').firstMatch(n)?.group(1) ?? '0') ?? 0;
    names.sort((a, b) => ver(b).compareTo(ver(a)));
    return names.first;
  } catch (_) {
    return null;
  }
}
