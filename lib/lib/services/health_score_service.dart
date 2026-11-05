import 'package:cloud_firestore/cloud_firestore.dart';
import 'dose_service.dart';
import 'health_calculator.dart';

const healthScoreKeys = ['bloodPressure', 'bloodSugar', 'adherence', 'age', 'bmi'];
Map<String, dynamic> scoreMap(Object? value) => value is Map ? Map<String, dynamic>.from(value) : {};
double? scoreNumber(Object? value) {
  final number = value is num ? value.toDouble() : double.tryParse('$value');
  return number != null && number.isFinite ? number : null;
}
int? _component(Object? value) {
  final number = scoreNumber(value);
  return number == null || number < 0 || number > 100 ? null : number.round();
}
DateTime? scoreDate(Object? value) => value is Timestamp ? value.toDate().toLocal()
    : value is DateTime ? value.toLocal() : value is String ? DateTime.tryParse(value)?.toLocal() : null;

class HealthScoreSnapshot {
  final Map<String, int?> components;
  final Map<String, dynamic> signals;
  final DateTime? at;
  const HealthScoreSnapshot({required this.components, required this.signals, this.at});

  int get coverage => components.values.whereType<int>().length;
  int? get overall {
    final available = components.values.whereType<int>().toList();
    return available.isEmpty ? null : (available.reduce((a, b) => a+b) / available.length).round();
  }
  bool comparableTo(HealthScoreSnapshot other) => healthScoreKeys.every(
      (key) => (components[key] != null) == (other.components[key] != null)) && coverage > 0;

  factory HealthScoreSnapshot.fromProfile(Map<String, dynamic> profile,
      {int? adherence, DateTime? at}) {
    final now = at ?? DateTime.now();
    final health = scoreMap(profile['healthInfo']);
    final bp = scoreMap(profile['latestBP']);
    final sugar = scoreMap(profile['latestSugar']);
    final height = scoreNumber(health['height']);
    final weight = scoreNumber(health['weight']);
    final bmi = height != null && height > 0 && weight != null && weight > 0
        ? HealthCalculator.bmi(height, weight) : null;
    final age = _age(profile, now);
    final rawSugar = scoreNumber(sugar['value']);
    final unit = (sugar['unit'] ?? '').toString();
    final sugarMmol = unit.toLowerCase().contains('mmol')
        ? (rawSugar ?? scoreNumber(sugar['valueMmol']))
        : scoreNumber(sugar['valueMmol']) ?? (rawSugar == null ? null : rawSugar/18);
    return HealthScoreSnapshot(at: now, components: {
      'bloodPressure': _component(bp['score']), 'bloodSugar': _component(sugar['score']),
      'adherence': _component(adherence), 'age': age == null ? null : HealthCalculator.ageScore(age),
      'bmi': bmi == null ? null : HealthCalculator.bmiScore(bmi),
    }, signals: {
      'systolic': scoreNumber(bp['systolic']), 'diastolic': scoreNumber(bp['diastolic']),
      'sugarValue': rawSugar, 'sugarUnit': unit, 'sugarMmol': sugarMmol,
      'heightCm': height, 'weightKg': weight, 'bmiValue': bmi, 'ageYears': age,
    });
  }

  // A historical upload without a score snapshot only supplies values it
  // actually stored. Current profile weight/age/adherence are not backfilled.
  factory HealthScoreSnapshot.fromUpload(Map<String, dynamic> upload) {
    final stored = scoreMap(upload['healthScoreSnapshot']);
    final at = scoreDate(upload['recordedAt']) ?? scoreDate(upload['clientRecordedAt']);
    if (stored.isNotEmpty) {
      final parts = scoreMap(stored['components']);
      return HealthScoreSnapshot(at: at, components: {
        for (final key in healthScoreKeys) key: _component(parts[key]),
      }, signals: scoreMap(stored['signals']));
    }
    final bp = scoreMap(upload['bloodPressure']);
    final sugar = scoreMap(upload['bloodSugar']);
    final value = scoreNumber(sugar['value']);
    final unit = (sugar['unit'] ?? '').toString();
    return HealthScoreSnapshot(at: at, components: {
      'bloodPressure': _component(bp['score']), 'bloodSugar': _component(sugar['score']),
      'adherence': null, 'age': null, 'bmi': null,
    }, signals: {
      'systolic': scoreNumber(bp['systolic']), 'diastolic': scoreNumber(bp['diastolic']),
      'sugarValue': value, 'sugarUnit': unit,
      'sugarMmol': unit.toLowerCase().contains('mmol') ? (value ?? scoreNumber(sugar['valueMmol']))
          : scoreNumber(sugar['valueMmol']) ?? (value == null ? null : value/18),
    });
  }

