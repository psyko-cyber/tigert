import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/ids.dart';
import '../data/app_state.dart';

/// Sincronizzazione PC ↔ telefono sulla rete di casa, senza cloud.
///
/// Il PC espone un piccolo server HTTP (porta 47800) e risponde agli annunci
/// UDP (porta 47801). Il telefono si abbina leggendo un QR con indirizzi e
/// chiave, poi invia/riceve solo i record cambiati dall'ultima volta.
class SyncService extends ChangeNotifier {
  static const port = 47800;
  static const discoveryPort = 47801;
  static const _keyAlphabet = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';

  final AppState app;
  SyncService(this.app);

  // ================================================================ server (PC)

  HttpServer? _server;
  RawDatagramSocket? _udp;
  String? serverError;
  List<String> localIps = [];
  DateTime? lastServed;

  bool get serverRunning => _server != null;

  String get serverKey {
    var k = app.prefs.serverKey;
    if (k == null || k.length < 12) {
      k = randomString(12, _keyAlphabet);
      app.prefs.serverKey = k;
    }
    return k;
  }

  static String keyTag(String key) {
    var h = 0x811c9dc5;
    for (final c in key.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xffffffff;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }

  static String prettyKey(String k) =>
      k.length == 12 ? '${k.substring(0, 4)}-${k.substring(4, 8)}-${k.substring(8)}' : k;

  Future<void> startServer() async {
    if (_server != null) return;
    serverError = null;
    final key = serverKey;
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      _server!.listen(_handle, onError: (Object e) => debugPrint('sync server: $e'));
    } catch (e) {
      serverError = 'Non riesco ad aprire la porta $port (forse è già in uso da un\'altra finestra di Tigert).';
      _server = null;
      notifyListeners();
      return;
    }
    try {
      _udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, discoveryPort);
      _udp!.listen((ev) {
        if (ev != RawSocketEvent.read) return;
        final dg = _udp?.receive();
        if (dg == null) return;
        final msg = utf8.decode(dg.data, allowMalformed: true);
        if (msg == 'TIGERT?${keyTag(key)}') {
          _udp?.send(utf8.encode('TIGERT!$port'), dg.address, dg.port);
        }
      });
    } catch (e) {
      debugPrint('sync discovery non disponibile: $e');
    }
    localIps = await listLocalIps();
    notifyListeners();
  }

  Future<void> stopServer() async {
    await _server?.close(force: true);
    _server = null;
    _udp?.close();
    _udp = null;
    notifyListeners();
  }

  Future<void> regenerateKey() async {
    app.prefs.serverKey = randomString(12, _keyAlphabet);
    app.prefs.peers = {};
    if (serverRunning) {
      await stopServer();
      await startServer();
    }
    notifyListeners();
  }

  Future<void> refreshIps() async {
    localIps = await listLocalIps();
    notifyListeners();
  }

  /// Contenuto del QR di abbinamento.
  String pairingPayload() {
    final j = {'h': localIps, 'p': port, 'k': serverKey, 'n': deviceLabel(), 'id': app.store.deviceId};
    return 'tigert://pair?d=${base64Url.encode(utf8.encode(jsonEncode(j)))}';
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    try {
      final path = req.uri.path;
      res.headers.contentType = ContentType.json;
      if (path == '/tigert/hello') {
        res.write(jsonEncode({'app': 'tigert', 'v': 1, 'name': deviceLabel(), 'id': app.store.deviceId}));
        await res.close();
        return;
      }
      final auth = req.headers.value(HttpHeaders.authorizationHeader) ?? '';
      if (auth != 'Bearer $serverKey') {
        res.statusCode = HttpStatus.unauthorized;
        res.write(jsonEncode({'error': 'chiave non valida'}));
        await res.close();
        return;
      }
      if (path == '/tigert/sync' && req.method == 'POST') {
        final body = jsonDecode(await utf8.decoder.bind(req).join()) as Map;
        final since = (body['since'] as num?)?.toInt() ?? 0;
        final out = app.store.changesSince(since);
        app.store.applyRemote((body['changes'] as List?) ?? const []);
        final dev = body['device'];
        if (dev is Map && dev['id'] is String) {
          final peers = Map<String, dynamic>.from(app.prefs.peers);
          peers[dev['id'] as String] = {'name': dev['name'] ?? 'Telefono', 'at': DateTime.now().millisecondsSinceEpoch};
          app.prefs.peers = peers;
        }
        lastServed = DateTime.now();
        res.write(jsonEncode({'seq': app.store.seq, 'id': app.store.deviceId, 'changes': out, 'blobs': app.store.blobIds().toList()}));
        await res.close();
        notifyListeners();
        return;
      }
      if (path.startsWith('/tigert/blob/')) {
        final id = path.substring('/tigert/blob/'.length);
        if (!RegExp(r'^[a-z0-9]{6,40}$').hasMatch(id)) {
          res.statusCode = HttpStatus.badRequest;
          await res.close();
          return;
        }
        if (req.method == 'GET') {
          final f = app.store.blobFile(id);
          if (!f.existsSync()) {
            res.statusCode = HttpStatus.notFound;
            await res.close();
            return;
          }
          res.headers.contentType = ContentType('image', 'jpeg');
          await res.addStream(f.openRead());
          await res.close();
          return;
        }
        if (req.method == 'PUT') {
          final bytes = <int>[];
          await for (final chunk in req) {
            bytes.addAll(chunk);
            if (bytes.length > 30 * 1024 * 1024) throw Exception('file troppo grande');
          }
          await app.store.writeBlob(id, bytes);
          res.write('{}');
          await res.close();
          return;
        }
      }
      res.statusCode = HttpStatus.notFound;
      await res.close();
    } catch (e) {
      try {
        res.statusCode = HttpStatus.internalServerError;
        res.write(jsonEncode({'error': e.toString()}));
        await res.close();
      } catch (_) {}
    }
  }

  // ================================================================ client (telefono)

  bool syncing = false;
  String? lastError;
  Timer? _debounce;
  Timer? _periodic;

  bool get paired => app.prefs.pairing != null;
  DateTime? get lastSyncAt => app.prefs.lastSyncAt == 0 ? null : DateTime.fromMillisecondsSinceEpoch(app.prefs.lastSyncAt);

  /// Da chiamare dopo ogni modifica locale: sincronizza dopo qualche secondo.
  void onLocalChange() {
    if (!paired) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 4), () => syncNow(quiet: true));
  }

  void startAuto() {
    _periodic?.cancel();
    if (!paired) return;
    _periodic = Timer.periodic(const Duration(minutes: 3), (_) => syncNow(quiet: true));
  }

  void stopAuto() {
    _periodic?.cancel();
    _debounce?.cancel();
  }

  static Map<String, dynamic>? parsePairing(String raw) {
    try {
      final uri = Uri.parse(raw.trim());
      if (uri.scheme != 'tigert' || uri.host != 'pair') return null;
      final d = uri.queryParameters['d'];
      if (d == null) return null;
      final j = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(d)))) as Map;
      return {
        'hosts': ((j['h'] as List?) ?? const []).cast<String>(),
        'port': (j['p'] as num?)?.toInt() ?? port,
        'key': j['k'] as String,
        'name': (j['n'] as String?) ?? 'PC',
        'serverId': j['id'] as String?,
      };
    } catch (_) {
      return null;
    }
  }

  /// Abbina il telefono al PC e fa la prima sincronizzazione completa.
  Future<String?> pair(Map<String, dynamic> pairing) async {
    final hosts = (pairing['hosts'] as List).cast<String>();
    final p = (pairing['port'] as num?)?.toInt() ?? port;
    String? ok;
    for (final h in hosts) {
      if (await _hello(h, p) != null) {
        ok = h;
        break;
      }
    }
    ok ??= await _discover(pairing['key'] as String, p);
    if (ok == null) {
      return 'Non trovo il PC. Controlla che Tigert sia aperto sul PC con la sincronizzazione attiva e che telefono e PC siano sulla stessa rete Wi-Fi.';
    }
    app.prefs.pairing = {...pairing, 'hosts': [ok, ...hosts.where((h) => h != ok)], 'port': p};
    app.prefs.lastServerSeq = 0;
    app.prefs.lastPushedSeq = 0;
    final err = await syncNow();
    if (err != null) {
      app.prefs.pairing = null;
      return err;
    }
    startAuto();
    return null;
  }

  void unpair() {
    app.prefs.pairing = null;
    app.prefs.lastServerSeq = 0;
    app.prefs.lastPushedSeq = 0;
    stopAuto();
    notifyListeners();
  }

  /// Ritorna null se è andata bene, altrimenti il messaggio di errore.
  Future<String?> syncNow({bool quiet = false}) async {
    final pairing = app.prefs.pairing;
    if (pairing == null) return 'Nessun PC abbinato.';
    if (syncing) return null;
    syncing = true;
    if (!quiet) notifyListeners();
    try {
      final key = pairing['key'] as String;
      final p = (pairing['port'] as num?)?.toInt() ?? port;
      final hosts = ((pairing['hosts'] as List?) ?? const []).cast<String>();
      String? host;
      Map? hello;
      for (final h in hosts) {
        hello = await _hello(h, p);
        if (hello != null) {
          host = h;
          break;
        }
      }
      if (host == null) {
        host = await _discover(key, p);
        if (host != null) {
          hello = await _hello(host, p);
          app.prefs.pairing = {...pairing, 'hosts': [host, ...hosts.where((h) => h != host)]};
        }
      }
      if (host == null || hello == null) {
        throw const _SyncError('PC non raggiungibile: apri Tigert sul PC e collegati alla stessa rete Wi-Fi.');
      }
      // Il PC è stato reinstallato? Riparto da zero.
      final serverId = hello['id'] as String?;
      if (serverId != null && pairing['serverId'] != null && pairing['serverId'] != serverId) {
        app.prefs.lastServerSeq = 0;
        app.prefs.lastPushedSeq = 0;
      }
      if (serverId != null) app.prefs.pairing = {...app.prefs.pairing!, 'serverId': serverId};

      final store = app.store;
      final upTo = store.seq;
      final since = app.prefs.lastServerSeq;
      final changes = store.changesSince(app.prefs.lastPushedSeq);
      final r = await http
          .post(Uri.parse('http://$host:$p/tigert/sync'),
              headers: {'Authorization': 'Bearer $key', 'Content-Type': 'application/json'},
              body: jsonEncode({
                'since': since,
                'changes': changes,
                'device': {'id': store.deviceId, 'name': deviceLabel()},
              }))
          .timeout(const Duration(seconds: 60));
      if (r.statusCode == 401) throw const _SyncError('Il PC ha cambiato codice di abbinamento: abbina di nuovo il telefono.');
      if (r.statusCode != 200) throw _SyncError('Il PC ha risposto con errore ${r.statusCode}.');
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map;
      final remote = (j['changes'] as List?) ?? const [];
      final applied = store.applyRemote(remote);
      final newSeq = (j['seq'] as num?)?.toInt() ?? since;
      app.prefs.lastServerSeq = newSeq < since ? 0 : newSeq;
      // se nel frattempo non ho modificato nulla, non rimando indietro ciò che ho appena ricevuto
      app.prefs.lastPushedSeq = store.seq == upTo + applied ? store.seq : upTo;
      await _syncBlobs(host, p, key, ((j['blobs'] as List?) ?? const []).cast<String>().toSet());
      app.prefs.lastSyncAt = DateTime.now().millisecondsSinceEpoch;
      lastError = null;
      return null;
    } on _SyncError catch (e) {
      lastError = e.message;
      return e.message;
    } on TimeoutException {
      lastError = 'La sincronizzazione ci sta mettendo troppo: riprova.';
      return lastError;
    } catch (e) {
      lastError = 'Sincronizzazione non riuscita: $e';
      return lastError;
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  Future<void> _syncBlobs(String host, int p, String key, Set<String> remote) async {
    final store = app.store;
    final local = store.blobIds();
    final referenced = <String>{
      for (final ph in app.photos) ph.blob,
      for (final l in app.logByDate.values)
        for (final e in l)
          if (e.photoId != null) e.photoId!,
    };
    final headers = {'Authorization': 'Bearer $key'};
    for (final id in local.difference(remote)) {
      if (!referenced.contains(id)) continue;
      final bytes = await store.blobFile(id).readAsBytes();
      await http.put(Uri.parse('http://$host:$p/tigert/blob/$id'), headers: headers, body: bytes).timeout(const Duration(seconds: 60));
    }
    for (final id in referenced.difference(local)) {
      if (!remote.contains(id)) continue;
      final r = await http.get(Uri.parse('http://$host:$p/tigert/blob/$id'), headers: headers).timeout(const Duration(seconds: 60));
      if (r.statusCode == 200) await store.writeBlob(id, r.bodyBytes);
    }
  }

  Future<Map?> _hello(String host, int p) async {
    try {
      final r = await http.get(Uri.parse('http://$host:$p/tigert/hello')).timeout(const Duration(milliseconds: 2500));
      if (r.statusCode != 200) return null;
      final j = jsonDecode(r.body);
      return j is Map && j['app'] == 'tigert' ? j : null;
    } catch (_) {
      return null;
    }
  }

  /// Chiede in broadcast "chi è il PC con questa chiave?".
  Future<String?> _discover(String key, int p) async {
    RawDatagramSocket? sock;
    try {
      sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      sock.broadcastEnabled = true;
      final c = Completer<String?>();
      sock.listen((ev) {
        if (ev != RawSocketEvent.read) return;
        final dg = sock?.receive();
        if (dg == null) return;
        if (utf8.decode(dg.data, allowMalformed: true).startsWith('TIGERT!') && !c.isCompleted) c.complete(dg.address.address);
      });
      final msg = utf8.encode('TIGERT?${keyTag(key)}');
      final targets = <String>{'255.255.255.255'};
      for (final ip in await listLocalIps()) {
        final parts = ip.split('.');
        if (parts.length == 4) targets.add('${parts[0]}.${parts[1]}.${parts[2]}.255');
      }
      for (var round = 0; round < 3 && !c.isCompleted; round++) {
        for (final t in targets) {
          try {
            sock.send(msg, InternetAddress(t), discoveryPort);
          } catch (_) {}
        }
        await Future.any([c.future, Future<void>.delayed(const Duration(milliseconds: 700))]);
      }
      return c.isCompleted ? await c.future : null;
    } catch (_) {
      return null;
    } finally {
      sock?.close();
    }
  }

  @override
  void dispose() {
    stopAuto();
    stopServer();
    super.dispose();
  }
}

class _SyncError implements Exception {
  final String message;
  const _SyncError(this.message);
}

String deviceLabel() {
  try {
    final h = Platform.localHostname;
    if (isAndroid) return 'Telefono Android';
    return h.isEmpty ? 'PC' : h;
  } catch (_) {
    return isAndroid ? 'Telefono Android' : 'PC';
  }
}

Future<List<String>> listLocalIps() async {
  try {
    final ifs = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
    final out = <String>[];
    for (final i in ifs) {
      final n = i.name.toLowerCase();
      final virtual = n.contains('vethernet') || n.contains('virtual') || n.contains('vmware') || n.contains('vbox') || n.contains('wsl') || n.contains('docker');
      for (final a in i.addresses) {
        final ip = a.address;
        if (ip.startsWith('169.254.')) continue;
        if (virtual) continue;
        out.add(ip);
      }
    }
    // reti di casa prima
    out.sort((a, b) => (b.startsWith('192.168.') ? 1 : 0).compareTo(a.startsWith('192.168.') ? 1 : 0));
    return out;
  } catch (_) {
    return [];
  }
}
