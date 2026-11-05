import 'package:flutter/material.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// MedicTrack Health Score Engine
/// ═══════════════════════════════════════════════════════════════════════════
/// Implements the deterministic (non-AI) scoring model supplied for MedicTrack:
/// every metric is converted into a 0-100 "how are you trending" score using
/// fixed bands, and the daily Health Score is the plain average of the
/// available component scores. This is NOT a clinical diagnostic tool — it is
/// a system-generated awareness indicator only (see Terms & Conditions).
///
/// Component bands source: project "Health monitoring calculation" notes.
/// ═══════════════════════════════════════════════════════════════════════════
class HealthCalculator {
  HealthCalculator._();

  // ── Tier colors (shared across all component tables) ───────────────────────
  static const Color green   = Color(0xFF22C55E); // Excellent / Normal
  static const Color yellow  = Color(0xFFEAB308); // Good / Elevated
  static const Color orange  = Color(0xFFF97316); // Moderate / Stage 1
  static const Color red     = Color(0xFFEF4444); // Poor / Stage 2
  static const Color darkRed = Color(0xFF991B1B); // Critical

  // ═══════════════════════════════════════════════════════════════════════
  // 1. BLOOD SUGAR (HbA1c %) — Excellent 100 → Critical 20
  // ═══════════════════════════════════════════════════════════════════════
  static int bloodSugarScore(double hba1c) {
    if (hba1c >= 4.0 && hba1c <= 6.0) return 100;
    if (hba1c > 6.0  && hba1c <= 7.0) return 80;
    if (hba1c > 7.0  && hba1c <= 8.0) return 60;
    if (hba1c > 8.0  && hba1c <= 10.0) return 40;
    return 20; // < 4.0 or > 10.0
  }

  static String bloodSugarCategory(double hba1c) {
    final s = bloodSugarScore(hba1c);
    switch (s) {
      case 100: return 'Excellent';
      case 80:  return 'Good';
      case 60:  return 'Moderate';
      case 40:  return 'Poor';
      default:  return 'Critical';
    }
  }

