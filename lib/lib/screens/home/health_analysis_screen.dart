import 'daily_health_score_card.dart';
import '../../services/dose_service.dart';
import 'package:medictrack/design/medic_design.dart';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../../services/auth_service.dart';
import '../../services/gemini_service.dart';

// ─── Design Tokens ────────────────────────────────────────────────────────────
class _C {
  static const navy    = MedicColors.c142F2B;
  static const navyMid = MedicColors.c23473E;
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
}

// ─── Language Config ──────────────────────────────────────────────────────────
class _Lang {
  final String code, name, flag, geminiName, ttsLocale;
  const _Lang({
    required this.code,
    required this.name,
    required this.flag,
    required this.geminiName,
    required this.ttsLocale, // BCP-47 locale for flutter_tts
  });
}

const _kLanguages = [
  _Lang(code: 'en', name: 'English',          flag: '🇬🇧', geminiName: 'English',           ttsLocale: 'en-US'),
  _Lang(code: 'ms', name: 'Bahasa Melayu',    flag: '🇲🇾', geminiName: 'Bahasa Melayu',      ttsLocale: 'ms-MY'),
  _Lang(code: 'zh', name: 'Mandarin',         flag: '🇨🇳', geminiName: 'Simplified Chinese', ttsLocale: 'zh-CN'),
  _Lang(code: 'ta', name: 'Tamil',            flag: '🇮🇳', geminiName: 'Tamil',              ttsLocale: 'ta-IN'),
  _Lang(code: 'ar', name: 'Arabic',           flag: '🇸🇦', geminiName: 'Arabic',             ttsLocale: 'ar-SA'),
  _Lang(code: 'hi', name: 'Hindi',            flag: '🇮🇳', geminiName: 'Hindi',              ttsLocale: 'hi-IN'),
  _Lang(code: 'id', name: 'Bahasa Indonesia', flag: '🇮🇩', geminiName: 'Bahasa Indonesia',   ttsLocale: 'id-ID'),
  _Lang(code: 'th', name: 'Thai',             flag: '🇹🇭', geminiName: 'Thai',               ttsLocale: 'th-TH'),
  _Lang(code: 'ja', name: 'Japanese',         flag: '🇯🇵', geminiName: 'Japanese',           ttsLocale: 'ja-JP'),
  _Lang(code: 'ko', name: 'Korean',           flag: '🇰🇷', geminiName: 'Korean',             ttsLocale: 'ko-KR'),
  _Lang(code: 'fr', name: 'Francais',         flag: '🇫🇷', geminiName: 'French',             ttsLocale: 'fr-FR'),
  _Lang(code: 'de', name: 'Deutsch',          flag: '🇩🇪', geminiName: 'German',             ttsLocale: 'de-DE'),
  _Lang(code: 'es', name: 'Espanol',          flag: '🇪🇸', geminiName: 'Spanish',            ttsLocale: 'es-ES'),
  _Lang(code: 'pt', name: 'Portugues',        flag: '🇧🇷', geminiName: 'Portuguese',         ttsLocale: 'pt-BR'),
  _Lang(code: 'ru', name: 'Russian',          flag: '🇷🇺', geminiName: 'Russian',            ttsLocale: 'ru-RU'),
];

// ─── Models ───────────────────────────────────────────────────────────────────
class _Message {
  final String text;
  final bool isUser;
  final DateTime time;
  final _AnalysisReport? report;
  final bool isTyping;
  final bool isVoice;
  final String? voiceDuration;
  const _Message({
    required this.text,
    required this.isUser,
    required this.time,
    this.report,
    this.isTyping = false,
    this.isVoice = false,
    this.voiceDuration,
  });
}

class _AnalysisReport {
  final int score;
  final String scoreLabel;
  final Color scoreColor;
  final List<_TimelineEntry> timeline;
  final List<_InsightCard> insights;
  final String summary;
  const _AnalysisReport({
    required this.score,
    required this.scoreLabel,
    required this.scoreColor,
    required this.timeline,
    required this.insights,
    required this.summary,
  });
}

class _TimelineEntry {
  final String period, status, note;
  final Color color;
  final IconData icon;
  const _TimelineEntry({
    required this.period,
    required this.status,
    required this.note,
    required this.color,
    required this.icon,
  });
}

class _InsightCard {
  final String title, value, subtitle;
  final IconData icon;
  final Color color;
  const _InsightCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });
}

// ─── Screen ───────────────────────────────────────────────────────────────────
class HealthAnalysisScreen extends StatefulWidget {
  const HealthAnalysisScreen({Key? key}) : super(key: key);

  @override
  State<HealthAnalysisScreen> createState() => _HealthAnalysisScreenState();
}

