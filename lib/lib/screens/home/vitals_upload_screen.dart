import 'daily_health_score_card.dart';
import '../../services/health_monitoring_service.dart';
import '../../design/medic_dialog_controller_scope.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:medictrack/design/medic_design.dart';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../services/auth_service.dart';
import '../../services/dependant_service.dart';
import '../../services/health_calculator.dart';
import '../../services/health_score_service.dart';
import '../../services/vital_summary_service.dart';
import '../../services/gemini_service.dart';

// ─── Design Tokens ────────────────────────────────────────────────────────────
class _C {
  static const navy    = MedicColors.c142F2B;
  static const teal    = MedicColors.c28715D;
  static const sky     = MedicColors.c477C91;
  static const amber   = MedicColors.cB77A27;
  static const rose    = MedicColors.cC05256;
  static const violet  = MedicColors.c78659B;
  static const surface = MedicColors.cF6F5F0;
  static const card    = MedicColors.cFFFFFF;
  static const border  = MedicColors.cE2E5DC;
  static const textPri = MedicColors.c142F2B;
  static const textSec = MedicColors.c63756D;
  static const textTer = MedicColors.c83938B;
  static const green   = MedicColors.c4CAF50;
}

// ─── Scoring Logic ─────────────────────────────────────────────────────────
// Thin wrapper around HealthCalculator (the single source of truth for the
// MedicTrack Health Score formula) so the rest of this file — which was
// written against a systolic-only BP score and a 4-band sugar score — keeps
// working, but now produces numbers consistent with the project's official
// scoring tables (Blood Sugar / Blood Pressure / BMI / Age / Adherence,
// averaged for the daily Health Score).
class VitalsScoring {
  /// BP Score — needs both systolic AND diastolic per the official table.
  static int bpScore(int systolic, [int? diastolic]) =>
      VitalSummaryService.bloodPressure(systolic, diastolic).awarenessScore ?? 0;

  static String bpCondition(int systolic, [int? diastolic]) =>
      VitalSummaryService.bloodPressure(systolic, diastolic).label;

  static Color bpColor(int systolic, [int? diastolic]) {
    final summary = VitalSummaryService.bloodPressure(systolic, diastolic);
    return summary.needsAttention ? _C.rose : summary.level == 'reference' ? _C.teal : _C.amber;
  }

  static int? sugarScore(double value, {bool isMgDl = true, String context = VitalSummaryService.unknown}) =>
      VitalSummaryService.glucose(value, isMgDl: isMgDl, context: context).awarenessScore;
  static String sugarCondition(double value, {bool isMgDl = true, String context = VitalSummaryService.unknown}) =>
      VitalSummaryService.glucose(value, isMgDl: isMgDl, context: context).label;
  static Color sugarColor(double value, {bool isMgDl = true, String context = VitalSummaryService.unknown}) {
    final level = VitalSummaryService.glucose(value, isMgDl: isMgDl, context: context).level;
    return level == 'high' || level == 'low' || level == 'urgent' ? _C.rose
        : level == 'reference' ? _C.teal : _C.amber;
  }

  /// Age Score
  static int ageScore(int age) => HealthCalculator.ageScore(age);
  static String ageRisk(int age) => HealthCalculator.ageRiskTier(age);

  /// Adherence Score = (taken / total) * 100
  static int adherenceScore(int taken, int total) =>
      HealthCalculator.adherenceScore(taken, total);

  /// Final daily Health Score = plain average of every available component
  /// (Blood Sugar, Blood Pressure, BMI, Age, Adherence).
  static int healthScore({
    int? bpScore,
    int? sugarScore,
    required int bmiScore,
    required int ageScore,
    required int adherenceScore,
  }) =>
      HealthCalculator.overallScore(
        bloodPressure: bpScore,
        bloodSugar: sugarScore,
        bmiScoreValue: bmiScore,
        ageScoreValue: ageScore,
        adherenceScoreValue: adherenceScore,
      );

  static String scoreLevel(int score) => HealthCalculator.overallLevel(score);
  static String scoreMeaning(int score) => HealthCalculator.overallMeaning(score);
  static Color scoreColor(int score) => HealthCalculator.overallColor(score);
}

// ═══════════════════════════════════════════════════════════════════════════════
// VITALS UPLOAD SCREEN
// ═══════════════════════════════════════════════════════════════════════════════
class VitalsUploadScreen extends StatefulWidget {
  /// Set when this screen was opened to re-check a reading that came back
  /// high/urgent the first time (see `_handleRecheckFlow`). `recheckOf` is
  /// the Firestore id of that first high reading; `recheckType` is
  /// 'bloodPressure' or 'bloodSugar'.
  final String? recheckOf;
  final String? recheckType;
  const VitalsUploadScreen({Key? key, this.recheckOf, this.recheckType}) : super(key: key);

  @override
  State<VitalsUploadScreen> createState() => _VitalsUploadScreenState();
}

