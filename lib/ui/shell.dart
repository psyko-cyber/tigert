import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/fmt.dart';
import '../core/theme.dart';
import '../data/app_state.dart';
import '../logic/achievements.dart';
import '../logic/nutrition.dart';
import '../services/services.dart';
import '../services/updates.dart';
import 'add_hub.dart';
import 'achievements_screen.dart';
import 'profile.dart';
import 'progress.dart';
import 'session.dart';
import 'today.dart';
import 'training.dart';
import 'widgets.dart';

Future<T?> push<T>(BuildContext context, Widget page) => Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => page));

/// Permette alle schermate di cambiare scheda (es. "Vedi allenamento").
class ShellNav {
  static final tab = ValueNotifier<int>(0);
  static void go(int i) {
    // "Oggi" toccato di nuovo mentre sei già lì: si torna al giorno corrente
    if (i == 0 && tab.value == 0) DayNav.reset();
    tab.value = i;
  }
}

/// Giorno aperto in Oggi e Aggiungi (null = oggi): si entra in una giornata
/// passata e la si modifica come se fosse oggi.
class DayNav {
  static final day = ValueNotifier<String?>(null);
  static String get key => day.value ?? todayKey();
  static bool get isToday => key == todayKey();
  static void set(String k) => day.value = k.compareTo(todayKey()) >= 0 ? null : k;
  static void reset() => day.value = null;

  /// Apre la giornata [k] nella scheda Oggi (es. dal Voto).
  static void open(BuildContext context, String k) {
    set(k);
    Navigator.of(context).popUntil((r) => r.isFirst);
    ShellNav.tab.value = 0;
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _NavItem {
  final String label;
  final IconData icon;
  final IconData iconOn;
  const _NavItem(this.label, this.icon, this.iconOn);
}

const _items = [
  _NavItem('Oggi', Icons.radio_button_checked_outlined, Icons.radio_button_checked),
  _NavItem('Allena', Icons.fitness_center_outlined, Icons.fitness_center),
  _NavItem('Aggiungi', Icons.add, Icons.add),
  _NavItem('Progressi', Icons.show_chart_rounded, Icons.show_chart_rounded),
  _NavItem('Profilo', Icons.person_outline_rounded, Icons.person_rounded),
];

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  bool _checkingBadges = false;
  DateTime? _away;

  @override
  void initState() {
    super.initState();
    ShellNav.tab.addListener(_onTab);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startup());
  }

  @override
  void dispose() {
    ShellNav.tab.removeListener(_onTab);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // dopo un quarto d'ora fuori dall'app si riparte da oggi
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.paused || s == AppLifecycleState.hidden) _away ??= DateTime.now();
    if (s == AppLifecycleState.resumed) {
      final away = _away;
      _away = null;
      if (away != null && DateTime.now().difference(away).inMinutes >= 15) DayNav.reset();
    }
  }

  void _onTab() => setState(() {});

  Future<void> _startup() async {
    final app = context.appRead;
    // Adeguamento automatico dei target ogni 2 settimane
    final p = app.profile;
    if (p != null && p.autoAdjust) {
      final adj = checkAdjustment(p, app.weightStats);
      if (adj != null) {
        app.applyKcal(adj.newKcal, adj.reason, fromAuto: true);
        if (mounted) {
          toast(context, 'Target aggiornato a ${fInt(adj.newKcal)} kcal (${adj.delta > 0 ? '+' : ''}${adj.delta})');
        }
      }
    }
    if (!app.prefs.badgesInitialized) {
      app.prefs.seenBadges = badges(app).where((b) => b.unlocked).map((b) => b.id).toList();
      app.prefs.badgesInitialized = true;
    }
    unawaited(Future.delayed(const Duration(seconds: 4), () => checkForUpdate(app.prefs)));
  }

  void _checkBadges(AppState app) {
    if (_checkingBadges || !app.prefs.badgesInitialized) return;
    final seen = app.prefs.seenBadges.toSet();
    final fresh = badges(app).where((b) => b.unlocked && !seen.contains(b.id)).toList();
    if (fresh.isEmpty) return;
    _checkingBadges = true;
    app.prefs.seenBadges = [...seen, ...fresh.map((b) => b.id)];
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      await showBadgeDialog(context, fresh);
      _checkingBadges = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final index = ShellNav.tab.value;
    _checkBadges(app);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final pages = const [TodayScreen(), TrainingScreen(), AddHubScreen(embedded: true), ProgressScreen(), ProfileScreen()];
    final body = IndexedStack(index: index, children: pages);
    final active = app.activeSession;
    final banner = active == null
        ? null
        : Material(
            color: TC.accent,
            child: InkWell(
              onTap: () => push(context, SessionScreen(sessionId: active.id)),
              child: SafeArea(
                top: false,
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  child: Row(children: [
                    const Icon(Icons.timer_outlined, color: TC.onAccent, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('Sessione in corso · ${active.name}',
                          style: const TextStyle(color: TC.onAccent, fontWeight: FontWeight.w700, fontSize: 14), overflow: TextOverflow.ellipsis),
                    ),
                    const Text('Riprendi ›', style: TextStyle(color: TC.onAccent, fontWeight: FontWeight.w800)),
                  ]),
                ),
              ),
            ),
          );

    if (wide) {
      return Scaffold(
        body: Row(children: [
          _SideNav(index: index, onTap: ShellNav.go),
          VerticalDivider(width: 1, color: t.line),
          Expanded(child: Column(children: [?banner, Expanded(child: body)])),
        ]),
      );
    }
    return Scaffold(
      body: SafeArea(bottom: false, child: body),
      bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [?banner, _BottomNav(index: index, onTap: ShellNav.go)]),
    );
  }
}

