import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../core/fmt.dart';
import '../core/ids.dart';
import '../data/app_state.dart';

/// Backup su Google Drive, nella cartella nascosta dell'app (appDataFolder):
/// Tigert vede solo i suoi file, non il resto del Drive.
///
/// - Una copia al giorno di tutti i dati (json compresso), una per dispositivo,
///   e le ultime [keep] di ogni dispositivo. Le foto si caricano una volta sola.
/// - Il ripristino unisce il backup ai dati attuali (vince la modifica più
///   recente), come il ripristino da file.
/// - Solo sul PC: accesso nel browser con redirect su 127.0.0.1 e PKCE; il
///   client "Desktop" arriva dalla build (--dart-define-from-file, fuori dal
///   repo). Il telefono ha già tutto sul PC con la sincronizzazione Wi-Fi.
///   La versione anche per il telefono (google_sign_in) è nel branch drive-telefono.
class DriveBackup extends ChangeNotifier {
  final AppState app;
  final http.Client _http;
  DriveBackup(this.app, {http.Client? client}) : _http = client ?? http.Client();

  static const scope = 'https://www.googleapis.com/auth/drive.appdata';
  static const desktopId = String.fromEnvironment('GOOGLE_DESKTOP_ID');
  static const desktopSecret = String.fromEnvironment('GOOGLE_DESKTOP_SECRET');
  static const keep = 7;

  /// Solo su PC, con il client OAuth incluso nella build.
  static bool get available => debugAvailable ?? (isDesktop && desktopId.isNotEmpty);
  @visibleForTesting
  static bool? debugAvailable;

  String get device => isDesktop ? 'pc' : 'telefono';

