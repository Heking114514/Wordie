int getDayStartTime([DateTime? now]) {
  final value = now ?? DateTime.now();
  return DateTime(value.year, value.month, value.day).millisecondsSinceEpoch;
}

String getDayKey([DateTime? now]) {
  final value = now ?? DateTime.now();
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year}-$month-$day';
}

bool isTimestampToday(int? timestamp, [DateTime? now]) {
  if (timestamp == null || timestamp <= 0) return false;
  final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
  final current = now ?? DateTime.now();
  return date.year == current.year &&
      date.month == current.month &&
      date.day == current.day;
}
