String formatDistance(double meters) {
  if (meters < 1000) return '${meters.round()} м';
  return '${(meters / 1000).toStringAsFixed(1)} км';
}

String formatDuration(double seconds) {
  final total = (seconds / 60).ceil().clamp(1, 1 << 30);
  if (total < 60) return '$total мин';
  final h = total ~/ 60;
  final m = total % 60;
  return m == 0 ? '$h ч' : '$h ч $m мин';
}
