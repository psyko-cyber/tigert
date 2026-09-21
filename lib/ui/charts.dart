import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/fmt.dart';
import '../core/theme.dart';
import '../logic/nutrition.dart';
import 'widgets.dart';

// =================================================================== peso

class WeightChart extends StatelessWidget {
  final List<(DateTime, double)> points; // pesate
  final List<(DateTime, double)> avg; // media 7 giorni
  final (DateTime, double, DateTime, double)? trajectory; // da -> a
  final double? target;
  final double height;
  const WeightChart({super.key, required this.points, required this.avg, this.trajectory, this.target, this.height = 170});

  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    if (points.isEmpty) {
      return SizedBox(
        height: height * 0.6,
        child: Center(child: Text('Registra il peso per vedere il grafico', style: TS.muted(t))),
      );
    }
    return SizedBox(height: height, child: CustomPaint(painter: _WeightPainter(this, t), size: Size.infinite));
  }
}

class _WeightPainter extends CustomPainter {
  final WeightChart c;
  final TT t;
  _WeightPainter(this.c, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    const left = 34.0, bottom = 18.0, top = 6.0;
    final w = size.width - left, h = size.height - bottom - top;
    final xs = [...c.points.map((e) => e.$1), ...c.avg.map((e) => e.$1)];
    var x0 = xs.reduce((a, b) => a.isBefore(b) ? a : b);
    var x1 = xs.reduce((a, b) => a.isAfter(b) ? a : b);
    if (!x1.isAfter(x0)) x1 = x0.add(const Duration(days: 1));
    final ys = [...c.points.map((e) => e.$2), ...c.avg.map((e) => e.$2)];
    var y0 = ys.reduce(math.min), y1 = ys.reduce(math.max);
    final tr = c.trajectory;
    if (tr != null) {
      y0 = math.min(y0, math.min(tr.$2, tr.$4));
      y1 = math.max(y1, math.max(tr.$2, tr.$4));
    }
    final pad = math.max(0.4, (y1 - y0) * 0.12);
    y0 -= pad;
    y1 += pad;
    final span = x1.difference(x0).inHours.toDouble();
    double px(DateTime d) => left + w * (d.difference(x0).inHours / span).clamp(0.0, 1.0);
    double py(double v) => top + h * (1 - (v - y0) / (y1 - y0));

    // griglia
    final grid = Paint()
      ..color = t.line
      ..strokeWidth = 1;
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (var i = 0; i <= 3; i++) {
      final v = y0 + (y1 - y0) * i / 3;
      final y = py(v);
      canvas.drawLine(Offset(left, y), Offset(size.width, y), grid);
      tp.text = TextSpan(text: fDec(v, 1), style: TextStyle(fontSize: 10, color: t.dim, fontFamily: 'Archivo'));
      tp.layout();
      tp.paint(canvas, Offset(0, y - tp.height / 2));
    }
    for (final (d, lbl) in [(x0, shortDate(x0)), (x1, shortDate(x1))]) {
      tp.text = TextSpan(text: lbl, style: TextStyle(fontSize: 10, color: t.dim, fontFamily: 'Archivo'));
      tp.layout();
      final x = (px(d) - (d == x1 ? tp.width : 0)).clamp(left, size.width - tp.width);
      tp.paint(canvas, Offset(x, size.height - tp.height));
    }

    // traiettoria obiettivo (tratteggiata, lime)
    if (tr != null) {
      final a = Offset(px(tr.$1), py(tr.$2)), b = Offset(px(tr.$3), py(tr.$4));
      final p = Paint()
        ..color = TC.accent
        ..strokeWidth = 2;
      const dash = 6.0, gap = 5.0;
      final len = (b - a).distance;
      if (len > 0) {
        final dir = (b - a) / len;
        var s = 0.0;
        while (s < len) {
          final e = math.min(len, s + dash);
          canvas.drawLine(a + dir * s, a + dir * e, p);
          s = e + gap;
        }
      }
    }

    // pesate
    final dot = Paint()..color = t.dim.withValues(alpha: 0.8);
    for (final (d, v) in c.points) {
      canvas.drawCircle(Offset(px(d), py(v)), 2.6, dot);
    }
    // media 7 gg
    if (c.avg.length >= 2) {
      final path = Path()..moveTo(px(c.avg.first.$1), py(c.avg.first.$2));
      for (final (d, v) in c.avg.skip(1)) {
        path.lineTo(px(d), py(v));
      }
      canvas.drawPath(
          path,
          Paint()
            ..color = t.ink
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.4
            ..strokeJoin = StrokeJoin.round
            ..strokeCap = StrokeCap.round);
    }
  }

