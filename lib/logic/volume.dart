import 'dart:math' as math;

import '../core/fmt.dart';
import '../data/app_state.dart';
import '../data/models.dart';

/// Volume efficace per gruppo muscolare.
///
/// Non tutte le serie valgono uguale:
/// - **posizione**: con la fatica accumulata, ogni serie allenante già fatta
///   nella seduta toglie il 2,5% alla successiva (minimo 50%). 8 serie di
///   petto a inizio seduta valgono più di 10 di bicipiti in coda;
/// - **vicinanza al cedimento**: RPE 8 o più vale 1, RPE 7 vale 0,75, sotto 0,5;
/// - **tipo**: avvicinamento 0, dropset 0,5;
/// - **muscoli secondari**: i multiarticolari (anche a corpo libero: trazioni, dip,
///   piegamenti, squat) danno 0,5 ai muscoli che aiutano.

const mainMuscles = ['Petto', 'Dorso', 'Spalle', 'Bicipiti', 'Tricipiti', 'Quadricipiti', 'Femorali', 'Glutei'];
const minEffective = 8.0; // sotto: poco stimolo a settimana
const maxEffective = 22.0; // sopra: difficile recuperare

const _secondary = <String, Map<String, double>>{
  'Petto': {'Tricipiti': 0.5, 'Spalle': 0.5},
  'Dorso': {'Bicipiti': 0.5},
  'Spalle': {'Tricipiti': 0.5},
  'Quadricipiti': {'Glutei': 0.5},
  'Femorali': {'Glutei': 0.5},
};

/// Multiarticolari a corpo libero (tipo 'b' nel catalogo): contano i secondari come i 'c'.
const _bodyweightCompound = {
  'trazioni', 'chin-up', 'trazioni-presa-larga', 'trazioni-presa-neutra', 'trazioni-negative', 'trazioni-elastico',
  'trazioni-archer', 'trazioni-esplosive', 'muscle-up', 'muscle-up-anelli', 'rematore-inverso', 'rematore-anelli',
  'dip-petto', 'dip-anelli', 'dip-sbarra', 'push-up', 'push-up-inclinati', 'push-up-declinati', 'push-up-larghi',
  'push-up-archer', 'push-up-esplosivi', 'push-up-anelli', 'pike-push-up', 'pike-push-up-rialzato', 'hspu',
  'pseudo-planche-push-up', 'squat-corpo-libero', 'jump-squat', 'pistol-squat', 'pistol-squat-assistito', 'shrimp-squat',
  'affondi-corpo-libero', 'affondi-saltati', 'bulgarian-corpo-libero', 'cossack-squat',
};

bool isCompound(Exercise ex) => ex.type == 'c' || _bodyweightCompound.contains(ex.id);

double positionFactor(int workSetsBefore) => math.max(0.5, 1 - 0.025 * workSetsBefore);
double rpeFactor(double? rpe) => rpe == null || rpe >= 8 ? 1 : (rpe >= 7 ? 0.75 : 0.5);

/// Una serie nell'ordine in cui è stata (o sarà) fatta.
class VolSet {
  final Exercise? ex;
  final String type; // n | a | d
  final double? rpe;
  const VolSet(this.ex, this.type, this.rpe);
}

class MuscleVolume {
  final String muscle;
  double sets = 0; // serie dirette (dropset = 0,5)
  double effective = 0; // dirette + indirette, pesate
  double direct = 0; // solo la parte diretta pesata: dice quanto pesano le posizioni
  MuscleVolume(this.muscle);

  /// Quanto valgono in media le serie dirette (1 = tutte a inizio seduta e dure).
  double get quality => sets <= 0 ? 1 : direct / sets;
  bool get isMain => mainMuscles.contains(muscle);
  MuscleVolume scaled(double k) => MuscleVolume(muscle)
    ..sets = sets * k
    ..effective = effective * k
    ..direct = direct * k;
}

/// Somma il volume di più sedute: ogni seduta è la lista delle sue serie in ordine.
Map<String, MuscleVolume> muscleVolume(Iterable<List<VolSet>> sessions) {
  final out = <String, MuscleVolume>{};
  MuscleVolume of(String m) => out[m] ??= MuscleVolume(m);
  for (final sets in sessions) {
    var before = 0;
    for (final s in sets) {
      final ex = s.ex;
      if (ex == null || ex.isCardio || s.type == setWarmup) continue;
      final kind = s.type == setDrop ? 0.5 : 1.0;
      final w = kind * positionFactor(before) * rpeFactor(s.rpe);
      final m = of(ex.muscle);
      m.sets += kind;
      m.direct += w;
      m.effective += w;
      if (isCompound(ex)) {
        _secondary[ex.muscle]?.forEach((sec, k) => of(sec).effective += w * k);
      }
      if (s.type == setWork) before++;
    }
  }
  return out;
}