  static Color bloodSugarColor(double hba1c) {
    final s = bloodSugarScore(hba1c);
    switch (s) {
      case 100: return green;
      case 80:  return yellow;
      case 60:  return orange;
      case 40:  return red;
      default:  return darkRed;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 2. BLOOD PRESSURE (systolic / diastolic mmHg)
  //    Checked worst-first since the bands overlap on purpose (AND/OR logic).
  // ═══════════════════════════════════════════════════════════════════════
  static int bloodPressureScore(int systolic, int diastolic) {
    if (systolic > 180 || diastolic > 120) return 20;  // Hypertensive Crisis
    if (systolic >= 140 || diastolic >= 90) return 40;  // Stage 2
    if (systolic >= 130 || diastolic >= 80) return 60;  // Stage 1
    if (systolic >= 120 && diastolic < 80)  return 80;  // Elevated
    if (systolic < 120  && diastolic < 80)  return 100; // Normal
    return 60; // fallback (mixed edge case) → treat as Stage 1
  }

  static String bloodPressureCategory(int systolic, int diastolic) {
    final s = bloodPressureScore(systolic, diastolic);
    switch (s) {
      case 100: return 'Normal';
      case 80:  return 'Elevated';
      case 60:  return 'Stage 1 Hypertension';
      case 40:  return 'Stage 2 Hypertension';
      default:  return 'Hypertensive Crisis';
    }
  }

  static Color bloodPressureColor(int systolic, int diastolic) {
    final s = bloodPressureScore(systolic, diastolic);
    switch (s) {
      case 100: return green;
      case 80:  return yellow;
      case 60:  return orange;
      case 40:  return red;
      default:  return darkRed;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 3. BMI (kg/m²)
  // ═══════════════════════════════════════════════════════════════════════
  static double bmi(double heightCm, double weightKg) {
    if (heightCm <= 0) return 0;
    final m = heightCm / 100.0;
    return weightKg / (m * m);
  }

  static int bmiScore(double bmiValue) {
    if (bmiValue >= 18.5 && bmiValue <= 24.9) return 100;
    if (bmiValue >= 25.0 && bmiValue <= 29.9) return 80;
    if (bmiValue >= 30.0 && bmiValue <= 34.9) return 60;
    if (bmiValue >= 35.0 && bmiValue <= 39.9) return 40;
    return 20; // < 18.5 or >= 40.0
  }

  /// Detailed clinical-style tier (used for the score breakdown table).
  static String bmiTier(double bmiValue) {
    final s = bmiScore(bmiValue);
    switch (s) {
      case 100: return 'Normal Weight';
      case 80:  return 'Overweight';
      case 60:  return 'Obesity Class I';
      case 40:  return 'Obesity Class II';
      default:  return bmiValue < 18.5 ? 'Underweight' : 'Severe Obesity';
    }
  }

  /// Simple 3-way category for the dashboard, per app requirements:
  /// Underweight / Normal / Overweight.
  static String bmiSimpleCategory(double bmiValue) {
    if (bmiValue < 18.5) return 'Underweight';
    if (bmiValue <= 24.9) return 'Normal';
    return 'Overweight';
  }

  static Color bmiColor(double bmiValue) {
    final s = bmiScore(bmiValue);
    switch (s) {
      case 100: return green;
      case 80:  return yellow;
      case 60:  return orange;
      case 40:  return red;
      default:  return darkRed;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 4. AGE
  // ═══════════════════════════════════════════════════════════════════════
  static int ageScore(int age) {
    if (age >= 18 && age <= 35) return 100;
    if (age >= 36 && age <= 50) return 80;
    if (age >= 51 && age <= 65) return 60;
    if (age >= 66 && age <= 75) return 40;
    return 20; // > 75 (or < 18, out of normal adult range)
  }

  static String ageRiskTier(int age) {
    final s = ageScore(age);
    switch (s) {
      case 100: return 'Low Baseline Risk';
      case 80:  return 'Mild Baseline Risk';
      case 60:  return 'Moderate Baseline Risk';
      case 40:  return 'High Baseline Risk';
      default:  return 'Critical Baseline Risk';
    }
  }

  static Color ageColor(int age) {
    final s = ageScore(age);
    switch (s) {
      case 100: return green;
      case 80:  return yellow;
      case 60:  return orange;
      case 40:  return red;
      default:  return darkRed;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 5. MEDICATION ADHERENCE — (doses taken ÷ doses scheduled) × 100
  // ═══════════════════════════════════════════════════════════════════════
  static int adherenceScore(int taken, int total) {
    if (total <= 0) return 100; // nothing scheduled → don't penalise
    return ((taken / total) * 100).round().clamp(0, 100);
  }

  static Color adherenceColor(int score) {
    if (score >= 80) return green;
    if (score >= 60) return yellow;
    if (score >= 40) return orange;
    return red;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // OVERALL DAILY HEALTH SCORE
  // = plain average of every available component (Blood Sugar, Blood
  //   Pressure, Adherence, BMI, Age). A component only enters the average
  //   once its underlying data exists, so a fresh account without vitals
  //   yet still gets a meaningful score from BMI/Age/Adherence.
  // ═══════════════════════════════════════════════════════════════════════
  static int overallScore({
    int? bloodSugar,
    int? bloodPressure,
    required int bmiScoreValue,
    required int ageScoreValue,
    required int adherenceScoreValue,
  }) {
    final parts = <int>[
      if (bloodSugar != null) bloodSugar,
      if (bloodPressure != null) bloodPressure,
      bmiScoreValue,
      ageScoreValue,
      adherenceScoreValue,
    ];
    if (parts.isEmpty) return 0;
    final sum = parts.fold<int>(0, (a, b) => a + b);
    return (sum / parts.length).round().clamp(0, 100);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Overall classification — Good / Moderate / High Risk (dashboard tiers)
  // ═══════════════════════════════════════════════════════════════════════
  static String overallLevel(int score) {
    if (score >= 80) return 'Good';
    if (score >= 50) return 'Moderate';
    return 'High Risk';
  }

  static String overallMeaning(int score) {
    if (score >= 80) return 'Your health indicators look healthy and stable.';
    if (score >= 50) return 'Some indicators need attention — keep monitoring.';
    return 'Multiple indicators are concerning — consider medical advice.';
  }

  static Color overallColor(int score) {
    if (score >= 80) return green;
    if (score >= 50) return const Color(0xFFF59E0B); // amber, matches app accent
    return const Color(0xFFEF4444);
  }
}
