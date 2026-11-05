import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../../services/medicine_photo_service.dart';
import 'medicine_photo_widgets.dart';
import 'medicine_stock_card.dart';
import 'dose_history_screen.dart';
import 'package:medictrack/design/medic_design.dart';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../../services/auth_service.dart';
import '../../services/gemini_service.dart';
import 'package:flutter_tts/flutter_tts.dart';

// ─── Design Tokens ────────────────────────────────────────────────────────────
class _C {
  static const navy     = MedicColors.c142F2B;
  static const teal     = MedicColors.c28715D;
  static const amber    = MedicColors.cB77A27;
  static const rose     = MedicColors.cC05256;
  static const sky      = MedicColors.c477C91;
  static const violet   = MedicColors.c78659B;
  static const surface  = MedicColors.cF6F5F0;
  static const card     = MedicColors.cFFFFFF;
  static const border   = MedicColors.cE2E5DC;
  static const textPri  = MedicColors.c142F2B;
  static const textSec  = MedicColors.c63756D;
  static const textTer  = MedicColors.c83938B;
  static const safe     = MedicColors.c28715D;
  static const warn     = MedicColors.cB77A27;
  static const danger   = MedicColors.cC05256;
}

// ═══════════════════════════════════════════════════════════════════════════════
// MEDICINE DETAILS SCREEN
// ═══════════════════════════════════════════════════════════════════════════════
class MedicineDetailsScreen extends StatefulWidget {
  final String docId;
  final Map<String, dynamic> data;
  const MedicineDetailsScreen({Key? key, required this.docId, required this.data})
      : super(key: key);

  @override
  State<MedicineDetailsScreen> createState() => _MedicineDetailsScreenState();
}

