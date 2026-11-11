import 'package:flutter/material.dart';

/// Schriftzug „Bociva – AI Food Tracking“, im dunklen Modus hell.
class BrandWordmark extends StatelessWidget {
  const BrandWordmark({super.key, this.width = 200});
  final double width;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Image.asset(
      dark ? 'assets/brand/wordmark_dark.png' : 'assets/brand/wordmark.png',
      width: width,
      semanticLabel: 'Bociva',
      filterQuality: FilterQuality.medium,
    );
  }
}

/// Das Apfel-Maskottchen.
class Mascot extends StatelessWidget {
  const Mascot({super.key, this.height = 160});
  final double height;

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/brand/mascot.png',
    height: height,
    excludeFromSemantics: true,
    filterQuality: FilterQuality.medium,
  );
}

/// Maskottchen mit kurzem Text, etwa für leere Listen.
class MascotHint extends StatelessWidget {
  const MascotHint({super.key, required this.text, this.height = 140});
  final String text;
  final double height;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(32),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Mascot(height: height),
        const SizedBox(height: 16),
        Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}

/// Rundes, farbig getöntes Symbol wie auf dem Telefon des Maskottchens.
class IconBubble extends StatelessWidget {
  const IconBubble({
    super.key,
    required this.icon,
    required this.color,
    this.size = 42,
  });
  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: dark ? 0.22 : 0.16),
      ),
      child: Icon(icon, color: color, size: size * 0.55),
    );
  }
}

/// Großes, angedeutetes Blatt als Verzierung auf farbigen Flächen.
class LeafDecoration extends CustomPainter {
  const LeafDecoration({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final leaf = Path()
      ..moveTo(w * 0.62, h * 1.05)
      ..quadraticBezierTo(w * 0.70, h * 0.05, w * 1.12, -h * 0.05)
      ..quadraticBezierTo(w * 1.02, h * 0.85, w * 0.62, h * 1.05)
      ..close();
    canvas.drawPath(leaf, Paint()..color = color);
    final vein = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.66, h * 0.98)
        ..quadraticBezierTo(w * 0.86, h * 0.45, w * 1.08, 0),
      vein,
    );
  }

  @override
  bool shouldRepaint(LeafDecoration old) => old.color != color;
}
