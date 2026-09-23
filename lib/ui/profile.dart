import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/fmt.dart';
import '../core/ids.dart';
import '../core/theme.dart';
import '../data/app_state.dart';
import '../data/catalog.dart';
import '../data/models.dart';
import '../logic/nutrition.dart';
import '../services/drive_backup.dart';
import '../services/services.dart';
import '../services/updates.dart';
import 'charts.dart';
import 'hevy_import.dart';
import 'plans.dart';
import 'settings/drive_settings.dart';
import 'settings/gemini_settings.dart';
import 'settings/misc_settings.dart';
import 'settings/profile_settings.dart';
import 'settings/reminders_settings.dart';
import 'settings/sync_settings.dart';
import 'shell.dart';
import 'training.dart';
import 'widgets.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final p = app.profile!;
    final plan = app.activePlan;
    final suggested = suggestTemplate(p.trainingDays.length);
    final update = UpdateInfo.fromMap(app.prefs.availableUpdate);

    Widget row(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(children: [
            Expanded(child: Text(k, style: TS.soft(t, 13))),
            Text(v, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: t.ink, fontFeatures: tabular)),
          ]),
        );

    return PageBody(children: [
      Text('Profilo', style: TS.h1(t).copyWith(fontSize: 24)),
      const SizedBox(height: 14),
      TCard(
        onTap: () => push(context, const ProfileEditScreen()),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: Label('Dati personali')),
            Icon(Icons.edit_outlined, size: 16, color: t.dim),
          ]),
          const SizedBox(height: 4),
          if (p.name.isNotEmpty) row('Nome', p.name),
          row('Età', '${p.age} anni'),
          row('Altezza', '${fDec(p.heightCm, 0)} cm'),
          row('Peso (media 7 gg)', '${fDec(app.currentWeight, 1)} kg'),
          row('Obiettivo', p.goal == Goal.maintain ? 'Mantenimento' : '${p.goal.label} · ${fKg(p.targetWeight)} kg'),
          row('Attività', activityLevels[p.activity]?.$1 ?? p.activity),
        ]),
      ),
      const SizedBox(height: 12),
      TCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Label(switch (p.goal) { Goal.bulk => 'Target · salita graduale', Goal.cut => 'Target · discesa graduale', Goal.maintain => 'Target' }),
          const SizedBox(height: 10),
          RampChart(bars: targetRamp(p)),
          const SizedBox(height: 10),
          Text(rampText(p), style: TS.soft(t, 12.5)),
          const SizedBox(height: 12),
          Row(children: [
            _TargetTile('KCAL', fInt(p.kcal), t.ink),
            _TargetTile('P', '${p.protein} g', TC.prot),
            _TargetTile('C', '${p.carbs} g', TC.carb),
            _TargetTile('G', '${p.fat} g', TC.fat),
          ]),
          const SizedBox(height: 6),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: p.autoAdjust,
            onChanged: (v) => app.saveProfile(p.copyWith(autoAdjust: v)),
            title: Text('Adeguamento automatico', style: TS.body(t)),
            subtitle: Text('Ogni 2 settimane confronta il peso reale con l\'obiettivo', style: TS.muted(t, 12)),
          ),
          SmallButton('Modifica target', onTap: () => push(context, const TargetsEditScreen())),
        ]),
      ),
      const SizedBox(height: 12),
      TCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Label('Giorni di allenamento'),
          const SizedBox(height: 10),
          Row(children: [
            for (var d = 1; d <= 7; d++) ...[
              if (d > 1) const SizedBox(width: 6),
              Expanded(
                child: Material(
                  color: p.trainingDays.contains(d) ? TC.accent : t.surf2,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      final days = {...p.trainingDays};
                      days.contains(d) ? days.remove(d) : days.add(d);
                      app.saveProfile(p.copyWith(trainingDays: days.toList()..sort()));
                    },
                    child: SizedBox(
                      height: 40,
                      child: Center(
                        child: Text(giorniBrevi[d - 1],
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.trainingDays.contains(d) ? TC.onAccent : t.dim)),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ]),
          const SizedBox(height: 10),
          Text('${p.trainingDays.length} giorni attivi · le sedute della scheda ruotano su questi giorni', style: TS.muted(t, 12)),
          if (plan != null && plan.template != suggested.key && plan.days.length != p.trainingDays.length) ...[
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: Text('Con ${p.trainingDays.length} giorni ti consiglio ${suggested.name}.', style: TS.soft(t, 12.5))),
              SmallButton('Cambia', onTap: () => chooseTemplate(context)),
            ]),
          ],
        ]),
      ),
      const SectionLabel('Impostazioni'),
      _Setting(Icons.fitness_center_rounded, 'Le mie schede', plan == null ? 'Nessuna' : '${plan.name} attiva · ${app.plans.length} in tutto',
          () => plan == null ? chooseTemplate(context) : push(context, const PlansScreen())),
      _Setting(Icons.move_to_inbox_rounded, 'Importa da Hevy', 'Storico, schede ed esercizi', () => push(context, const HevyImportScreen())),
      _Setting(Icons.notifications_none_rounded, 'Promemoria', _remindersSummary(p.reminders), () => push(context, const RemindersScreen())),
      _Setting(Icons.checklist_rounded, 'Abitudini nel voto', '${p.habits.entries.where((e) => e.value && e.key != 'supp').length} attive', () => push(context, const HabitsSettingsScreen())),
      _Setting(Icons.auto_awesome_rounded, 'Foto con Gemini', app.prefs.geminiKey.isEmpty ? 'Copia-incolla' : 'Chiave API attiva', () => push(context, const GeminiSettingsScreen())),
      ListenableBuilder(
        listenable: Services.sync,
        builder: (context, _) {
          final s = Services.sync;
          final sub = isDesktop
              ? (s.serverRunning ? 'Attiva · ${app.prefs.peers.length} dispositivi' : 'Spenta')
              : (s.paired ? (s.lastSyncAt == null ? 'Abbinato' : 'Ultima ${relDay(s.lastSyncAt!).toLowerCase()} ${hhmm(s.lastSyncAt!)}') : 'Non abbinato');
          return _Setting(Icons.wifi_rounded, 'Sincronizzazione Wi-Fi', sub, () => push(context, const SyncSettingsScreen()));
        },
      ),
      if (DriveBackup.available)
        ListenableBuilder(
          listenable: Services.drive,
          builder: (context, _) => _Setting(Icons.cloud_outlined, 'Backup su Google Drive', driveSummary(), () => push(context, const DriveSettingsScreen())),
        ),
      _Setting(Icons.dark_mode_outlined, 'Tema', switch (app.prefs.themeMode) { ThemeMode.dark => 'Scuro', ThemeMode.light => 'Chiaro', _ => 'Come il sistema' },
          () => showThemeSheet(context)),
      if (isDesktop) _Setting(Icons.desktop_windows_outlined, 'Windows', 'Avvio automatico e area di notifica', () => push(context, const DesktopSettingsScreen())),
      _Setting(Icons.straighten_rounded, 'Unità', 'kg · cm · kcal', null),
      _Setting(Icons.download_rounded, 'Esporta e backup', 'CSV, backup completo, ripristino', () => push(context, const DataSettingsScreen())),
      _Setting(
        Icons.system_update_rounded,
        'Aggiornamenti',
        update != null && isNewer(update.version, appVersion) ? 'Disponibile la ${update.version}' : 'Versione $appVersion',
        () async {
          final u = await checkForUpdate(app.prefs, force: true);
          if (!context.mounted) return;
          if (u == null) {
            toast(context, 'Hai già l\'ultima versione ($appVersion)');
          } else {
            final go = await confirm(context, title: 'Tigert ${u.version}', body: u.notes.isEmpty ? 'È disponibile una nuova versione.' : u.notes, ok: 'Scarica');
            if (go) launchUrl(Uri.parse(u.downloadUrl ?? u.pageUrl), mode: LaunchMode.externalApplication);
          }
        },
      ),
      _Setting(Icons.info_outline_rounded, 'Informazioni', 'Tigert $appVersion', () => push(context, const AboutScreen())),
    ]);
  }

  String _remindersSummary(Reminders r) {
    final n = r.meals.where((m) => m.on).length;
    final parts = [if (n > 0) 'Pasti', if (r.waterOn) 'acqua', if (r.trainingOn) 'allenamento', if (r.weightOn) 'peso'];
    return parts.isEmpty ? 'Spenti' : parts.join(' + ');
  }
}