class _MedicineDetailsScreenState extends State<MedicineDetailsScreen>
    with TickerProviderStateMixin {
  final _db         = FirebaseFirestore.instance;
  final _authSvc    = AuthService();
  final _formKey    = GlobalKey<FormState>();

  bool _photoBusy = false;
  double _photoProgress = 0;
  bool _editMode  = false;
  bool _saving    = false;
  bool _analyzing = false;

  late TextEditingController _nameCtrl, _genericCtrl, _dosageCtrl,
      _expiryCtrl, _mfgCtrl, _catCtrl, _usageCtrl, _instrCtrl,
      _warnCtrl, _storageCtrl, _notesCtrl;

  late AnimationController _fadeCtrl, _pulseCtrl, _fabCtrl;
  late Animation<double> _fadeAnim, _pulseAnim, _fabAnim;

  // Reads the one shared key/endpoint from GeminiService instead of its own
  // copy — see the doc comment on GeminiService for why this was centralized.
  static const _apiKey = GeminiService.apiKey;
  static const _apiUrl = GeminiService.baseUrl;

  int _potency = 0;
  String _status = 'Unknown';
  int? _daysLeft;

  // ── Live schedule data (read from Firestore & editable) ──────────────────
  // ── Expiry source: 'label' | 'ai' | 'user' ────────────────────────────────
  String _expirySource = 'label';

  // ── Assigned-to (who this medicine is for) ────────────────────────────────
  List<Map<String, dynamic>> _members = [];
  String _assignedTo         = 'me';
  String _assignedToName     = 'Me';
  String _assignedToRelation = 'Self';

  List<String> _scheduleTimes  = ['08:00'];
  int          _timesPerDay    = 1;
  String       _frequencyLabel = '1x / day';
  String       _mealTiming     = 'anytime';
  bool         _trackingEnabled = false;

  @override
  void initState() {
    super.initState();
    final m = widget.data;

    _nameCtrl    = TextEditingController(text: (m['medicineName']          ?? '').toString());
    _genericCtrl = TextEditingController(text: (m['genericName']           ?? '').toString());
    _dosageCtrl  = TextEditingController(text: (m['dosage']                ?? '').toString());
    _expiryCtrl  = TextEditingController(text: (m['expiryDate']            ?? '').toString());
    _mfgCtrl     = TextEditingController(text: (m['manufacturer']          ?? '').toString());
    _catCtrl     = TextEditingController(text: (m['category']              ?? '').toString());
    _usageCtrl   = TextEditingController(text: (m['usage']                 ?? '').toString());
    _instrCtrl   = TextEditingController(text: (m['dosageInstructions']    ?? '').toString());
    _warnCtrl    = TextEditingController(text: (m['warnings']              ?? '').toString());
    _storageCtrl = TextEditingController(
        text: (m['storageInstructions'] ?? m['storage'] ?? '').toString());
    _notesCtrl   = TextEditingController(text: (m['notes']                 ?? '').toString());

    // Load schedule from medicine data
    _loadScheduleFromData(m);

    // Expiry source + assignment
    _expirySource       = (m['expirySource'] ?? 'label').toString();
    _assignedTo         = (m['assignedTo'] ?? 'me').toString();
    _assignedToName     = (m['assignedToName'] ?? 'Me').toString();
    _assignedToRelation = (m['assignedToRelation'] ?? 'Self').toString();
    _loadMembers();

    _fadeCtrl  = AnimationController(duration: const Duration(milliseconds: 700), vsync: this);
    _pulseCtrl = AnimationController(duration: const Duration(milliseconds: 1800), vsync: this);
    _fabCtrl   = AnimationController(duration: const Duration(milliseconds: 600), vsync: this);

    _fadeAnim  = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.05).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _fabAnim   = CurvedAnimation(parent: _fabCtrl, curve: Curves.elasticOut);

    _fadeCtrl.forward();
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _fabCtrl.forward();
    });
    _calcPotency();
  }

  void _loadScheduleFromData(Map<String, dynamic> m) {
    final raw = m['scheduleTimes'];
    _scheduleTimes   = raw != null ? List<String>.from(raw) : ['08:00'];
    _timesPerDay     = (m['timesPerDay']    as num?)?.toInt() ?? _scheduleTimes.length;
    _frequencyLabel  = (m['frequencyLabel'] ?? '${_timesPerDay}x / day').toString();
    _mealTiming      = (m['mealTiming']     ?? 'anytime').toString();
    _trackingEnabled = m['trackingEnabled'] == true;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _fadeCtrl.value = 1; _fabCtrl.value = 1; _pulseCtrl.value = 0;
    }
  }

  @override
  void dispose() {
    for (final c in [_nameCtrl, _genericCtrl, _dosageCtrl, _expiryCtrl,
      _mfgCtrl, _catCtrl, _usageCtrl, _instrCtrl, _warnCtrl,
      _storageCtrl, _notesCtrl]) c.dispose();
    _fadeCtrl.dispose(); _pulseCtrl.dispose(); _fabCtrl.dispose();
    super.dispose();
  }

  // ── Potency ───────────────────────────────────────────────────────────────
  void _calcPotency() {
    final s = _expiryCtrl.text.trim();
    if (s.isEmpty || s == 'Not visible') {
      setState(() { _potency = 0; _status = 'Unknown'; _daysLeft = null; });
      return;
    }
    try {
      DateTime? exp;
      for (final fmt in [
        RegExp(r'(\d{1,2})/(\d{1,2})/(\d{4})'),
        RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})'),
        RegExp(r'(\d{1,2})-(\d{1,2})-(\d{4})'),
      ]) {
        final match = fmt.firstMatch(s);
        if (match != null) {
          exp = s.startsWith(RegExp(r'\d{4}'))
              ? DateTime(int.parse(match.group(1)!), int.parse(match.group(2)!), int.parse(match.group(3)!))
              : DateTime(int.parse(match.group(3)!), int.parse(match.group(2)!), int.parse(match.group(1)!));
          break;
        }
      }
      if (exp == null) { setState(() { _potency = 0; _status = 'Unknown'; _daysLeft = null; }); return; }
      final diff = exp.difference(DateTime.now()).inDays;
      setState(() {
        _daysLeft = diff;
        if (diff < 0)         { _potency = 0;  _status = 'Expired'; }
        else if (diff <= 30)  { _potency = (20 + diff * 2).clamp(0, 50); _status = 'Expiring Soon'; }
        else if (diff <= 90)  { _potency = (50 + ((diff - 30) * 0.5).round()).clamp(0, 80); _status = 'Low Potency'; }
        else if (diff <= 180) { _potency = (80 + ((diff - 90) * 0.1).round()).clamp(0, 90); _status = 'Good'; }
        else                  { _potency = 95; _status = 'Safe to Use'; }
      });
    } catch (_) {
      setState(() { _potency = 0; _status = 'Unknown'; _daysLeft = null; });
    }
  }

  Color get _sColor {
    if (_daysLeft != null && _daysLeft! < 0) return _C.danger;
    if (_status.toLowerCase().contains('expired')) return _C.danger;
    if (_status.toLowerCase().contains('low') || _status.toLowerCase().contains('expiring')) return _C.warn;
    return _C.safe;
  }

  IconData get _sIcon {
    if (_daysLeft != null && _daysLeft! < 0) return Icons.dangerous_rounded;
    if (_potency >= 80) return Icons.check_circle_rounded;
    if (_potency >= 50) return Icons.warning_rounded;
    return Icons.dangerous_rounded;
  }

  // ── Save medicine info ─────────────────────────────────────────────────────
  // ── Family / care members ─────────────────────────────────────────────────
  Future<void> _loadMembers() async {
    final user = _authSvc.currentUser;
    if (user == null) return;
    try {
      final snap = await _db.collection('users').doc(user.uid)
          .collection('familyMembers').orderBy('createdAt').get();
      if (mounted) {
        setState(() => _members =
            snap.docs.map((d) => {'id': d.id, ...d.data()}).toList());
      }
    } catch (_) {}
  }

  Future<void> _addMemberDialog() async {
    final nameCtrl = TextEditingController();
    final relCtrl  = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Add Care Member', style: TextStyle(
            fontSize: 17, fontWeight: FontWeight.w700, color: _C.textPri)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: nameCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
                labelText: 'Name', hintText: 'e.g. Amma, John'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: relCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
                labelText: 'Relationship', hintText: 'e.g. Mother, Son, Spouse'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: _C.textSec))),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Add', style: TextStyle(
                  color: _C.teal, fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (ok != true || nameCtrl.text.trim().isEmpty) return;
    final user = _authSvc.currentUser;
    if (user == null) return;
    try {
      final ref = await _db.collection('users').doc(user.uid)
          .collection('familyMembers').add({
        'name':      nameCtrl.text.trim(),
        'relation':  relCtrl.text.trim().isEmpty ? 'Family' : relCtrl.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      await _loadMembers();
      _setAssignee(ref.id, nameCtrl.text.trim(),
          relCtrl.text.trim().isEmpty ? 'Family' : relCtrl.text.trim());
    } catch (e) {
      _showSnack('Failed to add member: $e', color: _C.rose);
    }
  }

  /// Update assignee locally AND persist it immediately.
  Future<void> _setAssignee(String id, String name, String relation) async {
    HapticFeedback.selectionClick();
    setState(() {
      _assignedTo         = id;
      _assignedToName     = name;
      _assignedToRelation = relation;
    });
    try {
      await _db.collection('medicines').doc(widget.docId).update({
        'assignedTo':         id,
        'assignedToName':     name,
        'assignedToRelation': relation,
        'updatedAt':          FieldValue.serverTimestamp(),
      });
      _showSnack('Medicine assigned to $name', color: _C.teal);
    } catch (e) {
      _showSnack('Failed to update: $e', color: _C.rose);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    HapticFeedback.mediumImpact();
    setState(() => _saving = true);
    try {
      _calcPotency();
      await _db.collection('medicines').doc(widget.docId).update({
        'medicineName':        _nameCtrl.text.trim(),
        'genericName':         _genericCtrl.text.trim(),
        'dosage':              _dosageCtrl.text.trim(),
        'expiryDate':          _expiryCtrl.text.trim(),
        'manufacturer':        _mfgCtrl.text.trim(),
        'category':            _catCtrl.text.trim(),
        'usage':               _usageCtrl.text.trim(),
        'dosageInstructions':  _instrCtrl.text.trim(),
        'warnings':            _warnCtrl.text.trim(),
        'storageInstructions': _storageCtrl.text.trim(),
        'notes':               _notesCtrl.text.trim(),
        'potency':             _potency,
        'status':              _status,
        'daysUntilExpiry':     _daysLeft,
        'expirySource':        _expirySource,   // 'label' | 'ai' | 'user'
        'assignedTo':          _assignedTo,
        'assignedToName':      _assignedToName,
        'assignedToRelation':  _assignedToRelation,
        'updatedAt':           FieldValue.serverTimestamp(),
      });
      if (mounted) {
        _showSnack('Medicine updated successfully', color: _C.teal);
        setState(() => _editMode = false);
      }
    } catch (e) {
      if (mounted) _showSnack('Update failed: $e', color: _C.rose);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Save schedule only ─────────────────────────────────────────────────────
  Future<void> _saveSchedule({
    required List<String> times,
    required int timesPerDay,
    required String mealTiming,
    required bool trackingEnabled,
  }) async {
    final label = '${timesPerDay}x / day';
    try {
      await _db.collection('medicines').doc(widget.docId).update({
        'scheduleTimes':   times,
        'timesPerDay':     timesPerDay,
        'frequencyLabel':  label,
        'mealTiming':      mealTiming,
        'trackingEnabled': trackingEnabled,
        'scheduleUpdatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        setState(() {
          _scheduleTimes   = times;
          _timesPerDay     = timesPerDay;
          _frequencyLabel  = label;
          _mealTiming      = mealTiming;
          _trackingEnabled = trackingEnabled;
        });
        _showSnack('Schedule updated! $label', color: _C.teal);
      }
    } catch (e) {
      if (mounted) _showSnack('Failed to save schedule: $e', color: _C.rose);
    }
  }

  // ── Delete ─────────────────────────────────────────────────────────────────
  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context, barrierColor: Colors.black54,
      builder: (_) => _DeleteDialog(name: _nameCtrl.text),
    );
    if (ok != true) return;
    try {
      final user = _authSvc.currentUser;
      if (user != null) {
        final rem = await _db.collection('reminders')
            .where('userId', isEqualTo: user.uid)
            .where('medicineId', isEqualTo: widget.docId).get();
        for (final d in rem.docs) await d.reference.delete();
      }
      final medicine = await _db.collection('medicines').doc(widget.docId).get();
      await _db.collection('medicines').doc(widget.docId).delete();
      await MedicinePhotoService.remove(MedicinePhotoService.paths(medicine.data() ?? {}));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) _showSnack('Delete failed: $e', color: _C.rose);
    }
  }

  // ── AI Analysis ────────────────────────────────────────────────────────────
  // ── Step 1: pick language, THEN generate ─────────────────────────────────
  Future<void> _analyze() async {
    HapticFeedback.mediumImpact();

    // Show language picker first — user must confirm before we call Gemini
    final chosenLang = await _pickAnalysisLanguage();
    if (chosenLang == null) return; // user cancelled

    setState(() => _analyzing = true);
    try {
      final langInstruction = chosenLang.code == 'en'
          ? ''
          : '\n\nIMPORTANT: Write the ENTIRE response in ${chosenLang.geminiName}. Every word must be in ${chosenLang.geminiName}.';

      final prompt = '''
You are a pharmaceutical expert AI. Analyze the following medicine and provide comprehensive A-Z information.

Medicine: ${_nameCtrl.text}
Generic: ${_genericCtrl.text.isNotEmpty ? _genericCtrl.text : 'N/A'}
Category: ${_catCtrl.text.isNotEmpty ? _catCtrl.text : 'N/A'}
Dosage: ${_dosageCtrl.text.isNotEmpty ? _dosageCtrl.text : 'N/A'}
Status: $_status | Potency: $_potency%

Provide these sections with emojis and concise bullet points:
1. OVERVIEW  2. DRUG CLASS  3. HOW IT WORKS  4. COMMON USES  5. DOSAGE GUIDELINES
6. WHEN TO TAKE  7. FOOD INTERACTIONS  8. SIDE EFFECTS  9. WARNINGS  10. DRUG INTERACTIONS
11. SPECIAL POPULATIONS  12. STORAGE TIPS  13. MISSED DOSE  14. OVERDOSE SIGNS
15. ALTERNATIVES  16. QUICK TIPS

Keep language simple and patient-friendly. Recommend consulting a doctor where appropriate.

IMPORTANT FORMATTING RULES:
- Do NOT use markdown syntax: no #, ##, ###, **, __, *, backticks, or ---
- Use plain numbered sections like: "1. OVERVIEW" (all caps, translated if needed)
- Use a simple dash "-" for list items — do NOT use * for bullets
- Use emojis for section headers (e.g. "💊 1. OVERVIEW")
- Write in clean plain text only$langInstruction
''';

      final res = await http.post(Uri.parse('$_apiUrl?key=$_apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [{'parts': [{'text': prompt}]}],
          'generationConfig': {'temperature': 0.7, 'maxOutputTokens': 4096},
        }),
      );
      if (res.statusCode == 200) {
        final d    = jsonDecode(res.body);
        var text   = d['candidates']?[0]?['content']?['parts']?[0]?['text'] ?? '';
        text = text.replaceAll('**', '').replaceAll('`', '').trim();
        if (mounted) _showAnalysisSheet(text, chosenLang);
      } else {
        _showSnack('Analysis failed. Try again.', color: _C.rose);
      }
    } catch (e) {
      _showSnack('Error: $e', color: _C.rose);
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  // ── Language picker dialog shown BEFORE generating ─────────────────────────
  Future<_AnalysisLang?> _pickAnalysisLanguage() async {
    return showDialog<_AnalysisLang>(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => _LangPickerDialog(),
    );
  }

  void _showAnalysisSheet(String text, _AnalysisLang lang) => showModalBottomSheet(
    context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
    builder: (_) => _AnalysisSheet(
        name: _nameCtrl.text, text: text,
        statusColor: _sColor, potency: _potency, status: _status,
        initialLang: lang),
  );

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 365)),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
            colorScheme: ColorScheme.light(primary: _sColor, onPrimary: Colors.white)),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _expiryCtrl.text = '${picked.day}/${picked.month}/${picked.year}';
        _expirySource    = 'user';
        _calcPotency();
      });
    }
  }

  void _showSnack(String msg, {required Color color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(color == _C.rose ? Icons.error_outline_rounded : Icons.check_circle_rounded,
            color: Colors.white, size: 16),
        const SizedBox(width: 10),
        Expanded(child: Text(msg, style: const TextStyle(
            fontWeight: FontWeight.w600, fontSize: 13))),
      ]),
      backgroundColor: _C.navy,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.all(16),
    ));
  }

  // ── Open schedule editor ───────────────────────────────────────────────────
  Future<void> _showScheduleEditor() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ScheduleEditorSheet(
        medicineName:    _nameCtrl.text,
        scheduleTimes:   _scheduleTimes,
        timesPerDay:     _timesPerDay,
        mealTiming:      _mealTiming,
        trackingEnabled: _trackingEnabled,
        medicineData:    widget.data,
        apiKey:          _apiKey,
        apiUrl:          _apiUrl,
      ),
    );
    if (result != null) {
      await _saveSchedule(
        times:          List<String>.from(result['times']),
        timesPerDay:    (result['timesPerDay'] as num).toInt(),
        mealTiming:     result['mealTiming'].toString(),
        trackingEnabled: result['trackingEnabled'] == true,
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.light,
    child: Scaffold(
      backgroundColor: _C.surface,
      floatingActionButton: ScaleTransition(
        scale: _fabAnim,
        child: GestureDetector(
          onTap: _analyzing ? null : _analyze,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: _analyzing ? _C.violet.withOpacity(0.7) : _C.violet,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [BoxShadow(color: _C.violet.withOpacity(0.35),
                  blurRadius: 18, offset: const Offset(0, 7))],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              _analyzing
                  ? const SizedBox(width: 19, height: 19,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 19),
              const SizedBox(width: 8),
              Text(_analyzing ? 'Analysing…' : 'AI Analysis',
                  style: const TextStyle(color: Colors.white,
                      fontWeight: FontWeight.w700, fontSize: 14)),
            ]),
          ),
        ),
      ),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Column(children: [
          _buildHeader(),
          Expanded(child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 110),
            child: Form(key: _formKey, child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [

              _detailReveal(_buildPhotoCard(), 0),
              const SizedBox(height: 18),
              _detailReveal(MedicineStockCard(medicineId: widget.docId), 1),
              const SizedBox(height: 28),
              // ── Dosing Schedule Section ──────────────────────────────────
              _SectionLabel(
                label: 'Dosing Schedule', icon: Icons.alarm_rounded,
                accent: _C.teal,
                action: GestureDetector(
                  onTap: _showScheduleEditor,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                        color: _C.teal.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: _C.teal.withOpacity(0.3))),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.edit_rounded, color: _C.teal, size: 13),
                      SizedBox(width: 4),
                      Text('Edit Schedule', style: TextStyle(
                          color: _C.teal, fontSize: 12, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _detailReveal(_buildScheduleCard(), 2),
              ListTile(leading: const Icon(Icons.fact_check_outlined), title: const Text('Record doses & view history'),
                trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => DoseHistoryScreen(medicineId: widget.docId)))),
              const SizedBox(height: 28),

              // ── Who is this medicine for ─────────────────────────────────
              _SectionLabel(label: 'This Medicine Is For',
                  icon: Icons.family_restroom_rounded, accent: _C.rose),
              const SizedBox(height: 12),
              _detailReveal(_buildAssignedCard(), 3),
              const SizedBox(height: 28),

              // ── Medicine Information ─────────────────────────────────────
              _SectionLabel(label: 'Medicine Information',
                  icon: Icons.medication_rounded, accent: _C.teal),
              const SizedBox(height: 14),

              _buildFieldGroup([
                _FieldCfg(_nameCtrl,    'Medicine Name',     Icons.medication_rounded,       _C.teal,   required: true),
                _FieldCfg(_genericCtrl, 'Generic Name',      Icons.science_rounded,          _C.sky),
                _FieldCfg(_dosageCtrl,  'Dosage',            Icons.medical_services_rounded, _C.violet, required: true),
              ]),
              const SizedBox(height: 12),

              _ExpiryField(ctrl: _expiryCtrl, editMode: _editMode,
                  onTap: _pickDate, statusColor: _sColor,
                  source: _expirySource),
              const SizedBox(height: 12),

              _buildFieldGroup([
                _FieldCfg(_mfgCtrl, 'Manufacturer', Icons.business_rounded,  _C.teal),
                _FieldCfg(_catCtrl, 'Category',     Icons.category_rounded,  _C.sky, isLast: true),
              ]),
              const SizedBox(height: 12),

              _buildFieldGroup([
                _FieldCfg(_usageCtrl,  'Usage / Purpose',        Icons.info_outline_rounded,  _C.amber, maxLines: 3, required: true),
                _FieldCfg(_instrCtrl,  'Dosage Instructions',    Icons.schedule_rounded,      _C.sky,   maxLines: 2),
                _FieldCfg(_warnCtrl,   'Warnings / Precautions', Icons.warning_amber_rounded, _C.rose,  maxLines: 2),
                _FieldCfg(_storageCtrl,'Storage Instructions',   Icons.air_rounded,           _C.teal,  maxLines: 2),
                _FieldCfg(_notesCtrl,  'Personal Notes',         Icons.notes_rounded,         _C.violet, maxLines: 3, isLast: true),
              ]),
              const SizedBox(height: 24),

              if (_editMode) ...[
                _ActionBtn(label: 'Save Changes', icon: Icons.check_rounded,
                    color: _C.teal, loading: _saving, onTap: _save),
                const SizedBox(height: 10),
                _OutlineBtn(label: 'Cancel', icon: Icons.close_rounded,
                    color: _C.textSec, onTap: () => setState(() => _editMode = false)),
              ],
            ])),
          )),
        ]),
      ),
    ),
  );

  Widget _detailReveal(Widget child, int order) => AnimatedBuilder(animation: _fadeCtrl, child: child,
    builder: (context, child) {
      final delay = order * .09;
      final phase = ((_fadeCtrl.value - delay) / (1 - delay)).clamp(0.0, 1.0).toDouble();
      final value = Curves.easeOutCubic.transform(phase);
      return Opacity(opacity: value, child: Transform.translate(offset: Offset(0, 20 * (1-value)), child: child));
    });

  Widget _buildPhotoCard() => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: _db.collection('medicines').doc(widget.docId).snapshots(), builder: (context, snap) {
      final paths = MedicinePhotoService.paths(snap.data?.data() ?? widget.data);
      return AnimatedSize(duration: MediaQuery.of(context).disableAnimations ? Duration.zero : const Duration(milliseconds: 350),
        child: Container(width: double.infinity, padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: _C.card, borderRadius: BorderRadius.circular(28), border: Border.all(color: _C.border),
            boxShadow: [BoxShadow(color: _C.navy.withOpacity(.025), blurRadius: 22, offset: const Offset(0, 8))]),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const MedicEyebrow('Your medicine, at a glance'), const SizedBox(height: 9),
            const Text('Medicine photos', style: TextStyle(fontFamily: 'serif', fontSize: 25, color: _C.navy)),
            const SizedBox(height: 7), const Text('Keep the label and packaging together. Tap a photo to zoom.',
              style: TextStyle(fontSize: 12, color: _C.textSec, height: 1.5)),
            const SizedBox(height: 18),
            if (snap.hasError) const Text('Photos could not be refreshed. Check your connection.',
              style: TextStyle(color: _C.rose, fontSize: 12)),
            if (paths.isEmpty) Container(width: double.infinity, padding: const EdgeInsets.all(25),
              decoration: BoxDecoration(color: MedicColors.canvas, borderRadius: BorderRadius.circular(20)),
              child: const Column(children: [Icon(Icons.add_photo_alternate_outlined, size: 32, color: _C.teal),
                SizedBox(height: 8), Text('Add your first medicine photo', style: TextStyle(fontSize: 12, color: _C.textSec))]))
            else Wrap(spacing: 12, runSpacing: 12, children: [for (final path in paths) Stack(children: [
              MedicinePhoto(key: ValueKey(path), path: path, size: 112, expandable: true),
              Positioned(top: 3, right: 3, child: IconButton.filledTonal(tooltip: 'Remove photo',
                onPressed: _photoBusy ? null : () => _removePhoto(path), icon: const Icon(Icons.close_rounded, size: 16))),
            ])]),
            const SizedBox(height: 12),
            if (_photoBusy) ...[LinearProgressIndicator(value: _photoProgress, color: _C.teal, backgroundColor: _C.border),
              const SizedBox(height: 7), Text('Saving photo… ${(_photoProgress * 100).round()}%', style: const TextStyle(fontSize: 11, color: _C.textSec))],
            Wrap(spacing: 8, children: [
              TextButton.icon(onPressed: _photoBusy || paths.length >= MedicinePhotoService.maxPhotos || snap.hasError ? null : () => _addPhoto(ImageSource.camera),
                icon: const Icon(Icons.camera_alt_outlined, size: 17), label: const Text('Camera')),
              TextButton.icon(onPressed: _photoBusy || paths.length >= MedicinePhotoService.maxPhotos || snap.hasError ? null : () => _addPhoto(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined, size: 17), label: const Text('Gallery')),
            ]),
          ])));
    });

  Future<void> _addPhoto(ImageSource source) async {
    if (_photoBusy) return;
    setState(() { _photoBusy = true; _photoProgress = 0; });
    List<String> uploaded = [];
    bool committed = false;
    try {
      final user = _authSvc.currentUser;
      if (user == null) throw StateError('Sign in again to upload photos.');
      final photo = await ImagePicker().pickImage(source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 82);
      if (photo == null) return;
      uploaded = await MedicinePhotoService.upload(user.uid, widget.docId, [File(photo.path)], onProgress: (value) {
        if (mounted) setState(() => _photoProgress = value);
      });
      final ref = _db.collection('medicines').doc(widget.docId);
      await _db.runTransaction((tx) async {
        final data = (await tx.get(ref)).data();
        if (data == null || data['userId'] != user.uid) throw StateError('Medicine no longer available.');
        final existing = MedicinePhotoService.paths(data);
        if (existing.length >= MedicinePhotoService.maxPhotos) throw StateError('You can save up to four photos.');
        tx.update(ref, {'photoPaths': [...existing, ...uploaded], 'photoCount': existing.length + uploaded.length,
          'updatedAt': FieldValue.serverTimestamp()});
      });
      committed = true;
      if (mounted) _showSnack('Medicine photo saved', color: _C.teal);
    } catch (error) {
      // Keep Storage data on uncertain Firestore failures; never break a possibly committed record.
      if (!committed && uploaded.isNotEmpty && error is StateError) await MedicinePhotoService.remove(uploaded);
      if (mounted) _showSnack('Photo could not be saved: $error', color: _C.rose);
    } finally { if (mounted) setState(() => _photoBusy = false); }
  }

  Future<void> _removePhoto(String path) async {
    final ok = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Remove this medicine photo?'), actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove'))]));
    if (ok != true || !mounted) return;
    setState(() => _photoBusy = true);
    try {
      final ref = _db.collection('medicines').doc(widget.docId);
      await _db.runTransaction((tx) async {
        final data = (await tx.get(ref)).data();
        if (data == null) throw StateError('Medicine no longer available.');
        final paths = MedicinePhotoService.paths(data)..remove(path);
        tx.update(ref, {'photoPaths': paths, 'photoCount': paths.length});
      });
      await MedicinePhotoService.remove([path]);
    } catch (_) { if (mounted) _showSnack('Could not remove photo. Try again.', color: _C.rose); }
    finally { if (mounted) setState(() => _photoBusy = false); }
  }

  // ── Assigned-to card ───────────────────────────────────────────────────────
  Widget _buildAssignedCard() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
        color: _C.card, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _C.border),
        boxShadow: [BoxShadow(color: MedicColors.forest.withOpacity(0.025),
            blurRadius: 10, offset: const Offset(0, 3))]),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
              color: _C.rose.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12)),
          child: Icon(
              _assignedTo == 'me'
                  ? Icons.person_rounded : Icons.favorite_rounded,
              color: _C.rose, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_assignedToName, style: const TextStyle(
              fontSize: 15, fontWeight: FontWeight.w700, color: _C.textPri)),
          const SizedBox(height: 2),
          Text(_assignedTo == 'me'
              ? 'This medicine is for you'
              : 'Relationship: $_assignedToRelation',
              style: const TextStyle(fontSize: 11, color: _C.textSec)),
        ])),
      ]),
      const SizedBox(height: 12),
      const Divider(height: 1, color: _C.border),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        _assigneeChip('me', 'Me', 'Self'),
        for (final m in _members)
          _assigneeChip(m['id'] as String,
              (m['name'] ?? '').toString(),
              (m['relation'] ?? 'Family').toString()),
        GestureDetector(
          onTap: _addMemberDialog,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
                color: _C.teal.withOpacity(0.08),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: _C.teal.withOpacity(0.35))),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.add_rounded, color: _C.teal, size: 14),
              SizedBox(width: 4),
              Text('Add member', style: TextStyle(
                  color: _C.teal, fontSize: 12, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      ]),
    ]),
  );

  Widget _assigneeChip(String id, String name, String relation) {
    final selected = _assignedTo == id;
    return GestureDetector(
      onTap: selected ? null : () => _setAssignee(id, name, relation),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
            color: selected ? _C.rose : _C.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: selected ? _C.rose : _C.border)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(id == 'me' ? Icons.person_rounded : Icons.favorite_rounded,
              color: selected ? Colors.white : _C.textSec, size: 13),
          const SizedBox(width: 5),
          Text('$name${id == 'me' ? '' : ' · $relation'}', style: TextStyle(
              color: selected ? Colors.white : _C.textPri,
              fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }

  // ── Schedule card ──────────────────────────────────────────────────────────
  Widget _buildScheduleCard() {
    final hasSchedule = _scheduleTimes.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
          color: _C.card, borderRadius: BorderRadius.circular(24),
          border: Border.all(
              color: _trackingEnabled ? _C.teal.withOpacity(0.25) : _C.border),
          boxShadow: [BoxShadow(color: MedicColors.forest.withOpacity(0.025),
              blurRadius: 12, offset: const Offset(0, 3))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Header row
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Row(children: [
            // Tracking on/off toggle
            Container(width: 38, height: 38,
                decoration: BoxDecoration(
                    color: (_trackingEnabled ? _C.teal : _C.textTer).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(11)),
                child: Icon(Icons.medication_liquid_rounded,
                    color: _trackingEnabled ? _C.teal : _C.textTer, size: 19)),
            const SizedBox(width: 12),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_frequencyLabel, style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, color: _C.textPri)),
              Text(_mealTiming == 'anytime' ? 'No meal restriction'
                  : _mealTiming.capitalize(),
                  style: const TextStyle(fontSize: 11, color: _C.textSec,
                      fontWeight: FontWeight.w500)),
            ])),
            // Tracking toggle
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(_trackingEnabled ? 'Tracking ON' : 'Tracking OFF',
                  style: TextStyle(
                      fontSize: 9, fontWeight: FontWeight.w700,
                      color: _trackingEnabled ? _C.teal : _C.textTer)),
              const SizedBox(height: 2),
              Transform.scale(
                scale: 0.8,
                alignment: Alignment.centerRight,
                child: Switch(
                  value: _trackingEnabled,
                  onChanged: (v) async {
                    HapticFeedback.selectionClick();
                    await _saveSchedule(
                      times: _scheduleTimes,
                      timesPerDay: _timesPerDay,
                      mealTiming: _mealTiming,
                      trackingEnabled: v,
                    );
                  },
                  activeColor: Colors.white,
                  activeTrackColor: _C.teal,
                  inactiveThumbColor: Colors.white,
                  inactiveTrackColor: _C.border,
                  trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
                ),
              ),
            ]),
          ]),
        ),

        // Time slots
        if (hasSchedule) ...[
          Divider(height: 1, color: _C.border),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.alarm_rounded, color: _C.textTer, size: 13),
                const SizedBox(width: 5),
                Text('${_scheduleTimes.length} reminder${_scheduleTimes.length == 1 ? '' : 's'} per day',
                    style: const TextStyle(fontSize: 11, color: _C.textSec,
                        fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: _scheduleTimes.map((t) {
                final color = _trackingEnabled ? _C.rose : _C.textTer;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                      color: color.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: color.withOpacity(0.25))),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.access_time_rounded, color: color, size: 14),
                      const SizedBox(width: 5),
                      Text(_fmt12(t), style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700, color: color)),
                    ]),
                    const SizedBox(height: 3),
                    Text(_slotLabel(t), style: TextStyle(
                        fontSize: 10, color: color.withOpacity(0.75),
                        fontWeight: FontWeight.w600)),
                  ]),
                );
              }).toList()),
            ]),
          ),

          // Meal timing badge + edit shortcut
          Container(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                    color: _C.sky.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _C.sky.withOpacity(0.25))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(_mealIcon(_mealTiming), color: _C.sky, size: 13),
                  const SizedBox(width: 5),
                  Text(_mealTiming == 'anytime' ? 'Anytime'
                      : _mealTiming.capitalize(),
                      style: const TextStyle(fontSize: 11,
                          color: _C.sky, fontWeight: FontWeight.w700)),
                ]),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _showScheduleEditor,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                      color: _C.violet.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _C.violet.withOpacity(0.25))),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.tune_rounded, color: _C.violet, size: 13),
                    SizedBox(width: 5),
                    Text('Adjust Times', style: TextStyle(
                        fontSize: 11, color: _C.violet, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
            ]),
          ),
        ],

        // No schedule state
        if (!hasSchedule) ...[
          Divider(height: 1, color: _C.border),
          Padding(
            padding: const EdgeInsets.all(16),
            child: GestureDetector(
              onTap: _showScheduleEditor,
              child: Container(
                height: 42, width: double.infinity,
                decoration: BoxDecoration(
                    color: _C.teal.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _C.teal.withOpacity(0.25),
                        style: BorderStyle.solid)),
                child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.add_alarm_rounded, color: _C.teal, size: 16),
                  SizedBox(width: 6),
                  Text('Set Dosing Schedule', style: TextStyle(
                      color: _C.teal, fontWeight: FontWeight.w700, fontSize: 13)),
                ]),
              ),
            ),
          ),
        ],
      ]),
    );
  }

  IconData _mealIcon(String m) {
    if (m.contains('before')) return Icons.no_meals_rounded;
    if (m.contains('after'))  return Icons.restaurant_rounded;
    if (m.contains('with'))   return Icons.rice_bowl_rounded;
    return Icons.access_time_rounded;
  }

  String _fmt12(String t24) {
    final p  = t24.split(':');
    final h  = int.tryParse(p[0]) ?? 8;
    final m  = int.tryParse(p[1]) ?? 0;
    final am = h < 12 ? 'AM' : 'PM';
    final h12 = h == 0 ? 12 : h > 12 ? h - 12 : h;
    return '$h12:${m.toString().padLeft(2,'0')} $am';
  }

  String _slotLabel(String t) {
    final h = int.tryParse(t.split(':')[0]) ?? 8;
    if (h < 12) return 'Morning';
    if (h < 17) return 'Afternoon';
    if (h < 20) return 'Evening';
    return 'Night';
  }

  // ── Header ─────────────────────────────────────────────────────────────────
  Widget _buildHeader() => MedicHeaderSurface(
    child: Stack(children: [
      Positioned.fill(child: CustomPaint(painter: _MeshPainter(accent: _sColor))),
      SafeArea(bottom: false, child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        child: Column(children: [
          Row(children: [
            _HBtn(icon: Icons.arrow_back_ios_new_rounded,
                onTap: () => Navigator.pop(context)),
            const SizedBox(width: 12),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_nameCtrl.text.isEmpty ? 'Medicine Details' : _nameCtrl.text,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'serif',color: Colors.white, fontSize: 20,
                      fontWeight: FontWeight.w700, letterSpacing: -0.4)),
              if (_genericCtrl.text.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(_genericCtrl.text, style: TextStyle(
                    color: Colors.white.withOpacity(0.45), fontSize: 12)),
              ],
            ])),
            const SizedBox(width: 10),
            _HBtn(
              icon: _editMode
                  ? (_saving ? Icons.hourglass_empty_rounded : Icons.check_rounded)
                  : Icons.edit_outlined,
              accent: _editMode ? _C.teal : null,
              onTap: _saving ? null
                  : (_editMode ? _save : () => setState(() => _editMode = true)),
            ),
            const SizedBox(width: 8),
            _HBtn(icon: Icons.delete_outline_rounded, accent: _C.rose,
                onTap: _saving || _photoBusy ? null : _delete),
          ]),
          const SizedBox(height: 20),
          ScaleTransition(
            scale: _pulseAnim,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
              decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: _sColor.withOpacity(0.3), width: 1.5)),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                _StatCell(icon: _sIcon, value: '$_potency%',
                    label: 'Potency', accent: _sColor),
                _VertDivider(),
                _StatCell(
                  icon: Icons.timer_outlined,
                  value: _daysLeft == null ? 'N/A'
                      : _daysLeft! < 0 ? '${_daysLeft!.abs()}d' : '${_daysLeft}d',
                  label: (_daysLeft != null && _daysLeft! < 0) ? 'Overdue' : 'Left',
                  accent: _sColor,
                ),
                _VertDivider(),
                _StatCell(icon: Icons.alarm_rounded,
                    value: _frequencyLabel.split(' ').first,
                    label: 'Schedule', accent: _C.teal),
              ]),
            ),
          ),
        ]),
      )),
    ]),
  );

  // ── Field Group ────────────────────────────────────────────────────────────
  // ── Field Group — edit_profile style ──────────────────────────────────────
  // Icon badge on left, small coloured label above, TextField with focus
  // underline only, isDense true, full-width divider between rows.
  Widget _buildFieldGroup(List<_FieldCfg> fields) => Container(
    decoration: BoxDecoration(
        color: _C.card, borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _C.border),
        boxShadow: [BoxShadow(color: MedicColors.forest.withOpacity(0.025),
            blurRadius: 12, offset: const Offset(0, 3))]),
    child: Column(children: fields.map((f) {
      final isLast = f.isLast || fields.last == f;
      return Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Icon badge — fixed top-aligned
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                    color: f.accent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(f.icon, color: f.accent, size: 18),
              ),
            ),
            const SizedBox(width: 12),
            // Label + TextField stacked vertically
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(height: 10),
              // Small coloured label — always visible above field
              Text(
                f.required ? '${f.label} *' : f.label,
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700,
                    color: f.accent, letterSpacing: 0.2),
              ),
              const SizedBox(height: 4),
              TextFormField(
                controller: f.ctrl,
                enabled:    _editMode && !_saving,
                maxLines:   f.maxLines,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600,
                    color: _C.textPri, height: 1.4),
                validator: f.required
                    ? (v) => (v == null || v.trim().isEmpty ||
                    v == 'Not visible') ? 'Required' : null
                    : null,
                decoration: InputDecoration(
                  hintText: _editMode ? _hintFor(f.label) : null,
                  hintStyle: const TextStyle(
                      color: _C.textTer, fontSize: 13),
                  isDense: true,
                  contentPadding: const EdgeInsets.only(bottom: 8),
                  // No border when not focused; accent underline on focus
                  border:        InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(
                          color: f.accent.withOpacity(0.4), width: 1.5)),
                  errorBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(color: _C.rose, width: 1.5)),
                  focusedErrorBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(color: _C.rose, width: 1.5)),
                  errorStyle: const TextStyle(
                      fontSize: 10, color: _C.rose, height: 1.2),
                ),
              ),
              const SizedBox(height: 6),
            ])),
          ]),
        ),
        // Full-width separator (no indent — matches edit_profile style)
        if (!isLast) Container(height: 1, color: _C.border),
      ]);
    }).toList()),
  );

  String _hintFor(String label) {
    switch (label) {
      case 'Medicine Name':          return 'e.g. Amoxicillin';
      case 'Generic Name':           return 'e.g. Amoxicillin Trihydrate';
      case 'Dosage':                 return 'e.g. 500mg Capsule';
      case 'Manufacturer':           return 'e.g. Duopharma';
      case 'Category':               return 'e.g. Antibiotic';
      case 'Usage / Purpose':        return 'What is this medicine for?';
      case 'Dosage Instructions':    return 'e.g. Take 1 tablet 3x daily';
      case 'Warnings / Precautions': return 'e.g. Avoid alcohol';
      case 'Storage Instructions':   return 'e.g. Store below 30°C';
      case 'Personal Notes':         return 'Any personal notes…';
      default:                       return '';
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SCHEDULE EDITOR SHEET — mirrors the picker in scan_medicine_screen
// ═══════════════════════════════════════════════════════════════════════════════
class _ScheduleEditorSheet extends StatefulWidget {
  final String medicineName;
  final List<String> scheduleTimes;
  final int timesPerDay;
  final String mealTiming;
  final bool trackingEnabled;
  final Map<String, dynamic> medicineData;
  final String apiKey, apiUrl;

  const _ScheduleEditorSheet({
    required this.medicineName,
    required this.scheduleTimes,
    required this.timesPerDay,
    required this.mealTiming,
    required this.trackingEnabled,
    required this.medicineData,
    required this.apiKey,
    required this.apiUrl,
  });

  @override
  State<_ScheduleEditorSheet> createState() => _ScheduleEditorSheetState();
}

class _ScheduleEditorSheetState extends State<_ScheduleEditorSheet> {
  late int _timesPerDay;
  late List<TimeOfDay> _times;
  late String _mealTiming;
  late bool _trackingEnabled;
  bool _loadingAI = false;

  static const _presets = {
    1: [TimeOfDay(hour: 8,  minute: 0)],
    2: [TimeOfDay(hour: 8,  minute: 0), TimeOfDay(hour: 20, minute: 0)],
    3: [TimeOfDay(hour: 7,  minute: 30), TimeOfDay(hour: 13, minute: 0), TimeOfDay(hour: 19, minute: 30)],
    4: [TimeOfDay(hour: 7,  minute: 0),  TimeOfDay(hour: 11, minute: 0), TimeOfDay(hour: 15, minute: 0),  TimeOfDay(hour: 20, minute: 0)],
  };

  static const _mealOptions = [
    {'key': 'before meal', 'label': 'Before Meal',  'icon': Icons.no_meals_rounded},
    {'key': 'after meal',  'label': 'After Meal',   'icon': Icons.restaurant_rounded},
    {'key': 'with food',   'label': 'With Food',    'icon': Icons.rice_bowl_rounded},
    {'key': 'anytime',     'label': 'Anytime',      'icon': Icons.access_time_rounded},
  ];

  @override
  void initState() {
    super.initState();
    _timesPerDay    = widget.timesPerDay;
    _mealTiming     = widget.mealTiming;
    _trackingEnabled = widget.trackingEnabled;
    _times = widget.scheduleTimes.map((t) {
      final p = t.split(':');
      return TimeOfDay(hour: int.tryParse(p[0]) ?? 8, minute: int.tryParse(p[1]) ?? 0);
    }).toList();
    if (_times.isEmpty) _times = [const TimeOfDay(hour: 8, minute: 0)];
  }

  void _setTimesPerDay(int n) {
    setState(() {
      _timesPerDay = n;
      _times = List.from(_presets[n] ?? [const TimeOfDay(hour: 8, minute: 0)]);
    });
  }

  Future<void> _pickTime(int i) async {
    final t = await showTimePicker(
      context: context, initialTime: _times[i],
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
            colorScheme: const ColorScheme.light(
                primary: _C.teal, onPrimary: Colors.white,
                surface: _C.card, onSurface: _C.textPri)),
        child: child!,
      ),
    );
    if (t != null) setState(() => _times[i] = t);
  }

  Future<void> _rerunAI() async {
    setState(() => _loadingAI = true);
    try {
      final prompt = '''
You are a pharmacist AI. Determine the best dosing schedule for this medicine.

Medicine: ${widget.medicineData['medicineName'] ?? ''}
Dosage: ${widget.medicineData['dosage'] ?? ''}
Instructions: ${widget.medicineData['dosageInstructions'] ?? 'Not specified'}
Usage: ${widget.medicineData['usage'] ?? 'Not specified'}
Category: ${widget.medicineData['category'] ?? 'General'}

Respond ONLY with valid JSON, no markdown:
{
  "timesPerDay": <integer 1-4>,
  "times": ["HH:MM", ...],
  "mealTiming": "<before meal|after meal|with food|anytime>",
  "frequencyLabel": "<e.g. 2x / day>"
}
''';
      final res = await http.post(Uri.parse('${widget.apiUrl}?key=${widget.apiKey}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [{'parts': [{'text': prompt}]}],
          'generationConfig': {
            'temperature': 0.1, 'maxOutputTokens': 200,
            'responseMimeType': 'application/json',
          },
        }),
      );
      if (res.statusCode == 200) {
        final d   = jsonDecode(res.body);
        var raw   = d['candidates']?[0]?['content']?['parts']?[0]?['text'] ?? '{}';
        raw = raw.replaceAll('```json','').replaceAll('```','').trim();
        final parsed = jsonDecode(raw) as Map<String, dynamic>;
        final tpd   = (parsed['timesPerDay'] as num?)?.toInt() ?? 1;
        final rawTimes = parsed['times'] as List? ?? [];
        setState(() {
          _timesPerDay = tpd.clamp(1, 4);
          _mealTiming  = (parsed['mealTiming'] ?? 'anytime').toString();
          _times = rawTimes.map<TimeOfDay>((t) {
            final p = t.toString().split(':');
            return TimeOfDay(hour: int.tryParse(p[0]) ?? 8,
                minute: int.tryParse(p[1]) ?? 0);
          }).toList();
          if (_times.isEmpty) _times = [const TimeOfDay(hour: 8, minute: 0)];
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingAI = false);
  }

  String _fmt(TimeOfDay t) {
    final h  = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m  = t.minute.toString().padLeft(2, '0');
    return '$h:$m ${t.period == DayPeriod.am ? 'AM' : 'PM'}';
  }

  String _fmt24(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2,'0')}:${t.minute.toString().padLeft(2,'0')}';

  String _slotLabel(TimeOfDay t) {
    if (t.hour < 12) return 'Morning';
    if (t.hour < 17) return 'Afternoon';
    if (t.hour < 20) return 'Evening';
    return 'Night';
  }

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
        color: _C.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 32),
      child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [

            // Handle
            Center(child: Container(width: 36, height: 4,
                decoration: BoxDecoration(color: _C.border,
                    borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 18),

            // Header
            Row(children: [
              Container(width: 46, height: 46,
                  decoration: BoxDecoration(
                      color: _C.teal.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(14)),
                  child: const Icon(Icons.schedule_rounded, color: _C.teal, size: 22)),
              const SizedBox(width: 12),
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Edit Dosing Schedule', style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700, color: _C.textPri)),
                Text(widget.medicineName, style: const TextStyle(
                    fontSize: 12, color: _C.textSec), maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ])),
              // Re-run AI button
              GestureDetector(
                onTap: _loadingAI ? null : _rerunAI,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                      color: _C.violet.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _C.violet.withOpacity(0.3))),
                  child: _loadingAI
                      ? const SizedBox(width: 14, height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: _C.violet))
                      : const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.auto_awesome_rounded, color: _C.violet, size: 13),
                    SizedBox(width: 4),
                    Text('AI', style: TextStyle(fontSize: 11,
                        color: _C.violet, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
            ]),
            const SizedBox(height: 22),

            // Tracking on/off
            Row(children: [
              const Text('Enable Tracking', style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: _C.textPri)),
              const Spacer(),
              Switch(
                value: _trackingEnabled,
                onChanged: (v) { HapticFeedback.selectionClick(); setState(() => _trackingEnabled = v); },
                activeColor: Colors.white,
                activeTrackColor: _C.teal,
                inactiveThumbColor: Colors.white,
                inactiveTrackColor: _C.border,
                trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
              ),
            ]),
            Text(_trackingEnabled
                ? 'Dose logging and reminders are active'
                : 'Turn on to track doses and get reminders',
                style: const TextStyle(fontSize: 11, color: _C.textSec)),
            const SizedBox(height: 20),

            const Divider(color: _C.border),
            const SizedBox(height: 16),

            // How many times per day
            const Text('How many times per day?', style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: _C.textPri)),
            const SizedBox(height: 4),
            const Text('Tap a number to change — times will update automatically',
                style: TextStyle(fontSize: 11, color: _C.textTer)),
            const SizedBox(height: 12),

            Row(children: List.generate(4, (i) {
              final n  = i + 1;
              final on = _timesPerDay == n;
              return Expanded(child: Padding(
                padding: EdgeInsets.only(right: i < 3 ? 8 : 0),
                child: GestureDetector(
                  onTap: () { HapticFeedback.selectionClick(); _setTimesPerDay(n); },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: on ? _C.teal : _C.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: on ? _C.teal : _C.border, width: on ? 0 : 1.5),
                      boxShadow: on ? [BoxShadow(color: _C.teal.withOpacity(0.28),
                          blurRadius: 10, offset: const Offset(0, 4))] : [],
                    ),
                    child: Column(children: [
                      Text('$n', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
                          color: on ? Colors.white : _C.textPri)),
                      const SizedBox(height: 2),
                      Text(n == 1 ? 'time' : 'times', style: TextStyle(
                          fontSize: 10, fontWeight: FontWeight.w600,
                          color: on ? Colors.white.withOpacity(0.7) : _C.textTer)),
                      Text('/ day', style: TextStyle(
                          fontSize: 9, color: on ? Colors.white.withOpacity(0.5) : _C.textTer)),
                    ]),
                  ),
                ),
              ));
            })),
            const SizedBox(height: 22),

            // Time slots
            Row(children: [
              const Text('Reminder Times', style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: _C.textPri)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                    color: _C.amber.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8)),
                child: const Text('Tap to change', style: TextStyle(
                    fontSize: 10, color: _C.amber, fontWeight: FontWeight.w600)),
              ),
            ]),
            const SizedBox(height: 12),

            ...List.generate(_times.length, (i) => GestureDetector(
              onTap: () => _pickTime(i),
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                    color: _C.surface, borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _C.border)),
                child: Row(children: [
                  Container(width: 38, height: 38,
                      decoration: BoxDecoration(
                          color: _C.rose.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.alarm_rounded, color: _C.rose, size: 19)),
                  const SizedBox(width: 14),
                  Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_fmt(_times[i]), style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700, color: _C.textPri)),
                    Text(_slotLabel(_times[i]), style: const TextStyle(
                        fontSize: 11, color: _C.textSec)),
                  ])),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                        color: _C.teal.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8)),
                    child: Text('Dose ${i + 1}', style: const TextStyle(
                        fontSize: 11, color: _C.teal, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.edit_rounded, color: _C.textTer, size: 16),
                ]),
              ),
            )),
            const SizedBox(height: 18),

            // Meal timing
            const Text('When to take?', style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: _C.textPri)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8,
                children: _mealOptions.map((opt) {
                  final k   = opt['key']   as String;
                  final lbl = opt['label'] as String;
                  final ic  = opt['icon']  as IconData;
                  final on  = _mealTiming == k;
                  return GestureDetector(
                    onTap: () { HapticFeedback.selectionClick(); setState(() => _mealTiming = k); },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                          color: on ? _C.sky : _C.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: on ? _C.sky : _C.border),
                          boxShadow: on ? [BoxShadow(color: _C.sky.withOpacity(0.25),
                              blurRadius: 8, offset: const Offset(0, 3))] : []),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(ic, size: 15, color: on ? Colors.white : _C.textSec),
                        const SizedBox(width: 6),
                        Text(lbl, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                            color: on ? Colors.white : _C.textSec)),
                      ]),
                    ),
                  );
                }).toList()),
            const SizedBox(height: 24),

            // Summary
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: _C.navy, borderRadius: BorderRadius.circular(16)),
              child: Column(children: [
                Row(children: [
                  const Icon(Icons.check_circle_rounded, color: _C.teal, size: 16),
                  const SizedBox(width: 8),
                  const Text('Schedule Summary', style: TextStyle(
                      color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: _C.teal.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8)),
                    child: Text('${_timesPerDay}x / day', style: const TextStyle(
                        color: _C.teal, fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                ]),
                const SizedBox(height: 10),
                ..._times.asMap().entries.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Row(children: [
                    Container(width: 22, height: 22,
                        decoration: BoxDecoration(
                            color: _C.teal.withOpacity(0.15), shape: BoxShape.circle),
                        child: Center(child: Text('${e.key + 1}',
                            style: const TextStyle(color: _C.teal,
                                fontSize: 10, fontWeight: FontWeight.w700)))),
                    const SizedBox(width: 10),
                    Text(_fmt(e.value), style: const TextStyle(
                        color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 8),
                    Text('· ${_slotLabel(e.value)}',
                        style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 12)),
                    const Spacer(),
                    Text(_mealTiming, style: TextStyle(
                        color: _C.teal.withOpacity(0.7), fontSize: 11)),
                  ]),
                )),
              ]),
            ),
            const SizedBox(height: 20),

            // Save button
            GestureDetector(
              onTap: () {
                HapticFeedback.mediumImpact();
                Navigator.pop(context, {
                  'times':          _times.map(_fmt24).toList(),
                  'timesPerDay':    _timesPerDay,
                  'mealTiming':     _mealTiming,
                  'trackingEnabled': _trackingEnabled,
                });
              },
              child: Container(
                height: 52, width: double.infinity,
                decoration: BoxDecoration(
                    color: _C.teal, borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: _C.teal.withOpacity(0.35),
                        blurRadius: 14, offset: const Offset(0, 6))]),
                child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.check_rounded, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text('Save Schedule', style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            Center(child: GestureDetector(
              onTap: () => Navigator.pop(context, null),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Cancel', style: TextStyle(
                    color: _C.textTer, fontSize: 13, fontWeight: FontWeight.w500)),
              ),
            )),
          ]),
    ),
  );
}

