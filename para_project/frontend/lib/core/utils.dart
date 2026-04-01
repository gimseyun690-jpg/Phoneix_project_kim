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

String formatTime(DateTime date) {
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
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

String formatSpeedKmh(double speedMps) {
  final speedKmh = speedMps * 3.6;
  final fractionDigits = speedKmh >= 10 ? 0 : 1;
  return '${speedKmh.toStringAsFixed(fractionDigits)}km/h';
}

String formatVerticalSpeed(double speedMps) {
  final prefix = speedMps > 0 ? '+' : '';
  return '$prefix${speedMps.toStringAsFixed(1)}m/s';
}

String formatAccuracy(double? meters) {
  if (meters == null) {
    return '정보 없음';
  }
  return '${meters.toStringAsFixed(0)}m';
}

String formatTemperature(double? celsius) {
  if (celsius == null) {
    return '정보 준비 중';
  }
  return '${celsius.toStringAsFixed(1)}°C';
}

String formatCoordinates(double latitude, double longitude) {
  return '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';
}

String formatHeading(double? degrees) {
  if (degrees == null) {
    return '정보 없음';
  }

  final normalized = ((degrees % 360) + 360) % 360;
  final direction = switch (normalized) {
    >= 337.5 || < 22.5 => '북',
    >= 22.5 && < 67.5 => '북동',
    >= 67.5 && < 112.5 => '동',
    >= 112.5 && < 157.5 => '남동',
    >= 157.5 && < 202.5 => '남',
    >= 202.5 && < 247.5 => '남서',
    >= 247.5 && < 292.5 => '서',
    _ => '북서',
  };

  return '${normalized.toStringAsFixed(0)}° $direction';
}
