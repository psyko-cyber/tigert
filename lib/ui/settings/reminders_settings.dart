import 'package:flutter/material.dart';

import '../../core/ids.dart';
import '../../core/theme.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../services/services.dart';
import '../widgets.dart';

class RemindersScreen extends StatelessWidget {
  const RemindersScreen({super.key});

  static const _waterSteps = [60, 90, 120, 180];

  void _save(BuildContext context, Reminders r) {
    final app = context.appRead;
    app.saveProfile(app.profile!.copyWith(reminders: r));
    Services.notif.rescheduleNow();
  }

  Future<String?> _time(BuildContext context, String cur) async {
    final t = await askTime(context, cur);
    return t == null ? null : timeStr(t);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    final r = context.app.profile!.reminders;
    final missing = [for (final k in mealKeys) if (!r.meals.any((m) => m.id == k)) k];

    Future<void> editMeal(int i, {String? time, bool? on}) async {
      final meals = [...r.meals];
      meals[i] = meals[i].copyWith(time: time, on: on);
      meals.sort((a, b) => a.time.compareTo(b.time));
      _save(context, r.copyWith(meals: meals));
    }

    return SubPage(
      title: 'Promemoria',
      body: PageBody(children: [
        Text(
          isAndroid
              ? 'Le notifiche arrivano anche ad app chiusa. Se hai già registrato il pasto o bevuto abbastanza, il promemoria non parte.'
              : 'Su PC i promemoria arrivano finché Tigert è aperto o nell\'area di notifica (in basso a destra).',
          style: TS.muted(t, 12.5),
        ),
        const SectionLabel('Pasti'),
        for (var i = 0; i < r.meals.length; i++)
          _ReminderRow(
            title: r.meals[i].label,
            time: r.meals[i].time,
            on: r.meals[i].on,
            onToggle: (v) => editMeal(i, on: v),
            onTime: () async {
              final v = await _time(context, r.meals[i].time);
              if (v != null) editMeal(i, time: v);
            },
            onLongPress: () async {
              if (await confirm(context, title: 'Rimuovere ${r.meals[i].label}?', body: 'Non riceverai più questo promemoria.', ok: 'Rimuovi')) {
                if (context.mounted) _save(context, r.copyWith(meals: [...r.meals]..removeAt(i)));
              }
            },
          ),
        if (missing.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final k in missing)
                PillChip('+ ${mealLabels[k]}', onTap: () {
                  const def = {'colazione': '08:00', 'spuntino': '10:30', 'pranzo': '13:00', 'merenda': '16:30', 'cena': '20:00', 'post': '19:00'};
                  final meals = [...r.meals, Reminder(k, mealLabels[k]!, def[k] ?? '12:00', true)]..sort((a, b) => a.time.compareTo(b.time));
                  _save(context, r.copyWith(meals: meals));
                }),
            ]),
          ),
        const SizedBox(height: 4),
        Text('Tieni premuto un pasto per rimuoverlo.', style: TS.muted(t, 11.5)),
        const SectionLabel('Acqua'),
        _ReminderRow(
          title: 'Promemoria acqua',
          subtitle: 'Solo se sei indietro rispetto all\'obiettivo',
          on: r.waterOn,
          onToggle: (v) => _save(context, r.copyWith(waterOn: v)),
        ),
        if (r.waterOn) ...[
          const SizedBox(height: 4),
          Row(children: [
            Text('Ogni', style: TS.soft(t)),
            const SizedBox(width: 10),
            Expanded(
              child: Wrap(spacing: 6, runSpacing: 6, children: [
                for (final m in _waterSteps)
                  PillChip(m % 60 == 0 ? '${m ~/ 60} h' : '${m ~/ 60} h ${m % 60}′', selected: r.waterEvery == m, onTap: () => _save(context, r.copyWith(waterEvery: m))),
              ]),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: _TimeBox(label: 'Dalle', time: r.waterFrom, onTap: () async {
                final v = await _time(context, r.waterFrom);
                if (v != null && context.mounted) _save(context, r.copyWith(waterFrom: v));
              }),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _TimeBox(label: 'Alle', time: r.waterTo, onTap: () async {
                final v = await _time(context, r.waterTo);
                if (v != null && context.mounted) _save(context, r.copyWith(waterTo: v));
              }),
            ),
          ]),
        ],
        const SectionLabel('Allenamento e peso'),
        _ReminderRow(
          title: 'Allenamento',
          subtitle: 'Nei giorni di allenamento, se non l\'hai ancora iniziato',
          time: r.trainingTime,
          on: r.trainingOn,
          onToggle: (v) => _save(context, r.copyWith(trainingOn: v)),
          onTime: () async {
            final v = await _time(context, r.trainingTime);
            if (v != null && context.mounted) _save(context, r.copyWith(trainingTime: v));
          },
        ),
        _ReminderRow(
          title: 'Pesata',
          subtitle: 'Al mattino, a digiuno',
          time: r.weightTime,
          on: r.weightOn,
          onToggle: (v) => _save(context, r.copyWith(weightOn: v)),
          onTime: () async {
            final v = await _time(context, r.weightTime);
            if (v != null && context.mounted) _save(context, r.copyWith(weightTime: v));
          },
        ),
        _ReminderRow(
          title: 'Riepilogo serale',
          subtitle: 'Ti dice cosa manca per chiudere bene la giornata',
          time: r.eveningTime,
          on: r.eveningOn,
          onToggle: (v) => _save(context, r.copyWith(eveningOn: v)),
          onTime: () async {
            final v = await _time(context, r.eveningTime);
            if (v != null && context.mounted) _save(context, r.copyWith(eveningTime: v));
          },
        ),
        const SizedBox(height: 16),
        GhostButton('Prova una notifica', icon: Icons.notifications_active_outlined, dense: true, onTap: () async {
          await Services.notif.requestPermission();
          await Services.notif.show('Tigert', 'Le notifiche funzionano. Ruggisci! 🐯');
        }),
      ]),
    );
  }
}

class _ReminderRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? time;
  final bool on;
  final ValueChanged<bool> onToggle;
  final VoidCallback? onTime;
  final VoidCallback? onLongPress;
  const _ReminderRow({required this.title, this.subtitle, this.time, required this.on, required this.onToggle, this.onTime, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: TCard(
        radius: 14,
        onLongPress: onLongPress,
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: on ? t.ink : t.dim)),
              if (subtitle != null) Text(subtitle!, style: TS.muted(t, 11.5)),
            ]),
          ),
          if (time != null)
            Opacity(
              opacity: on ? 1 : 0.4,
              child: SmallButton(time!, onTap: onTime),
            ),
          const SizedBox(width: 4),
          Switch(value: on, onChanged: onToggle),
        ]),
      ),
    );
  }
}

class _TimeBox extends StatelessWidget {
  final String label;
  final String time;
  final VoidCallback onTap;
  const _TimeBox({required this.label, required this.time, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    return TCard(
      radius: 12,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(children: [
        Text(label, style: TS.muted(t, 12)),
        const Spacer(),
        Text(time, style: TS.num(t, 16, w: FontWeight.w700)),
      ]),
    );
  }
}