// ─── Extension ────────────────────────────────────────────────────────────────
extension _StringExt on String {
  String capitalize() => isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}

// ─── Field Config ─────────────────────────────────────────────────────────────
class _FieldCfg {
  final TextEditingController ctrl;
  final String label;
  final IconData icon;
  final Color accent;
  final int maxLines;
  final bool required, isLast, isDateField;
  final VoidCallback? onTap;
  const _FieldCfg(this.ctrl, this.label, this.icon, this.accent,
      {this.maxLines = 1, this.required = false,
        this.isLast = false, this.isDateField = false, this.onTap});
}

// ─── Expiry Field — edit_profile style ───────────────────────────────────────
class _ExpiryField extends StatelessWidget {
  final TextEditingController ctrl;
  final bool editMode;
  final VoidCallback onTap;
  final Color statusColor;
  final String source; // 'label' | 'ai' | 'user'
  const _ExpiryField({required this.ctrl, required this.editMode,
    required this.onTap, required this.statusColor, this.source = 'label'});

  Widget _sourceChip() {
    final Color c; final IconData ic; final String label;
    switch (source) {
      case 'ai':
        c = _C.violet; ic = Icons.auto_awesome_rounded; label = 'AI estimated';
        break;
      case 'user':
        c = _C.sky; ic = Icons.person_rounded; label = 'Set by you';
        break;
      default:
        c = _C.teal; ic = Icons.verified_rounded; label = 'From label';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
          color: c.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.withOpacity(0.3))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(ic, color: c, size: 10),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(
            color: c, fontSize: 9, fontWeight: FontWeight.w700)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: editMode ? onTap : null,
    child: Container(
      decoration: BoxDecoration(
          color: _C.card, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _C.border),
          boxShadow: [BoxShadow(color: MedicColors.forest.withOpacity(0.025),
              blurRadius: 10, offset: const Offset(0, 3))]),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Icon badge — same style as field group
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.cake_outlined, color: statusColor, size: 18),
            ),
          ),
          const SizedBox(width: 12),
          // Label + value stacked
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 10),
            Row(children: [
              Text('Expiry Date *', style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700,
                  color: statusColor, letterSpacing: 0.2)),
              if (editMode) ...[
                const SizedBox(width: 6),
                Icon(Icons.calendar_today_rounded,
                    color: statusColor, size: 11),
              ],
              const SizedBox(width: 8),
              _sourceChip(),
            ]),
            const SizedBox(height: 4),
            AbsorbPointer(child: TextFormField(
              controller: ctrl,
              enabled: false,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600,
                  color: _C.textPri, height: 1.4),
              validator: (v) =>
              (v == null || v.isEmpty || v == 'Not visible')
                  ? 'Expiry date is required' : null,
              decoration: InputDecoration(
                hintText: editMode ? 'Tap to select date' : null,
                hintStyle: const TextStyle(
                    color: _C.textTer, fontSize: 13),
                isDense: true,
                contentPadding: const EdgeInsets.only(bottom: 8),
                border:             InputBorder.none,
                enabledBorder:      InputBorder.none,
                focusedBorder:      InputBorder.none,
                errorBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: _C.rose, width: 1.5)),
                focusedErrorBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: _C.rose, width: 1.5)),
                errorStyle: const TextStyle(
                    fontSize: 10, color: _C.rose, height: 1.2),
              ),
            )),
            const SizedBox(height: 6),
          ])),
        ]),
      ),
    ),
  );
}

