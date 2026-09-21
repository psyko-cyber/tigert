import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/fmt.dart';
import '../core/theme.dart';

// =================================================================== layout

/// Corpo pagina: colonna centrata con larghezza massima (desktop) e padding.
class PageBody extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsets padding;
  final double maxWidth;
  final ScrollController? controller;
  const PageBody({super.key, required this.children, this.padding = const EdgeInsets.fromLTRB(18, 8, 18, 28), this.maxWidth = 760, this.controller});

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: controller,
      padding: EdgeInsets.zero,
      children: [
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Padding(
              padding: padding,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
            ),
          ),
        ),
      ],
    );
  }
}

/// Barra inferiore fissa con azioni (es. "Aggiungi a pranzo").
class BottomActions extends StatelessWidget {
  final List<Widget> children;
  const BottomActions({super.key, required this.children});
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    return Container(
      decoration: BoxDecoration(
        color: t.bg,
        border: Border(top: BorderSide(color: t.line)),
      ),
      child: SafeArea(
        top: false,
        // heightFactor: nello slot bottomNavigationBar un Center "normale" occuperebbe tutta l'altezza
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
              child: Row(
                children: [
                  for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(width: 10), Expanded(child: children[i])],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Scaffold per le schermate secondarie con freccia indietro stile prototipo.
class SubPage extends StatelessWidget {
  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? bottom;
  final Widget? fab;
  const SubPage({super.key, required this.title, required this.body, this.actions, this.bottom, this.fab});

  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    return Scaffold(
      appBar: AppBar(
        leadingWidth: 64,
        leading: Navigator.canPop(context)
            ? Padding(
                padding: const EdgeInsets.only(left: 14),
                child: Center(child: BackSquare(onTap: () => Navigator.maybePop(context))),
              )
            : null,
        title: Text(
          title,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: t.ink),
        ),
        actions: actions == null ? null : [...actions!, const SizedBox(width: 8)],
      ),
      body: SafeArea(top: false, bottom: bottom == null, child: body),
      bottomNavigationBar: bottom,
      floatingActionButton: fab,
    );
  }
}

class BackSquare extends StatelessWidget {
  final VoidCallback onTap;
  const BackSquare({super.key, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    return Tap(
      onTap: onTap,
      radius: 12,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: t.surf2, borderRadius: BorderRadius.circular(12)),
        alignment: Alignment.center,
        child: Icon(Icons.chevron_left_rounded, color: t.ink, size: 26),
      ),
    );
  }
}

// =================================================================== superfici

class Tap extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double radius;
  const Tap({super.key, required this.child, this.onTap, this.onLongPress, this.radius = 14});
  @override
  Widget build(BuildContext context) {
    if (onTap == null && onLongPress == null) return child;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onTap,
        onLongPress: onLongPress,
        splashColor: TC.accent.withValues(alpha: 0.08),
        highlightColor: TC.accent.withValues(alpha: 0.05),
        child: child,
      ),
    );
  }
}

class TCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final Color? borderColor;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double radius;
  final EdgeInsets margin;
  const TCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
    this.borderColor,
    this.onTap,
    this.onLongPress,
    this.radius = 18,
    this.margin = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    return Padding(
      padding: margin,
      child: Material(
        color: color ?? t.surf,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: borderColor ?? t.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          splashColor: TC.accent.withValues(alpha: 0.06),
          highlightColor: TC.accent.withValues(alpha: 0.04),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Riga "lista" del prototipo: superficie, bordo, altezza minima 56.
class RowTile extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? borderColor;
  final TextStyle? titleStyle;
  const RowTile({super.key, this.leading, required this.title, this.subtitle, this.trailing, this.onTap, this.onLongPress, this.borderColor, this.titleStyle});

  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    return TCard(
      radius: 14,
      onTap: onTap,
      onLongPress: onLongPress,
      borderColor: borderColor,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 34),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 12)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: titleStyle ?? TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: t.ink),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(fontSize: 12, color: t.dim, fontFeatures: tabular),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 10), trailing!],
          ],
        ),
      ),
    );
  }
}