/// Volume previsto dalla scheda, in media a settimana (con il ciclo su più settimane
/// conta tutte le sedute e le divide per le settimane).
Map<String, MuscleVolume> planVolume(AppState s, Plan plan) {
  if (plan.days.isEmpty) return const {};
  final sessions = [
    for (final d in plan.days)
      [
        for (final it in d.items)
          for (var i = 0; i < it.sets; i++) VolSet(s.exercise(it.ex), setWork, it.rpe),
      ],
  ];
  final perWeek = (s.profile?.trainingDays.length ?? 0) > 0 ? s.profile!.trainingDays.length : (plan.days.length / plan.cycle).ceil();
  final k = perWeek / plan.days.length;
  return muscleVolume(sessions).map((m, v) => MapEntry(m, v.scaled(k)));
}

/// Volume davvero fatto negli ultimi [days] giorni, riportato a una settimana.
Map<String, MuscleVolume> recentVolume(AppState s, {int days = 14}) {
  final from = dayKey(today().subtract(Duration(days: days - 1)));
  final sessions = [
    for (final ss in s.doneSessions)
      if (ss.date.compareTo(from) >= 0)
        [
          for (final e in ss.items)
            for (final st in e.sets)
              if (st.done) VolSet(s.exercise(e.ex), st.t, st.rpe),
        ],
  ];
  return muscleVolume(sessions).map((m, v) => MapEntry(m, v.scaled(7 / days)));
}

class VolumeTip {
  final String muscle;
  final String text;
  final bool warn;
  const VolumeTip(this.muscle, this.text, {this.warn = true});
}

String _n(double v) => fDec(v, 1, true);

/// Consigli sul volume: poco o troppo stimolo, serie "sprecate" a fine seduta, squilibri.
List<VolumeTip> volumeTips(Map<String, MuscleVolume> v, {bool planned = false}) {
  final out = <VolumeTip>[];
  final perWeek = planned ? 'previste a settimana' : 'a settimana';
  final none = <String>[], low = <MuscleVolume>[], high = <MuscleVolume>[];
  for (final m in mainMuscles) {
    final x = v[m];
    if (x == null || x.effective < 0.5) {
      none.add(m);
    } else if (x.sets >= minEffective && x.quality < 0.78 && x.effective < minEffective + 2) {
      // il caso tipico: tante serie ma tutte in coda alla seduta
      out.add(VolumeTip(m,
          '$m: ${_n(x.sets)} serie $perWeek ma quasi tutte a fine seduta, in tutto valgono circa ${_n(x.effective)}. Metti un esercizio di $m tra i primi della seduta.'));
    } else if (x.effective < minEffective) {
      low.add(x);
    } else if (x.effective > maxEffective) {
      high.add(x);
    }
  }
  String list(List<MuscleVolume> l) => l.map((x) => '${x.muscle} ${_n(x.effective)}').join(' · ');
  if (low.isNotEmpty) {
    out.add(VolumeTip(low.first.muscle,
        'Poche serie efficaci $perWeek: ${list(low)}. Ne servono almeno ${fInt(minEffective + 2)}: aggiungi 2-3 serie o sposta questi esercizi prima nella seduta.'));
  }
  if (high.isNotEmpty) out.add(VolumeTip(high.first.muscle, 'Tanto volume $perWeek: ${list(high)}. Se non recuperi, togli qualche serie.'));
  if (none.isNotEmpty) out.add(VolumeTip(none.first, 'Nessuna serie $perWeek per ${none.join(', ')}.'));
  for (final (a, b) in const [('Petto', 'Dorso'), ('Quadricipiti', 'Femorali'), ('Bicipiti', 'Tricipiti')]) {
    final va = v[a]?.effective ?? 0, vb = v[b]?.effective ?? 0;
    if (va < 1 || vb < 1) continue;
    final hi = va >= vb ? a : b, lo = va >= vb ? b : a;
    final r = math.max(va, vb) / math.min(va, vb);
    if (r >= 1.8) out.add(VolumeTip(hi, '$hi riceve ${_n(r)} volte il volume di $lo: bilancia i due distretti.'));
  }
  return out;
}