// ─── Shared small widgets ─────────────────────────────────────────────────────
class _HBtn extends StatelessWidget {
  final IconData icon;
  final Color? accent;
  final VoidCallback? onTap;
  const _HBtn({required this.icon, this.accent, this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 40, height: 40,
      decoration: BoxDecoration(
          color: accent != null ? accent!.withOpacity(0.15) : Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accent != null
              ? accent!.withOpacity(0.4) : Colors.white.withOpacity(0.15))),
      child: Icon(icon, color: accent ?? Colors.white, size: 19),
    ),
  );
}

class _StatCell extends StatelessWidget {
  final IconData icon;
  final String value, label;
  final Color accent;
  const _StatCell({required this.icon, required this.value,
    required this.label, required this.accent});
  @override
  Widget build(BuildContext context) => Column(children: [
    Icon(icon, color: accent, size: 20),
    const SizedBox(height: 6),
    Text(value, style: const TextStyle(color: Colors.white, fontSize: 17,
        fontWeight: FontWeight.w700, letterSpacing: -0.3)),
    const SizedBox(height: 2),
    Text(label, style: TextStyle(color: Colors.white.withOpacity(0.5),
        fontSize: 10, fontWeight: FontWeight.w500)),
  ]);
}

class _VertDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 40, color: Colors.white.withOpacity(0.12));
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color accent;
  final Widget? action;
  const _SectionLabel({required this.label, required this.icon,
    required this.accent, this.action});
  @override
  Widget build(BuildContext context) => Row(children: [
    Container(width: 30, height: 30,
        decoration: BoxDecoration(color: accent.withOpacity(0.1),
            borderRadius: BorderRadius.circular(9)),
        child: Icon(icon, color: accent, size: 16)),
    const SizedBox(width: 9),
    Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
        color: _C.textPri, letterSpacing: -0.3)),
    if (action != null) ...[const Spacer(), action!],
  ]);
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool loading;
  final VoidCallback? onTap;
  const _ActionBtn({required this.label, required this.icon,
    required this.color, required this.loading, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: 52, width: double.infinity,
      decoration: BoxDecoration(
          color: loading ? color.withOpacity(0.6) : color,
          borderRadius: BorderRadius.circular(16),
          boxShadow: loading ? [] : [BoxShadow(color: color.withOpacity(0.3),
              blurRadius: 14, offset: const Offset(0, 6))]),
      child: Center(child: loading
          ? const SizedBox(width: 22, height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
          : Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: Colors.white, size: 19),
        const SizedBox(width: 9),
        Text(label, style: const TextStyle(color: Colors.white,
            fontWeight: FontWeight.w700, fontSize: 14)),
      ])),
    ),
  );
}