class _VitalsUploadScreenState extends State<VitalsUploadScreen>
    with SingleTickerProviderStateMixin {
  final AuthService _authSvc = AuthService();
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final ImagePicker _picker  = ImagePicker();

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  // ── Blood Pressure ────────────────────────────────────────────────────────
  File? _bpImage;
  bool _bpAnalyzing = false;
  bool _bpDone      = false;
  int?    _systolic;
  int?    _diastolic;
  int?    _pulse;

  // ── Blood Sugar ───────────────────────────────────────────────────────────
  File? _sugarImage;
  bool _sugarAnalyzing = false;
  bool _sugarDone      = false;
  double? _sugarValue;
  String _glucoseContext = VitalSummaryService.unknown;
  bool    _sugarIsMgDl = true; // default mg/dL

  // ── Saving ─────────────────────────────────────────────────────────────────
  bool _saving = false;
  final _a1cController = TextEditingController();
  double? get _a1cValue => scoreNumber(_a1cController.text.trim());
  final _weightController = TextEditingController();
  DateTime _measuredAt = DateTime.now();
  double? get _weightKg => double.tryParse(_weightController.text.trim().replaceAll(',', '.'));

  // Reads the one shared key/endpoint from GeminiService instead of its own
  // copy — see the doc comment on GeminiService for why this was centralized.
  static const _apiKey = GeminiService.apiKey;
  static const _apiUrl = GeminiService.baseUrl;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        duration: const Duration(milliseconds: 600), vsync: this);
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeIn);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _a1cController.dispose();
    _weightController.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  // ═══ GEMINI IMAGE ANALYSIS ════════════════════════════════════════════════

  Future<Map<String, dynamic>> _analyzeImageWithGemini(
      File image, String prompt) async {
    try {
      final bytes     = await image.readAsBytes();
      final base64Img = base64Encode(bytes);

      final res = await http.post(
        Uri.parse('$_apiUrl?key=$_apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {
                  'inline_data': {
                    'mime_type': 'image/jpeg',
                    'data': base64Img,
                  },
                },
                {'text': prompt},
              ],
            }
          ],
          'generationConfig': {
            'temperature': 0.1,
            'maxOutputTokens': 512,
            'responseMimeType': 'application/json',
          },
        }),
      );

      if (res.statusCode == 200) {
        final d   = jsonDecode(res.body);
        final raw = d['candidates']?[0]?['content']?['parts']?[0]?['text'] ?? '{}';
        final cleaned = raw
            .replaceAll('```json', '')
            .replaceAll('```', '')
            .trim();
        return jsonDecode(cleaned) as Map<String, dynamic>;
      }
      return {'error': 'HTTP ${res.statusCode}'};
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  // ─── Analyse BP image ─────────────────────────────────────────────────────
  Future<void> _analyzeBp() async {
    if (_bpImage == null) return;
    setState(() { _bpAnalyzing = true; _bpDone = false; });

    const prompt = '''
You are a medical data extractor. Look at this blood pressure monitor image carefully.
Extract the readings shown on the display.

Respond ONLY with valid JSON, no markdown:
{
  "systolic": <integer mmHg or null if not visible>,
  "diastolic": <integer mmHg or null if not visible>,
  "pulse": <integer bpm or null if not visible>,
  "confidence": "<high|medium|low>",
  "notes": "<any relevant notes about the reading>"
}

If the image does not show a blood pressure monitor, set all numeric values to null.
''';

    final result = await _analyzeImageWithGemini(_bpImage!, prompt);
    if (!mounted) return;

    if (result['error'] != null) {
      // debugPrint keeps the real status code visible in `flutter logs` /
      // `firebase functions:log`-style debugging without showing a
      // meaningless "HTTP 402" to someone trying to log a BP reading.
      debugPrint('BP analysis error: ${result['error']}');
      _snack(friendlyGeminiError(result['error']), error: true);
      setState(() { _bpAnalyzing = false; });
      return;
    }

    setState(() {
      _systolic  = scoreNumber(result['systolic'])?.round();
      _diastolic = scoreNumber(result['diastolic'])?.round();
      _pulse     = scoreNumber(result['pulse'])?.round();
      _bpAnalyzing = false;
      _bpDone = _systolic != null && _systolic! > 0 && _diastolic != null && _diastolic! > 0;
    });

    if (!_bpDone) {
      _snack('Could not read BP values from image. Try a clearer photo.',
          error: true);
    }
  }

  // ─── Analyse Blood Sugar image ────────────────────────────────────────────
  Future<void> _analyzeSugar() async {
    if (_sugarImage == null) return;
    setState(() { _sugarAnalyzing = true; _sugarDone = false; });

    const prompt = '''
You are a medical data extractor. Look at this blood glucose monitor image carefully.
Extract the blood sugar reading shown on the display.

Respond ONLY with valid JSON, no markdown:
{
  "value": <number or null if not visible>,
  "unit": "<mg/dL or mmol/L>",
  "confidence": "<high|medium|low>",
  "notes": "<any relevant notes>"
}

If the image does not show a glucose meter reading, set value to null.
''';

    final result = await _analyzeImageWithGemini(_sugarImage!, prompt);
    if (!mounted) return;

    if (result['error'] != null) {
      debugPrint('Blood sugar analysis error: ${result['error']}');
      _snack(friendlyGeminiError(result['error']), error: true);
      setState(() { _sugarAnalyzing = false; });
      return;
    }

    final rawVal = result['value'];
    final unit   = (result['unit'] ?? '').toString().toLowerCase();

    setState(() {
      _sugarValue  = scoreNumber(rawVal);
      _sugarIsMgDl = !unit.contains('mmol');
      _sugarAnalyzing = false;
      _sugarDone = _sugarValue != null && _sugarValue! > 0 && (unit.contains('mg/dl') || unit.contains('mmol'));
    });

    if (!_sugarDone) {
      _snack('Could not confirm the glucose value and unit. Try a clearer photo.',
          error: true);
    }
  }

  // ─── Pick image ────────────────────────────────────────────────────────────
  Future<void> _pickBpImage(ImageSource src) async {
    HapticFeedback.mediumImpact();
    try {
      final f = await _picker.pickImage(
          source: src, maxWidth: 1920, imageQuality: 90);
      if (f != null) {
        setState(() { _bpImage = File(f.path); _bpDone = false;
        _systolic = null; _diastolic = null; _pulse = null; });
        await _analyzeBp();
      }
    } catch (e) { _snack('Failed to pick image: $e', error: true); }
  }

  Future<void> _pickSugarImage(ImageSource src) async {
    HapticFeedback.mediumImpact();
    try {
      final f = await _picker.pickImage(
          source: src, maxWidth: 1920, imageQuality: 90);
      if (f != null) {
        setState(() { _sugarImage = File(f.path); _sugarDone = false;
        _sugarValue = null; });
        await _analyzeSugar();
      }
    } catch (e) { _snack('Failed to pick image: $e', error: true); }
  }

  // ─── Save to Firestore ────────────────────────────────────────────────────
  Future<void> _saveVitals() async {
    final weight = _weightKg;
    final lab = _a1cValue;
    if (_a1cController.text.trim().isNotEmpty && (lab == null || lab <= 0 || lab > 25)) {
      _snack('Enter the HbA1c percentage printed on your lab result.', error: true); return;
    }
    if (_weightController.text.trim().isNotEmpty &&
        (weight == null || !weight.isFinite || weight <= 0 || weight > 500)) {
      _snack('Enter a valid weight in kg (greater than 0 and at most 500).', error: true);
      return;
    }
    if (!_bpDone && !_sugarDone && weight == null && lab == null) {
      _snack('Scan a vital or enter your weight first.', error: true); return;
    }
    if (_measuredAt.isAfter(DateTime.now())) {
      _snack('The reading time cannot be in the future.', error: true); return;
    }
    final user = _authSvc.currentUser;
    if (user == null) { _snack('Not logged in', error: true); return; }

    setState(() => _saving = true);

    try {
      final now = FieldValue.serverTimestamp();
      int? adherenceAtSave;
      try {
        adherenceAtSave = await HealthScoreService.adherence(user.uid)
            .timeout(const Duration(seconds: 8));
      } catch (error) {
        debugPrint('Adherence omitted from this upload snapshot: $error');
      }


      // Save vitals record
      final vitalsRef = _db
          .collection('users')
          .doc(user.uid)
          .collection('vitals')
          .doc();

      final vitalsData = <String, dynamic>{
        'userId':    user.uid,
        'recordedAt': now,
        'measuredAt': Timestamp.fromDate(_measuredAt),
        'clientRecordedAt': Timestamp.now(),
        if (weight != null) 'weightKg': weight,
        if (lab != null) 'hba1c': {'value': lab, 'unit': '%', 'type': 'lab', 'score': HealthCalculator.bloodSugarScore(lab)},
      };

      if (_bpDone && _systolic != null) {
        vitalsData['bloodPressure'] = {
          'systolic':  _systolic,
          'diastolic': _diastolic,
          'pulse':     _pulse,
          'condition': VitalSummaryService.bloodPressure(_systolic!, _diastolic).label,
          'score':     VitalSummaryService.bloodPressure(_systolic!, _diastolic).awarenessScore,
          'summary': VitalSummaryService.bloodPressure(_systolic!, _diastolic).toMap(),
        };
      }
      if (_sugarDone && _sugarValue != null) {
        vitalsData['bloodSugar'] = {
          'value':     _sugarValue,
          'unit':      _sugarIsMgDl ? 'mg/dL' : 'mmol/L',
          'valueMmol': _sugarIsMgDl ? _sugarValue! / 18.0 : _sugarValue,
          'condition': VitalsScoring.sugarCondition(_sugarValue!, isMgDl: _sugarIsMgDl, context: _glucoseContext),
          'score':     VitalsScoring.sugarScore(_sugarValue!, isMgDl: _sugarIsMgDl, context: _glucoseContext),
          'readingContext': _glucoseContext,
          'scoreModel': 'glucose-reference-v1',
          'summary': VitalSummaryService.glucose(_sugarValue!, isMgDl: _sugarIsMgDl, context: _glucoseContext).toMap(),
        };
      }



      // Update latest vitals on user doc (for quick access in profile)
      final userRef = _db.collection('users').doc(user.uid);
      final updateData = <String, dynamic>{'latestVitalsAt': now};
      if (_bpDone && _systolic != null) {
        updateData['latestBP'] = {
          'systolic':  _systolic,
          'diastolic': _diastolic,
          'pulse':     _pulse,
          'condition': VitalSummaryService.bloodPressure(_systolic!, _diastolic).label,
          'score':     VitalSummaryService.bloodPressure(_systolic!, _diastolic).awarenessScore,
          'summary': VitalSummaryService.bloodPressure(_systolic!, _diastolic).toMap(),
          'recordedAt': now,
          'measuredAt': Timestamp.fromDate(_measuredAt),
        };
      }
      if (_sugarDone && _sugarValue != null) {
        updateData['latestSugar'] = {
          'value':     _sugarValue,
          'unit':      _sugarIsMgDl ? 'mg/dL' : 'mmol/L',
          'valueMmol': _sugarIsMgDl ? _sugarValue! / 18.0 : _sugarValue,
          'condition': VitalsScoring.sugarCondition(_sugarValue!, isMgDl: _sugarIsMgDl, context: _glucoseContext),
          'score':     VitalsScoring.sugarScore(_sugarValue!, isMgDl: _sugarIsMgDl, context: _glucoseContext),
          'readingContext': _glucoseContext,
          'scoreModel': 'glucose-reference-v1',
          'summary': VitalSummaryService.glucose(_sugarValue!, isMgDl: _sugarIsMgDl, context: _glucoseContext).toMap(),
          'recordedAt': now,
          'measuredAt': Timestamp.fromDate(_measuredAt),
        };
      }
      // Update history and cached latest readings atomically. A backdated
      // reading belongs in history but must not replace a more recent vital.
      await _db.runTransaction((transaction) async {
        final profile = (await transaction.get(userRef)).data() ?? {};
        bool replaceLatest(Object? old) {
          final map = old is Map ? old : const <String, dynamic>{};
          final timestamp = map['measuredAt'] ?? map['recordedAt'];
          return timestamp is! Timestamp ||
              !_measuredAt.isBefore(timestamp.toDate());
        }
        final updates = Map<String, dynamic>.from(updateData);
        if (lab != null && replaceLatest(profile['latestHbA1c'])) {
          updates['latestHbA1c'] = {'value': lab, 'unit': '%', 'measuredAt': Timestamp.fromDate(_measuredAt), 'recordedAt': now};
        }
        if (!replaceLatest(profile['latestBP'])) updates.remove('latestBP');
        if (!replaceLatest(profile['latestSugar'])) updates.remove('latestSugar');
        if (weight != null && replaceLatest(profile['latestWeight'])) {
          updates['latestWeight'] = {
            'value': weight, 'unit': 'kg',
            'measuredAt': Timestamp.fromDate(_measuredAt), 'recordedAt': now,
          };
          updates['healthInfo'] = {'weight': weight};
        }
        final snapshotProfile = <String, dynamic>{
          ...profile, ...updates,
          'healthInfo': {
            ...scoreMap(profile['healthInfo']), ...scoreMap(updates['healthInfo']),
          },
        };
        final scoreSnapshot = HealthScoreSnapshot.fromProfile(
          snapshotProfile, adherence: adherenceAtSave,
        );
        transaction.set(vitalsRef, {
          ...vitalsData, 'healthScoreSnapshot': scoreSnapshot.toFirestore(),
        });
        transaction.set(userRef, updates, SetOptions(merge: true));
      });

      // Notification delivery runs independently of the saved-reading summary.
      HealthMonitoringService.refresh().then<void>((_) {}, onError: (Object error, StackTrace stack) {
        debugPrint('Vitals saved; monitoring refresh deferred to backend: $error');
      });

      if (mounted) {
        HapticFeedback.mediumImpact();
        await _handleRecheckFlow(user.uid, vitalsRef.id);
        if (mounted) Navigator.pop(context, true);
      }
    } catch (e) {
      _snack('Failed to save: $e', error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  // ── High-reading recheck workflow ───────────────────────────────────────
  // Step 1: a high/urgent BP or sugar reading is saved as normal. Step 2:
  // the person is asked to wait (1–3 minutes for BP, ~30 minutes for sugar —
  // the same windows shown in the on-reading guidance) and recheck. Step 3:
  // if the recheck is ALSO high, this escalates to a clear "visit a doctor"
  // message instead of just repeating the reading summary.
  static const bpRecheckWait = Duration(minutes: 3);
  static const sugarRecheckWait = Duration(minutes: 30);

  Future<void> _handleRecheckFlow(String uid, String vitalsId) async {
    final bpSummary = _bpDone && _systolic != null
        ? VitalSummaryService.bloodPressure(_systolic!, _diastolic) : null;
    final sugarSummary = _sugarDone && _sugarValue != null
        ? VitalSummaryService.glucose(_sugarValue!, isMgDl: _sugarIsMgDl, context: _glucoseContext) : null;
    final bpHigh = bpSummary?.needsAttention ?? false;
    final sugarHigh = sugarSummary?.needsAttention ?? false;

    if (widget.recheckOf != null) {
      // This save IS the recheck of an earlier high reading.
      final type = widget.recheckType;
      final stillHigh = (type == 'bloodPressure' && bpHigh) || (type == 'bloodSugar' && sugarHigh);
      try {
        await _db.collection('users').doc(uid).update({'pendingRecheck': FieldValue.delete()});
      } catch (_) { /* best effort */ }
      if (stillHigh) {
        await _showRecheckEscalation(type == 'bloodPressure' ? bpSummary : sugarSummary,
            type == 'bloodPressure' ? 'blood pressure' : 'blood sugar');
        return;
      }
      await _showSavedSummary(reassureAfterRecheck: true);
      return;
    }

    // Fresh reading: if it's high, save the "needs a recheck" state and
    // ask the person to wait before rechecking, instead of just moving on.
    String? type;
    Duration? wait;
    if (bpHigh) { type = 'bloodPressure'; wait = bpRecheckWait; }
    else if (sugarHigh) { type = 'bloodSugar'; wait = sugarRecheckWait; }

    if (type != null && wait != null) {
      final dueAt = DateTime.now().add(wait);
      final direction = (type == 'bloodPressure' ? bpSummary : sugarSummary)?.level == 'low' ? 'low' : 'high';
      try {
        // remindedAt starts null so the server-side reminder (see
        // functions/index.js sendRecheckReminders) knows this one still
        // needs a push once dueAt passes — covers the case where the
        // person closes the app before the in-app countdown finishes.
        await _db.collection('users').doc(uid).set({'pendingRecheck': {
          'type': type, 'direction': direction, 'firstVitalsId': vitalsId, 'dueAt': Timestamp.fromDate(dueAt),
          'createdAt': FieldValue.serverTimestamp(), 'remindedAt': null,
        }}, SetOptions(merge: true));
      } catch (_) { /* best effort; the on-screen prompt still shows */ }
      await _showRecheckPrompt(type, wait, vitalsId, direction);
      return;
    }

    await _showSavedSummary();
  }

  Future<void> _showRecheckPrompt(String type, Duration wait, String firstVitalsId, String direction) async {
    if (!mounted) return;
    final label = type == 'bloodPressure' ? 'blood pressure' : 'blood sugar';
    final waitLabel = type == 'bloodPressure' ? '1 to 3 minutes' : 'about 30 minutes';
    await showModalBottomSheet<void>(context: context, isScrollControlled: true, backgroundColor: _C.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      isDismissible: false, enableDrag: false,
      builder: (sheetContext) {
        Duration left = wait;
        Timer? timer;
        return SafeArea(child: StatefulBuilder(builder: (context, setLocal) {
          timer ??= Timer.periodic(const Duration(seconds: 1), (t) {
            final remaining = wait - Duration(seconds: t.tick);
            setLocal(() => left = remaining.isNegative ? Duration.zero : remaining);
            if (remaining.isNegative) t.cancel();
          });
          final ready = left == Duration.zero;
          final minutes = left.inMinutes, seconds = left.inSeconds % 60;
          return SingleChildScrollView(padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Icon(Icons.warning_amber_rounded, color: _C.rose, size: 26),
                const SizedBox(width: 10), Expanded(child: Text('Your $label reading is $direction',
                  style: const TextStyle(fontFamily: 'serif', fontSize: 22, color: _C.navy)))]),
              const SizedBox(height: 14),
              Text('This first reading has been saved. Please rest, then recheck your $label in $waitLabel '
                  'to confirm it — a single high reading is not unusual and rechecking avoids a false alarm.',
                  style: const TextStyle(fontSize: 13, height: 1.6, color: _C.textSec)),
              const SizedBox(height: 20),
              if (!ready) Container(width: double.infinity, padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: _C.teal.withOpacity(.08), borderRadius: BorderRadius.circular(18)),
                child: Column(children: [
                  Text('${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: _C.navy)),
                  const SizedBox(height: 4),
                  const Text('until you can recheck', style: TextStyle(fontSize: 12, color: _C.textSec)),
                ])),
              const SizedBox(height: 16),
              SizedBox(width: double.infinity, child: FilledButton.icon(
                onPressed: !ready ? null : () {
                  timer?.cancel();
                  Navigator.pop(sheetContext);
                  Navigator.push(context, MaterialPageRoute(builder: (_) =>
                    VitalsUploadScreen(recheckOf: firstVitalsId, recheckType: type)));
                },
                icon: const Icon(Icons.replay_rounded),
                label: Text(ready ? 'Recheck now' : 'Please wait…'))),
              const SizedBox(height: 8),
              SizedBox(width: double.infinity, child: TextButton(
                onPressed: () { timer?.cancel(); Navigator.pop(sheetContext); },
                child: const Text("I'll recheck later"))),
            ]));
        }));
      },
    );
  }

  Future<void> _showRecheckEscalation(VitalSummary? summary, String label) async {
    if (!mounted) return;
    // Wording adapts to the actual direction (high/low/urgent) — this also
    // covers low BP/sugar, not just high, since needsAttention and this
    // whole recheck flow already treat 'low' the same as 'high'/'urgent'.
    final direction = summary?.level == 'low' ? 'low' : 'high';
    await showDialog<void>(context: context, barrierDismissible: false, builder: (context) => AlertDialog(
      backgroundColor: _C.surface,
      title: Row(children: [Icon(Icons.local_hospital_rounded, color: _C.rose), const SizedBox(width: 10),
        const Expanded(child: Text('Please visit a doctor'))]),
      content: Text('Your $label was $direction on the first reading and is still $direction on the recheck'
          '${summary != null ? ' (${summary.label.toLowerCase()})' : ''}. Two confirmed $direction readings in a '
          'row are not something to wait out — please contact your clinician or visit a doctor soon. '
          'If you also feel unwell (chest pain, shortness of breath, confusion, fainting or severe symptoms), '
          'treat it as an emergency and get help immediately.',
          style: const TextStyle(fontSize: 13, height: 1.6, color: _C.textSec)),
      actions: [FilledButton(onPressed: () => Navigator.pop(context), style: FilledButton.styleFrom(backgroundColor: _C.rose),
          child: const Text('I understand'))],
    ));
  }

  List<VitalSummary> get _summaries => [
    if (_a1cValue != null) VitalSummary('HbA1c lab result recorded',
      'This laboratory percentage reflects longer-term glucose exposure and is separate from a meter reading. '
      'Compare it with your clinician’s individual target; do not interpret changes as a daily glucose trend.',
      _a1cValue! >= 7 ? 'watch' : 'reference', null),
    if (_bpDone && _systolic != null) VitalSummaryService.bloodPressure(_systolic!, _diastolic),
    if (_sugarDone && _sugarValue != null) VitalSummaryService.glucose(_sugarValue!, isMgDl: _sugarIsMgDl, context: _glucoseContext),
  ];

  Widget _mealContextCard() => Container(padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: _C.border)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const MedicEyebrow('When was glucose measured?'), const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final entry in const {VitalSummaryService.unknown: 'Not sure', VitalSummaryService.beforeMeal: 'Before meal',
          VitalSummaryService.afterMeal: '1–2 hours after meal'}.entries)
          ChoiceChip(label: Text(entry.value, style: const TextStyle(fontSize: 11)), selected: _glucoseContext == entry.key,
            selectedColor: MedicColors.mint, onSelected: _saving ? null : (_) => setState(() => _glucoseContext = entry.key)),
      ]),
      const SizedBox(height: 10), const Text('General diabetes targets for nonpregnant adults. Use your clinician’s personal target.',
        style: TextStyle(fontSize: 11, color: _C.textSec, height: 1.5)),
    ]));

  Widget _readingSummary() => AnimatedSize(duration: MediaQuery.of(context).disableAnimations ? Duration.zero : const Duration(milliseconds: 300),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Your reading summary', style: TextStyle(fontFamily: 'serif', fontSize: 24, color: _C.navy)),
      const SizedBox(height: 12),
      for (final summary in _summaries) Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: (summary.needsAttention ? _C.rose : _C.teal).withOpacity(.07),
          borderRadius: BorderRadius.circular(22), border: Border.all(color: _C.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(summary.label, style: TextStyle(fontWeight: FontWeight.w700, color: summary.needsAttention ? _C.rose : _C.teal)),
          const SizedBox(height: 7), Text(summary.message, style: const TextStyle(fontSize: 12, height: 1.6, color: _C.textSec)),
        ])),
      TextButton.icon(onPressed: _saving ? null : _confirmReadings, icon: const Icon(Icons.edit_outlined, size: 17),
        label: const Text('Check or correct scanned readings')),
    ]));

  Future<void> _confirmReadings() async {
    final sys = TextEditingController(text: _systolic?.toString() ?? '');
    final dia = TextEditingController(text: _diastolic?.toString() ?? '');
    final glucose = TextEditingController(text: _sugarValue?.toString() ?? '');
    var mg = _sugarIsMgDl;
    final form = GlobalKey<FormState>();
    final ok = await showDialog<bool>(context: context, builder: (context) => MedicDialogControllerScope(controllers: [sys, dia, glucose], child: StatefulBuilder(builder: (context, update) => AlertDialog(
      backgroundColor: _C.surface, title: const Text('Confirm meter readings'),
      content: SingleChildScrollView(child: Form(key: form, child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (_bpDone) ...[
          TextFormField(controller: sys, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Systolic · mmHg'),
            validator: (v) => (int.tryParse(v ?? '') ?? 0) > 0 ? null : 'Enter a positive whole number'),
          TextFormField(controller: dia, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Diastolic · mmHg'),
            validator: (v) => (int.tryParse(v ?? '') ?? 0) > 0 ? null : 'Enter a positive whole number'),
        ],
        if (_sugarDone) ...[
          TextFormField(controller: glucose, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Blood glucose'),
            validator: (v) { final n = scoreNumber(v); return n != null && n > 0 ? null : 'Enter a positive number'; }),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(mg ? 'Unit: mg/dL' : 'Unit: mmol/L'), value: mg,
            onChanged: (v) => update(() => mg = v)),
        ],
      ]))), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () { if (form.currentState!.validate()) Navigator.pop(context, true); }, child: const Text('Confirm'))],
    ))));
    if (ok == true && mounted) setState(() {
      if (_bpDone) { _systolic = int.parse(sys.text); _diastolic = int.parse(dia.text); }
      if (_sugarDone) { _sugarValue = double.parse(glucose.text); _sugarIsMgDl = mg; }
    });
  }

  Future<void> _showSavedSummary({bool reassureAfterRecheck = false}) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(context: context, isScrollControlled: true, backgroundColor: _C.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      builder: (context) => SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          MedicEyebrow(reassureAfterRecheck ? 'Recheck saved' : 'Record saved'), const SizedBox(height: 10),
          Text(reassureAfterRecheck ? 'Good — back within reference' : 'Your latest readings',
            style: const TextStyle(fontFamily: 'serif', fontSize: 28, color: _C.navy)),
          const SizedBox(height: 20),
          if (reassureAfterRecheck) Padding(padding: const EdgeInsets.only(bottom: 14), child: Text(
            'Your recheck reading is no longer high/urgent. No doctor visit is needed based on this alone — '
            'keep an eye on it and mention the earlier high reading at your next check-up.',
            style: const TextStyle(fontSize: 13, height: 1.6, color: _C.textSec))),
          for (final summary in _summaries) Padding(padding: const EdgeInsets.only(bottom: 18), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(summary.label, style: TextStyle(color: summary.needsAttention ? _C.rose : _C.teal, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6), Text(summary.message, style: const TextStyle(fontSize: 13, height: 1.6, color: _C.textSec)),
            ])),
          if (_summaries.isEmpty) const Text('Your weight record has been saved.'),
          SizedBox(width: double.infinity, child: FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))),
        ]))));
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(error ? Icons.error_outline_rounded : Icons.check_circle_rounded,
            color: Colors.white, size: 15),
        const SizedBox(width: 9),
        Expanded(child: Text(msg, style: const TextStyle(
            fontWeight: FontWeight.w600, fontSize: 13))),
      ]),
      backgroundColor: _C.navy,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(14),
    ));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.light,
    child: Scaffold(
      backgroundColor: _C.surface,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Column(children: [
          _buildHeader(),
          Expanded(child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
            child: Column(children: [

              // ── Intro banner ─────────────────────────────────────────────
              _InfoBanner(),
              const SizedBox(height: 20),

              _readingDateCard(),
              const SizedBox(height: 16),

              // ── Blood Pressure card ───────────────────────────────────────
              _VitalScanCard(
                icon: Icons.favorite_rounded,
                iconColor: _C.rose,
                title: 'Blood Pressure',
                subtitle: 'Upload a photo of your BP monitor display',
                image: _bpImage,
                isAnalyzing: _bpAnalyzing,
                isDone: _bpDone,
                onCamera: () => _pickBpImage(ImageSource.camera),
                onGallery: () => _pickBpImage(ImageSource.gallery),
                onRetake: () => setState(() {
                  _bpImage = null; _bpDone = false;
                  _systolic = null; _diastolic = null; _pulse = null;
                }),
                resultWidget: _bpDone && _systolic != null
                    ? _BpResult(
                  systolic: _systolic!,
                  diastolic: _diastolic,
                  pulse: _pulse,
                )
                    : null,
              ),
              const SizedBox(height: 16),

              // ── Blood Sugar card ──────────────────────────────────────────
              _VitalScanCard(
                icon: Icons.water_drop_rounded,
                iconColor: _C.amber,
                title: 'Blood Sugar',
                subtitle: 'Upload a photo of your glucose meter display',
                image: _sugarImage,
                isAnalyzing: _sugarAnalyzing,
                isDone: _sugarDone,
                onCamera: () => _pickSugarImage(ImageSource.camera),
                onGallery: () => _pickSugarImage(ImageSource.gallery),
                onRetake: () => setState(() {
                  _sugarImage = null; _sugarDone = false; _sugarValue = null;
                }),
                resultWidget: _sugarDone && _sugarValue != null
                    ? _SugarResult(
                  value: _sugarValue!,
                  isMgDl: _sugarIsMgDl,
                  readingContext: _glucoseContext,
                )
                    : null,
              ),
              const SizedBox(height: 24),

              if (_sugarDone) ...[
                _mealContextCard(), const SizedBox(height: 16),
              ],
              if (_bpDone || _sugarDone) ...[
                _readingSummary(), const SizedBox(height: 22),
              ],
              _labEntryCard(), const SizedBox(height: 18),
              _weightEntryCard(),
              const SizedBox(height: 24),

              // ── Save button ───────────────────────────────────────────────
              if (_bpDone || _sugarDone || _weightController.text.trim().isNotEmpty || _a1cController.text.trim().isNotEmpty) ...[
                GestureDetector(
                  onTap: _saving ? null : _saveVitals,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    height: 52, width: double.infinity,
                    decoration: BoxDecoration(
                        color: _saving ? _C.teal.withOpacity(0.6) : _C.teal,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: _saving ? [] : [BoxShadow(
                            color: _C.teal.withOpacity(0.3),
                            blurRadius: 14, offset: const Offset(0, 5))]),
                    child: Center(child: _saving
                        ? const SizedBox(width: 22, height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.white))
                        : const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.save_rounded, color: Colors.white, size: 19),
                        SizedBox(width: 9),
                        Text('Save Vitals', style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w700,
                            fontSize: 15)),
                      ],
                    )),
                  ),
                ),
              ],
            ]),
          )),
        ]),
      ),
    ),
  );

  Widget _readingDateCard() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('When was this reading taken?', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      const Text('Use the measurement date for accurate daily comparisons.',
          style: TextStyle(fontSize: 12, color: _C.textSec)),
      const SizedBox(height: 10),
      Wrap(spacing: 8, children: [
        OutlinedButton.icon(icon: const Icon(Icons.calendar_today_outlined, size: 16),
          label: Text('${_measuredAt.day}/${_measuredAt.month}/${_measuredAt.year}'),
          onPressed: _saving ? null : () async {
            final now = DateTime.now();
            final date = await showDatePicker(context: context,
                initialDate: _measuredAt, firstDate: DateTime(2000), lastDate: now);
            if (date == null || !mounted) return;
            setState(() {
              final chosen = DateTime(date.year, date.month, date.day, _measuredAt.hour, _measuredAt.minute);
              _measuredAt = chosen.isAfter(now) ? now : chosen;
            });
          }),
        OutlinedButton.icon(icon: const Icon(Icons.access_time_rounded, size: 16),
          label: Text('${_measuredAt.hour.toString().padLeft(2, '0')}:${_measuredAt.minute.toString().padLeft(2, '0')}'),
          onPressed: _saving ? null : () async {
            final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_measuredAt));
            if (time == null || !mounted) return;
            final chosen = DateTime(_measuredAt.year, _measuredAt.month, _measuredAt.day, time.hour, time.minute);
            if (chosen.isAfter(DateTime.now())) {
              _snack('Choose a reading time that is not in the future.', error: true);
              return;
            }
            setState(() => _measuredAt = chosen);
          }),
      ]),
    ]),
  );

  Widget _labEntryCard() => Container(padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: _C.border)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const MedicEyebrow('Optional laboratory result'), const SizedBox(height: 10),
      TextField(controller: _a1cController, enabled: !_saving, keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'HbA1c · %', hintText: 'Enter the value printed on your lab report')),
      const SizedBox(height: 10), const Text('Use the laboratory test date above. HbA1c is separate from daily meter glucose and does not trigger an emergency alarm from its percentage alone.',
        style: TextStyle(fontSize: 11, color: _C.textSec, height: 1.5)),
    ]));

  Widget _weightEntryCard() => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Row(children: [Icon(Icons.monitor_weight_outlined, color: _C.teal), SizedBox(width: 10),
        Text('Weight', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))]),
      const SizedBox(height: 8),
      const Text('Optional: enter the scale reading for this measurement date.',
          style: TextStyle(fontSize: 12, color: _C.textSec)),
      const SizedBox(height: 12),
      TextField(controller: _weightController, enabled: !_saving,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(labelText: 'Weight', suffixText: 'kg', hintText: 'e.g. 72.5',
          border: OutlineInputBorder())),
    ]),
  );

  Widget _buildHeader() => const MedicPageTitle(
    title: 'Capture your vitals', subtitle: 'Add a health report or enter your latest readings.',
  );
}

