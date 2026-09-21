import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../core/ids.dart';

/// Impostazioni del singolo dispositivo (NON sincronizzate):
/// tema, chiave Gemini, abbinamento Wi-Fi, avvio automatico, ecc.
class LocalPrefs extends ChangeNotifier {
  late File _file;
  Map<String, dynamic> _m = {};

  Future<void> init(Directory root) async {
    _file = File('${root.path}${Platform.pathSeparator}local.json');
    try {
      if (_file.existsSync()) _m = Map<String, dynamic>.from(jsonDecode(_file.readAsStringSync()) as Map);
    } catch (_) {
      _m = {};
    }
  }

  T? get<T>(String k) => _m[k] as T?;

  void set(String k, Object? v) {
    if (v == null) {
      _m.remove(k);
    } else {
      _m[k] = v;
    }
    _save();
    notifyListeners();
  }

  void _save() {
    try {
      final tmp = File('${_file.path}.tmp');
      tmp.writeAsStringSync(jsonEncode(_m), flush: true);
      if (_file.existsSync()) _file.deleteSync();
      tmp.renameSync(_file.path);
    } catch (e) {
      debugPrint('LocalPrefs: salvataggio fallito $e');
    }
  }

  // ---------------------------------------------------------------- tema
  ThemeMode get themeMode => switch (get<String>('theme')) {
        'dark' => ThemeMode.dark,
        'light' => ThemeMode.light,
        _ => ThemeMode.system,
      };
  set themeMode(ThemeMode m) => set('theme', switch (m) {
        ThemeMode.dark => 'dark',
        ThemeMode.light => 'light',
        _ => 'system',
      });

  // ---------------------------------------------------------------- Gemini
  String get geminiKey => get<String>('geminiKey') ?? '';
  set geminiKey(String v) => set('geminiKey', v.trim().isEmpty ? null : v.trim());
  String get geminiModel => get<String>('geminiModel') ?? 'gemini-flash-latest';
  set geminiModel(String v) => set('geminiModel', v.trim().isEmpty ? null : v.trim());

  // ---------------------------------------------------------------- sync (client)
  /// {hosts: [..], port: 47800, key: '...', name: 'PC'}
  Map<String, dynamic>? get pairing => (get<Map>('pairing'))?.cast<String, dynamic>();
  set pairing(Map<String, dynamic>? v) => set('pairing', v);
  int get lastServerSeq => get<int>('lastServerSeq') ?? 0;
  set lastServerSeq(int v) => set('lastServerSeq', v);
  int get lastPushedSeq => get<int>('lastPushedSeq') ?? 0;
  set lastPushedSeq(int v) => set('lastPushedSeq', v);
  int get lastSyncAt => get<int>('lastSyncAt') ?? 0;
  set lastSyncAt(int v) => set('lastSyncAt', v);

  // ---------------------------------------------------------------- sync (server PC)
  /// Sul PC il server di sincronizzazione è attivo di default.
  bool get serverEnabled => get<bool>('serverEnabled') ?? isDesktop;
  set serverEnabled(bool v) => set('serverEnabled', v);
  String? get serverKey => get<String>('serverKey');
  set serverKey(String? v) => set('serverKey', v);
  /// Dispositivi che si sono sincronizzati: {id: {name, at}}
  Map<String, dynamic> get peers => (get<Map>('peers') ?? {}).cast<String, dynamic>();
  set peers(Map<String, dynamic> v) => set('peers', v);

  // ---------------------------------------------------------------- desktop
  bool get trayEnabled => get<bool>('tray') ?? true;
  set trayEnabled(bool v) => set('tray', v);
  bool get closeHintShown => get<bool>('closeHint') ?? false;
  set closeHintShown(bool v) => set('closeHint', v);

  // ---------------------------------------------------------------- varie
  int get lastUpdateCheck => get<int>('lastUpdateCheck') ?? 0;
  set lastUpdateCheck(int v) => set('lastUpdateCheck', v);
  Map<String, dynamic>? get availableUpdate => (get<Map>('update'))?.cast<String, dynamic>();
  set availableUpdate(Map<String, dynamic>? v) => set('update', v);
  String? get dismissedUpdate => get<String>('dismissedUpdate');
  set dismissedUpdate(String? v) => set('dismissedUpdate', v);

  List<String> get seenBadges => (get<List>('seenBadges') ?? const []).cast<String>();
  set seenBadges(List<String> v) => set('seenBadges', v);
  bool get badgesInitialized => get<bool>('badgesInit') ?? false;
  set badgesInitialized(bool v) => set('badgesInit', v);

  /// Stato del timer di recupero (sopravvive al riavvio): fine in ms epoch.
  int? get restEndsAt => get<int>('restEndsAt');
  set restEndsAt(int? v) => set('restEndsAt', v);
}