class _OutlineBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  const _OutlineBtn({required this.label, required this.icon,
    required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      height: 50, width: double.infinity,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.4), width: 1.5)),
      child: Center(child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(color: color,
            fontWeight: FontWeight.w700, fontSize: 14)),
      ])),
    ),
  );
}

class _DeleteDialog extends StatelessWidget {
  final String name;
  const _DeleteDialog({required this.name});
  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: _C.card,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    child: Padding(padding: const EdgeInsets.all(24), child: Column(
        mainAxisSize: MainAxisSize.min, children: [
      Container(width: 52, height: 52,
          decoration: BoxDecoration(color: _C.rose.withOpacity(0.1), shape: BoxShape.circle),
          child: const Icon(Icons.delete_outline_rounded, color: _C.rose, size: 24)),
      const SizedBox(height: 16),
      const Text('Delete Medicine?', style: TextStyle(
          fontSize: 18, fontWeight: FontWeight.w700, color: _C.textPri)),
      const SizedBox(height: 8),
      Text('Remove "$name"?\nThis cannot be undone.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: _C.textSec, height: 1.5)),
      const SizedBox(height: 22),
      Row(children: [
        Expanded(child: GestureDetector(
          onTap: () => Navigator.pop(context, false),
          child: Container(height: 44,
              decoration: BoxDecoration(color: _C.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _C.border)),
              child: const Center(child: Text('Cancel', style: TextStyle(
                  fontWeight: FontWeight.w700, color: _C.textSec, fontSize: 13)))),
        )),
        const SizedBox(width: 12),
        Expanded(child: GestureDetector(
          onTap: () => Navigator.pop(context, true),
          child: Container(height: 44,
              decoration: BoxDecoration(color: _C.rose,
                  borderRadius: BorderRadius.circular(12)),
              child: const Center(child: Text('Delete', style: TextStyle(
                  fontWeight: FontWeight.w700, color: Colors.white, fontSize: 13)))),
        )),
      ]),
    ])),
  );
}

