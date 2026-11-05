import 'package:medictrack/design/medic_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/auth_service.dart';

// ─── Design Tokens ────────────────────────────────────────────────────────────
class _C {
  static const navy      = MedicColors.c142F2B;
  static const teal      = MedicColors.c28715D;
  static const sky       = MedicColors.c477C91;
  static const amber     = MedicColors.cB77A27;
  static const rose      = MedicColors.cC05256;
  static const violet    = MedicColors.c78659B;
  static const surface   = MedicColors.cF6F5F0;
  static const card      = MedicColors.cFFFFFF;
  static const border    = MedicColors.cE2E5DC;
  static const textPri   = MedicColors.c142F2B;
  static const textSec   = MedicColors.c63756D;
  static const textTer   = MedicColors.c83938B;
}

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({Key? key}) : super(key: key);
  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen>
    with SingleTickerProviderStateMixin {
  final _formKey  = GlobalKey<FormState>();
  final _authSvc  = AuthService();
  final _db       = FirebaseFirestore.instance;

  final _nameCtrl      = TextEditingController();
  final _phoneCtrl     = TextEditingController();
  final _addressCtrl   = TextEditingController();
  final _emergencyCtrl = TextEditingController();
  final _dobCtrl       = TextEditingController();
  final _ageCtrl       = TextEditingController();
  final _heightCtrl    = TextEditingController();
  final _weightCtrl    = TextEditingController();
  final _notesCtrl     = TextEditingController();

  String? _gender;
  String? _bloodType;
  double? _bmi;
  List<String> _conditions = [];

  bool _loading = false;
  bool _saving  = false;

  late AnimationController _fadeCtrl;
  late Animation<double>   _fadeAnim;

  final _bloodTypes = ['A+', 'A−', 'B+', 'B−', 'AB+', 'AB−', 'O+', 'O−'];

  final _conditionList = [
    {'label': 'Heart Disease', 'icon': Icons.favorite_outline_rounded},
    {'label': 'Diabetes', 'icon': Icons.bloodtype_outlined},
    {'label': 'Stroke', 'icon': Icons.psychology_outlined},
    {'label': 'Hypertension', 'icon': Icons.monitor_heart_outlined},
    {'label': 'Hypoglycemia', 'icon': Icons.water_drop_outlined},
  ];

  // Count only the options displayed by this picker, while retaining any
  // previously saved health information outside the revised option list.
  int get _selectedConditionCount => _conditionList
      .where((condition) => _conditions.contains(condition['label'])).length;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        duration: const Duration(milliseconds: 500), vsync: this);
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeIn);
    _heightCtrl.addListener(_recalcBmi);
    _weightCtrl.addListener(_recalcBmi);
    _loadData();
  }

  @override
  void dispose() {
    for (final c in [_nameCtrl, _phoneCtrl, _addressCtrl, _emergencyCtrl,
      _dobCtrl, _ageCtrl, _heightCtrl, _weightCtrl, _notesCtrl]) c.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _recalcBmi() {
    final h = double.tryParse(_heightCtrl.text);
    final w = double.tryParse(_weightCtrl.text);
    setState(() {
      _bmi = (h != null && w != null && h > 0)
          ? w / ((h / 100) * (h / 100)) : null;
    });
  }

  String _bmiLabel(double b) {
    if (b < 18.5) return 'Underweight';
    if (b < 25.0) return 'Normal';
    if (b < 30.0) return 'Overweight';
    return 'Obese';
  }

  Color _bmiColor(double b) {
    if (b < 18.5) return _C.sky;
    if (b < 25.0) return _C.teal;
    if (b < 30.0) return _C.amber;
    return _C.rose;
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final user = _authSvc.currentUser;
    if (user != null) {
      final d = await _authSvc.getUserData(user.uid);
      if (d != null && mounted) {
        final h = d['healthInfo'] as Map<String, dynamic>? ?? {};
        setState(() {
          _nameCtrl.text      = d['fullName']         ?? '';
          _phoneCtrl.text     = d['phoneNumber']      ?? '';
          _addressCtrl.text   = d['address']          ?? '';
          _emergencyCtrl.text = d['emergencyContact'] ?? '';
          _dobCtrl.text       = d['dateOfBirth']      ?? '';
          _ageCtrl.text       = d['age']?.toString()  ?? '';
          _gender             = d['gender'];
          _heightCtrl.text    = h['height']?.toString() ?? '';
          _weightCtrl.text    = h['weight']?.toString() ?? '';
          _bloodType          = h['bloodType'];
          _conditions         = List<String>.from(h['chronicConditions'] ?? []);
          _notesCtrl.text     = h['otherIllness'] ?? '';
          if (h['bmi'] != null) _bmi = (h['bmi'] as num).toDouble();
        });
      }
    }
    if (mounted) {
      setState(() => _loading = false);
      _fadeCtrl.forward();
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    HapticFeedback.mediumImpact();
    setState(() => _saving = true);
    try {
      final user = _authSvc.currentUser;
      if (user != null) {
        await _db.collection('users').doc(user.uid).update({
          'fullName':         _nameCtrl.text.trim(),
          'phoneNumber':      _phoneCtrl.text.trim(),
          'address':          _addressCtrl.text.trim(),
          'emergencyContact': _emergencyCtrl.text.trim(),
          'dateOfBirth':      _dobCtrl.text.trim(),
          'age':              int.tryParse(_ageCtrl.text.trim()),
          'gender':           _gender,
          'healthInfo': {
            'height':            double.tryParse(_heightCtrl.text.trim()),
            'weight':            double.tryParse(_weightCtrl.text.trim()),
            'bmi':               _bmi,
            'bloodType':         _bloodType,
            'chronicConditions': _conditions,
            'otherIllness':      _notesCtrl.text.trim(),
            'updatedAt':         FieldValue.serverTimestamp(),
          },
          'updatedAt': FieldValue.serverTimestamp(),
        });
        if (mounted) {
          _snack('Profile saved successfully!');
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) _snack('Error saving: $e', error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(error ? Icons.error_outline_rounded : Icons.check_circle_rounded,
            color: Colors.white, size: 16),
        const SizedBox(width: 8),
        Expanded(child: Text(msg, style: const TextStyle(
            fontWeight: FontWeight.w600, fontSize: 13))),
      ]),
      backgroundColor: error ? _C.rose : _C.teal,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.all(16),
    ));
  }

  Future<void> _pickDate() async {
    final p = await showDatePicker(
      context: context,
      initialDate: DateTime.now().subtract(const Duration(days: 6570)),
      firstDate: DateTime(1950),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(colorScheme: const ColorScheme.light(
            primary: _C.teal, onPrimary: Colors.white,
            surface: _C.card, onSurface: _C.textPri)),
        child: child!,
      ),
    );
    if (p != null) {
      setState(() => _dobCtrl.text = '${p.day}/${p.month}/${p.year}');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(backgroundColor: _C.navy,
          body: Center(child: CircularProgressIndicator(
              strokeWidth: 2.5, color: _C.teal,
              backgroundColor: _C.teal.withOpacity(0.2))));
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _C.surface,
        body: FadeTransition(
          opacity: _fadeAnim,
          child: Column(children: [
            _buildHeader(),
            Expanded(child: Form(
              key: _formKey,
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 48),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                  // ── Personal Details ──────────────────────────────────────
                  _sectionLabel('Personal Details', Icons.person_outline_rounded),
                  const SizedBox(height: 12),
                  _buildCard([
                    _buildField(
                      ctrl: _nameCtrl, label: 'Full Name',
                      hint: 'Your full legal name',
                      icon: Icons.badge_outlined, accent: _C.teal,
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                    _buildField(
                      ctrl: _phoneCtrl, label: 'Phone Number',
                      hint: '+60 12 345 6789',
                      icon: Icons.phone_outlined, accent: _C.sky,
                      keyboard: TextInputType.phone,
                    ),
                    _buildDateField(),
                  ]),
                  const SizedBox(height: 24),

                  // ── Gender ────────────────────────────────────────────────
                  _sectionLabel('Gender', Icons.wc_outlined),
                  const SizedBox(height: 12),
                  _buildGenderPicker(),
                  const SizedBox(height: 24),

                  // ── Contact ───────────────────────────────────────────────
                  _sectionLabel('Contact & Emergency', Icons.location_on_outlined),
                  const SizedBox(height: 12),
                  _buildCard([
                    _buildField(
                      ctrl: _addressCtrl, label: 'Address',
                      hint: 'Street, City, Postcode',
                      icon: Icons.home_outlined, accent: _C.violet,
                      maxLines: 2,
                    ),
                    _buildField(
                      ctrl: _emergencyCtrl, label: 'Emergency Contact',
                      hint: 'Contact name & number',
                      icon: Icons.emergency_outlined, accent: _C.rose,
                      keyboard: TextInputType.phone,
                      isLast: true,
                    ),
                  ]),
                  const SizedBox(height: 24),

                  // ── Health Info ───────────────────────────────────────────
                  Row(children: [
                    _sectionLabel('Health Info', Icons.favorite_border_rounded),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                          color: _C.teal.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: _C.teal.withOpacity(0.3))),
                      child: const Text('Used for health scoring',
                          style: TextStyle(color: _C.teal, fontSize: 11,
                              fontWeight: FontWeight.w600)),
                    ),
                  ]),
                  const SizedBox(height: 12),

                  // Age (used directly by the Health Score formula)
                  _buildNumericField(
                      ctrl: _ageCtrl, label: 'Age', unit: 'yrs',
                      icon: Icons.calendar_today_rounded, accent: _C.violet),
                  const SizedBox(height: 10),

                  // Height & Weight
                  Row(children: [
                    Expanded(child: _buildNumericField(
                        ctrl: _heightCtrl, label: 'Height', unit: 'cm',
                        icon: Icons.height_rounded, accent: _C.sky)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildNumericField(
                        ctrl: _weightCtrl, label: 'Weight', unit: 'kg',
                        icon: Icons.monitor_weight_outlined, accent: _C.teal)),
                  ]),
                  const SizedBox(height: 10),

                  // BMI result
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    transitionBuilder: (child, anim) =>
                        FadeTransition(opacity: anim, child: SizeTransition(
                            sizeFactor: anim, child: child)),
                    child: _bmi != null
                        ? Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _buildBmiCard(_bmi!),
                    )
                        : const SizedBox.shrink(),
                  ),

                  // Blood type
                  _buildPanelCard(
                    icon: Icons.bloodtype_outlined, accent: _C.rose,
                    title: 'Blood Type', subtitle: 'Select your blood group',
                    child: _buildBloodTypePicker(),
                  ),
                  const SizedBox(height: 10),

                  // Conditions
                  _buildPanelCard(
                    icon: Icons.health_and_safety_outlined, accent: _C.violet,
                    title: 'Chronic Conditions', subtitle: 'Select all that apply',
                    trailing: _selectedConditionCount > 0 ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                          color: _C.violet.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10)),
                      child: Text('$_selectedConditionCount selected',
                          style: const TextStyle(color: _C.violet,
                              fontSize: 11, fontWeight: FontWeight.w700)),
                    ) : null,
                    child: _buildConditionsPicker(),
                  ),
                  const SizedBox(height: 10),

                  // Notes standalone
                  _buildStandaloneField(
                    ctrl: _notesCtrl,
                    label: 'Other Medical Notes',
                    hint: 'Allergies, past surgeries, other conditions...',
                    icon: Icons.note_alt_outlined,
                    accent: _C.amber,
                    maxLines: 4,
                  ),
                  const SizedBox(height: 32),

                  // Save button
                  _buildSaveButton(),
                ]),
              ),
            )),
          ]),
        ),
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────────
  Widget _buildHeader() => const MedicPageTitle(
    title: 'Your health profile', subtitle: 'The details that make your care personal.',
  );

  // ── Section label ────────────────────────────────────────────────────────────
  Widget _sectionLabel(String label, IconData icon) => Row(children: [
    Container(width: 30, height: 30,
        decoration: BoxDecoration(
            color: _C.teal.withOpacity(0.12),
            borderRadius: BorderRadius.circular(9)),
        child: Icon(icon, color: _C.teal, size: 16)),
    const SizedBox(width: 9),
    Text(label, style: const TextStyle(
        fontSize: 15, fontWeight: FontWeight.w700,
        color: _C.textPri, letterSpacing: -0.3)),
  ]);

  // ─────────────────────────────────────────────────────────────────────────────
  // FIXED FIELD BUILDERS — proper padding, visible labels, clear hierarchy
  // ─────────────────────────────────────────────────────────────────────────────

  /// Card that groups multiple fields with dividers between them
  Widget _buildCard(List<Widget> children) => Container(
    decoration: BoxDecoration(
        color: _C.card, borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _C.border),
        boxShadow: [BoxShadow(color: MedicColors.forest.withOpacity(0.025),
            blurRadius: 10, offset: const Offset(0, 3))]),
    child: Column(children: children),
  );

  /// Standard field row inside a card
  Widget _buildField({
    required TextEditingController ctrl,
    required String label,
    required String hint,
    required IconData icon,
    required Color accent,
    TextInputType? keyboard,
    int maxLines = 1,
    String? Function(String?)? validator,
    bool isLast = false,
  }) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Icon badge
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                  color: accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: accent, size: 18),
            ),
          ),
          const SizedBox(width: 12),
          // Label + TextField stacked vertically
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 10),
            Text(label, style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700,
                color: accent, letterSpacing: 0.2)),
            const SizedBox(height: 4),
            TextFormField(
              controller: ctrl,
              keyboardType: keyboard,
              maxLines: maxLines,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600, color: _C.textPri, height: 1.4),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(color: _C.textTer, fontSize: 13),
                isDense: true,
                contentPadding: const EdgeInsets.only(bottom: 10),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: accent.withOpacity(0.4), width: 1.5)),
                errorBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: _C.rose, width: 1.5)),
                focusedErrorBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: _C.rose, width: 1.5)),
                errorStyle: const TextStyle(fontSize: 10, color: _C.rose),
              ),
              validator: validator,
            ),
            const SizedBox(height: 6),
          ])),
        ]),
      ),
      if (!isLast) Divider(height: 1, indent: 64, endIndent: 16, color: _C.border),
    ]);
  }

  /// Date field row inside a card
  Widget _buildDateField() => Column(children: [
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
                color: _C.amber.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.cake_outlined, color: _C.amber, size: 18),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: GestureDetector(
          onTap: _pickDate,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 10),
            const Text('Date of Birth', style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700,
                color: _C.amber, letterSpacing: 0.2)),
            const SizedBox(height: 4),
            AbsorbPointer(child: TextFormField(
              controller: _dobCtrl,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600,
                  color: _C.textPri, height: 1.4),
              decoration: const InputDecoration(
                hintText: 'Tap to select date',
                hintStyle: TextStyle(color: _C.textTer, fontSize: 13),
                isDense: true,
                contentPadding: EdgeInsets.only(bottom: 10),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                errorStyle: TextStyle(fontSize: 10, color: _C.rose),
                suffixIcon: Icon(Icons.calendar_today_rounded,
                    color: _C.textTer, size: 15),
                suffixIconConstraints: BoxConstraints(minWidth: 0, minHeight: 0),
              ),
            )),
            const SizedBox(height: 6),
          ]),
        )),
      ]),
    ),
  ]);

  /// Standalone numeric field (not inside a group card)
  Widget _buildNumericField({
    required TextEditingController ctrl,
    required String label,
    required String unit,
    required IconData icon,
    required Color accent,
  }) => Container(
    decoration: BoxDecoration(
        color: _C.card, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _C.border),
        boxShadow: [BoxShadow(color: MedicColors.forest.withOpacity(0.025),
            blurRadius: 8, offset: const Offset(0, 2))]),
    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Container(
          width: 34, height: 34,
          decoration: BoxDecoration(
              color: accent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(9)),
          child: Icon(icon, color: accent, size: 17),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w700,
            color: accent, letterSpacing: 0.2)),
        const SizedBox(height: 3),
        TextFormField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
          style: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.w700,
              color: _C.textPri),
          decoration: InputDecoration(
            hintText: '0',
            hintStyle: const TextStyle(color: _C.textTer),
            isDense: true,
            contentPadding: EdgeInsets.zero,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: accent.withOpacity(0.4), width: 1.5)),
            suffix: Text(unit, style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: accent)),
          ),
        ),
      ])),
    ]),
  );

  /// Standalone field (not inside group card)
  Widget _buildStandaloneField({
    required TextEditingController ctrl,
    required String label,
    required String hint,
    required IconData icon,
    required Color accent,
    int maxLines = 1,
  }) => Container(
    decoration: BoxDecoration(
        color: _C.card, borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _C.border),
        boxShadow: [BoxShadow(color: MedicColors.forest.withOpacity(0.025),
            blurRadius: 10, offset: const Offset(0, 3))]),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
              color: accent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: accent, size: 18),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 12),
        Text(label, style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w700,
            color: accent, letterSpacing: 0.2)),
        const SizedBox(height: 4),
        TextFormField(
          controller: ctrl,
          maxLines: maxLines,
          style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w600,
              color: _C.textPri, height: 1.5),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: _C.textTer, fontSize: 13),
            isDense: true,
            contentPadding: const EdgeInsets.only(bottom: 12),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: accent.withOpacity(0.4), width: 1.5)),
          ),
        ),
      ])),
    ]),
  );

  // ── BMI card ─────────────────────────────────────────────────────────────────
  Widget _buildBmiCard(double bmi) {
    final color = _bmiColor(bmi);
    final label = _bmiLabel(bmi);
    final pos   = ((bmi - 15) / 25).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: _C.card, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3)),
          boxShadow: [BoxShadow(color: color.withOpacity(0.08),
              blurRadius: 12, offset: const Offset(0, 4))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 36, height: 36,
              decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.calculate_rounded, color: color, size: 18)),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Your BMI', style: TextStyle(
                fontSize: 11, color: _C.textTer,
                fontWeight: FontWeight.w600, letterSpacing: 0.3)),
            const SizedBox(height: 2),
            Text(bmi.toStringAsFixed(1), style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.w700,
                color: color, letterSpacing: -0.5)),
          ]),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(24)),
            child: Text(label, style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
          ),
        ]),
        const SizedBox(height: 12),
        ClipRRect(borderRadius: BorderRadius.circular(4),
            child: SizedBox(height: 6, child: Row(children: [
              Expanded(flex: 2, child: Container(color: _C.sky)),
              Expanded(flex: 3, child: Container(color: _C.teal)),
              Expanded(flex: 2, child: Container(color: _C.amber)),
              Expanded(flex: 2, child: Container(color: _C.rose)),
            ]))),
        const SizedBox(height: 4),
        LayoutBuilder(builder: (_, c) => Stack(children: [
          const SizedBox(height: 12),
          Positioned(
            left: (c.maxWidth * pos - 5).clamp(0.0, c.maxWidth - 10),
            child: Container(width: 10, height: 10,
                decoration: BoxDecoration(color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: _C.textPri, width: 2.5))),
          ),
        ])),
        const SizedBox(height: 2),
        const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('15',   style: TextStyle(fontSize: 9, color: _C.textTer)),
          Text('18.5', style: TextStyle(fontSize: 9, color: _C.textTer)),
          Text('25',   style: TextStyle(fontSize: 9, color: _C.textTer)),
          Text('30',   style: TextStyle(fontSize: 9, color: _C.textTer)),
          Text('40',   style: TextStyle(fontSize: 9, color: _C.textTer)),
        ]),
      ]),
    );
  }

  // ── Panel card ────────────────────────────────────────────────────────────────
  Widget _buildPanelCard({
    required IconData icon, required Color accent,
    required String title, required String subtitle,
    required Widget child, Widget? trailing,
  }) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
        color: _C.card, borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _C.border),
        boxShadow: [BoxShadow(color: MedicColors.forest.withOpacity(0.025),
            blurRadius: 10, offset: const Offset(0, 3))]),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 36, height: 36,
            decoration: BoxDecoration(
                color: accent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: accent, size: 18)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w700, color: _C.textPri)),
          Text(subtitle, style: const TextStyle(
              fontSize: 11, color: _C.textTer, fontWeight: FontWeight.w500)),
        ])),
        if (trailing != null) trailing,
      ]),
      const SizedBox(height: 14),
      child,
    ]),
  );

  // ── Gender picker ─────────────────────────────────────────────────────────────
  Widget _buildGenderPicker() {
    const options = [
      {'label': 'Male',   'icon': Icons.male_rounded},
      {'label': 'Female', 'icon': Icons.female_rounded},
      {'label': 'Other',  'icon': Icons.transgender_rounded},
    ];
    return Row(
      children: options.asMap().entries.map((e) {
        final label = e.value['label'] as String;
        final icon  = e.value['icon']  as IconData;
        final on    = _gender == label;
        final isLast = e.key == options.length - 1;
        return Expanded(child: Padding(
          padding: EdgeInsets.only(right: isLast ? 0 : 10),
          child: GestureDetector(
            onTap: () { HapticFeedback.selectionClick(); setState(() => _gender = label); },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: on ? _C.teal : _C.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: on ? _C.teal : _C.border, width: on ? 0 : 1.5),
                boxShadow: on ? [BoxShadow(color: _C.teal.withOpacity(0.3),
                    blurRadius: 10, offset: const Offset(0, 4))]
                    : [BoxShadow(color: MedicColors.forest.withOpacity(0.025),
                    blurRadius: 8, offset: const Offset(0, 2))],
              ),
              child: Column(children: [
                Icon(icon, size: 28, color: on ? Colors.white : _C.textSec),
                const SizedBox(height: 6),
                Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                    color: on ? Colors.white : _C.textSec)),
              ]),
            ),
          ),
        ));
      }).toList(),
    );
  }

  // ── Blood type picker ──────────────────────────────────────────────────────────
  Widget _buildBloodTypePicker() => Wrap(
    spacing: 8, runSpacing: 8,
    children: _bloodTypes.map((bt) {
      final on = _bloodType == bt;
      return GestureDetector(
        onTap: () { HapticFeedback.selectionClick(); setState(() => _bloodType = bt); },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 58, height: 44,
          decoration: BoxDecoration(
            color: on ? _C.rose : _C.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: on ? _C.rose : _C.border, width: on ? 0 : 1.5),
            boxShadow: on ? [BoxShadow(color: _C.rose.withOpacity(0.25),
                blurRadius: 8, offset: const Offset(0, 3))] : [],
          ),
          child: Center(child: Text(bt, style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w700,
              color: on ? Colors.white : _C.textSec))),
        ),
      );
    }).toList(),
  );

  // ── Conditions picker ─────────────────────────────────────────────────────────
  Widget _buildConditionsPicker() => Wrap(
    spacing: 8, runSpacing: 8,
    children: _conditionList.map((item) {
      final label = item['label'] as String;
      final icon  = item['icon']  as IconData;
      final on    = _conditions.contains(label);
      return GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() {
            on ? _conditions.remove(label) : _conditions.add(label);
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: on ? _C.violet : _C.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: on ? _C.violet : _C.border, width: on ? 0 : 1.5),
            boxShadow: on ? [BoxShadow(color: _C.violet.withOpacity(0.25),
                blurRadius: 8, offset: const Offset(0, 3))] : [],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 14, color: on ? Colors.white : _C.textSec),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                color: on ? Colors.white : _C.textSec)),
          ]),
        ),
      );
    }).toList(),
  );

  // ── Save button ───────────────────────────────────────────────────────────────
  Widget _buildSaveButton() => GestureDetector(
    onTap: _saving ? null : _save,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: 56, width: double.infinity,
      decoration: BoxDecoration(
        color: _saving ? _C.teal.withOpacity(0.6) : _C.teal,
        borderRadius: BorderRadius.circular(22),
        boxShadow: _saving ? [] : [BoxShadow(
            color: _C.teal.withOpacity(0.35),
            blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Center(child: _saving
          ? const SizedBox(width: 24, height: 24,
          child: CircularProgressIndicator(strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
          : const Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.check_rounded, color: Colors.white, size: 22),
        SizedBox(width: 10),
        Text('Save Changes', style: TextStyle(
            fontSize: 16, fontWeight: FontWeight.w700,
            color: Colors.white, letterSpacing: 0.3)),
      ])),
    ),
  );
}

// ─── Mesh Painter ─────────────────────────────────────────────────────────────
class _MeshPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(Offset(size.width * 0.9, size.height * 0.2), 120,
        Paint()..color = _C.teal.withOpacity(0.07));
    canvas.drawCircle(Offset(size.width * 0.05, size.height * 0.85), 80,
        Paint()..color = const Color(0xFF4FACFE).withOpacity(0.06));
  }
  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}