class _HealthAnalysisScreenState extends State<HealthAnalysisScreen>
    with TickerProviderStateMixin {
  final AuthService _authSvc  = AuthService();
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl    = ScrollController();

  // ── Voice recorder ──────────────────────────────────────────────────────────
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording    = false;
  bool _isTranscribing = false;
  String? _recordingPath;
  DateTime? _recordingStart;
  late AnimationController _recordPulseCtrl;
  late Animation<double> _recordPulseAnim;

  // ── TTS ──────────────────────────────────────────────────────────────────────
  final FlutterTts _tts = FlutterTts();
  String? _speakingMessageId; // tracks which message is currently being spoken
  bool _ttsReady = false;
  double _ttsSpeed = 0.5;   // flutter_tts: 0.0=slowest, 0.5=normal, 1.0=fast
  double _ttsPitch = 1.0;

  // ── Language ─────────────────────────────────────────────────────────────────
  _Lang _selectedLang = _kLanguages[0];

  // ── API ──────────────────────────────────────────────────────────────────────
  // Reads the one shared key/endpoint from GeminiService instead of its own
  // copy — see the doc comment on GeminiService for why this was centralized.
  static const _apiKey = GeminiService.apiKey;
  static const _apiUrl = GeminiService.baseUrl;

  // ── Animations ───────────────────────────────────────────────────────────────
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;
  late AnimationController _scoreCtrl;
  late Animation<double> _scoreAnim;

  // ── State ────────────────────────────────────────────────────────────────────
  List<_Message> _messages = [];
  Map<String, dynamic> _profile = {};
  List<Map<String, dynamic>> _medicines = [];
  bool _loading          = true;
  bool _typing           = false;
  bool _analysisRunning  = false;
  bool _analysisComplete = false;
  _AnalysisReport? _report;

  // ── Chat history ─────────────────────────────────────────────────────────────
  String? _sessionId;               // Firestore doc id of the current session
  bool _viewingHistory = false;     // true when a past session has been loaded

  @override
  void initState() {
    super.initState();
    _fadeCtrl  = AnimationController(duration: const Duration(milliseconds: 700), vsync: this);
    _fadeAnim  = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeIn);
    _scoreCtrl = AnimationController(duration: const Duration(milliseconds: 1600), vsync: this);
    _scoreAnim = CurvedAnimation(parent: _scoreCtrl, curve: Curves.easeOutCubic);

    _recordPulseCtrl = AnimationController(
        duration: const Duration(milliseconds: 800), vsync: this);
    _recordPulseAnim = Tween<double>(begin: 1.0, end: 1.25).animate(
        CurvedAnimation(parent: _recordPulseCtrl, curve: Curves.easeInOut));

    _initTts();
    _loadData();
    _inputCtrl.addListener(() => setState(() {}));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TTS SETUP & CONTROL
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _initTts() async {
    await _tts.setLanguage(_selectedLang.ttsLocale);
    await _tts.setSpeechRate(_ttsSpeed);
    await _tts.setPitch(_ttsPitch);
    await _tts.setVolume(1.0);

    // Android: prefer network voice for better multilingual support
    if (Platform.isAndroid) {
      await _tts.setEngine('com.google.android.tts');
    }

    // Callbacks
    _tts.setStartHandler(() {
      if (mounted) setState(() {});
    });
    _tts.setCompletionHandler(() {
      if (mounted) setState(() => _speakingMessageId = null);
    });
    _tts.setCancelHandler(() {
      if (mounted) setState(() => _speakingMessageId = null);
    });
    _tts.setErrorHandler((msg) {
      if (mounted) setState(() => _speakingMessageId = null);
    });

    setState(() => _ttsReady = true);
  }

  /// Unique key for each message (index-based is fine since list is append-only)
  String _msgId(_Message msg) =>
      '${msg.time.millisecondsSinceEpoch}_${msg.text.hashCode}';

  /// Toggle speak/stop for a given AI message
  Future<void> _toggleSpeak(_Message msg) async {
    HapticFeedback.lightImpact();
    final id = _msgId(msg);

    if (_speakingMessageId == id) {
      // Already speaking this message — stop
      await _tts.stop();
      setState(() => _speakingMessageId = null);
      return;
    }

    // Stop any current speech first
    if (_speakingMessageId != null) {
      await _tts.stop();
    }

    // Set language matching selected UI language
    await _tts.setLanguage(_selectedLang.ttsLocale);
    await _tts.setSpeechRate(_ttsSpeed);
    await _tts.setPitch(_ttsPitch);

    // Clean text for TTS (strip markdown-like symbols)
    final cleaned = msg.text
        .replaceAll('**', '')
        .replaceAll('*', '')
        .replaceAll('__', '')
        .replaceAll('`', '')
        .replaceAll('#', '')
        .trim();

    setState(() => _speakingMessageId = id);
    await _tts.speak(cleaned);
  }

  /// Stop TTS globally
  Future<void> _stopTts() async {
    await _tts.stop();
    setState(() => _speakingMessageId = null);
  }

  /// Show TTS settings bottom sheet
  void _showTtsSettings() {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _TtsSettingsSheet(
        speed: _ttsSpeed,
        pitch: _ttsPitch,
        onSpeedChanged: (v) async {
          setState(() => _ttsSpeed = v);
          await _tts.setSpeechRate(v);
        },
        onPitchChanged: (v) async {
          setState(() => _ttsPitch = v);
          await _tts.setPitch(v);
        },
        onClose: () => Navigator.pop(context),
      ),
    );
  }

  @override
  void dispose() {
    _tts.stop();
    _fadeCtrl.dispose();
    _scoreCtrl.dispose();
    _recordPulseCtrl.dispose();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _recorder.dispose();
    super.dispose();
  }

  // ── Extra data pulled from new features ────────────────────────────────────
  Map<String, dynamic>? _latestBP;
  Map<String, dynamic>? _latestSugar;
  // Per-medicine dose adherence: medicineId → {taken, total}
  Map<String, Map<String, int>> _adherenceMap = {};

  // ── Load Firebase ────────────────────────────────────────────────────────────
  Future<void> _loadData() async {
    final user = _authSvc.currentUser;
    if (user == null) { setState(() => _loading = false); return; }
    try {
      final profileSnap = await _db.collection('users').doc(user.uid).get();
      final medSnap     = await _db
          .collection('medicines')
          .where('userId', isEqualTo: user.uid)
          .orderBy('scannedAt', descending: true)
          .limit(50)
          .get();

      _profile   = profileSnap.data() ?? {};
      _medicines = medSnap.docs.map((d) {
        final m = d.data(); m['id'] = d.id; return m;
      }).toList();

      // ── New: pull vitals from profile doc ─────────────────────────────────
      _latestBP    = _profile['latestBP']    as Map<String, dynamic>?;
      _latestSugar = _profile['latestSugar'] as Map<String, dynamic>?;

      final cutoff = DateTime.now().subtract(const Duration(days: 30));
      final events = await DoseService.instance.events(user.uid)
          .where('dueAt', isGreaterThanOrEqualTo: Timestamp.fromDate(cutoff)).get();
      _adherenceMap.clear();
      for (final event in events.docs) {
        final d = event.data();
        if (!DoseService.eligible(d, DateTime.now())) continue;
        final id = d['medicineId'] as String;
        final a = _adherenceMap.putIfAbsent(id, () => {'taken': 0, 'total': 0});
        a['total'] = a['total']! + 1;
        if (d['status'] == 'taken') a['taken'] = a['taken']! + 1;
      }
    } catch (_) {}
    setState(() => _loading = false);
    _fadeCtrl.forward();
    _addWelcome();
  }

  void _addWelcome() {
    // Build a personalised greeting based on available data
    final hasVitals   = _latestBP != null || _latestSugar != null;
    final trackedMeds = _medicines.where((m) => m['trackingEnabled'] == true).length;
    final adherencePct = _overallAdherencePct();

    String vitalsNote = '';
    if (hasVitals) {
      final bpStr    = _latestBP    != null ? 'BP: ${_latestBP!['display'] ?? '?'} mmHg (${_latestBP!['condition'] ?? '?'})' : '';
      final sugarStr = _latestSugar != null ? 'Sugar: ${_latestSugar!['display'] ?? '?'} (${_latestSugar!['condition'] ?? '?'})' : '';
      final parts    = [bpStr, sugarStr].where((s) => s.isNotEmpty).join(' · ');
      vitalsNote = '\n\n📊 Vitals on file: $parts';
    }
    String scheduleNote = '';
    if (trackedMeds > 0) {
      scheduleNote = '\n💊 Tracking $trackedMeds medicine${trackedMeds == 1 ? '' : 's'} · '
          'Overall adherence: ${adherencePct == null ? 'No recorded doses' : '$adherencePct%'} (last 30 days)';
    }

    _messages.add(_Message(
      text: "Hello! I am your Personal Health Analyst.\n\n"
          "I analyse your medicine inventory, vitals (BP & blood sugar), "
          "dose adherence, BMI, and chronic conditions to generate your personalised health score."
          "$vitalsNote$scheduleNote\n\n"
          "🌐 Select language using the globe icon above.\n"
          "🎤 Tap the mic to ask via voice note.\n"
          "🔊 Tap the speaker icon on any response to hear it read aloud.\n\n"
          "Tap Analyse to run your full health report, or ask me anything first.",
      isUser: false,
      time: DateTime.now(),
    ));
    setState(() {});
  }

  void _scrollDown() => Future.delayed(const Duration(milliseconds: 150), () {
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
    }
  });

  // ── Build context for Gemini (enriched with vitals + schedule + adherence) ──
  String _buildContext() {
    final health     = _profile['healthInfo'] as Map<String, dynamic>? ?? {};
    final conditions = List<String>.from(health['chronicConditions'] ?? []);

    // ── Medicine list with schedule + adherence data ───────────────────────
    final medList = _medicines.map((m) {
      final medId     = m['id'] as String? ?? '';
      final scannedAt = m['scannedAt'];
      String dateStr  = 'unknown date';
      if (scannedAt is Timestamp) {
        final d = scannedAt.toDate();
        dateStr = '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
      }

      // Schedule
      final tracked       = m['trackingEnabled'] == true;
      final tpd           = m['timesPerDay']    ?? 'Not set';
      final freqLabel     = m['frequencyLabel'] ?? 'Not set';
      final mealTiming    = m['mealTiming']     ?? 'Not set';
      final schedTimes    = (m['scheduleTimes'] as List?)?.join(', ') ?? 'Not set';

      // Adherence (last 30 days)
      String adherenceStr = 'Tracking off';
      if (tracked && _adherenceMap.containsKey(medId)) {
        final a = _adherenceMap[medId]!;
        final taken = a['taken']!;
        final total = a['total']!;
        final pct   = total > 0 ? ((taken / total) * 100).round() : 0;
        adherenceStr = '$taken/$total doses taken ($pct%) last 30d';
      }

      return '- ${m['medicineName'] ?? 'Unknown'} (${m['category'] ?? 'N/A'}) | '
          'Potency: ${m['potency'] ?? '?'}% | Status: ${m['status'] ?? '?'} | '
          'Expiry: ${m['expiryDate'] ?? '?'} | Days left: ${m['daysUntilExpiry'] ?? '?'} | '
          'Scanned: $dateStr | Schedule: $freqLabel @ $schedTimes | '
          'Meal timing: $mealTiming | Adherence: $adherenceStr';
    }).join('\n');

    // ── Vitals summary ─────────────────────────────────────────────────────
    final bpLine = _latestBP != null
        ? 'BP: ${_latestBP!['display'] ?? '?'} mmHg (${_latestBP!['condition'] ?? '?'}, score: ${_latestBP!['score'] ?? '?'}/100)'
        : 'BP: Not recorded';
    final sugarLine = _latestSugar != null
        ? 'Blood Sugar: ${_latestSugar!['display'] ?? '?'} (${_latestSugar!['condition'] ?? '?'}, score: ${_latestSugar!['score'] ?? '?'}/100)'
        : 'Blood Sugar: Not recorded';

    // ── Overall adherence across all tracked medicines ─────────────────────
    int totalTaken = 0, totalExpected = 0;
    for (final a in _adherenceMap.values) {
      totalTaken    += a['taken']!;
      totalExpected += a['total']!;
    }
    final overallAdherence = totalExpected > 0
        ? '${((totalTaken / totalExpected) * 100).round()}% ($totalTaken/$totalExpected doses)'
        : 'No tracked medicines';

    final trackedCount = _medicines.where((m) => m['trackingEnabled'] == true).length;

    return '''USER HEALTH PROFILE:
Name: ${_profile['fullName'] ?? 'N/A'}
Age/DOB: ${_profile['dateOfBirth'] ?? 'N/A'}
Gender: ${_profile['gender'] ?? 'N/A'}
BMI: ${health['bmi'] ?? 'N/A'} (Height: ${health['height'] ?? 'N/A'}cm, Weight: ${health['weight'] ?? 'N/A'}kg)
Blood Type: ${health['bloodType'] ?? 'N/A'}
Chronic Conditions: ${conditions.isEmpty ? 'None reported' : conditions.join(', ')}
Other Medical Notes: ${health['otherIllness'] ?? 'None'}

VITALS (from AI scan — see profile):
$bpLine
$sugarLine

DOSE ADHERENCE (last 30 days):
Overall: $overallAdherence
Tracked medicines: $trackedCount/${_medicines.length}

MEDICINE HISTORY (${_medicines.length} medicines):
$medList''';
  }

  // ── Compute overall adherence % for score ──────────────────────────────────
  int? _overallAdherencePct() {
    int taken = 0, total = 0;
    for (final a in _adherenceMap.values) {
      taken += a['taken']!;
      total += a['total']!;
    }
    if (total == 0) return null;
    return ((taken / total) * 100).round().clamp(0, 100);
  }

  String get _langInstruction => _selectedLang.code == 'en'
      ? ''
      : '\n\nIMPORTANT: Respond ENTIRELY in ${_selectedLang.geminiName}. All text must be in ${_selectedLang.geminiName}.';

  // ═══════════════════════════════════════════════════════════════════════════
  // JSON SANITIZER
  // ═══════════════════════════════════════════════════════════════════════════
  String _extractAndSanitizeJson(String raw) {
    raw = raw.replaceAll('```json', '').replaceAll('```', '').trim();
    final start = raw.indexOf('{');
    final end   = raw.lastIndexOf('}');
    if (start != -1 && end != -1 && end > start) {
      raw = raw.substring(start, end + 1);
    }
    final buf    = StringBuffer();
    bool inStr   = false;
    bool escaped = false;
    for (int i = 0; i < raw.length; i++) {
      final ch = raw[i];
      if (escaped) { buf.write(ch); escaped = false; continue; }
      if (ch == '\\') { escaped = true; buf.write(ch); continue; }
      if (ch == '"')  { inStr = !inStr; buf.write(ch); continue; }
      if (inStr) {
        if (ch == '\n') { buf.write(r'\n'); continue; }
        if (ch == '\r') { buf.write(r'\r'); continue; }
        if (ch == '\t') { buf.write(r'\t'); continue; }
      }
      buf.write(ch);
    }
    return buf.toString();
  }

  Map<String, dynamic> _safeJsonDecode(String raw) {
    try {
      return jsonDecode(_extractAndSanitizeJson(raw)) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('JSON parse error: $e');
      return {};
    }
  }

  // ─── Run Full Analysis ───────────────────────────────────────────────────────
  Future<void> _runAnalysis() async {
    if (_analysisRunning) return;
    // Stop any active TTS before starting
    await _stopTts();
    HapticFeedback.mediumImpact();

    setState(() {
      _analysisRunning = true;
      _messages.add(_Message(text: 'Run full health analysis', isUser: true, time: DateTime.now()));
      _typing = true;
    });
    _scrollDown();

    final langNote = _selectedLang.code == 'en'
        ? ''
        : 'IMPORTANT: All human-readable text fields (summary, timeline notes, '
        'insight titles/subtitles/values, clarificationQuestion) MUST be written in '
        '${_selectedLang.geminiName}. Keep JSON keys, color values, icon values, '
        'scoreLabel, and status values in English exactly as specified.';

    final prompt = '''
You are an advanced AI health analyst. Analyse the following patient data.

${_buildContext()}

Produce a health analysis in this EXACT JSON format. Do not compute, mention or invent an overall health score; the app displays its canonical daily score separately. The legacy healthScore field must be 0 and is not displayed as a score.
Respond ONLY with valid JSON. No markdown, no code fences, no text before or after.
All string values must be properly escaped. Use \\n for newlines inside strings, never raw newlines.

{
  "healthScore": 0,
  "scoreLabel": "Not used for daily health score",
  "summary": "<2-3 sentence overall summary>",
  "timeline": [
    {
      "period": "<Month Year e.g. Jan 2025>",
      "status": "<Healthy|Caution|Poor|Critical>",
      "note": "<one sentence about this period>",
      "color": "<green|amber|red|blue>"
    }
  ],
  "insights": [
    {
      "title": "<insight title>",
      "value": "<key metric>",
      "subtitle": "<brief explanation>",
      "icon": "<medication|warning|check_circle|trending_up|trending_down|favorite|science>",
      "color": "<teal|amber|rose|sky|violet>"
    }
  ],
  "clarificationNeeded": <true|false>,
  "clarificationQuestion": "<question or empty string>"
}

Rules:
- Score formula (use actual data provided):
  BMI component (15pts): normal BMI=15, overweight=10, obese=5
  Chronic conditions (15pts): none=15, 1-2=10, 3+=5
  Medicine potency avg (20pts): avg potency% × 0.20
  Expiry management (10pts): no expired=10, some expired=5, many expired=0
  BP component (15pts): use BP score from profile if available, else 10
  Blood sugar (10pts): use sugar score from profile if available, else 10
  Dose adherence (15pts): use overall adherence% × 0.15
- Timeline: cover all months medicines were scanned
- Include 5-7 insights covering: avg potency, expired count, BP status, blood sugar, adherence rate, BMI, most common category
- Never substitute assumed or default vitals, age, BMI or adherence. Exclude unavailable components and explicitly describe missing data. The score is an app awareness estimate, not a diagnosis.
- NEVER use raw newlines inside any string value
- For insights, use the actual BP/sugar/adherence numbers from the profile data provided
$langNote
''';

    try {
      final res = await http.post(
        Uri.parse('$_apiUrl?key=$_apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [{'parts': [{'text': prompt}]}],
          'generationConfig': {
            'temperature': 0.2,
            'maxOutputTokens': 4096,
            'responseMimeType': 'application/json',
          },
        }),
      );

      if (res.statusCode == 200) {
        final d      = jsonDecode(res.body);
        final raw    = d['candidates']?[0]?['content']?['parts']?[0]?['text'] ?? '';
        final parsed = _safeJsonDecode(raw);

        if (parsed.isEmpty) {
          _addAiMsg('Analysis returned an unreadable response. Please try again.');
          setState(() { _typing = false; _analysisRunning = false; });
          return;
        }

        _report = _parseReport(parsed);

        setState(() {
          _typing           = false;
          _analysisRunning  = false;
          _analysisComplete = true;
          _messages.add(_Message(
            text: _report!.summary,
            isUser: false,
            time: DateTime.now(),
            report: _report,
          ));
        });

        _scoreCtrl.forward();
        _persistSession(); // save history including the report

        if (parsed['clarificationNeeded'] == true &&
            (parsed['clarificationQuestion'] as String? ?? '').isNotEmpty) {
          await Future.delayed(const Duration(milliseconds: 800));
          if (mounted) {
            setState(() => _messages.add(_Message(
              text: parsed['clarificationQuestion'] as String,
              isUser: false,
              time: DateTime.now(),
            )));
          }
        }
      } else {
        _addAiMsg('Analysis failed (HTTP ${res.statusCode}). Please try again.');
      }
    } catch (e) {
      _addAiMsg('Error running analysis: $e');
    }

    setState(() { _typing = false; _analysisRunning = false; });
    _scrollDown();
  }

  _AnalysisReport _parseReport(Map<String, dynamic> d) {
    final score = (d['healthScore'] as num?)?.toInt() ?? 50;
    final label = d['scoreLabel'] ?? 'Fair';
    Color scoreColor;
    if (score >= 80)       scoreColor = _C.teal;
    else if (score >= 60)  scoreColor = _C.sky;
    else if (score >= 40)  scoreColor = _C.amber;
    else                   scoreColor = _C.rose;

    final timeline = (d['timeline'] as List? ?? []).map((e) {
      final c = (e['color'] ?? 'blue') as String;
      return _TimelineEntry(
        period: e['period'] ?? '', status: e['status'] ?? '', note: e['note'] ?? '',
        color:  c == 'green' ? _C.teal  : c == 'amber' ? _C.amber : c == 'red' ? _C.rose : _C.sky,
        icon:   c == 'green' ? Icons.check_circle_rounded
            : c == 'amber' ? Icons.warning_rounded
            : c == 'red'   ? Icons.dangerous_rounded : Icons.info_rounded,
      );
    }).toList();

    final insights = (d['insights'] as List? ?? []).map((e) {
      final ic = (e['color'] ?? 'sky') as String;
      final ii = (e['icon']  ?? 'info') as String;
      return _InsightCard(
        title: e['title'] ?? '', value: e['value'] ?? '', subtitle: e['subtitle'] ?? '',
        color:  ic == 'teal' ? _C.teal : ic == 'amber' ? _C.amber
            : ic == 'rose' ? _C.rose : ic == 'violet' ? _C.violet : _C.sky,
        icon:   ii == 'medication'    ? Icons.medication_rounded
            : ii == 'warning'       ? Icons.warning_rounded
            : ii == 'check_circle'  ? Icons.check_circle_rounded
            : ii == 'trending_up'   ? Icons.trending_up_rounded
            : ii == 'trending_down' ? Icons.trending_down_rounded
            : ii == 'favorite'      ? Icons.favorite_rounded
            : ii == 'science'       ? Icons.science_rounded
            : Icons.analytics_rounded,
      );
    }).toList();

    return _AnalysisReport(
      score: score, scoreLabel: label, scoreColor: scoreColor,
      timeline: timeline, insights: insights, summary: d['summary'] ?? '',
    );
  }

  // ─── Language picker ─────────────────────────────────────────────────────────
  void _showLanguagePicker() {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _LanguagePickerSheet(
        selected: _selectedLang,
        languages: _kLanguages,
        onSelect: (lang) async {
          setState(() => _selectedLang = lang);
          // Update TTS language immediately
          await _tts.setLanguage(lang.ttsLocale);
          Navigator.pop(context);
          _addAiMsg(lang.code == 'en'
              ? 'Language set to English. I will respond in English from now on.'
              : 'Language set to ${lang.name} ${lang.flag}. I will respond in ${lang.geminiName} from now on.');
        },
      ),
    );
  }

  // ─── Voice recording ─────────────────────────────────────────────────────────
  Future<void> _startRecording() async {
    await _stopTts(); // stop TTS before recording
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Microphone permission is required.')));
      }
      return;
    }
    final dir  = await getTemporaryDirectory();
    final path = '${dir.path}/voice_note_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000, sampleRate: 44100),
      path: path,
    );

    setState(() { _isRecording = true; _recordingPath = path; _recordingStart = DateTime.now(); });
    _recordPulseCtrl.repeat(reverse: true);
    HapticFeedback.mediumImpact();
  }

  Future<void> _stopRecordingAndTranscribe() async {
    if (!_isRecording) return;
    final path     = await _recorder.stop();
    final duration = DateTime.now().difference(_recordingStart ?? DateTime.now());
    final durStr   = '${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2,'0')}';

    _recordPulseCtrl..stop()..reset();
    setState(() { _isRecording = false; _isTranscribing = true; });
    HapticFeedback.lightImpact();

    if (path == null) { setState(() => _isTranscribing = false); return; }

    try {
      final audioBytes  = await File(path).readAsBytes();
      final base64Audio = base64Encode(audioBytes);

      final res = await http.post(
        Uri.parse('$_apiUrl?key=$_apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [{'parts': [
            {'inline_data': {'mime_type': 'audio/mp4', 'data': base64Audio}},
            {'text': 'Transcribe this voice note. Output ONLY the transcribed text. '
                'If unable, output exactly: [Could not transcribe audio]'},
          ]}],
          'generationConfig': {'temperature': 0.0, 'maxOutputTokens': 500},
        }),
      );

      String transcribed = '[Could not transcribe audio]';
      if (res.statusCode == 200) {
        final td = jsonDecode(res.body);
        transcribed = (td['candidates']?[0]?['content']?['parts']?[0]?['text'] ?? transcribed).trim();
      }

      setState(() => _isTranscribing = false);

      if (transcribed.isNotEmpty && transcribed != '[Could not transcribe audio]') {
        setState(() {
          _messages.add(_Message(
              text: transcribed, isUser: true, time: DateTime.now(),
              isVoice: true, voiceDuration: durStr));
          _typing = true;
        });
        _scrollDown();
        await _sendMessageInternal(transcribed);
      } else {
        _addAiMsg('Sorry, I could not transcribe your voice note. Please try again or type your question.');
      }
      try { await File(path).delete(); } catch (_) {}
    } catch (e) {
      setState(() => _isTranscribing = false);
      _addAiMsg('Voice note error: $e');
    }
    _scrollDown();
  }

  Future<void> _cancelRecording() async {
    await _recorder.cancel();
    _recordPulseCtrl..stop()..reset();
    setState(() { _isRecording = false; _recordingPath = null; });
    HapticFeedback.lightImpact();
  }

  // ─── Send message ────────────────────────────────────────────────────────────
  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;
    await _stopTts();
    HapticFeedback.lightImpact();
    setState(() {
      _messages.add(_Message(text: text, isUser: true, time: DateTime.now()));
      _typing = true;
    });
    _inputCtrl.clear();
    _scrollDown();
    await _sendMessageInternal(text);
    _scrollDown();
  }

  Future<void> _sendMessageInternal(String text) async {
    final prompt = '''
You are a personal health analyst AI assistant.
Overall health score is provided separately by the app’s canonical daily report. Do not calculate or invent another overall score.
Patient context:
${_buildContext()}
User question: $text
Answer helpfully and specifically about their health data. Keep answers concise but insightful.$_langInstruction
''';
    try {
      final res = await http.post(
        Uri.parse('$_apiUrl?key=$_apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [{'parts': [{'text': prompt}]}],
          'generationConfig': {'temperature': 0.6, 'maxOutputTokens': 1500},
        }),
      );
      if (res.statusCode == 200) {
        final d   = jsonDecode(res.body);
        var txt   = d['candidates']?[0]?['content']?['parts']?[0]?['text'] ?? '';
        txt = txt.replaceAll('**', '').trim();
        _addAiMsg(txt);
      } else {
        _addAiMsg('Could not get a response. Please try again.');
      }
    } catch (e) {
      _addAiMsg('Error: $e');
    }
  }

  void _addAiMsg(String text) {
    setState(() {
      _typing = false;
      _messages.add(_Message(text: text, isUser: false, time: DateTime.now()));
    });
    _persistSession(); // save history after every AI reply
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CHAT HISTORY — save & restore sessions (users/{uid}/healthChats)
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _persistSession() async {
    final user = _authSvc.currentUser;
    if (user == null) return;
    // Serialize (skip typing indicators, cap at last 100 messages)
    final serial = _messages
        .where((m) => !m.isTyping)
        .toList()
        .reversed.take(100).toList().reversed
        .map((m) => {
              'text':    m.report != null
                  ? 'Health insights\n\n${m.text}'
                  : m.text,
              'isUser':  m.isUser,
              'timeMs':  m.time.millisecondsSinceEpoch,
              'isVoice': m.isVoice,
            })
        .toList();
    if (serial.length < 2) return; // nothing meaningful to save yet

    final firstUserMsg = _messages.firstWhere(
        (m) => m.isUser, orElse: () => _Message(
            text: 'Health Analysis', isUser: true, time: DateTime.now()));
    final title = firstUserMsg.text.length > 60
        ? '${firstUserMsg.text.substring(0, 60)}…'
        : firstUserMsg.text;

    try {
      final col = _db.collection('users').doc(user.uid).collection('healthChats');
      final data = {
        'title':      title,
        'messages':   serial,
        'msgCount':   serial.length,
        'score':      _report?.score,
        'scoreLabel': _report?.scoreLabel,
        'language':   _selectedLang.code,
        'updatedAt':  FieldValue.serverTimestamp(),
      };
      if (_sessionId == null) {
        data['createdAt'] = FieldValue.serverTimestamp();
        final ref = await col.add(data);
        _sessionId = ref.id;
      } else {
        await col.doc(_sessionId).set(data, SetOptions(merge: true));
      }
    } catch (_) {} // history is best-effort — never break the chat
  }

  void _showHistory() {
    final user = _authSvc.currentUser;
    if (user == null) return;
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _HistorySheet(
        stream: _db.collection('users').doc(user.uid)
            .collection('healthChats')
            .orderBy('updatedAt', descending: true)
            .limit(30)
            .snapshots(),
        currentSessionId: _sessionId,
        onOpen: _loadSession,
        onDelete: (id) async {
          await _db.collection('users').doc(user.uid)
              .collection('healthChats').doc(id).delete();
          if (id == _sessionId) _sessionId = null;
        },
      ),
    );
  }

  void _loadSession(String id, Map<String, dynamic> data) {
    final raw = List<Map<String, dynamic>>.from(
        (data['messages'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)));
    setState(() {
      _sessionId       = id;               // continue this session
      _viewingHistory  = true;
      _report           = null;
      _analysisComplete = false;
      _messages = raw.map((m) => _Message(
        text:    (m['text'] ?? '').toString(),
        isUser:  m['isUser'] == true,
        time:    DateTime.fromMillisecondsSinceEpoch(
                     (m['timeMs'] as num?)?.toInt() ?? 0),
        isVoice: m['isVoice'] == true,
      )).toList();
    });
    Navigator.pop(context);
    _scrollDown();
  }

  void _startNewSession() {
    setState(() {
      _sessionId        = null;
      _viewingHistory   = false;
      _report            = null;
      _analysisComplete  = false;
      _messages          = [];
    });
    _addWelcome();
  }

  String _fmt(DateTime t) {
    final h = t.hour == 0 ? 12 : t.hour > 12 ? t.hour - 12 : t.hour;
    final p = t.hour >= 12 ? 'PM' : 'AM';
    return '$h:${t.minute.toString().padLeft(2,'0')} $p';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.light,
    child: Scaffold(
      backgroundColor: _C.surface,
      body: _loading ? _buildLoading() : FadeTransition(
        opacity: _fadeAnim,
        child: Column(children: [
          _buildHeader(),
          Expanded(child: Column(children: [
            Expanded(child: _buildMessages()),
            if (_typing || _isTranscribing) _buildTypingIndicator(),
            _buildInputBar(),
          ])),
        ]),
      ),
    ),
  );

  Widget _buildLoading() => Scaffold(
    backgroundColor: _C.navy,
    body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(width: 40, height: 40,
          child: CircularProgressIndicator(strokeWidth: 2.5, color: _C.teal,
              backgroundColor: _C.teal.withOpacity(0.15))),
      const SizedBox(height: 16),
      const Text('Loading your health data...', style: TextStyle(color: _C.teal, fontSize: 13)),
    ])),
  );

  // ── Header — compact 2-row layout to prevent overflow ───────────────────────
  Widget _buildHeader() => MedicHeaderSurface(
    child: Stack(children: [
      Positioned.fill(child: CustomPaint(painter: _MeshPainter())),
      SafeArea(bottom: false, child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Column(mainAxisSize: MainAxisSize.min, children: [

          // ── ROW 1: back + title + action button ──────────────────────────
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            // Back button
            GestureDetector(
              onTap: () async { await _stopTts(); Navigator.pop(context); },
              child: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withOpacity(0.15))),
                child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 15),
              ),
            ),
            const SizedBox(width: 10),

            // Title — flexible so it never pushes buttons off screen
            Expanded(
              child: Text(
                'Health Analysis',
                style: const TextStyle(fontFamily: 'serif',
                    color: Colors.white, fontSize: 18,
                    fontWeight: FontWeight.w700, letterSpacing: -0.4),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),

            // Score badge OR Analyse button (right-most, fixed width)
            if (_report != null)
              GestureDetector(
                onTap: _scrollDown,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                      color: _report!.scoreColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _report!.scoreColor.withOpacity(0.4))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(_report!.score.toString(), style: TextStyle(
                        color: _report!.scoreColor, fontSize: 16,
                        fontWeight: FontWeight.w700, letterSpacing: -0.5)),
                    const SizedBox(width: 3),
                    Text('/100', style: TextStyle(
                        color: _report!.scoreColor.withOpacity(0.6),
                        fontSize: 9, fontWeight: FontWeight.w600)),
                  ]),
                ),
              )
            else
              GestureDetector(
                onTap: _analysisRunning ? null : _runAnalysis,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                      color: _analysisRunning ? _C.teal.withOpacity(0.1) : _C.teal,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: _analysisRunning ? [] : [
                        BoxShadow(color: MedicColors.mint.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 3))
                      ]),
                  child: _analysisRunning
                      ? SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: MedicColors.mint,
                          backgroundColor: _C.teal.withOpacity(0.15)))
                      : const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.analytics_rounded, color: Colors.white, size: 14),
                    SizedBox(width: 4),
                    Text('Analyse', style: TextStyle(
                        color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
          ]),

          const SizedBox(height: 10),

          // ── ROW 2: badges + icon buttons (all same height, never overflows) ──
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            // AI Powered badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                  color: _C.violet.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: _C.violet.withOpacity(0.35))),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.smart_toy_rounded, color: _C.violet, size: 10),
                SizedBox(width: 3),
                Text('AI Powered', style: TextStyle(
                    color: _C.violet, fontSize: 9, fontWeight: FontWeight.w700)),
              ]),
            ),
            const SizedBox(width: 6),

            // Vitals chip — shown if BP or sugar scanned
            if (_latestBP != null || _latestSugar != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                    color: MedicColors.mint.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: MedicColors.mint.withOpacity(0.3))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.monitor_heart_rounded, color: MedicColors.mint, size: 10),
                  const SizedBox(width: 3),
                  Text(
                    _latestBP != null
                        ? '${_latestBP!['display'] ?? '?'} mmHg'
                        : '${_latestSugar!['display'] ?? '?'}',
                    style: const TextStyle(color: MedicColors.mint, fontSize: 9, fontWeight: FontWeight.w700),
                  ),
                ]),
              ),
              const SizedBox(width: 6),
            ],

            // Medicine count + adherence
            Text(
              _adherenceMap.isNotEmpty
                  ? '${_medicines.length} meds · ${_overallAdherencePct() == null ? 'No adherence data' : '${_overallAdherencePct()}% adherence'}'
                  : '${_medicines.length} medicines',
              style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10),
            ),

            const Spacer(),

            // History icon — past chat sessions
            GestureDetector(
              onTap: _showHistory,
              child: Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: Colors.white.withOpacity(0.15))),
                child: const Icon(Icons.history_rounded, color: Colors.white, size: 15),
              ),
            ),
            const SizedBox(width: 6),

            // New chat icon — only shown while viewing a past session
            if (_viewingHistory) ...[
              GestureDetector(
                onTap: _startNewSession,
                child: Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                      color: MedicColors.mint.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: MedicColors.mint.withOpacity(0.4))),
                  child: const Icon(Icons.add_comment_rounded, color: MedicColors.mint, size: 14),
                ),
              ),
              const SizedBox(width: 6),
            ],

            // TTS settings icon (tune)
            if (_ttsReady) ...[
              GestureDetector(
                onTap: _showTtsSettings,
                child: Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: Colors.white.withOpacity(0.15))),
                  child: const Icon(Icons.tune_rounded, color: Colors.white, size: 15),
                ),
              ),
              const SizedBox(width: 6),
            ],

            // Language picker button — flag + code only, compact
            GestureDetector(
              onTap: _showLanguagePicker,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: Colors.white.withOpacity(0.15))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(_selectedLang.flag, style: const TextStyle(fontSize: 13)),
                  const SizedBox(width: 4),
                  Text(_selectedLang.code.toUpperCase(),
                      style: const TextStyle(
                          color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 2),
                  Icon(Icons.arrow_drop_down_rounded,
                      color: Colors.white.withOpacity(0.6), size: 16),
                ]),
              ),
            ),
          ]),

        ]),
      )),
    ]),
  );

  // ── Messages ─────────────────────────────────────────────────────────────────
  Widget _buildMessages() => ListView.builder(
    controller: _scrollCtrl,
    padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
    itemCount: _messages.length,
    itemBuilder: (_, i) {
      final msg = _messages[i];
      return msg.report != null ? _buildReportBubble(msg) : _buildBubble(msg);
    },
  );

  // ── Standard chat bubble ─────────────────────────────────────────────────────
  Widget _buildBubble(_Message msg) {
    final u  = msg.isUser;
    final id = _msgId(msg);
    final isSpeaking = _speakingMessageId == id;

    return Padding(
      padding: EdgeInsets.only(bottom: 12, left: u ? 48 : 0, right: u ? 0 : 48),
      child: Row(
        mainAxisAlignment: u ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!u) ...[
            Container(width: 32, height: 32,
                decoration: BoxDecoration(color: _C.violet.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _C.violet.withOpacity(0.25))),
                child: const Icon(Icons.analytics_rounded, color: _C.violet, size: 16)),
            const SizedBox(width: 8),
          ],
          Flexible(child: Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: u ? _C.navy : _C.card,
              borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16), topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(u ? 16 : 4), bottomRight: Radius.circular(u ? 4 : 16)),
              border: u ? Border.all(color: Colors.white.withOpacity(0.08)) : Border.all(color: _C.border),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 3))],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Voice badge
              if (msg.isVoice && u) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: _C.rose.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _C.rose.withOpacity(0.3))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.mic_rounded, color: _C.rose, size: 11),
                    const SizedBox(width: 4),
                    Text('Voice Note${msg.voiceDuration != null ? ' - ${msg.voiceDuration}' : ''}',
                        style: const TextStyle(color: _C.rose, fontSize: 9, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ],

              Text(msg.text, style: TextStyle(
                  fontSize: 13, height: 1.6, color: u ? Colors.white : _C.textPri, fontWeight: FontWeight.w400)),

              const SizedBox(height: 8),

              // Bottom row: language tag + timestamp + TTS button
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                // Language badge (AI messages only, non-English)
                if (!u && _selectedLang.code != 'en')
                  Row(children: [
                    Text(_selectedLang.flag, style: const TextStyle(fontSize: 9)),
                    const SizedBox(width: 3),
                    Text(_selectedLang.name, style: const TextStyle(fontSize: 9, color: _C.textTer)),
                  ])
                else
                  const SizedBox(),

                Row(children: [
                  Text(_fmt(msg.time), style: TextStyle(
                      fontSize: 10, color: u ? Colors.white.withOpacity(0.35) : _C.textTer)),

                  // ── TTS button (AI messages only) ──
                  if (!u && _ttsReady) ...[
                    const SizedBox(width: 8),
                    _TtsButton(
                      isSpeaking: isSpeaking,
                      onTap: () => _toggleSpeak(msg),
                    ),
                  ],
                ]),
              ]),
            ]),
          )),
          if (u) ...[
            const SizedBox(width: 8),
            Container(width: 32, height: 32,
                decoration: BoxDecoration(color: _C.navy.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(10), border: Border.all(color: _C.border)),
                child: const Icon(Icons.person_rounded, color: _C.textSec, size: 16)),
          ],
        ],
      ),
    );
  }

  // ── Report bubble ─────────────────────────────────────────────────────────────
  Widget _buildReportBubble(_Message msg) {
    final r  = msg.report!;
    final id = _msgId(msg);
    final isSpeaking = _speakingMessageId == id;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(children: [
        // Summary bubble with TTS
        Padding(
          padding: const EdgeInsets.only(bottom: 12, right: 48),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Container(width: 32, height: 32,
                decoration: BoxDecoration(color: _C.violet.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _C.violet.withOpacity(0.25))),
                child: const Icon(Icons.analytics_rounded, color: _C.violet, size: 16)),
            const SizedBox(width: 8),
            Flexible(child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: _C.card, borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _C.border)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(msg.text, style: const TextStyle(fontSize: 13, height: 1.6, color: _C.textPri)),
                const SizedBox(height: 8),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  if (_selectedLang.code != 'en')
                    Row(children: [
                      Text(_selectedLang.flag, style: const TextStyle(fontSize: 9)),
                      const SizedBox(width: 3),
                      Text('Report in ${_selectedLang.name}', style: const TextStyle(fontSize: 9, color: _C.textTer)),
                    ])
                  else const SizedBox(),
                  Row(children: [
                    Text(_fmt(msg.time), style: const TextStyle(fontSize: 10, color: _C.textTer)),
                    // TTS for report summary
                    if (_ttsReady) ...[
                      const SizedBox(width: 8),
                      _TtsButton(isSpeaking: isSpeaking, onTap: () => _toggleSpeak(msg)),
                    ],
                  ]),
                ]),
              ]),
            )),
          ]),
        ),

        _ScoreCard(report: r, anim: _scoreAnim, adherencePct: _overallAdherencePct(), latestBP: _latestBP, latestSugar: _latestSugar),
        const SizedBox(height: 12),
        // Vitals strip — shows BP + Sugar + Adherence side by side
        if (_latestBP != null || _latestSugar != null || _adherenceMap.isNotEmpty)
          _VitalsStrip(
            latestBP:      _latestBP,
            latestSugar:   _latestSugar,
            adherencePct:  _overallAdherencePct(),
            trackedMeds:   _medicines.where((m) => m['trackingEnabled'] == true).length,
          ),
        if (_latestBP != null || _latestSugar != null || _adherenceMap.isNotEmpty)
          const SizedBox(height: 12),
        if (r.insights.isNotEmpty) ...[_InsightsGrid(insights: r.insights), const SizedBox(height: 12)],
        if (r.timeline.isNotEmpty) ...[_TimelineWidget(entries: r.timeline), const SizedBox(height: 12)],
        Align(alignment: Alignment.centerRight,
            child: Text(_fmt(msg.time), style: const TextStyle(fontSize: 10, color: _C.textTer))),
      ]),
    );
  }

  // ── Typing indicator ─────────────────────────────────────────────────────────
  Widget _buildTypingIndicator() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
    child: Row(children: [
      Container(width: 32, height: 32,
          decoration: BoxDecoration(
              color: _isTranscribing ? _C.rose.withOpacity(0.12) : _C.violet.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(_isTranscribing ? Icons.mic_rounded : Icons.analytics_rounded,
              color: _isTranscribing ? _C.rose : _C.violet, size: 16)),
      const SizedBox(width: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: _C.card, borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _C.border)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _Dot(0, _isTranscribing ? _C.rose : _C.violet), const SizedBox(width: 4),
          _Dot(1, _isTranscribing ? _C.rose : _C.violet), const SizedBox(width: 4),
          _Dot(2, _isTranscribing ? _C.rose : _C.violet),
        ]),
      ),
      const SizedBox(width: 8),
      Text(
        _isTranscribing ? 'Transcribing voice note...'
            : _analysisRunning ? 'Analysing health data...' : 'Thinking...',
        style: const TextStyle(fontSize: 11, color: _C.textTer, fontStyle: FontStyle.italic),
      ),
    ]),
  );

  // ── Input bar ────────────────────────────────────────────────────────────────
  Widget _buildInputBar() => Container(
    padding: EdgeInsets.fromLTRB(16, 10, 16, MediaQuery.of(context).padding.bottom + 12),
    decoration: BoxDecoration(color: _C.card, border: Border(top: BorderSide(color: _C.border))),
    child: Column(children: [
      if (!_analysisComplete && !_analysisRunning && !_isRecording) ...[
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            _QuickPrompt('Run Full Analysis', _runAnalysis),
            const SizedBox(width: 8),
            _QuickPrompt('My medicines', () => _sendMessage('What medicines am I currently taking and what are they for?')),
            const SizedBox(width: 8),
            _QuickPrompt('My vitals', () => _sendMessage('Analyse my blood pressure and blood sugar readings.')),
            const SizedBox(width: 8),
            _QuickPrompt('Adherence?', () => _sendMessage('How well am I taking my medicines? Show my adherence data.')),
            const SizedBox(width: 8),
            _QuickPrompt('Explain BMI', () => _sendMessage('Analyse my BMI and what it means for my health.')),
            const SizedBox(width: 8),
            _QuickPrompt('Health risks', () => _sendMessage('What are my main health risks based on my profile?')),
          ]),
        ),
        const SizedBox(height: 10),
      ],
      if (_analysisComplete && !_isRecording) ...[
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            _QuickPrompt('Re-analyse', _runAnalysis),
            const SizedBox(width: 8),
            _QuickPrompt('Improve score?', () => _sendMessage('What can I do to improve my health score?')),
            const SizedBox(width: 8),
            _QuickPrompt('My BP & sugar', () => _sendMessage('Analyse my blood pressure and blood sugar readings. What do they mean for my health?')),
            const SizedBox(width: 8),
            _QuickPrompt('Adherence tips', () => _sendMessage('How is my medicine adherence? Give tips to improve it.')),
            const SizedBox(width: 8),
            _QuickPrompt('Recommendations', () => _sendMessage('Give me specific health recommendations based on my data.')),
            const SizedBox(width: 8),
            _QuickPrompt('See a doctor for?', () => _sendMessage('What should I consult a doctor about based on my health data?')),
          ]),
        ),
        const SizedBox(height: 10),
      ],

      if (_isRecording)
        _RecordingStrip(
          pulseAnim: _recordPulseAnim,
          startTime: _recordingStart,
          onCancel: _cancelRecording,
          onStop: _stopRecordingAndTranscribe,
        ),

      if (!_isRecording)
        Row(children: [
          Expanded(child: Container(
            decoration: BoxDecoration(color: _C.surface, borderRadius: BorderRadius.circular(24),
                border: Border.all(color: _C.border)),
            child: TextField(
              controller: _inputCtrl,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: _C.textPri),
              decoration: const InputDecoration(
                hintText: 'Ask about your health...',
                hintStyle: TextStyle(color: _C.textTer, fontSize: 13),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              textCapitalization: TextCapitalization.sentences,
              onSubmitted: _sendMessage,
            ),
          )),
          const SizedBox(width: 8),

          // Mic button
          GestureDetector(
            onTap: _isTranscribing ? null : _startRecording,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: _isTranscribing ? _C.rose.withOpacity(0.3) : _C.rose.withOpacity(0.85),
                borderRadius: BorderRadius.circular(13),
                boxShadow: _isTranscribing ? [] : [
                  BoxShadow(color: _C.rose.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))
                ],
              ),
              child: Icon(_isTranscribing ? Icons.hourglass_empty_rounded : Icons.mic_rounded,
                  color: Colors.white, size: 19),
            ),
          ),
          const SizedBox(width: 8),

          // Send button
          GestureDetector(
            onTap: () => _sendMessage(_inputCtrl.text),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: _inputCtrl.text.trim().isNotEmpty ? _C.violet : _C.violet.withOpacity(0.3),
                borderRadius: BorderRadius.circular(13),
                boxShadow: _inputCtrl.text.trim().isNotEmpty ? [
                  BoxShadow(color: _C.violet.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))
                ] : [],
              ),
              child: const Icon(Icons.send_rounded, color: Colors.white, size: 19),
            ),
          ),
        ]),
    ]),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// ── TTS BUTTON WIDGET ─────────────────────────────────────────────────────────