// ─── AI Analysis Sheet ────────────────────────────────────────────────────────
// Fully updated: markdown cleaned, TTS with language picker

// ── Language config ───────────────────────────────────────────────────────────
class _AnalysisLang {
  final String code, name, flag, ttsLocale, geminiName;
  const _AnalysisLang(this.code, this.name, this.flag, this.ttsLocale, this.geminiName);
}

// Keep _Lang as alias so existing TTS code in _AnalysisSheet compiles unchanged
typedef _Lang = _AnalysisLang;

const _kAnalysisLangs = [
  _AnalysisLang('en', 'English',          '🇬🇧', 'en-US', 'English'),
  _AnalysisLang('ms', 'Bahasa Melayu',    '🇲🇾', 'ms-MY', 'Bahasa Melayu'),
  _AnalysisLang('zh', 'Mandarin',         '🇨🇳', 'zh-CN', 'Simplified Chinese'),
  _AnalysisLang('ta', 'Tamil',            '🇮🇳', 'ta-IN', 'Tamil'),
  _AnalysisLang('ar', 'Arabic',           '🇸🇦', 'ar-SA', 'Arabic'),
  _AnalysisLang('hi', 'Hindi',            '🇮🇳', 'hi-IN', 'Hindi'),
  _AnalysisLang('id', 'Bahasa Indonesia', '🇮🇩', 'id-ID', 'Bahasa Indonesia'),
  _AnalysisLang('th', 'Thai',             '🇹🇭', 'th-TH', 'Thai'),
  _AnalysisLang('ja', 'Japanese',         '🇯🇵', 'ja-JP', 'Japanese'),
  _AnalysisLang('ko', 'Korean',           '🇰🇷', 'ko-KR', 'Korean'),
  _AnalysisLang('fr', 'Francais',         '🇫🇷', 'fr-FR', 'French'),
  _AnalysisLang('de', 'Deutsch',          '🇩🇪', 'de-DE', 'German'),
  _AnalysisLang('es', 'Espanol',          '🇪🇸', 'es-ES', 'Spanish'),
  _AnalysisLang('pt', 'Portugues',        '🇧🇷', 'pt-BR', 'Portuguese'),
  _AnalysisLang('ru', 'Russian',          '🇷🇺', 'ru-RU', 'Russian'),
];

