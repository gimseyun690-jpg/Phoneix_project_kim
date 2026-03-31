String formatDate(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

String formatDateTime(DateTime date) {
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '${formatDate(date)} $hour:$minute';
}

String formatDuration(Duration duration) {
  final totalMinutes = duration.inMinutes;
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  final seconds = duration.inSeconds % 60;

  if (hours > 0) {
    return '$hours시간 ${minutes.toString().padLeft(2, '0')}분';
  }
  if (minutes > 0) {
    return '$minutes분 ${seconds.toString().padLeft(2, '0')}초';
  }
  return '$seconds초';
}

String formatDistanceMeters(double meters) {
  if (meters >= 1000) {
    return '${(meters / 1000).toStringAsFixed(1)}km';
  }
  return '${meters.toStringAsFixed(0)}m';
}

String formatAltitudeMeters(double meters) {
  return '${meters.toStringAsFixed(0)}m';
}

String formatSpeedMps(double speed) {
  return '${speed.toStringAsFixed(1)}m/s';
}
