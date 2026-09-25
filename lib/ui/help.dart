import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'widgets.dart';

/// Titolo e testo di una spiegazione.
typedef Help = (String, String);

const helpEffective = (
  'Serie efficaci',
  'Non tutte le serie valgono uguale:\n'
      '• ogni serie già fatta nella seduta toglie il 2,5% alle successive (minimo 50%): quelle a fine allenamento contano meno;\n'
      '• sotto RPE 8 valgono meno, i dropset mezza serie, gli avvicinamenti niente;\n'
      '• i multiarticolari (panca, trazioni, squat…) danno mezza serie anche ai muscoli che aiutano.\n\n'
      'Obiettivo: 10 serie efficaci a settimana per muscolo, cioè il 100%. Tra 8 e 22 va bene; sotto è poco, sopra è difficile recuperare.',
);

const helpRpe = (
  'RPE e tipi di serie',
  'RPE = quanto è stata dura la serie, da 1 a 10:\n'
      '10  non ne facevi un\'altra\n'
      '9  ne restava 1\n'
      '8  ne restavano 2\n'
      '7  3 o più\n'
      'Il coach lo usa per decidere quando alzare il carico. Se lo lasci vuoto, la serie conta piena.\n\n'
      'Il numero a sinistra è il tipo di serie:\n'
      '1, 2, 3…  allenanti: contano per coach, record e volume\n'
      'A  avvicinamento (riscaldamento): non conta\n'
      'D  dropset, scalata subito dopo una serie: mezza serie nel volume\n\n'
      'Tocca il numero per segnare la serie fatta, tienilo premuto per cambiarne il tipo.',
);

const helpPhase = (
  'Fase',
  'La fase non cambia le calorie da mangiare: cambia quanto puoi sgarrare prima che il voto delle calorie scenda.\n\n'
      'Voto pieno entro:\n'
      '• mantenimento ±10%\n'
      '• massa pulita −10% / +15%\n'
      '• bulk pesante −10% / +30%\n'
      '• definizione −15% / +10%\n\n'
      'Oltre, il voto cala piano fino a zero. Il cambio vale dal giorno in cui lo fai.',
);

const helpTdee = (
  'TDEE reale',
  'Le calorie che consumi davvero in un giorno, tra metabolismo, movimento e allenamento. '
      'Tigert lo ricava da quanto mangi e da come cambia il tuo peso nello stesso periodo, invece di stimarlo con una formula.\n\n'
      'Servono un paio di settimane con i pasti registrati e qualche pesata: più dati hai, più è preciso.',
);

const help1rm = (
  '1RM stimato',
  'Il massimo che potresti sollevare per una sola ripetizione, calcolato dalle tue serie: per esempio 40 kg × 10 vale circa 53 kg.\n\n'
      'Serve a confrontare serie con pesi e ripetizioni diverse: se sale, stai diventando più forte.',
);

/// "?" accanto a un termine tecnico: un tocco e lo spiega in poche righe.
class HelpDot extends StatelessWidget {
  final Help help;
  const HelpDot(this.help, {super.key});
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    return Tooltip(
      message: 'Cos\'è: ${help.$1}',
      child: InkResponse(
        radius: 18,
        onTap: () => showHelp(context, help),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Container(
            width: 17,
            height: 17,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: t.dim, width: 1.3)),
            child: Text('?', style: TextStyle(fontSize: 11, height: 1, fontWeight: FontWeight.w800, color: t.dim)),
          ),
        ),
      ),
    );
  }
}

Future<void> showHelp(BuildContext context, Help help) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) {
        final t = c.tt;
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(help.$1, style: TS.title(t)),
              const SizedBox(height: 10),
              Text(help.$2, style: TS.soft(t).copyWith(height: 1.5)),
              const SizedBox(height: 16),
              SizedBox(width: double.infinity, child: PrimaryButton('Ho capito', onTap: () => Navigator.pop(c))),
            ]),
          ),
        );
      },
    );