// ─── Language Picker Dialog — shown BEFORE generating ─────────────────────────
class _LangPickerDialog extends StatefulWidget {
  @override
  State<_LangPickerDialog> createState() => _LangPickerDialogState();
}

class _LangPickerDialogState extends State<_LangPickerDialog> {
  _AnalysisLang _selected = _kAnalysisLangs[0]; // default English

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: _C.card,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    child: Padding(
      padding: const EdgeInsets.all(0),
      child: Column(mainAxisSize: MainAxisSize.min, children: [

        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          decoration: BoxDecoration(
              color: _C.navy,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
          child: Column(children: [
            // Icon + title row
            Row(children: [
              Container(width: 44, height: 44,
                  decoration: BoxDecoration(
                      color: _C.violet.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: _C.violet.withOpacity(0.3))),
                  child: const Icon(Icons.auto_awesome_rounded,
                      color: _C.violet, size: 21)),
              const SizedBox(width: 12),
              const Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('AI Analysis', style: TextStyle(
                    color: Colors.white, fontSize: 17,
                    fontWeight: FontWeight.w700)),
                Text('Choose response language first',
                    style: TextStyle(color: Colors.white54, fontSize: 11)),
              ])),
            ]),
            const SizedBox(height: 14),
            // Selected language preview chip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withOpacity(0.12))),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(_selected.flag, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 10),
                Text(_selected.name, style: const TextStyle(
                    color: Colors.white, fontSize: 14,
                    fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                      color: _C.teal.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(6)),
                  child: const Text('Selected', style: TextStyle(
                      color: _C.teal, fontSize: 10,
                      fontWeight: FontWeight.w700)),
                ),
              ]),
            ),
          ]),
        ),

        // Language grid
        ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.40),
          child: ListView.builder(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: _kAnalysisLangs.length,
            itemBuilder: (_, i) {
              final lang = _kAnalysisLangs[i];
              final on   = lang.code == _selected.code;
              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _selected = lang);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  decoration: BoxDecoration(
                      color: on ? _C.sky.withOpacity(0.08) : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: on ? _C.sky.withOpacity(0.4) : Colors.transparent,
                          width: 1.5)),
                  child: Row(children: [
                    Text(lang.flag, style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 12),
                    Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(lang.name, style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700,
                          color: on ? _C.sky : _C.textPri)),
                      Text(lang.geminiName, style: const TextStyle(
                          fontSize: 10, color: _C.textTer)),
                    ])),
                    if (on)
                      Container(width: 22, height: 22,
                          decoration: const BoxDecoration(
                              color: _C.sky, shape: BoxShape.circle),
                          child: const Icon(Icons.check_rounded,
                              color: Colors.white, size: 13))
                    else
                      Container(width: 22, height: 22,
                          decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: _C.border, width: 1.5))),
                  ]),
                ),
              );
            },
          ),
        ),

        // Buttons
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Row(children: [
            Expanded(child: GestureDetector(
              onTap: () => Navigator.pop(context, null),
              child: Container(height: 44,
                  decoration: BoxDecoration(
                      color: _C.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _C.border)),
                  child: const Center(child: Text('Cancel', style: TextStyle(
                      color: _C.textSec, fontWeight: FontWeight.w700,
                      fontSize: 13)))),
            )),
            const SizedBox(width: 10),
            Expanded(child: GestureDetector(
              onTap: () => Navigator.pop(context, _selected),
              child: Container(height: 44,
                  decoration: BoxDecoration(
                      color: _C.violet,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [BoxShadow(
                          color: _C.violet.withOpacity(0.3),
                          blurRadius: 10, offset: const Offset(0, 4))]),
                  child: const Row(mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.auto_awesome_rounded,
                            color: Colors.white, size: 15),
                        SizedBox(width: 6),
                        Text('Generate', style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w700,
                            fontSize: 13)),
                      ])),
            )),
          ]),
        ),
      ]),
    ),
  );
}

/// Strips all markdown from AI output:
/// ####, ###, ##, #  →  removed
/// **text**          →  text
/// *text*            →  bullet  (leading *) or text (inline)
/// `code`            →  text
/// ---               →  blank
/// Triple blank lines → single
String _cleanAnalysisText(String raw) {
  final lines = raw.split('\n');
  final out   = <String>[];

  for (var line in lines) {
    // Strip leading #+ headings — keep the title text
    line = line.replaceAllMapped(RegExp(r'^#{1,6}\s*'), (_) => '');

    // Strip bold **text**
    line = line.replaceAll(RegExp(r'\*{2}'), '');

    // Leading * bullet → •
    line = line.replaceAllMapped(
        RegExp(r'^\s*\*\s+'), (_) => '• ');

    // Inline *italic* → plain
    line = line.replaceAll(RegExp(r'\*(.+?)\*'), r'\1');

    // Backticks
    line = line.replaceAll('`', '');

    // Horizontal rules
    if (RegExp(r'^---+$').hasMatch(line.trim())) line = '';

    out.add(line);
  }

  // Collapse 3+ consecutive blank lines to 1
  final collapsed = <String>[];
  int blanks = 0;
  for (final l in out) {
    if (l.trim().isEmpty) {
      blanks++;
      if (blanks <= 1) collapsed.add('');
    } else {
      blanks = 0;
      collapsed.add(l);
    }
  }

  return collapsed.join('\n').trim();
}

class _AnalysisSheet extends StatefulWidget {
  final String name, text;
  final Color statusColor;
  final int potency;
  final String status;
  final _AnalysisLang initialLang;
  _AnalysisSheet({required this.name, required this.text,
    required this.statusColor, required this.potency, required this.status,
    _AnalysisLang? initialLang})
      : initialLang = initialLang ?? _kAnalysisLangs[0];
  @override
  State<_AnalysisSheet> createState() => _AnalysisSheetState();
}

