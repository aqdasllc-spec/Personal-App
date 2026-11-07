/// Human-readable size: 0 B, 512 B, 1.5 KB, 340 MB, 1.2 GB (1024-based, one decimal when it helps).
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var v = bytes / 1024;
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  final text = v >= 100 || v == v.roundToDouble()
      ? v.round().toString()
      : v.toStringAsFixed(1);
  return '$text ${units[i]}';
}