class _TargetTile extends StatelessWidget {
  final String k, v;
  final Color c;
  const _TargetTile(this.k, this.v, this.c);
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    return Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(k, style: TextStyle(fontSize: 10.5, letterSpacing: 1.1, fontWeight: FontWeight.w700, color: c == t.ink ? t.dim : c)),
        Text(v, style: TS.num(t, 16, w: FontWeight.w700)),
      ]),
    );
  }
}

class _Setting extends StatelessWidget {
  final IconData icon;
  final String k;
  final String v;
  final VoidCallback? onTap;
  const _Setting(this.icon, this.k, this.v, this.onTap);
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: TCard(
        radius: 14,
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(children: [
          Icon(icon, size: 20, color: t.dim),
          const SizedBox(width: 12),
          Expanded(child: Text(k, style: TextStyle(fontSize: 14, color: t.ink))),
          Flexible(child: Text(v, textAlign: TextAlign.right, style: TS.muted(t, 12.5), maxLines: 1, overflow: TextOverflow.ellipsis)),
          if (onTap != null) ...[const SizedBox(width: 4), Icon(Icons.chevron_right_rounded, size: 18, color: t.dim)],
        ]),
      ),
    );
  }
}

Future<void> showThemeSheet(BuildContext context) {
  final app = context.appRead;
  return showModalBottomSheet(
    context: context,
    builder: (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (final (m, l) in const [(ThemeMode.system, 'Come il sistema'), (ThemeMode.dark, 'Scuro'), (ThemeMode.light, 'Chiaro')])
          ListTile(
            title: Text(l),
            trailing: app.prefs.themeMode == m ? const Icon(Icons.check_rounded) : null,
            onTap: () {
              app.prefs.themeMode = m;
              Navigator.pop(c);
            },
          ),
      ]),
    ),
  );
}
