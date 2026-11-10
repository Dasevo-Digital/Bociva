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
