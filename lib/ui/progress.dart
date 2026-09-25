import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/fmt.dart';
import '../core/ids.dart';
import '../core/theme.dart';
import '../data/app_state.dart';
import '../data/models.dart';
import '../logic/nutrition.dart';
import '../logic/training.dart';
import '../services/files.dart';
import 'achievements_screen.dart';
import 'charts.dart';
import 'shell.dart';
import 'week_report.dart';
import 'help.dart';
import 'widgets.dart';

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});
  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  int range = 90; // giorni, 0 = tutto

  Future<void> _addPhoto() async {
    final app = context.appRead;
    bool? camera = false;
    if (isMobile) {
      camera = await showModalBottomSheet<bool>(
        context: context,
        builder: (c) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(leading: const Icon(Icons.photo_camera_rounded), title: const Text('Scatta una foto'), onTap: () => Navigator.pop(c, true)),
            ListTile(leading: const Icon(Icons.photo_library_rounded), title: const Text('Scegli dalla galleria'), onTap: () => Navigator.pop(c, false)),
          ]),
        ),
      );
      if (camera == null) return;
    }
    final bytes = await pickPhoto(camera: camera);
    if (bytes == null) return;
    await app.addPhoto(bytes, date: todayKey());
    if (mounted) toast(context, 'Foto salvata');
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final p = app.profile!;
    final ws = app.weightStats;
    final now = today();
    final from = range == 0 ? DateTime(2000) : now.subtract(Duration(days: range));
    final pts = [
      for (final w in ws.entries)
        if (!fromKey(w.date).isBefore(from)) (fromKey(w.date), w.kg),
    ];
    final avg = [for (final (d, _) in pts) (d, ws.avg(d) ?? 0)];
    (DateTime, double, DateTime, double)? traj;
    if (p.goal != Goal.maintain && pts.isNotEmpty) {
      final start = fromKey(p.startDate).isBefore(pts.first.$1) ? pts.first.$1 : fromKey(p.startDate);
      final startW = ws.avg(start) ?? p.startWeight;
      final dir = p.goal == Goal.bulk ? 1 : -1;
      final weeks = (p.targetWeight - startW).abs() / math.max(0.05, p.rate);
      final endByGoal = start.add(Duration(days: (weeks * 7).round()));
      final end = endByGoal.isAfter(now.add(const Duration(days: 21))) ? now.add(const Duration(days: 21)) : endByGoal;
      final endW = startW + dir * p.rate * daysBetween(start, end) / 7;
      traj = (start, startW, end, endW);
    }
    final trend = ws.trend;
    final eta = trend == null ? null : goalEta(p, trend);
    final tdee = realTdee(totalsByDate: app.totalsByDate, weights: ws);
    final missing = tdeeDaysMissing(app.totalsByDate);
    final bests = bestByExercise(app);
    final photos = app.photos;

    return PageBody(children: [
      Row(children: [
        Expanded(child: Text('Progressi', style: TS.h1(t).copyWith(fontSize: 24))),
        SmallButton('🏆 Traguardi', onTap: () => push(context, const AchievementsScreen())),
      ]),
      const SizedBox(height: 14),
      TCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Peso · media 7 gg', style: TS.muted(t, 12)),
                Text(trend == null ? '—' : '${fDec(trend, 1)} kg', style: TS.num(t, 32)),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('Obiettivo', style: TS.muted(t, 12)),
              Text(
                p.goal == Goal.maintain ? 'Stabile' : '${fKg(p.targetWeight)} kg${eta == null ? '' : ' · ${mesiBrevi[eta.month - 1]}'}',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: t.accentInk),
              ),
            ]),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 6, children: [
            for (final (d, l) in const [(30, '1M'), (90, '3M'), (180, '6M'), (0, 'Tutto')]) PillChip(l, selected: range == d, onTap: () => setState(() => range = d)),
          ]),
          const SizedBox(height: 12),
          WeightChart(points: pts, avg: avg, trajectory: traj),
          const SizedBox(height: 8),
          Wrap(spacing: 14, children: [
            Text('● pesate', style: TS.muted(t, 11)),
            Text('— media 7 gg', style: TextStyle(fontSize: 11, color: t.ink)),
            if (traj != null) Text('- - traiettoria ${fSigned(p.goal == Goal.bulk ? p.rate : -p.rate, 2)} kg/sett', style: TextStyle(fontSize: 11, color: t.accentInk)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: SmallButton('Registra peso', accent: true, onTap: () async {
                final v = await askNumber(context, title: 'Peso di oggi', initial: app.weightOn(todayKey()) ?? app.latestWeight, unit: 'kg', decimals: 2, min: 30, max: 300);
                if (v != null) app.setWeight(todayKey(), double.parse(v.toStringAsFixed(2)));
              }),
            ),
            const SizedBox(width: 8),
            Expanded(child: SmallButton('Storico pesate', onTap: () => push(context, const WeightHistoryScreen()))),
          ]),
        ]),
      ),
      const SizedBox(height: 12),
      TCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Label(tdee == null ? 'TDEE reale' : 'TDEE reale · ${tdee.days} giorni di dati')),
            const HelpDot(helpTdee),
          ]),
          const SizedBox(height: 4),
          if (tdee == null) ...[
            Text('In arrivo', style: TS.num(t, 28, color: t.dim)),
            const SizedBox(height: 4),
            Text(
              missing > 0
                  ? 'Servono ancora $missing giorni con i pasti registrati e qualche pesata: poi calcolo quanto consumi davvero.'
                  : 'Servono almeno 4 pesate in 10 giorni per stimare l\'andamento del peso.',
              style: TS.soft(t, 13),
            ),
          ] else ...[
            Text('${fInt(tdee.tdee)} kcal', style: TS.num(t, 32)),
            const SizedBox(height: 4),
            Text.rich(TextSpan(style: TS.soft(t, 13), children: [
              TextSpan(text: 'Media assunta ${fInt(tdee.avgIntake)} kcal, peso ${fSigned(tdee.slopePerWeek, 2)} kg/sett. '),
              TextSpan(text: 'Il tuo ${tdee.balance >= 0 ? 'surplus' : 'deficit'} reale è '),
              TextSpan(text: '${tdee.balance >= 0 ? '+' : '−'}${fInt(tdee.balance.abs())} kcal', style: TextStyle(fontWeight: FontWeight.w800, color: t.accentInk)),
              TextSpan(text: _verdict(p, tdee)),
            ])),
          ],
        ]),
      ),
      const SizedBox(height: 12),
      const MusclesCard(),
      const SectionLabel('Record per esercizio', trailing: HelpDot(help1rm)),
      if (bests.isEmpty) Text('Completa qualche sessione: qui vedrai i tuoi massimali stimati e come crescono.', style: TS.muted(t)),
      for (final b in bests.take(12))
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: RowTile(
            title: b.name,
            subtitle: b.best.kg > 0 ? '${fKg(b.best.kg)} kg × ${b.best.reps} · 1RM stimato ${fDec(b.e1rm, 1)} kg · ${shortDate(fromKey(b.date))}' : '${b.best.reps} ripetizioni · ${shortDate(fromKey(b.date))}',
            onTap: () => push(context, ExerciseHistoryScreen(exId: b.exId)),
            trailing: b.pct4w == null
                ? null
                : Text('${b.pct4w! >= 0 ? '+' : '−'}${fDec(b.pct4w!.abs(), 1)}%',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: b.pct4w! >= 0 ? t.accentInk : TC.danger, fontFeatures: tabular)),
          ),
        ),
      SectionLabel('Foto progresso', trailing: photos.length >= 2 ? Tap(onTap: () => push(context, const PhotoCompareScreen()), radius: 6, child: Text('Confronta ›', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: t.accentInk))) : null),
      SizedBox(
        height: 132,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          _AddPhotoTile(onTap: _addPhoto),
          for (final ph in photos.reversed) ...[const SizedBox(width: 10), _PhotoThumb(photo: ph)],
        ]),
      ),
      const SizedBox(height: 6),
      Text('Le foto restano sui tuoi dispositivi (e passano al PC con la sincronizzazione Wi-Fi).', style: TS.muted(t, 11.5)),
    ]);
  }

  String _verdict(Profile p, TdeeEstimate e) {
    final b = e.balance;
    return switch (p.goal) {
      Goal.bulk => b > 150 ? ': in linea con la massa.' : ': troppo poco per crescere, alza un po\' le calorie.',
      Goal.cut => b < -200 ? ': in linea con la definizione.' : ': il deficit è piccolo, i risultati saranno lenti.',
      Goal.maintain => b.abs() < 150 ? ': sei in equilibrio.' : '.',
    };
  }
}

