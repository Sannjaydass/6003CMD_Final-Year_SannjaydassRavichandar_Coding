import 'nearby_facilities_screen.dart';
import 'package:medictrack/design/medic_design.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_tts/flutter_tts.dart';
import '../../services/auth_service.dart';
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
  static const safe    = MedicColors.c28715D;
  static const warn    = MedicColors.cB77A27;
  static const danger  = MedicColors.cC05256;
}

// ─── Language Config ──────────────────────────────────────────────────────────
class _Lang {
  final String code, name, flag, geminiName, ttsLocale;
  const _Lang({
    required this.code,
    required this.name,
    required this.flag,
    required this.geminiName,
    required this.ttsLocale,
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

// ─── Chat Message Model ───────────────────────────────────────────────────────
class _ChatMsg {
  final String text;
  final bool isUser, isError;
  final DateTime time;
  final Map<String, dynamic>? medicine;
  const _ChatMsg({
    required this.text,
    required this.isUser,
    required this.time,
    this.medicine,
    this.isError = false,
  });
}

// ─── Screen ───────────────────────────────────────────────────────────────────
class SafeDisposalScreen extends StatefulWidget {
  const SafeDisposalScreen({Key? key}) : super(key: key);

  @override
  State<SafeDisposalScreen> createState() => _SafeDisposalScreenState();
}

class _SafeDisposalScreenState extends State<SafeDisposalScreen>
    with SingleTickerProviderStateMixin {
  final AuthService _authSvc    = AuthService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _inputCtrl  = TextEditingController();
  final ScrollController _scrollCtrl     = ScrollController();

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  // ── TTS ──────────────────────────────────────────────────────────────────────
  final FlutterTts _tts = FlutterTts();
  String? _speakingMsgId;
  bool _ttsReady   = false;
  double _ttsSpeed = 0.5;
  double _ttsPitch = 1.0;

  // ── Language ─────────────────────────────────────────────────────────────────
  _Lang _selectedLang = _kLanguages[0];

  // ── State ────────────────────────────────────────────────────────────────────
  List<_ChatMsg> _messages     = [];
  List<Map<String, dynamic>> _medicines = [];
  Map<String, dynamic>? _activeMed;
  bool _loadingMeds = false;
  bool _typing      = false;

  // Reads the one shared key/endpoint from GeminiService instead of its own
  // copy — see the doc comment on GeminiService for why this was centralized.
  static const _apiKey = GeminiService.apiKey;
  static const _apiUrl = GeminiService.baseUrl;

  // ── Lifecycle ────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        duration: const Duration(milliseconds: 600), vsync: this);
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
    _initTts();
    _loadMedicines();
    _addWelcome();
    _inputCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tts.stop();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TTS
  // ═══════════════════════════════════════════════════════════════════════════
  Future<void> _initTts() async {
    await _tts.setLanguage(_selectedLang.ttsLocale);
    await _tts.setSpeechRate(_ttsSpeed);
    await _tts.setPitch(_ttsPitch);
    await _tts.setVolume(1.0);

    if (Platform.isAndroid) {
      await _tts.setEngine('com.google.android.tts');
    }

    _tts.setCompletionHandler(() {
      if (mounted) setState(() => _speakingMsgId = null);
    });
    _tts.setCancelHandler(() {
      if (mounted) setState(() => _speakingMsgId = null);
    });
    _tts.setErrorHandler((_) {
      if (mounted) setState(() => _speakingMsgId = null);
    });

    setState(() => _ttsReady = true);
  }

  String _msgId(_ChatMsg msg) =>
      '${msg.time.millisecondsSinceEpoch}_${msg.text.hashCode}';

  Future<void> _toggleSpeak(_ChatMsg msg) async {
    HapticFeedback.lightImpact();
    final id = _msgId(msg);

    if (_speakingMsgId == id) {
      await _tts.stop();
      setState(() => _speakingMsgId = null);
      return;
    }
    if (_speakingMsgId != null) await _tts.stop();

    await _tts.setLanguage(_selectedLang.ttsLocale);
    await _tts.setSpeechRate(_ttsSpeed);
    await _tts.setPitch(_ttsPitch);

    final cleaned = msg.text
        .replaceAll('**', '')
        .replaceAll('*', '')
        .replaceAll('`', '')
        .replaceAll('#', '')
        .trim();

    setState(() => _speakingMsgId = id);
    await _tts.speak(cleaned);
  }

  Future<void> _stopTts() async {
    await _tts.stop();
    setState(() => _speakingMsgId = null);
  }

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
          await _tts.setLanguage(lang.ttsLocale);
          Navigator.pop(context);
          _addAiMsg(
            lang.code == 'en'
                ? 'Language set to English. I will respond in English from now on.'
                : 'Language set to ${lang.name} ${lang.flag}. I will respond in ${lang.geminiName} from now on.',
          );
        },
      ),
    );
  }

  String get _langInstruction => _selectedLang.code == 'en'
      ? ''
      : '\n\nIMPORTANT: Respond ENTIRELY in ${_selectedLang.geminiName}. All text must be in ${_selectedLang.geminiName}.';

  // ─── Welcome ─────────────────────────────────────────────────────────────────
  void _addWelcome() {
    _messages.add(_ChatMsg(
      text: "Hello! I am your Safe Disposal Assistant.\n\n"
          "Tap the medicine icon below to pick a medicine from your inventory, "
          "or just type any question about medicine disposal.\n\n"
          "Use the globe icon to change language, and tap the speaker icon "
          "on any response to hear it read aloud.",
      isUser: false,
      time: DateTime.now(),
    ));
  }

  // ─── Load medicines ──────────────────────────────────────────────────────────
  Future<void> _loadMedicines() async {
    final user = _authSvc.currentUser;
    if (user == null) return;
    setState(() => _loadingMeds = true);
    try {
      final snap = await _firestore
          .collection('medicines')
          .where('userId', isEqualTo: user.uid)
          .orderBy('medicineName')
          .get();
      setState(() {
        _medicines = snap.docs.map((d) {
          final m = d.data(); m['id'] = d.id; return m;
        }).toList();
        _loadingMeds = false;
      });
    } catch (_) {
      setState(() => _loadingMeds = false);
    }
  }

  // ─── Scroll ──────────────────────────────────────────────────────────────────
  void _scrollDown() => Future.delayed(const Duration(milliseconds: 120), () {
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  });

  // ─── Select medicine ──────────────────────────────────────────────────────────
  Future<void> _selectMedicine(Map<String, dynamic> med) async {
    await _stopTts();
    HapticFeedback.lightImpact();
    setState(() {
      _activeMed = med;
      _messages.add(_ChatMsg(
        text: 'How do I safely dispose of ${med['medicineName']}?',
        isUser: true, time: DateTime.now(),
      ));
      _typing = true;
    });
    _scrollDown();
    await _callGemini(_buildDisposalPrompt(med), medicine: med);
    _scrollDown();
  }

  String _buildDisposalPrompt(Map<String, dynamic> med) => '''
You are a medicine disposal expert. Provide detailed safe disposal instructions for:

Name: ${med['medicineName']}
Generic: ${med['genericName'] ?? 'N/A'}
Category: ${med['category'] ?? 'N/A'}
Dosage Form: ${med['dosage'] ?? 'N/A'}
Status: ${med['status'] ?? 'Unknown'}
Days Until Expiry: ${med['daysUntilExpiry'] ?? 'Unknown'}

Include: 1) Disposal Method 2) Safety Precautions 3) What NOT to Do 4) Drop-off Locations
5) Environmental Impact 6) Step-by-Step Guide.

IMPORTANT FORMATTING RULES:
- Use emojis for section headers instead of markdown (e.g. "🗑️ 1) Disposal Method" not "### 1) Disposal Method")
- Do NOT use #, ##, ###, **, __ or any markdown syntax
- Write in plain readable text with emojis only
- Keep responses complete — do not cut off mid-sentence
- Be thorough but clear$_langInstruction
''';

  // ─── Send message ─────────────────────────────────────────────────────────────
  Future<void> _send(String text) async {
    if (text.trim().isEmpty) return;
    await _stopTts();
    HapticFeedback.lightImpact();
    setState(() {
      _messages.add(_ChatMsg(text: text, isUser: true, time: DateTime.now()));
      _typing = true;
    });
    _inputCtrl.clear();
    _scrollDown();

    final prompt = '''
You are a helpful medicine disposal assistant.
${_activeMed != null ? 'Current medicine context: ${_activeMed!['medicineName']} (${_activeMed!['category'] ?? ''})' : ''}
Question: $text
Provide a helpful accurate answer about safe medicine disposal.
FORMATTING: Use emojis for emphasis, plain text only — no markdown (#, ##, **, __). Be complete, do not cut off.$_langInstruction
''';
    await _callGemini(prompt);
    _scrollDown();
  }

  // ─── Clean markdown from Gemini text ────────────────────────────────────────
  String _cleanText(String raw) {
    return raw
        .replaceAll(RegExp(r'#{1,6}\s*'), '')
        .replaceAll('**', '')
        .replaceAll('__', '')
        .replaceAll(RegExp(r'`{3}[\s\S]*?`{3}'), '')
        .replaceAll('`', '')
        .replaceAll('---', '')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  // ─── Gemini call — with auto-continuation if truncated ───────────────────────
  static const _disposalSafety = 'Provide general medicine disposal advice, not a diagnosis or prescribing advice. '
      'Use Malaysia as the default jurisdiction but ask the user to confirm their country. Prefer returning unused or expired '
      'medicines to a pharmacist or authorised take-back service. Never invent facility names, addresses, acceptance policies, '
      'opening hours or donation eligibility. Direct location requests to the Nearby facilities button, where acceptance is unverified. '
      'Do not recommend sharing prescription medicines, flushing, burning, crushing, opening capsules or mixing chemicals. '
      'Ask about dosage form, expiry, original packaging and storage when relevant. Expired, opened, damaged or improperly stored '
      'medicines must not be recommended for donation. Even unopened unexpired products need explicit approval by an authorised programme. '
      'Needles, inhalers, cytotoxic medicines and refrigerated products require specific pharmacist advice. '
      'Do not infer shelf life or safety from a picture. Do not instruct a user to stop prescribed treatment. '
      'Keep answers concise, explain uncertainty and ask the pharmacist when medicine-specific disposal rules are unknown.';

  Future<void> _callGemini(String prompt,
      {Map<String, dynamic>? medicine}) async {
    try {
      final res = await http.post(
        Uri.parse('$_apiUrl?key=$_apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'systemInstruction': {'parts': [{'text': _disposalSafety}]},
          'contents': [{'parts': [{'text': prompt}]}],
          'generationConfig': {
            'temperature': 0.2,
            'maxOutputTokens': 8192,
          },
        }),
      ).timeout(const Duration(seconds: 45));
      if (!mounted) return;

      if (res.statusCode != 200) {
        _addError('AI service error (${res.statusCode}). Please try again.');
        return;
      }

      final d            = jsonDecode(res.body);
      final candidate    = d['candidates']?[0];
      var text           = candidate?['content']?['parts']?[0]?['text'] ?? '';
      final finishReason = candidate?['finishReason'] ?? 'STOP';

      // Auto-continue if Gemini hit token limit mid-response
      if (finishReason == 'MAX_TOKENS' && text.isNotEmpty) {
        final continueRes = await http.post(
          Uri.parse('$_apiUrl?key=$_apiKey'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'systemInstruction': {'parts': [{'text': _disposalSafety}]},
          'contents': [
              {'parts': [{'text': prompt}], 'role': 'user'},
              {'parts': [{'text': text}], 'role': 'model'},
              {
                'parts': [{'text': 'Continue exactly from where you left off. Do not repeat anything already written.'}],
                'role': 'user'
              },
            ],
            'generationConfig': {
              'temperature': 0.2,
              'maxOutputTokens': 8192,
            },
          }),
        ).timeout(const Duration(seconds: 45));
        if (!mounted) return;
        if (continueRes.statusCode == 200) {
          final cd   = jsonDecode(continueRes.body);
          final cont = cd['candidates']?[0]?['content']?['parts']?[0]?['text'] ?? '';
          if (cont.isNotEmpty) text = '$text $cont';
        }
      }

      if (!mounted) return;
      if (text.toString().trim().isEmpty) { _addError('No advice returned. Please ask a pharmacist or retry.'); return; }
      setState(() {
        _typing = false;
        _messages.add(_ChatMsg(
            text: _cleanText(text),
            isUser: false,
            time: DateTime.now(),
            medicine: medicine));
      });
    } catch (e) {
      _addError('Advice is unavailable. Please retry, or ask a pharmacist about safe return.');
    }
  }

  void _addAiMsg(String text) {
    setState(() {
      _typing = false;
      _messages.add(_ChatMsg(text: text, isUser: false, time: DateTime.now()));
    });
  }

  void _addError(String msg) {
    if (!mounted) return;
    setState(() {
      _typing = false;
      _messages.add(_ChatMsg(
          text: msg, isUser: false, time: DateTime.now(), isError: true));
    });
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Row(children: [
        Icon(Icons.check_circle_rounded, color: Colors.white, size: 15),
        SizedBox(width: 8),
        Text('Copied', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      ]),
      backgroundColor: _C.navy,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
      duration: const Duration(milliseconds: 1400),
    ));
  }

  void _openInventory() => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _MedicinePickerSheet(
      medicines: _medicines,
      onSelect: (med) { Navigator.pop(context); _selectMedicine(med); },
    ),
  );

  String _fmt(DateTime t) {
    final h = t.hour == 0 ? 12 : t.hour > 12 ? t.hour - 12 : t.hour;
    final p = t.hour >= 12 ? 'PM' : 'AM';
    return '$h:${t.minute.toString().padLeft(2, '0')} $p';
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
          Material(color: const Color(0xFFE4EEDC), child: ListTile(
            leading: const Icon(Icons.location_on_outlined),
            title: const Text('Nearby clinics, hospitals & pharmacies'),
            subtitle: const Text('Ask about safe returns and donation eligibility'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NearbyFacilitiesScreen())))),
          Expanded(child: Column(children: [
            Expanded(child: _loadingMeds ? _buildLoading() : _buildChat()),
            if (_typing) _buildTyping(),
            _buildInput(),
          ])),
        ]),
      ),
    ),
  );

  // ── Header — 2-row compact layout ────────────────────────────────────────────
  Widget _buildHeader() => MedicHeaderSurface(
    child: Stack(children: [
      Positioned.fill(child: CustomPaint(painter: _MeshPainter())),
      SafeArea(bottom: false, child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Column(mainAxisSize: MainAxisSize.min, children: [

          // ── ROW 1: back + title + inventory button ────────────────────────
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            // Back
            GestureDetector(
              onTap: () async { await _stopTts(); Navigator.pop(context); },
              child: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withOpacity(0.15))),
                child: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: Colors.white, size: 15),
              ),
            ),
            const SizedBox(width: 10),

            // Title
            Expanded(
              child: Text('Safe Disposal',
                style: const TextStyle(fontFamily: 'serif',
                    color: Colors.white, fontSize: 18,
                    fontWeight: FontWeight.w700, letterSpacing: -0.4),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),

            // Inventory button
            GestureDetector(
              onTap: _openInventory,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                    color: MedicColors.mint.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: MedicColors.mint.withOpacity(0.3))),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.inventory_2_rounded, color: MedicColors.mint, size: 14),
                  SizedBox(width: 5),
                  Text('Inventory', style: TextStyle(
                      color: MedicColors.mint, fontWeight: FontWeight.w700, fontSize: 11)),
                ]),
              ),
            ),
          ]),

          const SizedBox(height: 10),

          // ── ROW 2: badges + TTS settings + language picker ────────────────
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            // AI Assistant badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                  color: _C.violet.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: _C.violet.withOpacity(0.35))),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.smart_toy_rounded, color: _C.violet, size: 10),
                SizedBox(width: 3),
                Text('AI Assistant', style: TextStyle(
                    color: _C.violet, fontSize: 9, fontWeight: FontWeight.w700)),
              ]),
            ),
            const SizedBox(width: 6),

            // Online indicator
            Container(width: 6, height: 6,
                decoration: const BoxDecoration(
                    color: MedicColors.mint, shape: BoxShape.circle)),
            const SizedBox(width: 4),
            Text('Online', style: TextStyle(
                color: Colors.white.withOpacity(0.45), fontSize: 10)),

            const Spacer(),

            // TTS settings (tune icon)
            if (_ttsReady) ...[
              GestureDetector(
                onTap: _showTtsSettings,
                child: Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: Colors.white.withOpacity(0.15))),
                  child: const Icon(Icons.tune_rounded,
                      color: Colors.white, size: 15),
                ),
              ),
              const SizedBox(width: 6),
            ],

            // Language picker
            GestureDetector(
              onTap: _showLanguagePicker,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: Colors.white.withOpacity(0.15))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(_selectedLang.flag,
                      style: const TextStyle(fontSize: 13)),
                  const SizedBox(width: 4),
                  Text(_selectedLang.code.toUpperCase(),
                      style: const TextStyle(
                          color: Colors.white, fontSize: 10,
                          fontWeight: FontWeight.w700)),
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

  // ── Chat area ────────────────────────────────────────────────────────────────
  Widget _buildChat() => ListView.builder(
    controller: _scrollCtrl,
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
    itemCount: _messages.length,
    itemBuilder: (_, i) => _buildBubble(_messages[i]),
  );

  Widget _buildLoading() => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    SizedBox(width: 36, height: 36,
        child: CircularProgressIndicator(strokeWidth: 2.5, color: _C.teal,
            backgroundColor: _C.teal.withOpacity(0.15))),
    const SizedBox(height: 14),
    const Text('Loading your medicines...',
        style: TextStyle(color: _C.textSec, fontSize: 13, fontWeight: FontWeight.w500)),
  ]));

  // ── Chat bubble ───────────────────────────────────────────────────────────────
  Widget _buildBubble(_ChatMsg msg) {
    final u         = msg.isUser;
    final id        = _msgId(msg);
    final isSpeaking = _speakingMsgId == id;

    return Padding(
      padding: EdgeInsets.only(bottom: 14, left: u ? 52 : 0, right: u ? 0 : 52),
      child: Row(
        mainAxisAlignment: u ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!u) ...[
            _AiAvatar(isError: msg.isError),
            const SizedBox(width: 8),
          ],
          Flexible(child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: u ? _C.navy : (msg.isError ? _C.rose.withOpacity(0.06) : _C.card),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(u ? 18 : 4),
                bottomRight: Radius.circular(u ? 4 : 18),
              ),
              border: u
                  ? Border.all(color: Colors.white.withOpacity(0.08))
                  : Border.all(color: msg.isError
                  ? _C.rose.withOpacity(0.2) : _C.border),
              boxShadow: [BoxShadow(
                color: (u ? _C.navy : Colors.black).withOpacity(0.06),
                blurRadius: 12, offset: const Offset(0, 5),
              )],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Medicine context tag
              if (msg.medicine != null && !u) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                      color: _C.teal.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _C.teal.withOpacity(0.2))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.medication_rounded, color: _C.teal, size: 14),
                    const SizedBox(width: 6),
                    Text(msg.medicine!['medicineName'] ?? 'Medicine',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700,
                            color: _C.textPri)),
                  ]),
                ),
              ],

              // Message text + copy button
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: SelectableText(
                  msg.text,
                  style: TextStyle(
                    fontSize: 14, height: 1.6,
                    color: u ? Colors.white
                        : (msg.isError ? _C.rose : _C.textPri),
                  ),
                )),
                if (!u) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _copy(msg.text),
                    child: Container(
                      width: 30, height: 30,
                      decoration: BoxDecoration(
                          color: _C.surface,
                          borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.copy_outlined,
                          size: 14, color: _C.textTer),
                    ),
                  ),
                ],
              ]),

              const SizedBox(height: 8),

              // Bottom row: timestamp + language badge + TTS button
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                // Language badge for non-English AI messages
                if (!u && _selectedLang.code != 'en')
                  Row(children: [
                    Text(_selectedLang.flag,
                        style: const TextStyle(fontSize: 9)),
                    const SizedBox(width: 3),
                    Text(_selectedLang.name,
                        style: const TextStyle(
                            fontSize: 9, color: _C.textTer,
                            fontWeight: FontWeight.w500)),
                  ])
                else
                  const SizedBox(),

                Row(children: [
                  Text(_fmt(msg.time), style: TextStyle(
                      fontSize: 10,
                      color: u ? Colors.white.withOpacity(0.4) : _C.textTer)),

                  // TTS button — AI messages only
                  if (!u && _ttsReady && !msg.isError) ...[
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
            _UserAvatar(),
          ],
        ],
      ),
    );
  }

  // ── Typing indicator ──────────────────────────────────────────────────────────
  Widget _buildTyping() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
    child: Row(children: [
      const _AiAvatar(),
      const SizedBox(width: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
            color: _C.card, borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _C.border)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _Dot(0), const SizedBox(width: 5),
          _Dot(1), const SizedBox(width: 5),
          _Dot(2),
        ]),
      ),
    ]),
  );

  // ── Input bar ────────────────────────────────────────────────────────────────
  Widget _buildInput() => Container(
    padding: EdgeInsets.fromLTRB(
        16, 10, 16, MediaQuery.of(context).padding.bottom + 12),
    decoration: BoxDecoration(
        color: _C.card,
        border: Border(top: BorderSide(color: _C.border)),
        boxShadow: [BoxShadow(color: MedicColors.forest.withOpacity(0.025),
            blurRadius: 16, offset: const Offset(0, -4))]),
    child: Row(children: [
      // Inventory shortcut
      GestureDetector(
        onTap: _openInventory,
        child: Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
              color: _C.teal.withOpacity(0.1),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: _C.teal.withOpacity(0.25))),
          child: const Icon(Icons.medication_rounded, color: _C.teal, size: 20),
        ),
      ),
      const SizedBox(width: 10),

      // Text field
      Expanded(child: Container(
        decoration: BoxDecoration(
            color: _C.surface, borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _C.border)),
        child: TextField(
          controller: _inputCtrl,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500,
              color: _C.textPri),
          decoration: const InputDecoration(
            hintText: 'Ask about medicine disposal...',
            hintStyle: TextStyle(color: _C.textTer, fontSize: 13),
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: _send,
        ),
      )),
      const SizedBox(width: 10),

      // Send button
      GestureDetector(
        onTap: () => _send(_inputCtrl.text),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: _inputCtrl.text.trim().isNotEmpty
                ? _C.teal : _C.teal.withOpacity(0.35),
            borderRadius: BorderRadius.circular(13),
            boxShadow: _inputCtrl.text.trim().isNotEmpty ? [
              BoxShadow(color: _C.teal.withOpacity(0.3),
                  blurRadius: 10, offset: const Offset(0, 4))
            ] : [],
          ),
          child: const Icon(Icons.send_rounded, color: Colors.white, size: 19),
        ),
      ),
    ]),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// ── TTS BUTTON ────────────────────────────────────────────────────────────────
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
          BoxShadow(color: _C.teal.withOpacity(0.35),
              blurRadius: 8, offset: const Offset(0, 2))
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
  final double speed, pitch;
  final ValueChanged<double> onSpeedChanged, onPitchChanged;
  final VoidCallback onClose;
  const _TtsSettingsSheet({
    required this.speed, required this.pitch,
    required this.onSpeedChanged, required this.onPitchChanged,
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
    if (v <= 0.7)  return 'Low';
    if (v <= 1.0)  return 'Normal';
    if (v <= 1.3)  return 'High';
    return 'Very High';
  }

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
        color: _C.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    padding: EdgeInsets.fromLTRB(
        24, 16, 24, MediaQuery.of(context).padding.bottom + 24),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      // Handle
      Container(width: 36, height: 4,
          decoration: BoxDecoration(
              color: _C.border, borderRadius: BorderRadius.circular(2))),
      const SizedBox(height: 20),

      // Header
      Row(children: [
        Container(width: 40, height: 40,
            decoration: BoxDecoration(
                color: _C.teal.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.record_voice_over_rounded,
                color: _C.teal, size: 20)),
        const SizedBox(width: 12),
        const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Voice Settings', style: TextStyle(
              fontSize: 17, fontWeight: FontWeight.w700, color: _C.textPri)),
          Text('Adjust text-to-speech playback',
              style: TextStyle(fontSize: 11, color: _C.textSec)),
        ]),
        const Spacer(),
        GestureDetector(
          onTap: widget.onClose,
          child: Container(width: 32, height: 32,
              decoration: BoxDecoration(
                  color: _C.surface, borderRadius: BorderRadius.circular(10)),
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
        min: 0.1, max: 1.0, divisions: 9,
        activeColor: _C.violet,
        onChanged: (v) { setState(() => _speed = v); widget.onSpeedChanged(v); },
      ),
      const SizedBox(height: 20),

      // Pitch slider
      _SliderRow(
        icon: Icons.music_note_rounded,
        iconColor: _C.sky,
        label: 'Voice Pitch',
        valueLabel: _pitchLabel(_pitch),
        value: _pitch,
        min: 0.5, max: 1.5, divisions: 10,
        activeColor: _C.sky,
        onChanged: (v) { setState(() => _pitch = v); widget.onPitchChanged(v); },
      ),
      const SizedBox(height: 24),

      // Info note
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: _C.teal.withOpacity(0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _C.teal.withOpacity(0.2))),
        child: const Row(children: [
          Icon(Icons.info_outline_rounded, color: _C.teal, size: 14),
          SizedBox(width: 8),
          Expanded(child: Text(
            'Tap the speaker icon on any AI response to hear it read aloud. Tap again to stop.',
            style: TextStyle(fontSize: 11, color: _C.textSec, height: 1.4),
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
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 30, height: 30,
              decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: iconColor, size: 15)),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w700, color: _C.textPri)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: activeColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
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
            value: value, min: min, max: max,
            divisions: divisions, onChanged: onChanged,
          ),
        ),
      ]);
}