// ═══════════════════════════════════════════════════════════════════════════════
class _TtsButton extends StatelessWidget {
  final bool isSpeaking;
  final VoidCallback onTap;
  const _TtsButton({required this.isSpeaking, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 26, height: 26,
      decoration: BoxDecoration(
        color: isSpeaking ? _C.teal : _C.teal.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _C.teal.withOpacity(isSpeaking ? 0.0 : 0.3)),
        boxShadow: isSpeaking ? [
          BoxShadow(color: _C.teal.withOpacity(0.35), blurRadius: 8, offset: const Offset(0, 2))
        ] : [],
      ),
      child: Icon(
        isSpeaking ? Icons.stop_rounded : Icons.volume_up_rounded,
        color: isSpeaking ? Colors.white : _C.teal,
        size: 14,
      ),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// ── TTS SETTINGS SHEET ────────────────────────────────────────────────────────
// ═══════════════════════════════════════════════════════════════════════════════
class _TtsSettingsSheet extends StatefulWidget {
  final double speed;
  final double pitch;
  final ValueChanged<double> onSpeedChanged;
  final ValueChanged<double> onPitchChanged;
  final VoidCallback onClose;
  const _TtsSettingsSheet({
    required this.speed,
    required this.pitch,
    required this.onSpeedChanged,
    required this.onPitchChanged,
    required this.onClose,
  });
  @override
  State<_TtsSettingsSheet> createState() => _TtsSettingsSheetState();
}

class _TtsSettingsSheetState extends State<_TtsSettingsSheet> {
  late double _speed;
  late double _pitch;

  @override
  void initState() {
    super.initState();
    _speed = widget.speed;
    _pitch = widget.pitch;
  }

  String _speedLabel(double v) {
    if (v <= 0.25) return 'Slow';
    if (v <= 0.6)  return 'Normal';
    if (v <= 0.85) return 'Fast';
    return 'Very Fast';
  }

  String _pitchLabel(double v) {
    if (v <= 0.7) return 'Low';
    if (v <= 1.0) return 'Normal';
    if (v <= 1.3) return 'High';
    return 'Very High';
  }

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
        color: _C.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(context).padding.bottom + 24),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      // Handle
      Container(width: 36, height: 4,
          decoration: BoxDecoration(color: _C.border, borderRadius: BorderRadius.circular(2))),
      const SizedBox(height: 20),

      // Header
      Row(children: [
        Container(width: 40, height: 40,
            decoration: BoxDecoration(color: _C.teal.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.record_voice_over_rounded, color: _C.teal, size: 20)),
        const SizedBox(width: 12),
        const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Voice Settings', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: _C.textPri)),
          Text('Adjust text-to-speech playback', style: TextStyle(fontSize: 11, color: _C.textSec)),
        ]),
        const Spacer(),
        GestureDetector(
          onTap: widget.onClose,
          child: Container(width: 32, height: 32,
              decoration: BoxDecoration(color: _C.surface, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.close_rounded, color: _C.textSec, size: 16)),
        ),
      ]),
      const SizedBox(height: 28),

      // Speed slider
      _SliderRow(
        icon: Icons.speed_rounded,
        iconColor: _C.violet,
        label: 'Speech Speed',
        valueLabel: _speedLabel(_speed),
        value: _speed,
        min: 0.1,
        max: 1.0,
        divisions: 9,
        activeColor: _C.violet,
        onChanged: (v) {
          setState(() => _speed = v);
          widget.onSpeedChanged(v);
        },
      ),
      const SizedBox(height: 20),

      // Pitch slider
      _SliderRow(
        icon: Icons.music_note_rounded,
        iconColor: _C.sky,
        label: 'Voice Pitch',
        valueLabel: _pitchLabel(_pitch),
        value: _pitch,
        min: 0.5,
        max: 1.5,
        divisions: 10,
        activeColor: _C.sky,
        onChanged: (v) {
          setState(() => _pitch = v);
          widget.onPitchChanged(v);
        },
      ),
      const SizedBox(height: 24),

      // Info note
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: _C.teal.withOpacity(0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _C.teal.withOpacity(0.2))),
        child: Row(children: [
          const Icon(Icons.info_outline_rounded, color: _C.teal, size: 14),
          const SizedBox(width: 8),
          Expanded(child: Text(
            'Tap the speaker icon on any AI message to hear it read aloud. '
                'Tap again or tap stop to pause.',
            style: const TextStyle(fontSize: 11, color: _C.textSec, height: 1.4),
          )),
        ]),
      ),
    ]),
  );
}