class NoteBox extends StatelessWidget {
  final Widget? child;
  final String? text;
  final EdgeInsets margin;
  final IconData? icon;
  const NoteBox({super.key, this.child, this.text, this.margin = const EdgeInsets.only(top: 12), this.icon});
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    return Container(
      margin: margin,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: t.surf2, borderRadius: BorderRadius.circular(12)),
      child: DefaultTextStyle.merge(
        style: TextStyle(fontSize: 12.5, color: t.soft, height: 1.5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (icon != null) ...[Icon(icon, size: 16, color: t.dim), const SizedBox(width: 8)],
            Expanded(child: child ?? Text(text ?? '')),
          ],
        ),
      ),
    );
  }
}

/// Card "suggerimento" con bordo lime.
class TipCard extends StatelessWidget {
  final String title;
  final Widget child;
  final EdgeInsets margin;
  const TipCard({super.key, required this.title, required this.child, this.margin = const EdgeInsets.only(top: 12)});
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    return Container(
      margin: margin,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.accentTint,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.accentLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(), style: TS.label(t, t.accentInk)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

// =================================================================== testo

class Label extends StatelessWidget {
  final String text;
  final Color? color;
  const Label(this.text, {super.key, this.color});
  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(), style: TS.label(context.tt, color));
}

class SectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionLabel(this.text, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 22, 2, 10),
      child: Row(
        children: [
          Expanded(child: Label(text)),
          ?trailing,
        ],
      ),
    );
  }
}

class BigNumber extends StatelessWidget {
  final String value;
  final String? unit;
  final double size;
  final Color? color;
  const BigNumber(this.value, {super.key, this.unit, this.size = 44, this.color});
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: value,
            style: TS.num(t, size, color: color),
          ),
          if (unit != null)
            TextSpan(
              text: ' $unit',
              style: TextStyle(fontSize: size * 0.36, color: t.dim, fontWeight: FontWeight.w600),
            ),
        ],
      ),
    );
  }
}

// =================================================================== bottoni

class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool busy;
  final bool dense;
  const PrimaryButton(this.label, {super.key, this.onTap, this.icon, this.busy = false, this.dense = false});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !busy;
    return Opacity(
      opacity: enabled || busy ? 1 : 0.45,
      child: Material(
        color: TC.accent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: enabled
              ? () {
                  HapticFeedback.lightImpact();
                  onTap!();
                }
              : null,
          splashColor: TC.accentHi.withValues(alpha: 0.5),
          child: Container(
            constraints: BoxConstraints(minHeight: dense ? 42 : 50),
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: dense ? 10 : 14),
            // heightFactor: 1 → il bottone resta alto quanto il contenuto anche con vincoli "larghi"
            child: Align(
              heightFactor: 1,
              child: busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: TC.onAccent))
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (icon != null) ...[Icon(icon, size: 19, color: TC.onAccent), const SizedBox(width: 8)],
                        Flexible(
                          child: Text(
                            label,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: dense ? 14 : 15, fontWeight: FontWeight.w700, color: TC.onAccent),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class GhostButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool dense;
  final Color? color;
  const GhostButton(this.label, {super.key, this.onTap, this.icon, this.dense = false, this.color});

  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    final c = color ?? t.soft;
    return Opacity(
      opacity: onTap == null ? 0.45 : 1,
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: color?.withValues(alpha: 0.5) ?? t.line),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            constraints: BoxConstraints(minHeight: dense ? 42 : 50),
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: dense ? 10 : 14),
            child: Align(
              heightFactor: 1,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[Icon(icon, size: 18, color: c), const SizedBox(width: 8)],
                  Flexible(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: dense ? 14 : 15, fontWeight: FontWeight.w600, color: c),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottone piccolo (es. "+ 250 ml").
class SmallButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool accent;
  final IconData? icon;
  const SmallButton(this.label, {super.key, this.onTap, this.accent = false, this.icon});
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    return Material(
      color: accent ? TC.accent : t.surf2,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[Icon(icon, size: 16, color: accent ? TC.onAccent : t.ink), const SizedBox(width: 6)],
              Text(
                label,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: accent ? TC.onAccent : t.ink, fontFeatures: tabular),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PillChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;
  const PillChip(this.label, {super.key, this.selected = false, this.onTap, this.icon});
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    return Material(
      color: selected ? TC.accent : Colors.transparent,
      shape: StadiumBorder(side: BorderSide(color: selected ? TC.accent : t.line)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 15, color: selected ? TC.onAccent : t.soft), const SizedBox(width: 5)],
              Text(
                label,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: selected ? TC.onAccent : t.soft),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PlusBadge extends StatelessWidget {
  final VoidCallback? onTap;
  const PlusBadge({super.key, this.onTap});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: TC.accent.withValues(alpha: 0.14),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.lightImpact();
                onTap!();
              },
        child: SizedBox(width: 34, height: 34, child: Icon(Icons.add_rounded, size: 20, color: context.tt.accentInk)),
      ),
    );
  }
}