// ═══════════════════════════════════════════════════════════════════════════════
// ── LANGUAGE PICKER SHEET ─────────────────────────────────────────────────────
// ═══════════════════════════════════════════════════════════════════════════════
class _LanguagePickerSheet extends StatelessWidget {
  final _Lang selected;
  final List<_Lang> languages;
  final ValueChanged<_Lang> onSelect;
  const _LanguagePickerSheet({
    required this.selected,
    required this.languages,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
        color: _C.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      // Handle
      Container(
          margin: const EdgeInsets.only(top: 12, bottom: 4),
          width: 36, height: 4,
          decoration: BoxDecoration(
              color: _C.border, borderRadius: BorderRadius.circular(2))),

      // Header
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        child: Row(children: [
          Container(width: 36, height: 36,
              decoration: BoxDecoration(
                  color: _C.sky.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.language_rounded, color: _C.sky, size: 18)),
          const SizedBox(width: 12),
          const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Response Language', style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700, color: _C.textPri)),
            Text('AI will respond and speak in selected language',
                style: TextStyle(fontSize: 11, color: _C.textSec)),
          ]),
        ]),
      ),
      const Divider(height: 1),

      // Language list
      ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.5),
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
                    border: Border.all(
                        color: isSelected
                            ? _C.sky.withOpacity(0.35)
                            : Colors.transparent)),
                child: Row(children: [
                  Text(lang.flag, style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 14),
                  Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(lang.name, style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700,
                            color: isSelected ? _C.sky : _C.textPri)),
                        Text(lang.geminiName,
                            style: const TextStyle(
                                fontSize: 10, color: _C.textTer)),
                      ])),
                  // TTS locale badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: _C.teal.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: _C.teal.withOpacity(0.2))),
                    child: Text(lang.ttsLocale, style: const TextStyle(
                        fontSize: 8, color: _C.teal, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 8),
                  if (isSelected)
                    Container(
                        width: 22, height: 22,
                        decoration: const BoxDecoration(
                            color: _C.sky, shape: BoxShape.circle),
                        child: const Icon(Icons.check_rounded,
                            color: Colors.white, size: 13)),
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

// ═══════════════════════════════════════════════════════════════════════════════
// ── MEDICINE PICKER SHEET ─────────────────────────────────────────────────────
// ═══════════════════════════════════════════════════════════════════════════════
class _MedicinePickerSheet extends StatefulWidget {
  final List<Map<String, dynamic>> medicines;
  final ValueChanged<Map<String, dynamic>> onSelect;
  const _MedicinePickerSheet(
      {required this.medicines, required this.onSelect});

  @override
  State<_MedicinePickerSheet> createState() => _MedicinePickerSheetState();
}

class _MedicinePickerSheetState extends State<_MedicinePickerSheet> {
  String _q      = '';
  String _filter = 'All';

  List<Map<String, dynamic>> get _filtered {
    return widget.medicines.where((m) {
      final name  = (m['medicineName'] ?? '').toString().toLowerCase();
      final match = name.contains(_q.toLowerCase());
      if (_filter == 'Expired') return match && (m['daysUntilExpiry'] ?? 0) < 0;
      if (_filter == 'Expiring') {
        final d = m['daysUntilExpiry'] ?? 365;
        return match && d >= 0 && d <= 30;
      }
      return match;
    }).toList();
  }

  Color _statusColor(Map<String, dynamic> m) {
    final d = m['daysUntilExpiry'] ?? 365;
    if (d < 0) return _C.danger;
    if (d <= 30 || (m['potency'] ?? 100) < 80) return _C.warn;
    return _C.safe;
  }

  @override
  Widget build(BuildContext context) => Container(
    height: MediaQuery.of(context).size.height * 0.80,
    decoration: const BoxDecoration(
        color: _C.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    child: Column(children: [
      // Handle
      Center(child: Container(
        margin: const EdgeInsets.only(top: 10),
        width: 36, height: 4,
        decoration: BoxDecoration(
            color: _C.border, borderRadius: BorderRadius.circular(2)),
      )),

      // Header
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        child: Row(children: [
          Container(width: 42, height: 42,
              decoration: BoxDecoration(
                  color: _C.teal.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _C.teal.withOpacity(0.25))),
              child: const Icon(Icons.medication_rounded,
                  color: _C.teal, size: 20)),
          const SizedBox(width: 12),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Select Medicine', style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w700,
                color: _C.textPri, letterSpacing: -0.4)),
            Text('${widget.medicines.length} in inventory',
                style: const TextStyle(fontSize: 12, color: _C.textSec)),
          ])),
        ]),
      ),
      const SizedBox(height: 14),

      // Search
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          decoration: BoxDecoration(
              color: _C.surface, borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _C.border)),
          child: TextField(
            onChanged: (v) => setState(() => _q = v),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500,
                color: _C.textPri),
            decoration: const InputDecoration(
              hintText: 'Search medicines...',
              hintStyle: TextStyle(color: _C.textTer, fontSize: 13),
              prefixIcon:
              Icon(Icons.search_rounded, color: _C.textTer, size: 18),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ),
      const SizedBox(height: 12),

      // Filter chips
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: ['All', 'Expired', 'Expiring'].map((f) {
            final on    = _filter == f;
            final color = f == 'All'
                ? _C.teal
                : f == 'Expired'
                ? _C.danger
                : _C.warn;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() => _filter = f),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: on ? color : _C.surface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: on ? color : _C.border),
                    boxShadow: on
                        ? [BoxShadow(color: color.withOpacity(0.2),
                        blurRadius: 8, offset: const Offset(0, 3))]
                        : [],
                  ),
                  child: Text(f, style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700,
                      color: on ? Colors.white : _C.textSec)),
                ),
              ),
            );
          }).toList(),
        ),
      ),
      const SizedBox(height: 10),

      // List
      Expanded(
        child: _filtered.isEmpty
            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 56, height: 56,
              decoration: BoxDecoration(
                  color: _C.surface, borderRadius: BorderRadius.circular(22)),
              child: const Icon(Icons.search_off_rounded,
                  color: _C.textTer, size: 28)),
          const SizedBox(height: 12),
          const Text('No medicines found', style: TextStyle(
              color: _C.textSec, fontSize: 14, fontWeight: FontWeight.w600)),
        ]))
            : ListView.builder(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          itemCount: _filtered.length,
          itemBuilder: (_, i) => _MedItem(
            medicine: _filtered[i],
            statusColor: _statusColor(_filtered[i]),
            onTap: () => widget.onSelect(_filtered[i]),
          ),
        ),
      ),
    ]),
  );
}