class _AddPhotoTile extends StatelessWidget {
  final VoidCallback onTap;
  const _AddPhotoTile({required this.onTap});
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    return Material(
      color: t.surf2,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(
          width: 100,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.add_a_photo_rounded, color: t.accentInk),
            const SizedBox(height: 6),
            Text('Aggiungi', style: TS.muted(t, 12)),
          ]),
        ),
      ),
    );
  }
}

class _PhotoThumb extends StatelessWidget {
  final ProgressPhoto photo;
  const _PhotoThumb({required this.photo});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final has = app.store.hasBlob(photo.blob);
    return GestureDetector(
      onTap: () => push(context, PhotoViewScreen(photo: photo)),
      child: Container(
        width: 100,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: t.surf2, borderRadius: BorderRadius.circular(14)),
        child: Stack(fit: StackFit.expand, children: [
          if (has) Image.file(app.store.blobFile(photo.blob), fit: BoxFit.cover, cacheWidth: 300) else Center(child: Icon(Icons.cloud_sync_rounded, color: t.dim)),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 4),
              color: Colors.black.withValues(alpha: 0.45),
              child: Text(shortDate(fromKey(photo.date)), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600)),
            ),
          ),
        ]),
      ),
    );
  }
}

class PhotoViewScreen extends StatelessWidget {
  final ProgressPhoto photo;
  const PhotoViewScreen({super.key, required this.photo});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final w = app.weightOn(photo.date);
    return SubPage(
      title: '${shortDateY(fromKey(photo.date))}${w != null ? ' · ${fDec(w, 1)} kg' : ''}',
      actions: [
        IconButton(
          icon: const Icon(Icons.delete_outline_rounded),
          onPressed: () async {
            if (await confirm(context, title: 'Eliminare la foto?', body: 'Verrà rimossa anche dagli altri dispositivi sincronizzati.', ok: 'Elimina', danger: true)) {
              app.deletePhoto(photo.id);
              if (context.mounted) Navigator.pop(context);
            }
          },
        ),
      ],
      body: Center(
        child: app.store.hasBlob(photo.blob)
            ? InteractiveViewer(child: Image.file(app.store.blobFile(photo.blob)))
            : const Text('Foto non ancora arrivata su questo dispositivo: sincronizza col PC.'),
      ),
    );
  }
}

