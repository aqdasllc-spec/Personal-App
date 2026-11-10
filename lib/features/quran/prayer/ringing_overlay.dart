import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../presentation/cabinet_painters.dart';
import '../presentation/quran_style.dart';
import 'prayer_ringer.dart';

/// Over everything while a prayer alarm sounds: the prayer and one big "I'm up" button that stops it.
class RingingOverlay extends ConsumerWidget {
  const RingingOverlay({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ringing = ref.watch(prayerRingingProvider).value ?? const [];
    return Stack(
      children: [
        child,
        if (ringing.isNotEmpty) _Ringing(ringing.first, onStop: () async {
          final ringer = ref.read(prayerRingerProvider);
          for (final a in ringing) {
            await ringer.stop(a.id);
          }
        }),
      ],
    );
  }
}

class _Ringing extends StatelessWidget {
  const _Ringing(this.alarm, {required this.onStop});
  final RingingAlarm alarm;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final parts = alarm.title.split(' · ');
    final english = parts.first, urdu = parts.length > 1 ? parts[1] : '';
    final bodyParts = alarm.body.split(' · ');
    return Positioned.fill(
      child: Material(
        key: const Key('prayer-ringing'),
        color: QuranColors.velvetDeep,
        child: Stack(
          children: [
            const Positioned.fill(child: CustomPaint(painter: StarLatticePainter(opacity: .10))),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Spacer(),
                    const Icon(Icons.mosque_outlined, size: 56, color: QuranColors.gold),
                    const SizedBox(height: 20),
                    if (urdu.isNotEmpty)
                      Text(urdu, textAlign: TextAlign.center, textDirection: TextDirection.rtl, style: urduText(30, color: QuranColors.goldLight)),
                    const SizedBox(height: 8),
                    Text(
                      english,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 16),
                    Text(bodyParts.first, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 16)),
                    if (bodyParts.length > 1) ...[
                      const SizedBox(height: 6),
                      Text(bodyParts[1], textAlign: TextAlign.center, textDirection: TextDirection.rtl, style: urduText(16, color: Colors.white70)),
                    ],
                    const Spacer(),
                    SizedBox(
                      width: double.infinity,
                      height: 72,
                      child: FilledButton(
                        key: const Key('im-up'),
                        style: FilledButton.styleFrom(
                          backgroundColor: QuranColors.gold,
                          foregroundColor: QuranColors.velvetDeep,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(36)),
                          textStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                        ),
                        onPressed: onStop,
                        child: const Text("I'm up · اٹھ گیا"),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