// ─── Info Banner ──────────────────────────────────────────────────────────────
class _InfoBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
        color: _C.teal.withOpacity(0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _C.teal.withOpacity(0.2))),
    child: Row(children: [
      const Icon(Icons.tips_and_updates_rounded, color: _C.teal, size: 18),
      const SizedBox(width: 10),
      const Expanded(child: Text(
        'Take a clear photo of your monitor\'s display screen. '
            'The AI will extract the reading automatically.',
        style: TextStyle(fontSize: 12, color: _C.textSec, height: 1.4),
      )),
    ]),
  );
}

// ─── Vital Scan Card ──────────────────────────────────────────────────────────
class _VitalScanCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title, subtitle;
  final File? image;
  final bool isAnalyzing, isDone;
  final VoidCallback onCamera, onGallery, onRetake;
  final Widget? resultWidget;

  const _VitalScanCard({
    required this.icon, required this.iconColor,
    required this.title, required this.subtitle,
    required this.image, required this.isAnalyzing, required this.isDone,
    required this.onCamera, required this.onGallery, required this.onRetake,
    this.resultWidget,
  });

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
        color: _C.card, borderRadius: BorderRadius.circular(24),
        border: Border.all(
            color: isDone ? iconColor.withOpacity(0.3) : _C.border,
            width: isDone ? 1.5 : 1.0),
        boxShadow: [BoxShadow(
            color: MedicColors.forest.withOpacity(0.025),
            blurRadius: 12, offset: const Offset(0, 3))]),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

      // Card header
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Row(children: [
          Container(width: 40, height: 40,
              decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: iconColor, size: 20)),
          const SizedBox(width: 12),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w700, color: _C.textPri)),
            Text(subtitle, style: const TextStyle(
                fontSize: 11, color: _C.textTer)),
          ])),
          if (isDone)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.check_rounded, color: iconColor, size: 12),
                const SizedBox(width: 3),
                Text('Done', style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w700,
                    color: iconColor)),
              ]),
            ),
        ]),
      ),

      // Image preview
      if (image != null) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(children: [
              Image.file(image!,
                  height: 140, width: double.infinity, fit: BoxFit.cover),
              if (isAnalyzing)
                Positioned.fill(child: Container(
                  color: Colors.black.withOpacity(0.55),
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center, children: [
                    const SizedBox(width: 28, height: 28,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.white)),
                    const SizedBox(height: 10),
                    const Text('Analysing…', style: TextStyle(
                        color: Colors.white, fontSize: 12,
                        fontWeight: FontWeight.w600)),
                  ]),
                )),
              // Retake button
              if (!isAnalyzing)
                Positioned(top: 8, right: 8,
                    child: GestureDetector(
                      onTap: onRetake,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 5),
                        decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.65),
                            borderRadius: BorderRadius.circular(12)),
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.refresh_rounded,
                              color: Colors.white, size: 12),
                          SizedBox(width: 4),
                          Text('Retake', style: TextStyle(
                              color: Colors.white, fontSize: 10,
                              fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    )),
            ]),
          ),
        ),
      ],

      // Result widget
      if (resultWidget != null) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: resultWidget!,
        ),
      ],

      // Upload buttons (show if no image yet)
      if (image == null) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(children: [
            Expanded(child: _PickBtn(
              icon: Icons.camera_alt_rounded, label: 'Camera',
              color: iconColor, onTap: onCamera,
            )),
            const SizedBox(width: 10),
            Expanded(child: _PickBtn(
              icon: Icons.photo_library_rounded, label: 'Gallery',
              color: _C.violet, onTap: onGallery,
            )),
          ]),
        ),
      ],

      // Retry button (image present but analysis failed)
      if (image != null && !isDone && !isAnalyzing) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(children: [
            Expanded(child: _PickBtn(
              icon: Icons.camera_alt_rounded, label: 'Camera',
              color: iconColor, onTap: onCamera,
            )),
            const SizedBox(width: 10),
            Expanded(child: _PickBtn(
              icon: Icons.photo_library_rounded, label: 'Gallery',
              color: _C.violet, onTap: onGallery,
            )),
          ]),
        ),
      ],
    ]),
  );
}