  // ---------------------------------------------------------------- stato (per dispositivo)
  bool get on => app.prefs.get<bool>('driveOn') ?? false;
  String? get email => app.prefs.get<String>('driveEmail');
  DateTime? get lastBackup {
    final ms = app.prefs.get<int>('driveLast');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  int? get lastSize => app.prefs.get<int>('driveLastSize');
  String? get error => app.prefs.get<String>('driveError');
  bool busy = false;
  String? progress;

  // ---------------------------------------------------------------- accesso
  String? _access;
  int _accessExp = 0;

  /// Collega l'account: si apre il browser per l'accesso a Google.
  Future<void> connect() async {
    await _run(() async {
      _access = null;
      await _desktopLogin();
      final about = await _api((t) => _http.get(Uri.https('www.googleapis.com', '/drive/v3/about', {'fields': 'user(emailAddress)'}), headers: _h(t)));
      final mail = ((jsonDecode(about.body) as Map)['user'] as Map?)?['emailAddress'] as String?;
      app.prefs.set('driveEmail', mail);
      app.prefs.set('driveOn', true);
      app.prefs.set('driveError', null);
    });
    // su un dispositivo ancora vuoto (appena installato) niente backup: prima si ripristina
    if (on && error == null && app.hasProfile) await backupNow();
  }

  /// Scollega l'account (i backup restano sul Drive, per un eventuale ripristino).
  Future<void> disconnect() async {
    try {
      final token = app.prefs.get<String>('driveRefresh');
      if (token != null) await _http.post(Uri.https('oauth2.googleapis.com', '/revoke', {'token': token})).timeout(const Duration(seconds: 15));
    } catch (_) {}
    _access = null;
    for (final k in ['driveOn', 'driveEmail', 'driveRefresh', 'driveLast', 'driveLastSize', 'driveError']) {
      app.prefs.set(k, null);
    }
    notifyListeners();
  }

  Future<String> _token() async {
    if (_access != null && DateTime.now().millisecondsSinceEpoch < _accessExp - 60000) return _access!;
    return _desktopRefresh();
  }

  Future<void> _desktopLogin() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    try {
      final redirect = 'http://127.0.0.1:${server.port}';
      final verifier = _random(64);
      final challenge = base64Url.encode(sha256.convert(ascii.encode(verifier)).bytes).replaceAll('=', '');
      final state = _random(24);
      final url = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
        'client_id': desktopId,
        'redirect_uri': redirect,
        'response_type': 'code',
        'scope': scope,
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'access_type': 'offline',
        'prompt': 'consent',
        'state': state,
      });
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) throw const DriveError('Non riesco ad aprire il browser');
      String? code;
      try {
        await for (final req in server.timeout(const Duration(minutes: 5))) {
          final q = req.uri.queryParameters;
          if (q['state'] != state) {
            req.response.statusCode = 404;
            await req.response.close();
            continue;
          }
          final err = q['error'];
          code = q['code'];
          final ok = err == null && code != null;
          req.response
            ..statusCode = 200
            ..headers.contentType = ContentType.html
            ..write(_page(ok));
          await req.response.close();
          if (err != null) throw DriveError(err == 'access_denied' ? 'Accesso annullato' : 'Accesso non riuscito ($err)');
          break;
        }
      } on TimeoutException {
        throw const DriveError('Tempo scaduto: riprova e completa l\'accesso nel browser');
      }
      if (code == null) throw const DriveError('Accesso non completato');
      final r = await _http.post(Uri.https('oauth2.googleapis.com', '/token'), body: {
        'code': code,
        'client_id': desktopId,
        'client_secret': desktopSecret,
        'redirect_uri': redirect,
        'grant_type': 'authorization_code',
        'code_verifier': verifier,
      }).timeout(const Duration(seconds: 30));
      final j = jsonDecode(r.body) as Map;
      if (r.statusCode != 200 || j['refresh_token'] == null) throw DriveError('Accesso non riuscito: ${j['error_description'] ?? j['error'] ?? r.statusCode}');
      app.prefs.set('driveRefresh', j['refresh_token']);
      _setAccess(j);
    } finally {
      await server.close(force: true);
    }
  }

  Future<String> _desktopRefresh() async {
    final rt = app.prefs.get<String>('driveRefresh');
    if (rt == null) throw const DriveAuthError();
    final r = await _http.post(Uri.https('oauth2.googleapis.com', '/token'), body: {
      'client_id': desktopId,
      'client_secret': desktopSecret,
      'refresh_token': rt,
      'grant_type': 'refresh_token',
    }).timeout(const Duration(seconds: 30));
    final j = jsonDecode(r.body) as Map;
    if (r.statusCode == 400 || r.statusCode == 401) throw const DriveAuthError();
    if (r.statusCode != 200) throw DriveError('Google non risponde (${r.statusCode})');
    return _setAccess(j);
  }

  String _setAccess(Map j) {
    _access = j['access_token'] as String;
    _accessExp = DateTime.now().millisecondsSinceEpoch + ((j['expires_in'] as num?)?.toInt() ?? 3600) * 1000;
    return _access!;
  }

  // ---------------------------------------------------------------- Drive
  Map<String, String> _h(String token) => {'Authorization': 'Bearer $token'};

  /// Chiamata all'API con il token; se Google lo rifiuta ne prende uno nuovo e riprova una volta.
  Future<http.Response> _api(Future<http.Response> Function(String token) call) async {
    for (var attempt = 0;; attempt++) {
      final t = await _token();
      final r = await call(t).timeout(const Duration(minutes: 3));
      if (r.statusCode == 401 && attempt == 0) {
        _access = null;
        continue;
      }
      if (r.statusCode == 401) throw const DriveAuthError();
      if (r.statusCode >= 400) {
        String msg;
        try {
          msg = ((jsonDecode(r.body) as Map)['error'] as Map)['message'] as String;
        } catch (_) {
          msg = 'errore ${r.statusCode}';
        }
        throw DriveError('Google Drive: $msg');
      }
      return r;
    }
  }

  Future<List<DriveFile>> files() async {
    final out = <DriveFile>[];
    String? page;
    do {
      final r = await _api((t) => _http.get(
            Uri.https('www.googleapis.com', '/drive/v3/files', {
              'spaces': 'appDataFolder',
              'fields': 'nextPageToken,files(id,name,size,modifiedTime)',
              'pageSize': '1000',
              'pageToken': ?page,
            }),
            headers: _h(t),
          ));
      final j = jsonDecode(r.body) as Map;
      for (final f in (j['files'] as List?) ?? const []) {
        out.add(DriveFile.fromMap(f as Map));
      }
      page = j['nextPageToken'] as String?;
    } while (page != null);
    return out;
  }

  Future<String> _upload(String name, String mime, List<int> bytes) async {
    final init = await _api((t) => _http.post(
          Uri.parse('https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&fields=id'),
          headers: {..._h(t), 'Content-Type': 'application/json; charset=UTF-8', 'X-Upload-Content-Type': mime, 'X-Upload-Content-Length': '${bytes.length}'},
          body: jsonEncode({
            'name': name,
            'parents': ['appDataFolder'],
          }),
        ));
    final loc = init.headers['location'];
    if (loc == null) throw const DriveError('Google Drive non ha accettato il caricamento');
    final r = await _api((t) => _http.put(Uri.parse(loc), headers: {..._h(t), 'Content-Type': mime}, body: bytes));
    try {
      return ((jsonDecode(r.body) as Map)['id'] as String?) ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<List<int>> _download(String id) async =>
      (await _api((t) => _http.get(Uri.https('www.googleapis.com', '/drive/v3/files/$id', {'alt': 'media'}), headers: _h(t)))).bodyBytes;

  Future<void> _delete(String id) => _api((t) => _http.delete(Uri.https('www.googleapis.com', '/drive/v3/files/$id'), headers: _h(t)));

  // ---------------------------------------------------------------- backup e ripristino

  /// Backup completo: dati di oggi di questo dispositivo, foto mancanti, pulizia dei vecchi.
  Future<void> backupNow() => _run(() async {
        if (!app.hasProfile) throw const DriveError('Niente da salvare: prima crea il profilo o ripristina un backup');
        await app.store.flush();
        progress = 'Preparo i dati…';
        notifyListeners();
        final data = app.store.exportAll();
        final bytes = await compute(_pack, data);
        final name = 'tigert-${todayKey()}-$device.json.gz';
        progress = 'Carico i dati…';
        notifyListeners();
        final id = await _upload(name, 'application/gzip', bytes);

        final remote = await files();
        final names = {for (final f in remote) f.name};
        final photos = [
          for (final ph in app.photos)
            if (!names.contains(photoName(ph.blob)) && app.store.hasBlob(ph.blob)) ph.blob,
        ];
        for (final (i, blob) in photos.indexed) {
          progress = 'Carico le foto (${i + 1} di ${photos.length})…';
          notifyListeners();
          await _upload(photoName(blob), 'image/jpeg', await app.store.blobFile(blob).readAsBytes());
        }
        // per ogni giorno una sola copia di questo dispositivo, e solo le ultime [keep]
        final mine = remote.where((f) => f.isBackup && f.device == device && f.id != id).toList();
        final old = backupsToDelete(mine, today: name, keep: keep);
        for (final f in old) {
          await _delete(f.id);
        }
        app.prefs.set('driveLast', DateTime.now().millisecondsSinceEpoch);
        app.prefs.set('driveLastSize', bytes.length);
      });

  /// I backup disponibili, dal più recente.
  Future<List<DriveFile>> backups() async => (await files()).where((f) => f.isBackup).toList()..sort((a, b) => b.modified.compareTo(a.modified));

  /// Unisce il backup ai dati attuali e scarica le foto mancanti. Ritorna i record importati.
  Future<int> restore(DriveFile f) async {
    var n = 0;
    await _run(() async {
      progress = 'Scarico il backup…';
      notifyListeners();
      final bytes = await _download(f.id);
      final j = await compute(_unpack, bytes);
      if (j is! Map) throw const DriveError('Backup non valido');
      n = app.store.importAll(Map<String, dynamic>.from(j));
      final missing = [for (final ph in app.photos) if (!app.store.hasBlob(ph.blob)) ph.blob];
      if (missing.isNotEmpty) {
        final byName = {for (final x in await files()) x.name: x};
        for (final (i, blob) in missing.indexed) {
          final x = byName[photoName(blob)];
          if (x == null) continue;
          progress = 'Scarico le foto (${i + 1} di ${missing.length})…';
          notifyListeners();
          await app.store.writeBlob(blob, await _download(x.id));
        }
      }
    }, rethrowErrors: true);
    return n;
  }

  Future<void> _run(Future<void> Function() job, {bool rethrowErrors = false}) async {
    if (busy) return;
    busy = true;
    notifyListeners();
    try {
      await job();
      app.prefs.set('driveError', null);
    } catch (e) {
      final msg = e is DriveAuthError
          ? 'Accesso a Google scaduto: ricollega Google Drive'
          : e is DriveError
              ? e.message
              : (e is SocketException || e is TimeoutException || e is http.ClientException)
                  ? 'Nessuna connessione a internet'
                  : '$e';
      if (on) app.prefs.set('driveError', msg);
      if (rethrowErrors || !on) throw DriveError(msg);
    } finally {
      busy = false;
      progress = null;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------- automatico
  Timer? _timer;
  AppLifecycleListener? _life;

  /// Backup automatico: all'avvio, quando la finestra torna in primo piano e ogni ora (il PC resta acceso nel tray).
  void startAuto() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(hours: 1), (_) => maybeAuto());
    _life ??= AppLifecycleListener(onResume: maybeAuto);
    Timer(const Duration(seconds: 20), maybeAuto);
  }

  /// Fa il backup se oggi non è ancora stato fatto (o se l'ultimo tentativo è fallito da più di un'ora).
  Future<void> maybeAuto() async {
    if (!available || !on || busy || !app.hasProfile) return;
    final last = lastBackup;
    if (last != null && dayKey(last) == todayKey()) return;
    final tried = app.prefs.get<int>('driveTried') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - tried < 3600000) return;
    app.prefs.set('driveTried', now);
    try {
      await backupNow();
    } catch (_) {}
  }

  static String photoName(String blob) => 'foto-$blob.jpg';

  static String _random(int n) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final r = math.Random.secure();
    return List.generate(n, (_) => chars[r.nextInt(chars.length)]).join();
  }

  static String _page(bool ok) => '''<!DOCTYPE html>
<html lang="it"><head><meta charset="utf-8"><title>Tigert</title>
<style>body{font-family:system-ui,sans-serif;background:#0f110f;color:#f2f2ee;display:flex;align-items:center;justify-content:center;height:100vh;margin:0}
div{text-align:center;max-width:420px;padding:24px}h1{color:#c8f04a;font-size:26px}p{color:#b5b8ad;font-size:16px;line-height:1.5}</style></head>
<body><div><h1>${ok ? 'Fatto!' : 'Accesso non completato'}</h1><p>${ok ? 'Tigert è collegato a Google Drive. Puoi chiudere questa scheda e tornare all\'app.' : 'Torna su Tigert e riprova.'}</p></div></body></html>''';
}

