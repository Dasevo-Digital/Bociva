import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../widgets/brand.dart';
import 'connect_screen.dart';
import 'profile_form.dart';

/// Erster Start: Ziele festlegen, wahlweise vorher mit dem Server verbinden.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    // Auf schmalen Telefonen kleiner statt überzulaufen.
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: BrandWordmark(width: 190),
                    ),
                  ),
                  Mascot(height: 140),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Sag uns kurz etwas über dich, dann berechnen wir deine '
                'Tagesziele. Deine Daten bleiben auf diesem Gerät oder auf '
                'deinem eigenen Server.',
              ),
              const SizedBox(height: 18),
              const ProfileForm(submitLabel: 'Loslegen'),
              if (!kIsWeb) ...[
                const SizedBox(height: 8),
                TextButton(
                  key: const Key('onboarding-connect'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ConnectScreen(webMode: false),
                    ),
                  ),
                  child: const Text('Ich habe schon einen Bociva-Server'),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