class PhotoCompareScreen extends StatefulWidget {
  const PhotoCompareScreen({super.key});
  @override
  State<PhotoCompareScreen> createState() => _PhotoCompareScreenState();
}

class _PhotoCompareScreenState extends State<PhotoCompareScreen> {
  int? a, b;
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final ph = app.photos;
    final ia = (a ?? 0).clamp(0, ph.length - 1), ib = (b ?? ph.length - 1).clamp(0, ph.length - 1);
    Widget side(int i, ValueChanged<int> set) {
      final x = ph[i];
      final w = app.weightOn(x.date);
      return Expanded(
        child: Column(children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: app.store.hasBlob(x.blob) ? Image.file(app.store.blobFile(x.blob), fit: BoxFit.cover, width: double.infinity) : Container(color: t.surf2),
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            SmallButton('‹', onTap: i > 0 ? () => set(i - 1) : null),
            Expanded(child: Text('${shortDateY(fromKey(x.date))}${w != null ? '\n${fDec(w, 1)} kg' : ''}', textAlign: TextAlign.center, style: TS.muted(t, 12))),
            SmallButton('›', onTap: i < ph.length - 1 ? () => set(i + 1) : null),
          ]),
        ]),
      );
    }

    return SubPage(
      title: 'Confronta foto',
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          side(ia, (v) => setState(() => a = v)),
          const SizedBox(width: 12),
          side(ib, (v) => setState(() => b = v)),
        ]),
      ),
    );
  }
}