// in un isolate a parte: con le foto e un anno di dati il json pesa qualche MB
List<int> _pack(Map<String, dynamic> data) => gzip.encode(utf8.encode(jsonEncode(data)));
Object? _unpack(List<int> bytes) => jsonDecode(utf8.decode(gzip.decode(bytes)));

/// Tra i backup di un dispositivo: quelli da cancellare. Resta una sola copia per
/// giorno (quella appena caricata è [today], già esclusa dalla lista) e al massimo [keep] giorni.
List<DriveFile> backupsToDelete(List<DriveFile> mine, {required String today, required int keep}) {
  final sorted = [...mine]..sort((a, b) => b.modified.compareTo(a.modified));
  final seen = <String>{today};
  final out = <DriveFile>[];
  for (final f in sorted) {
    if (!seen.add(f.name) || seen.length > keep) out.add(f);
  }
  return out;
}

class DriveFile {
  final String id;
  final String name;
  final int size;
  final DateTime modified;
  const DriveFile(this.id, this.name, this.size, this.modified);
  factory DriveFile.fromMap(Map m) => DriveFile(
        m['id'] as String,
        (m['name'] as String?) ?? '',
        int.tryParse('${m['size'] ?? 0}') ?? 0,
        DateTime.tryParse('${m['modifiedTime']}')?.toLocal() ?? DateTime(2000),
      );

  bool get isBackup => name.startsWith('tigert-') && name.endsWith('.json.gz');

  /// "tigert-2026-09-23-telefono.json.gz" → "telefono"
  String get device {
    final base = name.replaceAll('.json.gz', '');
    return base.length > 18 ? base.substring(18) : '';
  }

  /// Giorno del backup (dal nome).
  DateTime? get day => name.length >= 17 ? DateTime.tryParse(name.substring(7, 17)) : null;
}

class DriveError implements Exception {
  final String message;
  const DriveError(this.message);
  @override
  String toString() => message;
}

class DriveAuthError extends DriveError {
  const DriveAuthError() : super('Accesso a Google scaduto');
}
