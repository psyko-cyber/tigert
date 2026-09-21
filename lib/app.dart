import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/fmt.dart';
import 'core/theme.dart';
import 'data/app_state.dart';
import 'services/services.dart';
import 'ui/onboarding.dart';
import 'ui/shell.dart';

class TigertApp extends StatefulWidget {
  final AppState app;
  const TigertApp({super.key, required this.app});
  @override
  State<TigertApp> createState() => _TigertAppState();
}

class _TigertAppState extends State<TigertApp> {
  late final AppLifecycleListener _life;
  String _day = todayKey();
  Timer? _midnight;

  @override
  void initState() {
    super.initState();
    _life = AppLifecycleListener(onResume: _onResume, onPause: _onPause, onHide: _onPause);
    // controllo cambio giorno anche se l'app resta aperta (tray su PC)
    _midnight = Timer.periodic(const Duration(minutes: 1), (_) => _checkDay());
  }

  void _checkDay() {
    final k = todayKey();
    if (k != _day) {
      _day = k;
      widget.app.refresh();
      Services.notif.reschedule(delay: const Duration(seconds: 2));
    }
  }

  void _onResume() {
    _checkDay();
    Services.notif.cancelRestEnd();
    if (Services.sync.paired) {
      Services.sync.startAuto();
      Services.sync.syncNow(quiet: true);
    }
  }

  void _onPause() {
    final app = widget.app;
    app.store.flush();
    Services.notif.rescheduleNow();
    final end = app.prefs.restEndsAt;
    if (end != null && end > DateTime.now().millisecondsSinceEpoch) {
      Services.notif.scheduleRestEnd(DateTime.fromMillisecondsSinceEpoch(end));
    }
  }

  @override
  void dispose() {
    _life.dispose();
    _midnight?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return AppScope(
      state: app,
      child: ListenableBuilder(
        listenable: app.prefs,
        builder: (context, _) => MaterialApp(
          title: 'Tigert',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(TT.lightT),
          darkTheme: buildTheme(TT.darkT),
          themeMode: app.prefs.themeMode,
          locale: const Locale('it', 'IT'),
          supportedLocales: const [Locale('it', 'IT')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: const _Root(),
        ),
      ),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      child: app.hasProfile ? const HomeShell(key: ValueKey('home')) : const OnboardingScreen(key: ValueKey('onb')),
    );
  }
}