// ─── BP Result Widget ─────────────────────────────────────────────────────────
class _BpResult extends StatelessWidget {
  final int systolic;
  final int? diastolic, pulse;
  const _BpResult({required this.systolic, this.diastolic, this.pulse});

  @override
  Widget build(BuildContext context) {
    final color     = VitalsScoring.bpColor(systolic, diastolic);
    final condition = VitalsScoring.bpCondition(systolic, diastolic);
    final score     = VitalsScoring.bpScore(systolic, diastolic);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.25))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Condition badge + score
        Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10)),
            constraints: const BoxConstraints(maxWidth: 190),
            child: Text(condition, maxLines: 2, style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          Text('App score: $score/100', style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700, color: color)),
        ]),
        const SizedBox(height: 12),
        // Readings row
        Row(children: [
          _Reading('$systolic', 'Systolic', 'mmHg', color),
          const SizedBox(width: 12),
          if (diastolic != null) ...[
            _Reading('$diastolic', 'Diastolic', 'mmHg', _C.textSec),
            const SizedBox(width: 12),
          ],
          if (pulse != null)
            _Reading('$pulse', 'Pulse', 'bpm', _C.sky),
        ]),
        const SizedBox(height: 8),
        // Progress bar
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (score ?? 0) / 100,
            backgroundColor: _C.border,
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 5,
          ),
        ),
      ]),
    );
  }
}