  Map<String, dynamic> toFirestore() => {
    'version': 1, 'components': components, 'signals': signals, 'overall': overall,
  };

  static int? _age(Map<String, dynamic> profile, DateTime now) {
    final raw = profile['dateOfBirth'];
    DateTime? birth = scoreDate(raw);
    if (birth == null && raw is String) {
      final parts = raw.split('/');
      if (parts.length == 3) {
        final day = int.tryParse(parts[0]); final month = int.tryParse(parts[1]); final year = int.tryParse(parts[2]);
        if (day != null && month != null && year != null) {
          final candidate = DateTime(year, month, day);
          if (candidate.year == year && candidate.month == month && candidate.day == day) birth = candidate;
        }
      }
    }
    if (birth != null && !birth.isAfter(now)) {
      var age = now.year-birth.year;
      if (now.month < birth.month || (now.month == birth.month && now.day < birth.day)) age--;
      if (age >= 1 && age <= 120) return age;
    }
    final age = scoreNumber(profile['age']);
    return age != null && age >= 1 && age <= 120 ? age.toInt() : null;
  }
}

class HealthScoreReport {
  final HealthScoreSnapshot current;
  final HealthScoreSnapshot? previous;
  final List<String> notices;
  const HealthScoreReport({required this.current, required this.previous, required this.notices});
  int? get delta => previous != null && current.comparableTo(previous!)
      ? current.overall! - previous!.overall! : null;
}

class HealthScoreService {
  static Future<int?> adherence(String uid, {DateTime? asOf}) async {
    final now = asOf ?? DateTime.now();
    final result = await DoseService.instance.events(uid).where('dueAt',
        isGreaterThanOrEqualTo: Timestamp.fromDate(now.subtract(const Duration(days: 30))))
        .get().timeout(const Duration(seconds: 15));
    final due = result.docs.where((doc) => DoseService.eligible(doc.data(), now)).toList();
    return due.isEmpty ? null : (100 * due.where((doc) => doc.data()['status'] == 'taken').length / due.length).round();
  }

  static Future<HealthScoreReport> load(String uid) async {
    final db = FirebaseFirestore.instance;
    final notices = <String>[];
    Future<QuerySnapshot<Map<String, dynamic>>?> history() async {
      try { return await db.collection('users').doc(uid).collection('vitals')
          .orderBy('recordedAt', descending: true).limit(2).get().timeout(const Duration(seconds: 15)); }
      catch (_) { notices.add('Previous uploads could not be loaded. Pull down to retry.'); return null; }
    }
    Future<int?> doseScore() async {
      try { return await adherence(uid); }
      catch (_) { notices.add('Medication adherence is unavailable. Pull down to retry.'); return null; }
    }
    final results = await Future.wait<Object?>([
      db.collection('users').doc(uid).get().timeout(const Duration(seconds: 15)), history(), doseScore(),
    ]);
    final profile = (results[0] as DocumentSnapshot<Map<String, dynamic>>).data() ?? {};
    final current = HealthScoreSnapshot.fromProfile(profile, adherence: results[2] as int?);
    final documents = (results[1] as QuerySnapshot<Map<String, dynamic>>?)?.docs ?? [];
    HealthScoreSnapshot? previous;
    if (documents.isNotEmpty) {
      final latest = HealthScoreSnapshot.fromUpload(documents.first.data());
      final stored = scoreMap(documents.first.data()['healthScoreSnapshot']);
      // A fully captured snapshot can detect changes since the last upload.
      // Legacy data can identify the same last reading only from actual vitals.
      final sameCurrent = stored.isNotEmpty
          ? healthScoreKeys.every((key) => latest.components[key] == current.components[key]) &&
              ['systolic', 'diastolic', 'sugarMmol', 'heightCm', 'weightKg', 'ageYears']
                  .every((key) => latest.signals[key] == current.signals[key])
          : _legacyMatches(latest, current);
      if (!sameCurrent) { previous = latest; }
      else if (documents.length > 1) { previous = HealthScoreSnapshot.fromUpload(documents[1].data()); }
    }
    return HealthScoreReport(current: current, previous: previous, notices: notices);
  }

  static bool _legacyMatches(HealthScoreSnapshot old, HealthScoreSnapshot current) {
    var matched = false;
    for (final key in ['systolic', 'diastolic', 'sugarMmol']) {
      final value = scoreNumber(old.signals[key]);
      if (value == null) continue;
      matched = true;
      final other = scoreNumber(current.signals[key]);
      if (other == null || (value-other).abs() > .00001) return false;
    }
    return matched;
  }
}
