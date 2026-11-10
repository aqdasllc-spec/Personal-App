import 'dart:typed_data';

/// The sound samples of a WAV file and how to read them.
class Pcm {
  const Pcm(this.channels, this.sampleRate, this.bitsPerSample, this.data);
  final int channels, sampleRate, bitsPerSample;
  final Uint8List data;
  int get bytesPerSecond => sampleRate * channels * bitsPerSample ~/ 8;
}

/// Reads an uncompressed (PCM) WAV file; null if it is anything else.
Pcm? readWav(Uint8List b) {
  if (b.length < 12) return null;
  final v = ByteData.sublistView(b);
  String tag(int at) => String.fromCharCodes(b.sublist(at, at + 4));
  if (tag(0) != 'RIFF' || tag(8) != 'WAVE') return null;
  int? channels, rate, bits, format;
  Uint8List? data;
  var at = 12;
  while (at + 8 <= b.length) {
    final id = tag(at), size = v.getUint32(at + 4, Endian.little);
    final body = at + 8;
    final end = (body + size).clamp(body, b.length); // some engines write a wrong (too big) size while streaming
    if (id == 'fmt ' && size >= 16) {
      format = v.getUint16(body, Endian.little);
      channels = v.getUint16(body + 2, Endian.little);
      rate = v.getUint32(body + 4, Endian.little);
      bits = v.getUint16(body + 14, Endian.little);
    } else if (id == 'data') {
      data = b.sublist(body, end);
    }
    at = end + (size.isOdd ? 1 : 0);
  }
  if (format != 1 || channels == null || rate == null || bits == null || data == null) return null;
  return Pcm(channels, rate, bits, data);
}

/// [pcm] said [times] times, each followed by [gap] of silence, as a WAV file.
Uint8List repeatWithGaps(Pcm pcm, {int times = 1, Duration gap = const Duration(milliseconds: 1200)}) {
  final align = pcm.channels * pcm.bitsPerSample ~/ 8;
  var silence = pcm.bytesPerSecond * gap.inMilliseconds ~/ 1000;
  silence -= silence % align;
  final one = pcm.data.length + silence;
  final dataLen = one * times;
  final out = Uint8List(44 + dataLen);
  final v = ByteData.sublistView(out);
  void tag(int at, String s) => out.setRange(at, at + 4, s.codeUnits);
  tag(0, 'RIFF');
  v.setUint32(4, 36 + dataLen, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  v.setUint32(16, 16, Endian.little);
  v.setUint16(20, 1, Endian.little);
  v.setUint16(22, pcm.channels, Endian.little);
  v.setUint32(24, pcm.sampleRate, Endian.little);
  v.setUint32(28, pcm.bytesPerSecond, Endian.little);
  v.setUint16(32, align, Endian.little);
  v.setUint16(34, pcm.bitsPerSample, Endian.little);
  tag(36, 'data');
  v.setUint32(40, dataLen, Endian.little);
  for (var i = 0; i < times; i++) {
    out.setRange(44 + i * one, 44 + i * one + pcm.data.length, pcm.data); // the silence is already zeros
  }
  // 8-bit PCM is unsigned: its silence is 128, not 0
  if (pcm.bitsPerSample == 8) {
    for (var i = 0; i < times; i++) {
      out.fillRange(44 + i * one + pcm.data.length, 44 + (i + 1) * one, 128);
    }
  }
  return out;
}