// ─── Medicine List Item ───────────────────────────────────────────────────────
class _MedItem extends StatelessWidget {
  final Map<String, dynamic> medicine;
  final Color statusColor;
  final VoidCallback onTap;
  const _MedItem(
      {required this.medicine, required this.statusColor, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final days      = medicine['daysUntilExpiry'];
    final isExpired = days != null && days < 0;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: _C.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: statusColor.withOpacity(0.18)),
            boxShadow: [BoxShadow(color: MedicColors.forest.withOpacity(0.025),
                blurRadius: 10, offset: const Offset(0, 3))]),
        child: Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12)),
            child: Icon(
              isExpired ? Icons.warning_rounded : Icons.medication_rounded,
              color: statusColor, size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(medicine['medicineName'] ?? 'Unknown',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700,
                    color: _C.textPri),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 5),
            Row(children: [
              if ((medicine['category'] ?? '').toString().isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(7)),
                  child: Text(medicine['category'] ?? '',
                      style: TextStyle(
                          fontSize: 10, fontWeight: FontWeight.w700,
                          color: statusColor)),
                ),
                const SizedBox(width: 8),
              ],
              Text(
                isExpired
                    ? 'Expired'
                    : days != null ? '${days}d left' : '',
                style: const TextStyle(
                    fontSize: 11, color: _C.textSec,
                    fontWeight: FontWeight.w500),
              ),
            ]),
          ])),
          const Icon(Icons.chevron_right_rounded, color: _C.textTer, size: 18),
        ]),
      ),
    );
  }
}