// ─── Slider Row ───────────────────────────────────────────────────────────────
class _SliderRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor, activeColor;
  final String label, valueLabel;
  final double value, min, max;
  final int divisions;
  final ValueChanged<double> onChanged;
  const _SliderRow({
    required this.icon, required this.iconColor, required this.label,
    required this.valueLabel, required this.value, required this.min,
    required this.max, required this.divisions, required this.activeColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      Container(width: 30, height: 30,
          decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: iconColor, size: 15)),
      const SizedBox(width: 10),
      Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _C.textPri)),
      const Spacer(),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
            color: activeColor.withOpacity(0.1), borderRadius: BorderRadius.circular(10),
            border: Border.all(color: activeColor.withOpacity(0.25))),
        child: Text(valueLabel, style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w700, color: activeColor)),
      ),
    ]),
    SliderTheme(
      data: SliderTheme.of(context).copyWith(
        activeTrackColor: activeColor,
        inactiveTrackColor: activeColor.withOpacity(0.15),
        thumbColor: activeColor,
        overlayColor: activeColor.withOpacity(0.12),
        trackHeight: 4,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
      ),
      child: Slider(
        value: value,
        min: min, max: max,
        divisions: divisions,
        onChanged: onChanged,
      ),
    ),
  ]);
}