// =================================================================== indicatori

class BarTrack extends StatelessWidget {
  final double pct; // 0..1 (anche > 1)
  final Color color;
  final double height;
  const BarTrack({super.key, required this.pct, required this.color, this.height = 6});
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: Container(
        height: height,
        color: t.surf2,
        child: Align(
          alignment: Alignment.centerLeft,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: pct.clamp(0, 1).toDouble()),
            duration: const Duration(milliseconds: 500),
            curve: const Cubic(.2, .8, .2, 1),
            builder: (_, v, _) => FractionallySizedBox(
              widthFactor: v,
              child: Container(
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(99)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MacroLabel extends StatelessWidget {
  final String text;
  final Color color;
  const MacroLabel(this.text, this.color, {super.key});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text(
        text,
        style: TextStyle(fontSize: 10.5, letterSpacing: 1.1, fontWeight: FontWeight.w700, color: color),
      ),
    ],
  );
}

Color scoreColor(double v) => v >= 8 ? TC.accent : (v >= 5.5 ? TC.warn : TC.danger);

/// Anello del voto (0-10).
class ScoreGauge extends StatelessWidget {
  final double value;
  final double size;
  final bool hasData;
  const ScoreGauge({super.key, required this.value, this.size = 104, this.hasData = true});
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    final col = hasData ? scoreColor(value) : t.dim;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: hasData ? value : 0),
      duration: const Duration(milliseconds: 700),
      curve: const Cubic(.2, .8, .2, 1),
      builder: (_, v, _) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(v / 10, col, t.surf2, size * 0.087),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(hasData ? fDec(value, 1) : '—', style: TS.num(t, size * 0.29)),
                Text(
                  '/ 10',
                  style: TextStyle(fontSize: size * 0.105, color: t.dim, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double frac;
  final Color color, track;
  final double stroke;
  _RingPainter(this.frac, this.color, this.track, this.stroke);
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - stroke / 2 - 1;
    final bg = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawCircle(c, r, bg);
    if (frac <= 0) return;
    final fg = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2, 2 * math.pi * frac.clamp(0, 1), false, fg);
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.frac != frac || o.color != color || o.track != track;
}

class StatusPill extends StatelessWidget {
  final String text;
  final Color? bg;
  final Color? fg;
  const StatusPill(this.text, {super.key, this.bg, this.fg});
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg ?? t.surf2, borderRadius: BorderRadius.circular(99)),
      child: Text(
        text,
        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: fg ?? t.soft),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final String emoji;
  final String title;
  final String body;
  final Widget? action;
  const EmptyState({super.key, required this.emoji, required this.title, required this.body, this.action});
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
      decoration: BoxDecoration(
        color: t.surf,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.line),
      ),
      child: Column(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 34)),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: t.ink),
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: t.dim, height: 1.45),
            ),
          ),
          if (action != null) ...[const SizedBox(height: 16), SizedBox(width: double.infinity, child: action!)],
        ],
      ),
    );
  }
}

