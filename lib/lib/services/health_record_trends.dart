// Pure comparison logic: no network requests and no clinical classifications.
enum HealthMetric { bloodPressure, bloodSugar, weight }

double? healthNumber(Object? value) {
  final number = value is num ? value.toDouble() : double.tryParse('$value');
  return number != null && number.isFinite && number > 0 ? number : null;
}

Map<String, dynamic> healthMap(Object? value) => value is Map
    ? Map<String, dynamic>.from(value)
    : <String, dynamic>{};

class HealthUpload {
  final String id;
  final DateTime at;
  final Map<String, dynamic> data;
  const HealthUpload({required this.id, required this.at, required this.data});

  ReadingPoint? reading(HealthMetric metric) {
    final bp = healthMap(data['bloodPressure']);
    final sugar = healthMap(data['bloodSugar']);
    double? value;
    double? secondary;
    switch (metric) {
      case HealthMetric.bloodPressure:
        value = healthNumber(bp['systolic']);
        secondary = healthNumber(bp['diastolic']);
        break;
      case HealthMetric.bloodSugar:
        // Compare a single unit even if uploads used different meter units.
        final raw = healthNumber(sugar['value']);
        final unit = (sugar['unit'] ?? '').toString().toLowerCase();
        if (unit.contains('mmol')) {
          value = (raw ?? healthNumber(sugar['valueMmol']));
          if (value != null) value *= 18;
        } else if (unit.contains('mg') || unit.isEmpty) {
          value = raw;
          final mmol = healthNumber(sugar['valueMmol']);
          value ??= mmol == null ? null : mmol * 18;
        }
        break;
      case HealthMetric.weight:
        final weight = data['weight'];
        value = healthNumber(data['weightKg']) ??
            healthNumber(weight is Map ? weight['value'] : weight);
        break;
    }
    if (value == null) return null;
    return ReadingPoint(upload: this, value: value, secondary: secondary);
  }
}

class ReadingPoint {
  final HealthUpload upload;
  final double value;
  final double? secondary;
  const ReadingPoint({required this.upload, required this.value, this.secondary});
  DateTime get at => upload.at;
}

bool sameHealthDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

class HealthTrend {
  final List<ReadingPoint> newestFirst;
  HealthTrend(Iterable<HealthUpload> uploads, HealthMetric metric)
      : newestFirst = uploads.map((u) => u.reading(metric))
            .whereType<ReadingPoint>().toList() {
    newestFirst.sort((a, b) {
      final order = b.at.compareTo(a.at);
      return order == 0 ? b.upload.id.compareTo(a.upload.id) : order;
    });
  }

  ReadingPoint? get latest => newestFirst.isEmpty ? null : newestFirst.first;
  ReadingPoint? get previous => newestFirst.length < 2 ? null : newestFirst[1];
  List<ReadingPoint> get latestThree => newestFirst.take(3).toList();
  List<ReadingPoint> get chartPoints => latestThree.reversed.toList();
  double? get change => latest == null || previous == null
      ? null : latest!.value - previous!.value;

  // The latest available reading on the preceding calendar date. This is
  // deliberately independent of the previous upload and the three-point chart.
  ReadingPoint? get previousDay {
    if (latest == null) return null;
    final at = latest!.at;
    final target = DateTime(at.year, at.month, at.day - 1);
    for (final point in newestFirst.skip(1)) {
      if (sameHealthDay(point.at, target)) return point;
    }
    return null;
  }

  ReadingPoint? get highest => _extreme(true);
  ReadingPoint? get lowest => _extreme(false);
  ReadingPoint? _extreme(bool high) {
    ReadingPoint? result;
    for (final point in latestThree) {
      if (result == null || (high ? point.value > result.value : point.value < result.value)) {
        result = point;
      }
    }
    return result;
  }
}
