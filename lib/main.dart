import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'app.dart';
import 'core/ids.dart';
import 'data/app_state.dart';
import 'data/catalog.dart';
import 'data/local_prefs.dart';
import 'data/store.dart';
import 'services/desktop.dart';
import 'services/notifications.dart';
import 'services/resume_guard.dart';
import 'services/services.dart';
import 'services/sync.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  if (isDesktop) {
    // Se Tigert è già aperto (anche nel tray) mostro quella finestra ed esco.
    if (!await DesktopService.ensureSingleInstance()) exit(0);
    await DesktopService.initWindow(hidden: args.contains('--tray'));
  }

  final store = Store();
  await store.init();
  final prefs = LocalPrefs();
  await prefs.init(store.root);
  final catalog = await Catalog.load();
  final app = AppState(store, prefs, catalog);

  final sync = SyncService(app);
  final notif = NotificationService(app);
  Services.app = app;
  Services.sync = sync;
  Services.notif = notif;

  store.onLocalChange = () {
    sync.onLocalChange();
    notif.reschedule();
  };

  await notif.init();

  if (isDesktop) {
    final d = DesktopService(
      app,
      onSyncNow: () async {
        if (sync.paired) await sync.syncNow();
      },
      onQuit: () async {
        await store.flush();
        await sync.stopServer();
      },
    );
    Services.desktop = d;
    await d.init();
    installResumeGuard();
    if (prefs.serverEnabled) unawaited(sync.startServer());
  }

  if (sync.paired) {
    sync.startAuto();
    unawaited(sync.syncNow(quiet: true));
  }
  notif.reschedule(delay: const Duration(seconds: 3));

  runApp(TigertApp(app: app));
}