// ─── Recording Strip ──────────────────────────────────────────────────────────
class _RecordingStrip extends StatefulWidget {
  final Animation<double> pulseAnim;
  final DateTime? startTime;
  final VoidCallback onCancel;
  final VoidCallback onStop;
  const _RecordingStrip({required this.pulseAnim, required this.startTime,
    required this.onCancel, required this.onStop});
  @override
  State<_RecordingStrip> createState() => _RecordingStripState();
}

class _RecordingStripState extends State<_RecordingStrip> {
  late final Stream<int> _ticker = Stream.periodic(const Duration(seconds: 1), (i) => i + 1);

  String _elapsed() {
    if (widget.startTime == null) return '0:00';
    final d = DateTime.now().difference(widget.startTime!);
    return '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2,'0')}';
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<int>(
    stream: _ticker,
    builder: (_, __) => Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
          color: _C.rose.withOpacity(0.07),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _C.rose.withOpacity(0.25))),
      child: Row(children: [
        AnimatedBuilder(
          animation: widget.pulseAnim,
          builder: (_, __) => Transform.scale(
            scale: widget.pulseAnim.value,
            child: Container(width: 10, height: 10,
                decoration: BoxDecoration(color: _C.rose, shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: _C.rose.withOpacity(0.5), blurRadius: 6)])),
          ),
        ),
        const SizedBox(width: 10),
        const Text('Recording...', style: TextStyle(color: _C.rose, fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(width: 8),
        Text(_elapsed(), style: const TextStyle(color: _C.rose, fontSize: 13, fontWeight: FontWeight.w500)),
        const Spacer(),
        GestureDetector(
          onTap: widget.onCancel,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: _C.border, borderRadius: BorderRadius.circular(10)),
            child: const Text('Cancel', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _C.textSec)),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: widget.onStop,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: _C.rose, borderRadius: BorderRadius.circular(10),
                boxShadow: [BoxShadow(color: _C.rose.withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 3))]),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.stop_rounded, color: Colors.white, size: 14),
              SizedBox(width: 4),
              Text('Send', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      ]),
    ),
  );
}