  @override
  bool shouldRepaint(covariant _WeightPainter old) => true;
}

// =================================================================== heatmap

class Heatmap extends StatelessWidget {
  final List<(DateTime, double?)> cells;
  final int columns;
  const Heatmap({super.key, required this.cells, this.columns = 14});

  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    return LayoutBuilder(builder: (context, cons) {
      const gap = 4.0;
      final size = (cons.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          // iniziali dei giorni (le celle partono sempre da un lunedì)
          for (var i = 0; i < columns; i++)
            SizedBox(
              width: size,
              child: Text('LMMGVSD'[i % 7], textAlign: TextAlign.center, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: t.dim)),
            ),
          for (final (d, v) in cells)
            Tooltip(
              message: v == null ? shortDate(d) : '${shortDate(d)} · voto ${fDec(v)}',
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: v == null ? t.surf2 : scoreColor(v).withValues(alpha: (0.35 + v / 16).clamp(0.35, 1.0)),
                  border: d == today() ? Border.all(color: t.ink, width: 1.2) : null,
                ),
              ),
            ),
        ],
      );
    });
  }
}

// =================================================================== rampa target

class RampChart extends StatelessWidget {
  final List<RampBar> bars;
  const RampChart({super.key, required this.bars});
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    final vals = bars.map((b) => b.kcal).toList();
    final lo = vals.reduce(math.min) - 150, hi = vals.reduce(math.max);
    return SizedBox(
      height: 78,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final b in bars)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Tooltip(
                  message: '${fInt(b.kcal)} kcal',
                  child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                    Container(
                      height: 14 + 44 * ((b.kcal - lo) / math.max(1, hi - lo)),
                      decoration: BoxDecoration(
                        color: b.future ? TC.accent.withValues(alpha: 0.28) : (b.current ? TC.accent : TC.accent.withValues(alpha: 0.7)),
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(b.label, style: TextStyle(fontSize: 9.5, color: b.current ? t.ink : t.dim, fontWeight: b.current ? FontWeight.w700 : FontWeight.w400)),
                  ]),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// =================================================================== linea semplice

class MiniLine extends StatelessWidget {
  final List<double> values;
  final double height;
  final Color? color;
  const MiniLine({super.key, required this.values, this.height = 90, this.color});
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    if (values.length < 2) return SizedBox(height: height * 0.5, child: Center(child: Text('Servono almeno due sessioni', style: TS.muted(t))));
    return SizedBox(height: height, child: CustomPaint(painter: _MiniPainter(values, color ?? TC.accent, t), size: Size.infinite));
  }
}

class _MiniPainter extends CustomPainter {
  final List<double> v;
  final Color color;
  final TT t;
  _MiniPainter(this.v, this.color, this.t);
  @override
  void paint(Canvas canvas, Size size) {
    final lo = v.reduce(math.min), hi = v.reduce(math.max);
    final span = math.max(0.001, hi - lo);
    Offset p(int i) => Offset(size.width * i / (v.length - 1), 6 + (size.height - 12) * (1 - (v[i] - lo) / span));
    final path = Path()..moveTo(p(0).dx, p(0).dy);
    for (var i = 1; i < v.length; i++) {
      path.lineTo(p(i).dx, p(i).dy);
    }
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [color.withValues(alpha: 0.25), color.withValues(alpha: 0)])
              .createShader(Offset.zero & size));
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeJoin = StrokeJoin.round);
    for (var i = 0; i < v.length; i++) {
      canvas.drawCircle(p(i), 3, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _MiniPainter old) => true;
}