class _BottomNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  const _BottomNav({required this.index, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    return Container(
      decoration: BoxDecoration(color: t.bg, border: Border(top: BorderSide(color: t.line))),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(children: [
            for (var i = 0; i < _items.length; i++)
              Expanded(
                child: i == 2
                    ? Center(
                        child: Material(
                          color: TC.accent,
                          shape: const CircleBorder(),
                          elevation: 0,
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () {
                              HapticFeedback.lightImpact();
                              onTap(2);
                            },
                            child: const SizedBox(width: 50, height: 50, child: Icon(Icons.add_rounded, color: TC.onAccent, size: 30)),
                          ),
                        ),
                      )
                    : InkWell(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          onTap(i);
                        },
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(index == i ? _items[i].iconOn : _items[i].icon, size: 23, color: index == i ? t.accentInk : t.dim),
                          const SizedBox(height: 3),
                          Text(_items[i].label,
                              style: TextStyle(fontSize: 11, fontWeight: index == i ? FontWeight.w700 : FontWeight.w500, color: index == i ? t.ink : t.dim)),
                        ]),
                      ),
              ),
          ]),
        ),
      ),
    );
  }
}

class _SideNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  const _SideNav({required this.index, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    final app = context.app;
    return Container(
      width: 220,
      color: t.bg,
      padding: const EdgeInsets.fromLTRB(14, 22, 14, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const TigertMark(size: 34),
          const SizedBox(width: 10),
          Text('TIGERT', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 1.5, color: t.ink)),
        ]),
        const SizedBox(height: 26),
        for (var i = 0; i < _items.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Material(
              color: index == i ? (i == 2 ? TC.accent : t.surf2) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => onTap(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                  child: Row(children: [
                    i == 2 && index != 2
                        ? Container(
                            width: 24,
                            height: 24,
                            decoration: const BoxDecoration(color: TC.accent, shape: BoxShape.circle),
                            child: const Icon(Icons.add_rounded, size: 18, color: TC.onAccent),
                          )
                        : Icon(index == i ? _items[i].iconOn : _items[i].icon, size: 22, color: index == i ? (i == 2 ? TC.onAccent : t.accentInk) : t.dim),
                    const SizedBox(width: 12),
                    Text(i == 2 ? 'Aggiungi cibo' : _items[i].label,
                        style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: index == i ? FontWeight.w700 : FontWeight.w500,
                            color: index == i ? (i == 2 ? TC.onAccent : t.ink) : t.soft)),
                  ]),
                ),
              ),
            ),
          ),
        const Spacer(),
        ListenableBuilder(
          listenable: Services.sync,
          builder: (context, _) {
            final s = Services.sync;
            final on = s.serverRunning;
            return Tap(
              onTap: () => onTap(4),
              radius: 10,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(children: [
                  Icon(on ? Icons.wifi_rounded : Icons.wifi_off_rounded, size: 16, color: on ? t.accentInk : t.dim),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      on ? (s.lastServed == null ? 'Sync Wi-Fi attiva' : 'Sync ${hhmm(s.lastServed!)}') : 'Sync Wi-Fi spenta',
                      style: TextStyle(fontSize: 12, color: t.dim),
                    ),
                  ),
                ]),
              ),
            );
          },
        ),
        Tap(
          onTap: () => push(context, const AchievementsScreen()),
          radius: 10,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [
              Text('🔥', style: TextStyle(fontSize: 14, color: t.ink)),
              const SizedBox(width: 8),
              Text('Streak ${streak(app)} giorni', style: TextStyle(fontSize: 12, color: t.dim)),
            ]),
          ),
        ),
      ]),
    );
  }
}