class WeightHistoryScreen extends StatelessWidget {
  const WeightHistoryScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final list = app.weights.reversed.toList();
    return SubPage(
      title: 'Storico pesate',
      bottom: BottomActions(children: [
        PrimaryButton('Aggiungi pesata', onTap: () async {
          final d = await showDatePicker(context: context, initialDate: today(), firstDate: DateTime(2020), lastDate: today());
          if (d == null || !context.mounted) return;
          final v = await askNumber(context, title: 'Peso del ${shortDate(d)}', initial: app.latestWeight, unit: 'kg', decimals: 2, min: 30, max: 300);
          if (v != null) app.setWeight(dayKey(d), double.parse(v.toStringAsFixed(2)));
        }),
      ]),
      body: PageBody(children: [
        if (list.isEmpty) const EmptyState(emoji: '⚖️', title: 'Nessuna pesata', body: 'Pesati al mattino, a digiuno: la media dei 7 giorni fa il resto.'),
        for (var i = 0; i < list.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: SwipeToDelete(
              id: list[i].date,
              onDelete: () {
                final w = list[i];
                app.deleteWeight(w.date);
                toast(context, 'Pesata eliminata', action: 'Annulla', onAction: () => app.setWeight(w.date, w.kg));
              },
              child: RowTile(
              title: '${fKg(list[i].kg)} kg',
              subtitle: longDate(fromKey(list[i].date)),
              trailing: i + 1 < list.length
                  ? Text(fSigned(list[i].kg - list[i + 1].kg, 1), style: TextStyle(fontSize: 12.5, color: t.dim, fontFeatures: tabular))
                  : null,
              onTap: () async {
                final v = await askNumber(context, title: 'Peso del ${shortDate(fromKey(list[i].date))}', initial: list[i].kg, unit: 'kg', decimals: 2, min: 30, max: 300);
                if (v != null) app.setWeight(list[i].date, double.parse(v.toStringAsFixed(2)));
              },
              onLongPress: () async {
                if (await confirm(context, title: 'Eliminare la pesata?', body: '${fKg(list[i].kg)} kg del ${shortDate(fromKey(list[i].date))}', ok: 'Elimina', danger: true)) {
                  app.deleteWeight(list[i].date);
                }
              },
            ),
            ),
          ),
        if (list.isNotEmpty) Text('Tocca per modificare, scorri a sinistra per eliminare.', style: TS.muted(t, 12)),
      ]),
    );
  }
}

class ExerciseHistoryScreen extends StatelessWidget {
  final String exId;
  const ExerciseHistoryScreen({super.key, required this.exId});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final hist = exerciseHistory(app, exId);
    final ex = app.exercise(exId);
    final vals = hist.map((h) => h.$2.kg > 0 ? h.$2.e1rm : h.$2.reps.toDouble()).toList();
    return SubPage(
      title: ex?.name ?? 'Esercizio',
      body: PageBody(children: [
        TCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Label(hist.isNotEmpty && hist.first.$2.kg > 0 ? '1RM stimato per sessione' : 'Ripetizioni migliori per sessione'),
            const SizedBox(height: 10),
            MiniLine(values: vals.length > 30 ? vals.sublist(vals.length - 30) : vals),
          ]),
        ),
        const SectionLabel('Sessioni'),
        for (final (s, set) in hist.reversed)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: RowTile(
              title: set.kg > 0 ? '${fKg(set.kg)} kg × ${set.reps}' : '${set.reps} ${ex?.repsLabel ?? 'rip'}',
              subtitle: '${shortDateY(fromKey(s.date))} · ${s.name}${set.rpe != null ? ' · RPE ${fDec(set.rpe!, 1, true)}' : ''}',
              trailing: set.kg > 0 ? Text('1RM ${fDec(set.e1rm, 1)}', style: TS.muted(t, 12)) : null,
            ),
          ),
      ]),
    );
  }
}