// ─── Language Picker Sheet ────────────────────────────────────────────────────
class _LanguagePickerSheet extends StatelessWidget {
  final _Lang selected;
  final List<_Lang> languages;
  final ValueChanged<_Lang> onSelect;
  const _LanguagePickerSheet({required this.selected, required this.languages, required this.onSelect});

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(color: _C.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(margin: const EdgeInsets.only(top: 12, bottom: 4),
          width: 36, height: 4,
          decoration: BoxDecoration(color: _C.border, borderRadius: BorderRadius.circular(2))),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        child: Row(children: [
          Container(width: 36, height: 36,
              decoration: BoxDecoration(color: _C.sky.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.language_rounded, color: _C.sky, size: 18)),
          const SizedBox(width: 12),
          const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Response Language', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _C.textPri)),
            Text('AI will respond and speak in selected language', style: TextStyle(fontSize: 11, color: _C.textSec)),
          ]),
        ]),
      ),
      const Divider(height: 1),
      ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: languages.length,
          itemBuilder: (_, i) {
            final lang       = languages[i];
            final isSelected = lang.code == selected.code;
            return GestureDetector(
              onTap: () => onSelect(lang),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                    color: isSelected ? _C.sky.withOpacity(0.08) : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: isSelected ? _C.sky.withOpacity(0.35) : Colors.transparent)),
                child: Row(children: [
                  Text(lang.flag, style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(lang.name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                        color: isSelected ? _C.sky : _C.textPri)),
                    Text(lang.geminiName, style: const TextStyle(fontSize: 10, color: _C.textTer)),
                  ])),
                  // TTS locale badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: _C.teal.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: _C.teal.withOpacity(0.2))),
                    child: Text(lang.ttsLocale, style: const TextStyle(
                        fontSize: 8, color: _C.teal, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 8),
                  if (isSelected)
                    Container(width: 22, height: 22,
                        decoration: const BoxDecoration(color: _C.sky, shape: BoxShape.circle),
                        child: const Icon(Icons.check_rounded, color: Colors.white, size: 13)),
                ]),
              ),
            );
          },
        ),
      ),
      SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
    ]),
  );
}