class _Reading extends StatelessWidget {
  final String value, label, unit;
  final Color color;
  const _Reading(this.value, this.label, this.unit, this.color);

  @override
  Widget build(BuildContext context) => Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(value, style: TextStyle(
        fontSize: 28, fontWeight: FontWeight.w700,
        color: color, letterSpacing: -1)),
    Text('$label ($unit)', style: const TextStyle(
        fontSize: 10, color: _C.textTer, fontWeight: FontWeight.w500)),
  ]);
}

// ─── Sugar Result Widget ──────────────────────────────────────────────────────
class _SugarResult extends StatelessWidget {
  final double value;
  final bool isMgDl;
  final String readingContext;
  const _SugarResult({required this.value, required this.isMgDl, this.readingContext = VitalSummaryService.unknown});

  @override
  Widget build(BuildContext context) {
    final color     = VitalsScoring.sugarColor(value, isMgDl: isMgDl, context: readingContext);
    final condition = VitalsScoring.sugarCondition(value, isMgDl: isMgDl, context: readingContext);
    final score     = VitalsScoring.sugarScore(value, isMgDl: isMgDl, context: readingContext);
    final mmol      = isMgDl ? value / 18.0 : value;
    final mgdl      = isMgDl ? value : value * 18.0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.25))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10)),
            constraints: const BoxConstraints(maxWidth: 190),
            child: Text(condition, maxLines: 2, style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          Text(score == null ? 'Add meal timing' : 'App score: $score/100', style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700, color: color)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Text(isMgDl ? '${value.toInt()}' : value.toStringAsFixed(1),
              style: TextStyle(
                  fontSize: 36, fontWeight: FontWeight.w700,
                  color: color, letterSpacing: -1)),
          const SizedBox(width: 6),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(isMgDl ? 'mg/dL' : 'mmol/L', style: const TextStyle(
                fontSize: 12, color: _C.textSec, fontWeight: FontWeight.w600)),
            Text(isMgDl
                ? '${mmol.toStringAsFixed(1)} mmol/L'
                : '${mgdl.toInt()} mg/dL',
                style: const TextStyle(fontSize: 10, color: _C.textTer)),
          ]),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (score ?? 0) / 100,
            backgroundColor: _C.border,
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 5,
          ),
        ),
      ]),
    );
  }
}