class _AnalysisSheetState extends State<_AnalysisSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _slide;

  // ── TTS ─────────────────────────────────────────────────────────────────────
  final FlutterTts _tts = FlutterTts();
  bool   _speaking    = false;
  bool   _ttsReady    = false;
  double _ttsSpeed    = 0.5;
  double _ttsPitch    = 1.0;
  late _AnalysisLang _lang; // set from widget.initialLang in initState

  // Cleaned text cached so we don't re-clean on every rebuild
  late final String _cleanText;

  @override
  void initState() {
    super.initState();
    _cleanText = _cleanAnalysisText(widget.text);
    _lang = widget.initialLang; // use the language the user selected before generating

    _ctrl  = AnimationController(duration: const Duration(milliseconds: 350), vsync: this);
    _slide = Tween<double>(begin: 1.0, end: 0.0).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();
    _initTts();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage(_lang.ttsLocale);
    await _tts.setSpeechRate(_ttsSpeed);
    await _tts.setPitch(_ttsPitch);
    await _tts.setVolume(1.0);
    _tts.setCompletionHandler(() { if (mounted) setState(() => _speaking = false); });
    _tts.setCancelHandler(()    { if (mounted) setState(() => _speaking = false); });
    _tts.setErrorHandler((_)    { if (mounted) setState(() => _speaking = false); });
    if (mounted) setState(() => _ttsReady = true);
  }

  Future<void> _toggleSpeak() async {
    HapticFeedback.lightImpact();
    if (_speaking) {
      await _tts.stop();
      setState(() => _speaking = false);
      return;
    }
    await _tts.setLanguage(_lang.ttsLocale);
    await _tts.setSpeechRate(_ttsSpeed);
    await _tts.setPitch(_ttsPitch);
    setState(() => _speaking = true);
    await _tts.speak(_cleanText);
  }

  Future<void> _stopTts() async {
    await _tts.stop();
    if (mounted) setState(() => _speaking = false);
  }

  @override
  void dispose() {
    _tts.stop();
    _ctrl.dispose();
    super.dispose();
  }

  // ── Language picker ──────────────────────────────────────────────────────────
  void _showLangPicker() {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.55,
        decoration: const BoxDecoration(
            color: _C.card,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(children: [
          Container(margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 36, height: 4,
              decoration: BoxDecoration(color: _C.border,
                  borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
            child: Row(children: [
              Container(width: 34, height: 34,
                  decoration: BoxDecoration(
                      color: _C.sky.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(9)),
                  child: const Icon(Icons.language_rounded, color: _C.sky, size: 17)),
              const SizedBox(width: 10),
              const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('TTS Language', style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700, color: _C.textPri)),
                Text('Select the language to read aloud',
                    style: TextStyle(fontSize: 11, color: _C.textSec)),
              ]),
            ]),
          ),
          const Divider(height: 1, color: _C.border),
          Expanded(child: ListView.builder(
            itemCount: _kAnalysisLangs.length,
            itemBuilder: (_, i) {
              final lang = _kAnalysisLangs[i];
              final on   = lang.code == _lang.code;
              return GestureDetector(
                onTap: () async {
                  setState(() => _lang = lang);
                  await _tts.setLanguage(lang.ttsLocale);
                  Navigator.pop(context);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  decoration: BoxDecoration(
                      color: on ? _C.sky.withOpacity(0.08) : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: on ? _C.sky.withOpacity(0.35) : Colors.transparent)),
                  child: Row(children: [
                    Text(lang.flag, style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 12),
                    Expanded(child: Text(lang.name, style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700,
                        color: on ? _C.sky : _C.textPri))),
                    if (on)
                      Container(width: 22, height: 22,
                          decoration: const BoxDecoration(
                              color: _C.sky, shape: BoxShape.circle),
                          child: const Icon(Icons.check_rounded,
                              color: Colors.white, size: 13)),
                  ]),
                ),
              );
            },
          )),
        ]),
      ),
    );
  }

  // ── TTS speed/pitch settings ─────────────────────────────────────────────────
  void _showTtsSettings() {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setInner) => Container(
          decoration: const BoxDecoration(
              color: _C.card,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          padding: EdgeInsets.fromLTRB(
              24, 16, 24, MediaQuery.of(ctx).padding.bottom + 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 36, height: 4,
                decoration: BoxDecoration(
                    color: _C.border, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 18),
            Row(children: [
              Container(width: 38, height: 38,
                  decoration: BoxDecoration(
                      color: _C.teal.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(11)),
                  child: const Icon(Icons.record_voice_over_rounded,
                      color: _C.teal, size: 19)),
              const SizedBox(width: 12),
              const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Voice Settings', style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700, color: _C.textPri)),
                Text('Speed & pitch', style: TextStyle(
                    fontSize: 11, color: _C.textSec)),
              ]),
            ]),
            const SizedBox(height: 24),
            // Speed
            _buildSliderRow(ctx, setInner,
                label: 'Speed', icon: Icons.speed_rounded, color: _C.violet,
                value: _ttsSpeed, min: 0.1, max: 1.0, divisions: 9,
                valueLabel: _ttsSpeed <= 0.25 ? 'Slow'
                    : _ttsSpeed <= 0.6 ? 'Normal'
                    : _ttsSpeed <= 0.85 ? 'Fast' : 'Very Fast',
                onChanged: (v) async {
                  setInner(() => _ttsSpeed = v);
                  setState(() => _ttsSpeed = v);
                  await _tts.setSpeechRate(v);
                }),
            const SizedBox(height: 16),
            // Pitch
            _buildSliderRow(ctx, setInner,
                label: 'Pitch', icon: Icons.music_note_rounded, color: _C.sky,
                value: _ttsPitch, min: 0.5, max: 1.5, divisions: 10,
                valueLabel: _ttsPitch <= 0.7 ? 'Low'
                    : _ttsPitch <= 1.0 ? 'Normal'
                    : _ttsPitch <= 1.3 ? 'High' : 'Very High',
                onChanged: (v) async {
                  setInner(() => _ttsPitch = v);
                  setState(() => _ttsPitch = v);
                  await _tts.setPitch(v);
                }),
            const SizedBox(height: 20),
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
                  'Tap the speaker button to hear the analysis read aloud.',
                  style: TextStyle(fontSize: 11, color: _C.textSec, height: 1.4),
                )),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildSliderRow(
      BuildContext ctx, StateSetter setInner, {
        required String label, required IconData icon, required Color color,
        required double value, required double min, required double max,
        required int divisions, required String valueLabel,
        required Future<void> Function(double) onChanged,
      }) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 28, height: 28,
              decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: color, size: 14)),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w700, color: _C.textPri)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withOpacity(0.25))),
            child: Text(valueLabel, style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: color)),
          ),
        ]),
        SliderTheme(
          data: SliderTheme.of(ctx).copyWith(
            activeTrackColor:   color,
            inactiveTrackColor: color.withOpacity(0.15),
            thumbColor:         color,
            overlayColor:       color.withOpacity(0.12),
            trackHeight:        4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
          ),
          child: Slider(
            value: value, min: min, max: max,
            divisions: divisions,
            onChanged: (v) => onChanged(v),
          ),
        ),
      ]);

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _cleanText));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Row(children: [
        Icon(Icons.check_circle_rounded, color: Colors.white, size: 16),
        SizedBox(width: 8), Text('Copied to clipboard'),
      ]),
      backgroundColor: _C.navy,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.all(16),
    ));
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _slide,
    builder: (_, child) => Transform.translate(
        offset: Offset(0, MediaQuery.of(context).size.height * 0.25 * _slide.value),
        child: child),
    child: Container(
      height: MediaQuery.of(context).size.height * 0.92,
      decoration: const BoxDecoration(color: _C.card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      child: Column(children: [

        // Handle
        Center(child: Container(
            margin: const EdgeInsets.only(top: 10),
            width: 36, height: 4,
            decoration: BoxDecoration(color: _C.border,
                borderRadius: BorderRadius.circular(2)))),

        // ── Header ──────────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          decoration: const BoxDecoration(color: _C.navy,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
          child: Column(children: [
            // Row 1: icon + title + close
            Row(children: [
              Container(width: 44, height: 44,
                  decoration: BoxDecoration(
                      color: _C.violet.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: _C.violet.withOpacity(0.3))),
                  child: const Icon(Icons.auto_awesome_rounded,
                      color: _C.violet, size: 21)),
              const SizedBox(width: 12),
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('AI Analysis', style: TextStyle(
                    color: Colors.white, fontSize: 18,
                    fontWeight: FontWeight.w700)),
                Text(widget.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.45), fontSize: 12)),
              ])),
              GestureDetector(
                onTap: () async { await _stopTts(); Navigator.pop(context); },
                child: Container(width: 36, height: 36,
                    decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.close_rounded,
                        color: Colors.white, size: 18)),
              ),
            ]),
            const SizedBox(height: 12),

            // Quick stats bar
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withOpacity(0.1))),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _QStat(Icons.verified_rounded, '${widget.potency}%',
                        'Potency', widget.statusColor),
                    Container(width: 1, height: 28,
                        color: Colors.white.withOpacity(0.1)),
                    _QStat(Icons.health_and_safety_outlined,
                        widget.status.split(' ').first, 'Status', widget.statusColor),
                    Container(width: 1, height: 28,
                        color: Colors.white.withOpacity(0.1)),
                    _QStat(Icons.smart_toy_rounded, 'AI', 'Source', _C.violet),
                  ]),
            ),
            const SizedBox(height: 10),

            // ── Row 2: TTS controls ─────────────────────────────────────────
            Row(children: [
              // Language picker button
              GestureDetector(
                onTap: _showLangPicker,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white.withOpacity(0.15))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(_lang.flag, style: const TextStyle(fontSize: 14)),
                    const SizedBox(width: 4),
                    Text(_lang.code.toUpperCase(), style: const TextStyle(
                        color: Colors.white, fontSize: 10,
                        fontWeight: FontWeight.w700)),
                    const SizedBox(width: 2),
                    Icon(Icons.arrow_drop_down_rounded,
                        color: Colors.white.withOpacity(0.6), size: 16),
                  ]),
                ),
              ),
              const SizedBox(width: 8),

              // Voice settings
              if (_ttsReady)
                GestureDetector(
                  onTap: _showTtsSettings,
                  child: Container(
                    width: 34, height: 34,
                    decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: Colors.white.withOpacity(0.15))),
                    child: const Icon(Icons.tune_rounded,
                        color: Colors.white, size: 15),
                  ),
                ),
              const Spacer(),

              // Speak / Stop button
              if (_ttsReady)
                GestureDetector(
                  onTap: _toggleSpeak,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: _speaking ? _C.rose : _C.teal,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [BoxShadow(
                          color: (_speaking ? _C.rose : _C.teal).withOpacity(0.35),
                          blurRadius: 8, offset: const Offset(0, 3))],
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(
                        _speaking ? Icons.stop_rounded : Icons.volume_up_rounded,
                        color: Colors.white, size: 16,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _speaking ? 'Stop' : 'Listen',
                        style: const TextStyle(color: Colors.white,
                            fontWeight: FontWeight.w700, fontSize: 12),
                      ),
                    ]),
                  ),
                ),
            ]),
          ]),
        ),

        // ── Content ──────────────────────────────────────────────────────────
        Expanded(child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // Disclaimer
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: _C.amber.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _C.amber.withOpacity(0.25))),
              child: const Row(children: [
                Icon(Icons.info_outline_rounded, color: _C.amber, size: 18),
                SizedBox(width: 10),
                Expanded(child: Text(
                  'For informational purposes only. '
                      'Always consult a healthcare professional.',
                  style: TextStyle(fontSize: 12, color: _C.textSec, height: 1.5),
                )),
              ]),
            ),
            const SizedBox(height: 16),

            // ── Cleaned AI text — rendered as structured sections ─────────────
            _buildCleanedContent(_cleanText),
            const SizedBox(height: 20),

            // Action buttons
            Row(children: [
              Expanded(child: _SheetBtn(Icons.copy_rounded, 'Copy', _C.violet, _copy)),
              const SizedBox(width: 10),
              Expanded(child: _SheetBtn(Icons.close_rounded, 'Close', _C.teal,
                      () async { await _stopTts(); Navigator.pop(context); })),
            ]),
            const SizedBox(height: 24),
          ]),
        )),
      ]),
    ),
  );

  /// Renders the cleaned text with section headers visually distinguished
  Widget _buildCleanedContent(String text) {
    final lines    = text.split('\n');
    final widgets  = <Widget>[];
    final buffer   = StringBuffer();

    void flushBuffer() {
      final s = buffer.toString().trim();
      if (s.isNotEmpty) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(s, style: const TextStyle(
              fontSize: 14, height: 1.7, color: _C.textPri)),
        ));
        buffer.clear();
      }
    }

    for (final line in lines) {
      // Detect section headers — numbered sections like "1. OVERVIEW" or
      // lines that are all-caps (after cleaning) and short (<50 chars)
      final trimmed = line.trim();
      final isSection = RegExp(
          r'^\d+\.\s+[A-Z].+').hasMatch(trimmed) ||
          (trimmed.length < 60 &&
              trimmed.isNotEmpty &&
              trimmed == trimmed.toUpperCase() &&
              !trimmed.startsWith('•'));

      if (isSection && trimmed.isNotEmpty) {
        flushBuffer();
        // Extract emoji if present at start
        final emojiMatch = RegExp(r'^([\u{1F300}-\u{1FFFF}]|[\u2600}-\u{27BF}]|\S*\p{Emoji}\S*)?\s*(.+)\$',
            unicode: true).firstMatch(trimmed);
        final headerText = emojiMatch?.group(2) ?? trimmed;
        final emoji      = (emojiMatch?.group(1) ?? '').trim();

        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 8),
          child: Row(children: [
            if (emoji.isNotEmpty) ...[
              Text(emoji, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
            ],
            Expanded(child: Text(headerText, style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700,
                color: _C.textPri, letterSpacing: -0.2))),
          ]),
        ));
        widgets.add(Container(height: 1, color: _C.border,
            margin: const EdgeInsets.only(bottom: 8)));
      } else if (trimmed.startsWith('•')) {
        flushBuffer();
        widgets.add(Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 5),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              margin: const EdgeInsets.only(top: 7),
              width: 5, height: 5,
              decoration: BoxDecoration(
                  color: _C.teal, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(trimmed.substring(1).trim(),
                style: const TextStyle(fontSize: 13.5, height: 1.55,
                    color: _C.textPri))),
          ]),
        ));
      } else if (trimmed.isEmpty) {
        if (buffer.isNotEmpty) buffer.write('\n');
      } else {
        if (buffer.isNotEmpty) buffer.write(' ');
        buffer.write(trimmed);
      }
    }
    flushBuffer();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: _C.surface, borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _C.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: widgets),
    );
  }
}

class _QStat extends StatelessWidget {
  final IconData icon; final String value, label; final Color accent;
  const _QStat(this.icon, this.value, this.label, this.accent);
  @override
  Widget build(BuildContext context) => Column(children: [
    Icon(icon, color: accent, size: 17),
    const SizedBox(height: 4),
    Text(value, style: const TextStyle(color: Colors.white, fontSize: 14,
        fontWeight: FontWeight.w700)),
    Text(label, style: TextStyle(color: Colors.white.withOpacity(0.4),
        fontSize: 10)),
  ]);
}

class _SheetBtn extends StatelessWidget {
  final IconData icon; final String label; final Color color;
  final VoidCallback onTap;
  const _SheetBtn(this.icon, this.label, this.color, this.onTap);
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      height: 48,
      decoration: BoxDecoration(color: color,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: color.withOpacity(0.28),
              blurRadius: 12, offset: const Offset(0, 5))]),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, color: Colors.white, size: 18),
        const SizedBox(width: 7),
        Text(label, style: const TextStyle(color: Colors.white,
            fontWeight: FontWeight.w700, fontSize: 13)),
      ]),
    ),
  );
}

// ─── Mesh Painter ─────────────────────────────────────────────────────────────
class _MeshPainter extends CustomPainter {
  final Color accent;
  const _MeshPainter({required this.accent});
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(Offset(size.width * 0.88, size.height * 0.15), 120,
        Paint()..color = accent.withOpacity(0.1));
    canvas.drawCircle(Offset(size.width * 0.05, size.height * 0.82), 80,
        Paint()..color = _C.sky.withOpacity(0.06));
  }
  @override
  bool shouldRepaint(covariant _MeshPainter old) => old.accent != accent;
}