// ─── Quick Prompt ─────────────────────────────────────────────────────────────
// ─── History Sheet — past health analysis chats ───────────────────────────────
class _HistorySheet extends StatelessWidget {
  final Stream<QuerySnapshot<Map<String, dynamic>>> stream;
  final String? currentSessionId;
  final void Function(String id, Map<String, dynamic> data) onOpen;
  final Future<void> Function(String id) onDelete;
  const _HistorySheet({
    required this.stream,
    required this.currentSessionId,
    required this.onOpen,
    required this.onDelete,
  });

  String _when(Timestamp? ts) {
    if (ts == null) return '';
    final d = ts.toDate();
    final now = DateTime.now();
    final diff = now.difference(d);
    if (diff.inMinutes < 1)  return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24)   return '${diff.inHours}h ago';
    if (diff.inDays < 7)     return '${diff.inDays}d ago';
    return '${d.day}/${d.month}/${d.year}';
  }

  @override
  Widget build(BuildContext context) => Container(
    constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.72),
    decoration: const BoxDecoration(
        color: _C.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const SizedBox(height: 10),
      Container(width: 40, height: 4, decoration: BoxDecoration(
          color: _C.border, borderRadius: BorderRadius.circular(2))),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Row(children: [
          Container(width: 36, height: 36,
              decoration: BoxDecoration(
                  color: _C.violet.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(11)),
              child: const Icon(Icons.history_rounded, color: _C.violet, size: 18)),
          const SizedBox(width: 10),
          const Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Chat History', style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700, color: _C.textPri)),
            Text('Tap a session to reopen & continue it',
                style: TextStyle(fontSize: 10.5, color: _C.textTer)),
          ])),
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Icon(Icons.close_rounded, color: _C.textSec, size: 20),
          ),
        ]),
      ),
      const Divider(height: 1, color: _C.border),
      Flexible(child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: SizedBox(width: 26, height: 26,
                  child: CircularProgressIndicator(strokeWidth: 2, color: _C.teal))),
            );
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(40),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.forum_outlined, color: _C.textTer, size: 40),
                SizedBox(height: 12),
                Text('No saved chats yet', style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700, color: _C.textSec)),
                SizedBox(height: 4),
                Text('Your health analysis conversations\nwill be saved here automatically.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11.5, color: _C.textTer, height: 1.4)),
              ]),
            );
          }
          return ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 26),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final doc  = docs[i];
              final data = doc.data();
              final score = (data['score'] as num?)?.toInt();
              final isCurrent = doc.id == currentSessionId;
              return GestureDetector(
                onTap: () => onOpen(doc.id, data),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: isCurrent ? _C.teal.withOpacity(0.05) : _C.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: isCurrent
                          ? _C.teal.withOpacity(0.4) : _C.border)),
                  child: Row(children: [
                    Container(width: 38, height: 38,
                        decoration: BoxDecoration(
                            color: (score != null ? _C.teal : _C.sky).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(11)),
                        child: score != null
                            ? Center(child: Text('$score', style: const TextStyle(
                                color: _C.teal, fontSize: 13, fontWeight: FontWeight.w700)))
                            : const Icon(Icons.chat_bubble_outline_rounded,
                                color: _C.sky, size: 16)),
                    const SizedBox(width: 11),
                    Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text((data['title'] ?? 'Health chat').toString(),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13,
                              fontWeight: FontWeight.w700, color: _C.textPri)),
                      const SizedBox(height: 3),
                      Text(
                        '${_when(data['updatedAt'] as Timestamp?)} · '
                        '${(data['msgCount'] as num?)?.toInt() ?? 0} messages'
                        '${score != null ? ' · Score $score/100' : ''}'
                        '${isCurrent ? ' · Current' : ''}',
                        style: const TextStyle(fontSize: 10, color: _C.textTer),
                      ),
                    ])),
                    GestureDetector(
                      onTap: () async {
                        HapticFeedback.lightImpact();
                        await onDelete(doc.id);
                      },
                      child: Container(
                        width: 30, height: 30,
                        decoration: BoxDecoration(
                            color: _C.rose.withOpacity(0.07),
                            borderRadius: BorderRadius.circular(9)),
                        child: const Icon(Icons.delete_outline_rounded,
                            color: _C.rose, size: 15),
                      ),
                    ),
                  ]),
                ),
              );
            },
          );
        },
      )),
    ]),
  );
}

class _QuickPrompt extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _QuickPrompt(this.label, this.onTap);

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
          color: _C.violet.withOpacity(0.08),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _C.violet.withOpacity(0.25))),
      child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _C.violet)),
    ),
  );
}

// ─── Vitals Strip ────────────────────────────────────────────────────────────
// Shows BP, sugar, and adherence as tappable data chips side by side
class _VitalsStrip extends StatelessWidget {
  final Map<String, dynamic>? latestBP;
  final Map<String, dynamic>? latestSugar;
  final int? adherencePct;
  final int trackedMeds;
  const _VitalsStrip({
    this.latestBP, this.latestSugar,
    required this.adherencePct, required this.trackedMeds,
  });