/// Logo Tigert (marchio) colorato.
class TigertMark extends StatelessWidget {
  final double size;
  final Color? color;
  const TigertMark({super.key, this.size = 40, this.color});
  @override
  Widget build(BuildContext context) =>
      Image.asset('assets/brand/mark.png', width: size, height: size, color: color ?? TC.accent, filterQuality: FilterQuality.medium);
}

// =================================================================== dialoghi

void toast(BuildContext context, String msg, {String? action, VoidCallback? onAction}) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  m.hideCurrentSnackBar();
  m.showSnackBar(
    SnackBar(
      content: Text(msg),
      duration: const Duration(seconds: 3),
      action: action == null ? null : SnackBarAction(label: action, textColor: TC.accent, onPressed: onAction ?? () {}),
    ),
  );
}

Future<bool> confirm(BuildContext context, {required String title, required String body, String ok = 'Conferma', bool danger = false}) async {
  final t = context.tt;
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: Text('Annulla', style: TextStyle(color: t.soft)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(c, true),
          child: Text(
            ok,
            style: TextStyle(color: danger ? TC.danger : t.accentInk, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
  return r == true;
}

/// Chiede un numero con tastiera numerica.
Future<double?> askNumber(
  BuildContext context, {
  required String title,
  double? initial,
  String? unit,
  int decimals = 1,
  String? hint,
  double min = 0,
  double max = 100000,
}) async {
  final ctl = TextEditingController(text: initial == null ? '' : fDec(initial, decimals, true).replaceAll('.', ''));
  final t = context.tt;
  String? err;
  return showDialog<double>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) {
        void submit() {
          final v = parseNum(ctl.text);
          if (v == null || v < min || v > max) {
            set(() => err = 'Inserisci un valore tra ${fDec(min, decimals, true)} e ${fDec(max, decimals, true)}');
            return;
          }
          Navigator.pop(c, v);
        }

        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: ctl,
            autofocus: true,
            keyboardType: TextInputType.numberWithOptions(decimal: decimals > 0),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            style: TS.num(t, 28),
            decoration: InputDecoration(suffixText: unit, hintText: hint, errorText: err),
            onSubmitted: (_) => submit(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: Text('Annulla', style: TextStyle(color: t.soft)),
            ),
            TextButton(
              onPressed: submit,
              child: Text(
                'Salva',
                style: TextStyle(color: t.accentInk, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        );
      },
    ),
  );
}

Future<String?> askText(BuildContext context, {required String title, String initial = '', String? hint, String ok = 'Salva'}) {
  final ctl = TextEditingController(text: initial);
  final t = context.tt;
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctl,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) => Navigator.pop(c, v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: Text('Annulla', style: TextStyle(color: t.soft)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(c, ctl.text.trim()),
          child: Text(
            ok,
            style: TextStyle(color: t.accentInk, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}

Future<TimeOfDay?> askTime(BuildContext context, String hhmm) {
  final p = hhmm.split(':');
  return showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: int.tryParse(p[0]) ?? 8, minute: int.tryParse(p.length > 1 ? p[1] : '0') ?? 0),
    builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true), child: child!),
  );
}

String timeStr(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Stepper orizzontale − valore +.
class Stepper2 extends StatelessWidget {
  final String value;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final VoidCallback? onTapValue;
  final String? minusLabel;
  final String? plusLabel;
  const Stepper2({super.key, required this.value, required this.onMinus, required this.onPlus, this.onTapValue, this.minusLabel, this.plusLabel});
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    Widget b(String l, VoidCallback f) => Expanded(
      child: Material(
        color: t.surf2,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            HapticFeedback.selectionClick();
            f();
          },
          child: SizedBox(
            height: 46,
            child: Center(
              child: Text(
                l,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: t.ink, fontFeatures: tabular),
              ),
            ),
          ),
        ),
      ),
    );
    return Row(
      children: [
        b(minusLabel ?? '−', onMinus),
        Expanded(
          flex: 2,
          child: Tap(
            onTap: onTapValue,
            radius: 12,
            child: SizedBox(
              height: 46,
              child: Center(child: Text(value, style: TS.num(t, 22))),
            ),
          ),
        ),
        b(plusLabel ?? '+', onPlus),
      ],
    );
  }
}
