import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/ids.dart';
import '../data/local_prefs.dart';

class UpdateInfo {
  final String version;
  final String pageUrl;
  final String? downloadUrl;
  final String notes;
  const UpdateInfo(this.version, this.pageUrl, this.downloadUrl, this.notes);

  Map<String, dynamic> toMap() => {'version': version, 'page': pageUrl, 'download': downloadUrl, 'notes': notes};
  static UpdateInfo? fromMap(Map<String, dynamic>? m) =>
      m == null ? null : UpdateInfo(m['version'] as String, m['page'] as String, m['download'] as String?, (m['notes'] as String?) ?? '');
}

/// true se [a] è più recente di [b] ("1.2.0" > "1.1.9").
bool isNewer(String a, String b) {
  List<int> parse(String v) => v.replaceFirst(RegExp(r'^[vV]'), '').split(RegExp(r'[.+-]')).map((e) => int.tryParse(e) ?? 0).toList();
  final x = parse(a), y = parse(b);
  for (var i = 0; i < 3; i++) {
    final xi = i < x.length ? x[i] : 0, yi = i < y.length ? y[i] : 0;
    if (xi != yi) return xi > yi;
  }
  return false;
}

/// Controlla l'ultima release su GitHub (al massimo ogni 12 ore).
Future<UpdateInfo?> checkForUpdate(LocalPrefs prefs, {bool force = false}) async {
  final now = DateTime.now().millisecondsSinceEpoch;
  if (!force && now - prefs.lastUpdateCheck < 12 * 3600 * 1000) {
    final cached = UpdateInfo.fromMap(prefs.availableUpdate);
    return cached != null && isNewer(cached.version, appVersion) ? cached : null;
  }
  try {
    final r = await http.get(Uri.parse('https://api.github.com/repos/$githubRepo/releases/latest'), headers: {
      'Accept': 'application/vnd.github+json',
      'User-Agent': 'Tigert/$appVersion',
    }).timeout(const Duration(seconds: 15));
    prefs.lastUpdateCheck = now;
    if (r.statusCode != 200) return null;
    final j = jsonDecode(r.body) as Map;
    final tag = (j['tag_name'] as String? ?? '').replaceFirst(RegExp(r'^[vV]'), '');
    if (tag.isEmpty || !isNewer(tag, appVersion)) {
      prefs.availableUpdate = null;
      return null;
    }
    String? dl;
    for (final a in (j['assets'] as List? ?? const [])) {
      final name = ((a as Map)['name'] as String? ?? '').toLowerCase();
      if ((isAndroid && name.endsWith('.apk')) || (isWindows && name.endsWith('.exe'))) {
        dl = a['browser_download_url'] as String?;
        break;
      }
    }
    final info = UpdateInfo(tag, j['html_url'] as String? ?? 'https://github.com/$githubRepo/releases', dl, (j['body'] as String? ?? '').trim());
    prefs.availableUpdate = info.toMap();
    return info;
  } catch (_) {
    return null;
  }
}