// ─── Pick Button ──────────────────────────────────────────────────────────────
class _PickBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _PickBtn({required this.icon, required this.label,
    required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
          color: color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.25))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 42, height: 42,
            decoration: BoxDecoration(
                color: color.withOpacity(0.12), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 20)),
        const SizedBox(height: 8),
        Text(label, style: TextStyle(
            fontSize: 13, fontWeight: FontWeight.w700, color: color)),
      ]),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// HEALTH SCORE PANEL — drop this into the Profile screen's Health section
// ═══════════════════════════════════════════════════════════════════════════════
class HealthScorePanel extends StatelessWidget {
  final Map<String,dynamic>? userData;
  final VoidCallback onTapScanVitals;
  const HealthScorePanel({super.key,required this.userData,required this.onTapScanVitals});
  @override
  Widget build(BuildContext context)=>Column(children:[
    const DailyHealthScoreCard(dark:true),const SizedBox(height:12),
    const Text('Same daily score across Home, My health, Records and monitoring. Missing data is excluded; this is not a diagnosis.',
      style:TextStyle(fontSize:11,height:1.6,color:MedicColors.muted)),const SizedBox(height:10),
    OutlinedButton.icon(onPressed:onTapScanVitals,icon:const Icon(Icons.add_rounded),label:const Text('Add or update readings')),
  ]);
}

class _MeshPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(Offset(size.width * 0.88, size.height * 0.2), 80,
        Paint()..color = _C.rose.withOpacity(0.07));
    canvas.drawCircle(Offset(size.width * 0.05, size.height * 0.85), 60,
        Paint()..color = _C.sky.withOpacity(0.06));
  }
  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _ScoreBgPainter extends CustomPainter {
  final Color accent;
  const _ScoreBgPainter(this.accent);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(Offset(size.width * 0.85, size.height * 0.15), 100,
        Paint()..color = accent.withOpacity(0.06));
    canvas.drawCircle(Offset(size.width * 0.05, size.height * 0.9), 80,
        Paint()..color = _C.sky.withOpacity(0.04));
  }
  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}