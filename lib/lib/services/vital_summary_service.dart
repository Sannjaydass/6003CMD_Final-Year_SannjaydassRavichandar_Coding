/// Reading interpretation is separate from HbA1c and the app awareness score.
/// General adult references: ADA glucose targets; AHA blood-pressure categories.
class VitalSummary {
  final String label, message, level;
  final int? awarenessScore;
  const VitalSummary(this.label, this.message, this.level, this.awarenessScore);
  bool get needsAttention => level == 'high' || level == 'low' || level == 'urgent';
  Map<String, dynamic> toMap() => {'label': label, 'message': message, 'level': level,
    'awarenessScore': awarenessScore, 'version': 1};
}

class VitalSummaryService {
  static const beforeMeal = 'beforeMeal';
  static const afterMeal = 'afterMeal';
  static const unknown = 'unknown';
  // Scores are app display heuristics, not validated clinical risk estimates.
  static VitalSummary glucose(double value, {bool isMgDl = true, String context = unknown}) {
    final mg = isMgDl ? value : value * 18;
    if (!mg.isFinite || mg <= 0) {
      return const VitalSummary('Check reading', 'Confirm the number and unit on your meter before saving.', 'unknown', null);
    }
    if (mg < 54 - .000001) {
      return const VitalSummary('Blood sugar is very low',
        'Confirm promptly and follow your prescribed low-glucose plan. If you are confused, fainting, '
        'or cannot swallow safely, seek emergency help now.', 'urgent', 20);
    }
    if (mg >= 300 - .000001) {
      return const VitalSummary('Blood sugar is very high',
        'Confirm the reading promptly. If it stays at 300 mg/dL or above, or you have vomiting, trouble breathing '
        'or fruity-smelling breath, seek emergency help. Contact your care team and follow your prescribed plan.', 'urgent', 20);
    }
    if (mg < 70 - .000001) {
      return const VitalSummary('Blood sugar is low',
        'This reading is below the general low-glucose threshold. Follow your prescribed low-glucose plan promptly. '
        'If you are confused, fainting, or unable to swallow safely, seek emergency help.', 'low', 20);
    }
    final before = context == beforeMeal;
    final after = context == afterMeal;
    final high = before ? mg > 130 + .000001 : mg >= 180 - .000001;
    if (high) {
      return VitalSummary('Blood sugar is high',
        'This reading is above the general ${before ? 'before-meal' : '1–2 hours after-meal'} reference target '
        'for most nonpregnant adults with diabetes.${!before && !after ? ' Meal timing is unknown; your personal target may differ.' : ''} '
        'Confirm the reading and contact your care team if it stays high or you feel unwell. '
        'Do not change medicine doses based only on this app.', 'high', 40);
    }
    if (before && mg < 80 - .000001) {
      return const VitalSummary('Below before-meal target',
        'Below the general 80–130 mg/dL before-meal reference, but not below 70 mg/dL. '
        'Use the target set by your care team.', 'watch', 80);
    }
    if (before || after) {
      return const VitalSummary('Within reference target',
        'Within the selected general adult diabetes reference target. Your clinician may set a different target. '
        'A single reading does not diagnose or rule out diabetes.', 'reference', 100);
    }
    return const VitalSummary('Meal timing needed',
      'Choose before meal or 1–2 hours after meal to compare with a reference target. '
      'This reading cannot be called normal from the number alone.', 'unknown', null);
  }

  static VitalSummary bloodPressure(int systolic, int? diastolic) {
    if (systolic <= 0 || diastolic == null || diastolic <= 0) {
      return const VitalSummary('Incomplete blood pressure', 'Confirm both numbers on your monitor before saving.', 'unknown', null);
    }
    if (systolic > 180 || diastolic > 120) {
      return const VitalSummary('Blood pressure is very high',
        'If you have chest pain, shortness of breath, weakness, vision changes or difficulty speaking, seek emergency help now. '
        'Without symptoms, repeat after one minute; if still this high, contact a healthcare professional immediately.', 'urgent', 20);
    }
    if (systolic >= 140 || diastolic >= 90) {
      return const VitalSummary('Blood pressure is high',
        'This reading is in the general stage 2 high-pressure range. Rest and repeat correctly, '
        'and discuss repeated high readings with your clinician. One reading does not confirm a diagnosis.', 'high', 40);
    }
    if (systolic >= 130 || diastolic >= 80) {
      return const VitalSummary('Blood pressure is high',
        'This reading is in the general stage 1 high-pressure range. Track repeat readings and share them with your clinician.', 'high', 60);
    }
    if (systolic < 90 || diastolic < 60) {
      return const VitalSummary('Blood pressure is low',
        'This reading is below the general 90/60 mmHg reference. If you feel faint, dizzy or unwell, seek medical advice promptly.', 'low', 40);
    }
    if (systolic >= 120) {
      return const VitalSummary('Blood pressure is elevated',
        'Above the general normal systolic reference. Continue monitoring and discuss persistent elevation with your clinician.', 'watch', 80);
    }
    return const VitalSummary('Within blood-pressure reference',
      'Below 120/80 mmHg and above the low-pressure reference. Continue following your care plan.', 'reference', 100);
  }
}