  Color _bpColor() {
    final score = (latestBP?['score'] as num?)?.toInt() ?? 50;
    if (score >= 80) return _C.teal;
    if (score >= 60) return _C.amber;
    return _C.rose;
  }

  Color _sugarColor() {
    final score = (latestSugar?['score'] as num?)?.toInt() ?? 50;
    if (score >= 80) return _C.teal;
    if (score >= 60) return _C.amber;
    return _C.rose;
  }

  Color _adherenceColor() {
    if (adherencePct == null) return _C.textTer;
    if (adherencePct! >= 80) return _C.teal;
    if (adherencePct! >= 50) return _C.amber;
    return _C.rose;
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
        color: _C.card, borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _C.border),
        boxShadow: [BoxShadow(color: MedicColors.forest.withOpacity(0.025),
            blurRadius: 10, offset: const Offset(0, 3))]),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Header
      Row(children: [
        Container(width: 26, height: 26,
            decoration: BoxDecoration(
                color: _C.sky.withOpacity(0.12),
                borderRadius: BorderRadius.circular(7)),
            child: const Icon(Icons.monitor_heart_rounded, color: _C.sky, size: 14)),
        const SizedBox(width: 8),
        const Text('Vitals & Adherence', style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w700, color: _C.textPri)),
        const Spacer(),
        const Text('from profile scans', style: TextStyle(
            fontSize: 9, color: _C.textTer)),
      ]),
      const SizedBox(height: 12),
      // Chips row
      Row(children: [
        if (latestBP != null)
          Expanded(child: _VitalChip(
            icon: Icons.favorite_rounded,
            color: _bpColor(),
            label: 'Blood Pressure',
            value: '${latestBP!['display'] ?? '?'} mmHg',
            sub: latestBP!['condition'] ?? '',
          )),
        if (latestBP != null && latestSugar != null) const SizedBox(width: 8),
        if (latestSugar != null)
          Expanded(child: _VitalChip(
            icon: Icons.water_drop_rounded,
            color: _sugarColor(),
            label: 'Blood Sugar',
            value: latestSugar!['display'] ?? '?',
            sub: latestSugar!['condition'] ?? '',
          )),
        if ((latestBP != null || latestSugar != null) && trackedMeds > 0)
          const SizedBox(width: 8),
        if (trackedMeds > 0)
          Expanded(child: _VitalChip(
            icon: Icons.medication_liquid_rounded,
            color: _adherenceColor(),
            label: 'Adherence',
            value: adherencePct == null ? 'No data' : '$adherencePct%',
            sub: '$trackedMeds medicine${trackedMeds == 1 ? '' : 's'} tracked',
          )),
        // If only one data point, add spacer for layout
        if (latestBP == null && latestSugar != null && trackedMeds == 0)
          Expanded(child: Container()),
      ]),
    ]),
  );
}

class _VitalChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label, value, sub;
  const _VitalChip({
    required this.icon, required this.color,
    required this.label, required this.value, required this.sub,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: color, size: 14),
      const SizedBox(height: 6),
      Text(value, style: TextStyle(
          fontSize: 13, fontWeight: FontWeight.w700,
          color: color, letterSpacing: -0.3)),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(
          fontSize: 9, fontWeight: FontWeight.w700, color: _C.textPri)),
      Text(sub, style: const TextStyle(
          fontSize: 8, color: _C.textTer),
          maxLines: 1, overflow: TextOverflow.ellipsis),
    ]),
  );
}

// ─── Score Card ───────────────────────────────────────────────────────────────
class _ScoreCard extends StatelessWidget {
  final _AnalysisReport report;
  final Animation<double> anim;
  final int? adherencePct;
  final Map<String, dynamic>? latestBP;
  final Map<String, dynamic>? latestSugar;
  const _ScoreCard({
    required this.report, required this.anim,
    this.adherencePct,
    this.latestBP, this.latestSugar,
  });

  @override
  Widget build(BuildContext context) => const DailyHealthScoreCard(dark: true);

}

class _ScoreBar extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  const _ScoreBar({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Row(children: [
    SizedBox(width: 90, child: Text(label, style: TextStyle(
        color: Colors.white.withOpacity(0.5), fontSize: 9, fontWeight: FontWeight.w500))),
    Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(3),
        child: LinearProgressIndicator(value: value.clamp(0.0, 1.0),
            backgroundColor: Colors.white.withOpacity(0.1),
            valueColor: AlwaysStoppedAnimation<Color>(color), minHeight: 4))),
    const SizedBox(width: 6),
    Text('${(value * 100).toInt()}%', style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w700)),
  ]);
}

// ─── Insights Grid ────────────────────────────────────────────────────────────
class _InsightsGrid extends StatelessWidget {
  final List<_InsightCard> insights;
  const _InsightsGrid({required this.insights});

  @override
  Widget build(BuildContext context) => GridView.count(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    crossAxisCount: 2, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.35,
    children: insights.take(4).map((c) => Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: _C.card, borderRadius: BorderRadius.circular(22),
          border: Border.all(color: c.color.withOpacity(0.2)),
          boxShadow: [BoxShadow(color: MedicColors.forest.withOpacity(0.025), blurRadius: 10, offset: const Offset(0, 3))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Row(children: [
              Container(width: 32, height: 32,
                  decoration: BoxDecoration(color: c.color.withOpacity(0.1), borderRadius: BorderRadius.circular(9)),
                  child: Icon(c.icon, color: c.color, size: 16)),
              const Spacer(),
            ]),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.color, letterSpacing: -0.3)),
              const SizedBox(height: 2),
              Text(c.title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _C.textPri)),
              const SizedBox(height: 2),
              Text(c.subtitle, style: const TextStyle(fontSize: 9, color: _C.textTer, height: 1.3),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
            ]),
          ]),
    )).toList(),
  );
}

// ─── Timeline Widget ──────────────────────────────────────────────────────────
class _TimelineWidget extends StatelessWidget {
  final List<_TimelineEntry> entries;
  const _TimelineWidget({required this.entries});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(color: _C.card, borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _C.border),
        boxShadow: [BoxShadow(color: MedicColors.forest.withOpacity(0.025), blurRadius: 12, offset: const Offset(0, 3))]),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 30, height: 30,
            decoration: BoxDecoration(color: _C.teal.withOpacity(0.1), borderRadius: BorderRadius.circular(9)),
            child: const Icon(Icons.timeline_rounded, color: _C.teal, size: 16)),
        const SizedBox(width: 9),
        const Text('Health Timeline', style: TextStyle(
            fontSize: 14, fontWeight: FontWeight.w700, color: _C.textPri, letterSpacing: -0.3)),
      ]),
      const SizedBox(height: 16),
      ...entries.asMap().entries.map((e) {
        final i = e.key; final ent = e.value; final isLast = i == entries.length - 1;
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Column(children: [
            Container(width: 30, height: 30,
                decoration: BoxDecoration(color: ent.color.withOpacity(0.12), shape: BoxShape.circle),
                child: Icon(ent.icon, color: ent.color, size: 14)),
            if (!isLast) Container(width: 2, height: 36, color: _C.border),
          ]),
          const SizedBox(width: 14),
          Expanded(child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(ent.period, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _C.textPri)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: ent.color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: Text(ent.status, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: ent.color)),
                ),
              ]),
              const SizedBox(height: 3),
              Text(ent.note, style: const TextStyle(fontSize: 11, color: _C.textSec, height: 1.4)),
            ]),
          )),
        ]);
      }),
    ]),
  );
}

// ─── Animated Dot ─────────────────────────────────────────────────────────────
class _Dot extends StatefulWidget {
  final int idx;
  final Color color;
  const _Dot(this.idx, this.color);
  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(duration: const Duration(milliseconds: 600), vsync: this)
      ..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
    Future.delayed(Duration(milliseconds: widget.idx * 150), () {
      if (mounted) _ctrl.repeat(reverse: true);
    });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder: (_, __) => Container(
      width: 7, height: 7,
      decoration: BoxDecoration(
          color: widget.color.withOpacity(0.3 + _anim.value * 0.65),
          shape: BoxShape.circle),
    ),
  );
}

// ─── Gauge Painter ────────────────────────────────────────────────────────────
class _GaugePainter extends CustomPainter {
  final double progress;
  final Color color;
  const _GaugePainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 8;
    const startAngle = math.pi * 0.75;
    const sweepAngle = math.pi * 1.5;

    canvas.drawArc(Rect.fromCircle(center: c, radius: r), startAngle, sweepAngle, false,
        Paint()..color = Colors.white.withOpacity(0.1)..strokeWidth = 8
          ..style = PaintingStyle.stroke..strokeCap = StrokeCap.round);

    if (progress > 0) {
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), startAngle, sweepAngle * progress, false,
          Paint()..color = color..strokeWidth = 8
            ..style = PaintingStyle.stroke..strokeCap = StrokeCap.round);
    }
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) => old.progress != progress || old.color != color;
}

// ─── Mesh Painters ────────────────────────────────────────────────────────────
class _MeshPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(Offset(size.width * 0.88, size.height * 0.2), 80,
        Paint()..color = _C.violet.withOpacity(0.07));
    canvas.drawCircle(Offset(size.width * 0.05, size.height * 0.82), 60,
        Paint()..color = _C.teal.withOpacity(0.06));
  }
  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _ScoreMeshPainter extends CustomPainter {
  final Color accent;
  const _ScoreMeshPainter(this.accent);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(Offset(size.width * 0.85, size.height * 0.15), 100,
        Paint()..color = accent.withOpacity(0.07));
    canvas.drawCircle(Offset(size.width * 0.05, size.height * 0.9), 80,
        Paint()..color = _C.sky.withOpacity(0.05));
  }
  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}