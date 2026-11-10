import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/features/quran/prayer/prayer_ringer.dart';
import 'package:folio/features/quran/prayer/prayer_reminders_card.dart' show soundName;
import 'package:folio/features/quran/prayer/wav.dart';

void main() {
  Uint8List wav(List<int> samples, {int rate = 16000}) => repeatWithGaps(Pcm(1, rate, 16, Uint8List.fromList(samples)), gap: Duration.zero);

  test('a WAV file is read back the same, and repeated with silence between', () {
    final w = wav([1, 2, 3, 4]);
    final p = readWav(w)!;
    expect((p.channels, p.sampleRate, p.bitsPerSample), (1, 16000, 16));
    expect(p.data, [1, 2, 3, 4]);
    final r = repeatWithGaps(p, times: 3, gap: const Duration(milliseconds: 1));
    final back = readWav(r)!;
    // 1 ms of 16-bit mono at 16 kHz = 16 samples = 32 bytes of silence after each copy
    expect(back.data.length, 3 * (4 + 32));
    expect(back.data.sublist(0, 4), [1, 2, 3, 4]);
    expect(back.data.sublist(4, 36).every((b) => b == 0), isTrue);
    expect(back.data.sublist(36, 40), [1, 2, 3, 4]);
  });

  test('not a WAV, or compressed: left alone', () {
    expect(readWav(Uint8List.fromList([1, 2, 3])), isNull);
    final w = wav([1, 2]);
    w[20] = 3; // format 3 = float, not plain PCM
    expect(readWav(w), isNull);
  });

  test('a size the engine left too large is tolerated', () {
    final w = wav([5, 6, 7, 8]);
    ByteData.sublistView(w).setUint32(40, 0x7fffffff, Endian.little);
    expect(readWav(w)!.data, [5, 6, 7, 8]);
  });

  test('Urdu script is noticed (it needs an Urdu voice); sound names are shown without the time stamp', () {
    expect(isUrduScript('اٹھ جاؤ'), isTrue);
    expect(isUrduScript('Uth jao, namaz ka waqt hai'), isFalse);
    expect(soundName('prayer_sounds/1731234567890_azan makkah.mp3'), 'azan makkah.mp3');
    expect(soundName(null), '');
  });
}
