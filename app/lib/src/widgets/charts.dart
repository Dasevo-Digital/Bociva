import 'dart:math';

import 'package:flutter/material.dart';

import '../theme.dart';

/// Kalorienring: wie viel vom Tagesbudget schon verbraucht ist.
class CalorieRing extends StatelessWidget {
  const CalorieRing({
    super.key,
    required this.fraction,
    required this.child,
    this.size = 168,
    this.over = false,
  });

  final double fraction;
  final Widget child;
  final double size;
  final bool over;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(
      painter: _RingPainter(fraction.clamp(0, 1), over),
      child: Center(child: child),
    ),
  );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.fraction, this.over);
  final double fraction;
  final bool over;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 14.0;
    final rect = Offset.zero & size;
    final arc = rect.deflate(stroke / 2);
    final track = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(arc, 0, 2 * pi, false, track);
    if (fraction > 0) {
      final progress = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round;
      if (over) {
        progress.color = BocivaColors.fatOnGreen;
      } else {
        // Von Hellgrün zu Lindgrün wie die Blätter im Icon.
        progress.shader = SweepGradient(
          colors: const [BocivaColors.lime, BocivaColors.leaf],
          stops: [0, fraction.clamp(0.01, 1)],
          transform: const GradientRotation(-pi / 2),
        ).createShader(arc);
      }
      canvas.drawArc(arc, -pi / 2, 2 * pi * fraction, false, progress);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction || old.over != over;
}

class ProgressLine extends StatelessWidget {
  const ProgressLine({
    super.key,
    required this.fraction,
    required this.color,
    this.track,
  });

  final double fraction;
  final Color color;
  final Color? track;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(6),
    child: LinearProgressIndicator(
      value: fraction.clamp(0, 1),
      minHeight: 8,
      color: color,
      backgroundColor: track ?? color.withValues(alpha: 0.18),
    ),
  );
}

/// Säulen pro Tag mit Ziellinie.
class BarChart extends StatelessWidget {
  const BarChart({
    super.key,
    required this.values,
    required this.labels,
    required this.color,
    this.goal,
    this.height = 150,
  });

  final List<double> values;
  final List<String> labels;
  final double? goal;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall!;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _BarPainter(values, labels, goal, color, style),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter(this.values, this.labels, this.goal, this.color, this.style);
  final List<double> values;
  final List<String> labels;
  final double? goal;
  final Color color;
  final TextStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    const labelHeight = 18.0;
    final chart = size.height - labelHeight;
    final top = [...values, goal ?? 0].reduce(max) * 1.1;
    if (top <= 0) return;
    final slot = size.width / values.length;
    final bar = min(slot * 0.62, 28.0);
    final paint = Paint()..color = color;
    final step = values.length > 14 ? 5 : 1;
    for (var i = 0; i < values.length; i++) {
      final h = values[i] / top * chart;
      final x = slot * i + (slot - bar) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, chart - h, bar, h),
          const Radius.circular(6),
        ),
        paint,
      );
      if (i % step == 0 && i < labels.length) {
        final text = TextPainter(
          text: TextSpan(text: labels[i], style: style),
          textDirection: TextDirection.ltr,
        )..layout();
        text.paint(
          canvas,
          Offset(slot * i + (slot - text.width) / 2, chart + 4),
        );
      }
    }
    if (goal != null && goal! > 0) {
      final y = chart - goal! / top * chart;
      final line = Paint()
        ..color = BocivaColors.coral
        ..strokeWidth = 1.5;
      for (double x = 0; x < size.width; x += 8) {
        canvas.drawLine(Offset(x, y), Offset(x + 4, y), line);
      }
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.values != values || old.goal != goal || old.color != color;
}

class LineChart extends StatelessWidget {
  const LineChart({
    super.key,
    required this.values,
    required this.color,
    this.trend,
    this.trendColor,
  });

  final List<double> values;
  final Color color;

  /// Geglättete Werte zu [values]. Dann zeigen die Messungen nur Punkte und
  /// der Trend die Linie.
  final List<double>? trend;
  final Color? trendColor;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 120,
    width: double.infinity,
    child: CustomPaint(
      painter: _LinePainter(values, color, trend, trendColor ?? color),
    ),
  );
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.values, this.color, this.trend, this.trendColor);
  final List<double> values;
  final Color color;
  final List<double>? trend;
  final Color trendColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final all = [...values, ...?trend];
    final low = all.reduce(min) - 0.5;
    final high = all.reduce(max) + 0.5;
    Offset at(List<double> v, int i) => Offset(
      v.length == 1 ? size.width / 2 : size.width * i / (v.length - 1),
      size.height - (v[i] - low) / (high - low) * size.height,
    );
    void line(List<double> v, Color c) {
      final path = Path()..moveTo(at(v, 0).dx, at(v, 0).dy);
      for (var i = 1; i < v.length; i++) {
        path.lineTo(at(v, i).dx, at(v, i).dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = c
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
    }

    final smooth = trend;
    if (smooth != null && smooth.length == values.length) {
      for (var i = 0; i < values.length; i++) {
        canvas.drawCircle(
          at(values, i),
          3.5,
          Paint()..color = color.withValues(alpha: 0.55),
        );
      }
      line(smooth, trendColor);
      canvas.drawCircle(
        at(smooth, smooth.length - 1),
        5,
        Paint()..color = trendColor,
      );
      return;
    }
    line(values, color);
    for (var i = 0; i < values.length; i++) {
      canvas.drawCircle(at(values, i), 4, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.values != values ||
      old.color != color ||
      old.trend != trend ||
      old.trendColor != trendColor;
}