// ─── Avatars ──────────────────────────────────────────────────────────────────
class _AiAvatar extends StatelessWidget {
  final bool isError;
  const _AiAvatar({this.isError = false});
  @override
  Widget build(BuildContext context) => Container(
    width: 34, height: 34,
    decoration: BoxDecoration(
        color: (isError ? _C.rose : _C.teal).withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: (isError ? _C.rose : _C.teal).withOpacity(0.25))),
    child: Icon(
      isError ? Icons.error_outline_rounded : Icons.smart_toy_rounded,
      color: isError ? _C.rose : _C.teal, size: 17,
    ),
  );
}

class _UserAvatar extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: 34, height: 34,
    decoration: BoxDecoration(
        color: _C.navy.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _C.border)),
    child: const Icon(Icons.person_rounded, color: _C.textSec, size: 17),
  );
}

// ─── Typing Dot ───────────────────────────────────────────────────────────────
class _Dot extends StatefulWidget {
  final int index;
  const _Dot(this.index);
  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        duration: const Duration(milliseconds: 600), vsync: this)
      ..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
    Future.delayed(Duration(milliseconds: widget.index * 150), () {
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
          color: _C.teal.withOpacity(0.3 + _anim.value * 0.6),
          shape: BoxShape.circle),
    ),
  );
}

// ─── Mesh Painter ─────────────────────────────────────────────────────────────
class _MeshPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(Offset(size.width * 0.88, size.height * 0.2), 80,
        Paint()..color = _C.teal.withOpacity(0.08));
    canvas.drawCircle(Offset(size.width * 0.05, size.height * 0.85), 60,
        Paint()..color = _C.sky.withOpacity(0.06));
  }
  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}