import 'package:medictrack/design/medic_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../home/home_screen.dart';
import 'onboarding_setup_screen.dart';
import 'verify_email_screen.dart';
import '../../services/auth_service.dart';

// ─── Design Tokens ────────────────────────────────────────────────────────────
class _C {
  static const navy     = MedicColors.c142F2B;
  static const navyMid  = MedicColors.c23473E;
  static const teal     = MedicColors.c28715D;
  static const tealDark = MedicColors.c1D5849;
  static const sky      = MedicColors.c477C91;
  static const amber    = MedicColors.cB77A27;
  static const rose     = MedicColors.cC05256;
  static const violet   = MedicColors.c78659B;
  static const surface  = MedicColors.cF6F5F0;
  static const card     = MedicColors.cFFFFFF;
  static const border   = MedicColors.cE2E5DC;
  static const textPri  = MedicColors.c142F2B;
  static const textSec  = MedicColors.c63756D;
  static const textTer  = MedicColors.c83938B;
}

class SignupScreen extends StatefulWidget {
  const SignupScreen({Key? key}) : super(key: key);

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen>
    with SingleTickerProviderStateMixin {
  final _formKey      = GlobalKey<FormState>();
  final _nameCtrl      = TextEditingController();
  final _ageCtrl       = TextEditingController();
  final _heightCtrl    = TextEditingController();
  final _weightCtrl    = TextEditingController();
  final _emailCtrl     = TextEditingController();
  final _passwordCtrl  = TextEditingController();
  final _confirmCtrl   = TextEditingController();
  final AuthService _auth = AuthService();

  bool _obscurePass    = true;
  bool _obscureConfirm = true;
  bool _agreeTerms     = false;
  bool _loading        = false;

  // 'patient' tracks their own vitals/medicines/health score. 'dependant'
  // is for someone creating their OWN login to manage another person's
  // medicines (see the Dependants/caregiver feature) — that account never
  // gets asked for personal vitals or a health score.
  String _accountType = 'patient';
  static const _conditionOptions = [
    'Stroke', 'Heart disease', 'Diabetes', 'Hypertension', 'Hypoglycemia',
  ];
  final Set<String> _conditions = {};

  late AnimationController _animCtrl;
  late Animation<double>   _fadeAnim;
  late Animation<Offset>   _slideAnim;

  // ── Lifecycle ───────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
    _animCtrl = AnimationController(
        duration: const Duration(milliseconds: 800), vsync: this);
    _fadeAnim  = CurvedAnimation(parent: _animCtrl, curve: Curves.easeIn);
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.18), end: Offset.zero)
        .animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));
    _animCtrl.forward();
  }

  @override
  void dispose() {
    for (final c in [_nameCtrl, _ageCtrl, _heightCtrl, _weightCtrl,
      _emailCtrl, _passwordCtrl, _confirmCtrl]) c.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  // ── Signup ──────────────────────────────────────────────────────────────────
  Future<void> _handleSignup() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_agreeTerms) {
      _showSnack('Please agree to the Terms & Conditions', color: _C.amber);
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() => _loading = true);

    final result = await _auth.signUp(
      email:    _emailCtrl.text.trim(),
      password: _passwordCtrl.text.trim(),
      fullName: _nameCtrl.text.trim(),
      age:      int.tryParse(_ageCtrl.text.trim()),
      height:   double.tryParse(_heightCtrl.text.trim()),
      weight:   double.tryParse(_weightCtrl.text.trim()),
      accountType: _accountType,
      conditions: _conditions.toList(),
    );

    if (!mounted) return;
    setState(() => _loading = false);

    if (result['success']) {
      // Email verification is required before the account can be used —
      // VerifyEmailScreen remembers which screen to continue to once it's
      // confirmed (the onboarding wizard for a patient, straight to the
      // dashboard for a dependant/caregiver).
      if (result['needsVerification'] == true) {
        Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => VerifyEmailScreen(
                email: _emailCtrl.text.trim(), accountType: _accountType)),
            (_) => false);
        return;
      }
      // Dependant/caregiver accounts skip the health-setup wizard entirely
      // — they manage medicines only, nothing there applies to them.
      Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => _accountType == 'patient'
              ? const OnboardingSetupScreen() : const HomeScreen()),
          (_) => false);
    } else {
      _showSnack(result['message'], color: _C.rose);
    }
  }

  void _showSnack(String msg, {required Color color}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(color == _C.rose ? Icons.error_outline_rounded
            : color == _C.amber ? Icons.info_outline_rounded
            : Icons.check_circle_rounded,
            color: Colors.white, size: 16),
        const SizedBox(width: 10),
        Expanded(child: Text(msg, style: const TextStyle(
            fontWeight: FontWeight.w600, fontSize: 13))),
      ]),
      backgroundColor: MedicColors.canvas,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.all(16),
    ));
  }

  // ── Build ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _C.navy,
        body: Stack(children: [
          

          Column(children: [
            _buildHeader(),
            Expanded(
              child: FadeTransition(
                opacity: _fadeAnim,
                child: SlideTransition(
                  position: _slideAnim,
                  child: Form(
                    key: _formKey,
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Form card
                            Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: _C.card,
                                borderRadius: BorderRadius.circular(28),
                                boxShadow: [
                                  BoxShadow(color: Colors.black.withOpacity(0.16),
                                      blurRadius: 24, offset: const Offset(0, 8))
                                ],
                              ),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Card header
                                    Row(children: [
                                      Container(width: 34, height: 34,
                                          decoration: BoxDecoration(
                                              color: _C.teal.withOpacity(0.12),
                                              borderRadius: BorderRadius.circular(10)),
                                          child: const Icon(Icons.person_outline_rounded,
                                              color: _C.teal, size: 17)),
                                      const SizedBox(width: 10),
                                      const Text('Who is this account for?', style: TextStyle(
                                          fontSize: 15, fontWeight: FontWeight.w700,
                                          color: _C.textPri, letterSpacing: -0.3)),
                                    ]),
                                    const SizedBox(height: 14),
                                    Wrap(spacing: 10, runSpacing: 10, children: [
                                      _RoleChip(
                                        label: 'Patient',
                                        subtitle: 'Track my own medicines & health',
                                        icon: Icons.favorite_rounded,
                                        selected: _accountType == 'patient',
                                        onTap: () => setState(() => _accountType = 'patient'),
                                      ),
                                      _RoleChip(
                                        label: 'Dependant / Caregiver',
                                        subtitle: "Manage someone else's medicines",
                                        icon: Icons.volunteer_activism_rounded,
                                        selected: _accountType == 'dependant',
                                        onTap: () => setState(() => _accountType = 'dependant'),
                                      ),
                                    ]),
                                    if (_accountType == 'dependant') Padding(
                                      padding: const EdgeInsets.only(top: 10),
                                      child: Text(
                                        "You won't be asked for personal vitals or a health score — "
                                        "just add and manage medicines. You can still track a patient's "
                                        "health data separately from the Dependants tab once they accept your request.",
                                        style: TextStyle(fontSize: 11.5, height: 1.5, color: _C.textSec)),
                                    ),
                                    const SizedBox(height: 22),

                                    // Name
                                    _Field(
                                      ctrl: _nameCtrl,
                                      label: 'Full Name',
                                      hint:  'Your full name',
                                      icon:  Icons.badge_outlined,
                                      accent: _C.teal,
                                      validator: (v) => (v == null || v.trim().isEmpty)
                                          ? 'This field is required' : null,
                                    ),
                                    const SizedBox(height: 12),

                                    if (_accountType == 'patient') ...[
                                    // Age / Height / Weight are now OPTIONAL — a person can
                                    // create the account first and add these later from
                                    // Profile; the health score simply waits until they're
                                    // filled in, instead of blocking signup on them.
                                    Padding(padding: const EdgeInsets.only(bottom: 10),
                                      child: Text('Optional — needed for your health score, can be added later',
                                        style: TextStyle(fontSize: 11.5, color: _C.textSec))),
                                    Row(children: [
                                      Expanded(child: _Field(
                                        ctrl: _ageCtrl,
                                        label: 'Age (optional)',
                                        hint:  'Years',
                                        icon:  Icons.cake_outlined,
                                        accent: _C.amber,
                                        keyboard: TextInputType.number,
                                        validator: (v) {
                                          if (v == null || v.trim().isEmpty) return null;
                                          final n = int.tryParse(v.trim());
                                          if (n == null || n < 1 || n > 100) return 'Enter a valid age';
                                          return null;
                                        },
                                      )),
                                      const SizedBox(width: 10),
                                      Expanded(child: _Field(
                                        ctrl: _heightCtrl,
                                        label: 'Height (cm, optional)',
                                        hint:  'e.g. 170',
                                        icon:  Icons.height_rounded,
                                        accent: _C.sky,
                                        keyboard: const TextInputType.numberWithOptions(decimal: true),
                                        validator: (v) {
                                          if (v == null || v.trim().isEmpty) return null;
                                          final n = double.tryParse(v.trim());
                                          if (n == null || n < 50 || n > 260) return 'Invalid';
                                          return null;
                                        },
                                      )),
                                    ]),
                                    const SizedBox(height: 12),

                                    _Field(
                                      ctrl: _weightCtrl,
                                      label: 'Weight (kg, optional)',
                                      hint:  'e.g. 65',
                                      icon:  Icons.monitor_weight_outlined,
                                      accent: _C.violet,
                                      keyboard: const TextInputType.numberWithOptions(decimal: true),
                                      validator: (v) {
                                        if (v == null || v.trim().isEmpty) return null;
                                        final n = double.tryParse(v.trim());
                                        if (n == null || n < 2 || n > 400) return 'Invalid';
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 20),

                                    Row(children: [
                                      Container(width: 30, height: 30,
                                          decoration: BoxDecoration(
                                              color: _C.rose.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(9)),
                                          child: const Icon(Icons.medical_information_outlined, color: _C.rose, size: 16)),
                                      const SizedBox(width: 10),
                                      const Text('Health conditions (optional)', style: TextStyle(
                                          fontSize: 15, fontWeight: FontWeight.w700,
                                          color: _C.textPri, letterSpacing: -0.3)),
                                    ]),
                                    const SizedBox(height: 12),
                                    Wrap(spacing: 8, runSpacing: 8, children: [
                                      for (final c in _conditionOptions)
                                        ChoiceChip(
                                          label: Text(c, style: const TextStyle(fontSize: 12)),
                                          selected: _conditions.contains(c),
                                          selectedColor: _C.teal.withOpacity(0.18),
                                          backgroundColor: _C.surface,
                                          side: BorderSide(color: _conditions.contains(c) ? _C.teal : _C.border),
                                          onSelected: (sel) => setState(
                                              () => sel ? _conditions.add(c) : _conditions.remove(c)),
                                        ),
                                    ]),
                                    const SizedBox(height: 20),
                                    ],

                                    Row(children: [
                                      Container(width: 30, height: 30,
                                          decoration: BoxDecoration(
                                              color: _C.sky.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(9)),
                                          child: const Icon(Icons.mail_outline_rounded, color: _C.sky, size: 16)),
                                      const SizedBox(width: 10),
                                      const Text('Account Details', style: TextStyle(
                                          fontSize: 15, fontWeight: FontWeight.w700,
                                          color: _C.textPri, letterSpacing: -0.3)),
                                    ]),
                                    const SizedBox(height: 16),

                                    // Email
                                    _Field(
                                      ctrl: _emailCtrl,
                                      label: 'Email Address',
                                      hint:  'you@example.com',
                                      icon:  Icons.mail_outline_rounded,
                                      accent: _C.sky,
                                      keyboard: TextInputType.emailAddress,
                                      validator: (v) {
                                        if (v == null || v.isEmpty) return 'Email is required';
                                        if (!v.contains('@')) return 'Enter a valid email';
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 12),

                                    // Password
                                    _Field(
                                      ctrl: _passwordCtrl,
                                      label: 'Password',
                                      hint:  '••••••••',
                                      icon:  Icons.lock_outline_rounded,
                                      accent: _C.teal,
                                      obscure: _obscurePass,
                                      suffixIcon: _VisibilityBtn(
                                        obscure: _obscurePass,
                                        onTap: () => setState(() => _obscurePass = !_obscurePass),
                                      ),
                                      validator: (v) {
                                        if (v == null || v.isEmpty) return 'Password is required';
                                        if (v.length < 6) return 'Minimum 6 characters';
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 12),

                                    // Confirm password
                                    _Field(
                                      ctrl: _confirmCtrl,
                                      label: 'Confirm Password',
                                      hint:  '••••••••',
                                      icon:  Icons.lock_outline_rounded,
                                      accent: _C.teal,
                                      obscure: _obscureConfirm,
                                      suffixIcon: _VisibilityBtn(
                                        obscure: _obscureConfirm,
                                        onTap: () => setState(() =>
                                        _obscureConfirm = !_obscureConfirm),
                                      ),
                                      validator: (v) {
                                        if (v == null || v.isEmpty) return 'Please confirm password';
                                        if (v != _passwordCtrl.text) return 'Passwords do not match';
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 20),

                                    // Terms checkbox
                                    _TermsCheckbox(
                                      value: _agreeTerms,
                                      onChanged: (v) =>
                                          setState(() => _agreeTerms = v),
                                    ),
                                    const SizedBox(height: 24),

                                    // Submit button
                                    _SubmitButton(
                                      loading:  _loading,
                                      onTap:    _handleSignup,
                                    ),
                                  ]),
                            ),
                            const SizedBox(height: 24),

                            // Sign in link
                            Center(child: Row(
                                mainAxisSize: MainAxisSize.min, children: [
                              Text('Already have an account? ',
                                  style: TextStyle(
                                      color: Colors.white.withOpacity(0.45),
                                      fontSize: 13)),
                              GestureDetector(
                                onTap: () => Navigator.pop(context),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: _C.teal.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(
                                        color: _C.teal.withOpacity(0.4)),
                                  ),
                                  child: const Text('Sign In', style: TextStyle(
                                      color: _C.teal, fontWeight: FontWeight.w700,
                                      fontSize: 13)),
                                ),
                              ),
                            ])),
                          ]),
                    ),
                  ),
                ),
              ),
            ),
          ]),

          // Loading overlay
          if (_loading)
            Positioned.fill(child: Container(
              color: Colors.black38,
              child: Center(child: Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                    color: _C.card, borderRadius: BorderRadius.circular(22)),
                child: const Center(child: SizedBox(width: 26, height: 26,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: _C.teal))),
              )),
            )),
        ]),
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────────
  Widget _buildHeader() => const MedicPageTitle(
    title: 'Begin your care journey', subtitle: 'Create a space for your everyday health.',
  );
}

// ─── Input Field ──────────────────────────────────────────────────────────────
class _Field extends StatelessWidget {
  final TextEditingController ctrl;
  final String label, hint;
  final IconData icon;
  final Color accent;
  final TextInputType? keyboard;
  final bool obscure;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;

  const _Field({
    required this.ctrl, required this.label, required this.hint,
    required this.icon, required this.accent,
    this.keyboard, this.obscure = false, this.suffixIcon, this.validator,
  });

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
        color: _C.surface, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _C.border, width: 1.5)),
    child: TextFormField(
      controller:   ctrl,
      keyboardType: keyboard,
      obscureText:  obscure,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
          color: _C.textPri),
      decoration: InputDecoration(
        labelText: label,
        hintText:  hint,
        labelStyle: TextStyle(color: accent, fontSize: 12,
            fontWeight: FontWeight.w700),
        hintStyle: const TextStyle(color: _C.textTer, fontSize: 13),
        prefixIcon: Padding(
          padding: const EdgeInsets.all(12),
          child: Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
                color: accent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(9)),
            child: Icon(icon, color: accent, size: 17),
          ),
        ),
        suffixIcon: suffixIcon != null
            ? Padding(padding: const EdgeInsets.only(right: 4), child: suffixIcon)
            : null,
        border: InputBorder.none,
        contentPadding: const EdgeInsets.fromLTRB(0, 15, 16, 15),
        errorStyle: const TextStyle(fontSize: 11, color: _C.rose),
      ),
      validator: validator,
    ),
  );
}

// ─── Role Chip ────────────────────────────────────────────────────────────────
class _RoleChip extends StatelessWidget {
  final String label, subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _RoleChip({required this.label, required this.subtitle, required this.icon,
    required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () { HapticFeedback.selectionClick(); onTap(); },
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 160,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: selected ? _C.teal.withOpacity(0.08) : _C.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: selected ? _C.teal : _C.border, width: selected ? 1.6 : 1.2),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: selected ? _C.teal : _C.textTer, size: 20),
        const SizedBox(height: 8),
        Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700,
            color: selected ? _C.teal : _C.textPri)),
        const SizedBox(height: 3),
        Text(subtitle, style: TextStyle(fontSize: 10.5, height: 1.3, color: _C.textSec)),
      ]),
    ),
  );
}

// ─── Visibility Button ────────────────────────────────────────────────────────
class _VisibilityBtn extends StatelessWidget {
  final bool obscure;
  final VoidCallback onTap;
  const _VisibilityBtn({required this.obscure, required this.onTap});

  @override
  Widget build(BuildContext context) => IconButton(
    icon: Icon(obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
        color: _C.textTer, size: 19),
    onPressed: onTap,
  );
}

// ─── Terms Checkbox ───────────────────────────────────────────────────────────
class _TermsCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _TermsCheckbox({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () { HapticFeedback.selectionClick(); onChanged(!value); },
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: value ? _C.teal.withOpacity(0.07) : _C.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: value ? _C.teal.withOpacity(0.4) : _C.border,
            width: 1.5),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 20, height: 20,
          decoration: BoxDecoration(
            color: value ? _C.teal : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
                color: value ? _C.teal : _C.textTer, width: 1.5),
          ),
          child: value
              ? const Icon(Icons.check_rounded, color: Colors.white, size: 13)
              : null,
        ),
        const SizedBox(width: 12),
        Expanded(child: RichText(
          text: TextSpan(
            text: 'I agree to the ',
            style: const TextStyle(fontSize: 13, color: _C.textSec, height: 1.5),
            children: [
              TextSpan(text: 'Terms & Conditions',
                  style: TextStyle(color: _C.teal, fontWeight: FontWeight.w700,
                      decoration: TextDecoration.underline,
                      decorationColor: _C.teal)),
              const TextSpan(text: ' and '),
              TextSpan(text: 'Privacy Policy',
                  style: TextStyle(color: _C.teal, fontWeight: FontWeight.w700,
                      decoration: TextDecoration.underline,
                      decorationColor: _C.teal)),
            ],
          ),
        )),
      ]),
    ),
  );
}

// ─── Submit Button ────────────────────────────────────────────────────────────
class _SubmitButton extends StatelessWidget {
  final bool loading;
  final VoidCallback onTap;
  const _SubmitButton({required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: loading ? null : onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: 54, width: double.infinity,
      decoration: BoxDecoration(
        color: loading ? _C.teal.withOpacity(0.55) : _C.teal,
        borderRadius: BorderRadius.circular(16),
        boxShadow: loading ? [] : [
          BoxShadow(color: _C.teal.withOpacity(0.32),
              blurRadius: 20, offset: const Offset(0, 8)),
        ],
      ),
      child: Center(child: loading
          ? const SizedBox(width: 22, height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
          : const Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.person_add_rounded, color: Colors.white, size: 19),
        SizedBox(width: 10),
        Text(
          'Create Account',
          style: TextStyle(color: Colors.white,
              fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.2),
        ),
      ])),
    ),
  );
}

// ─── Background Painter ───────────────────────────────────────────────────────
class _BgPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(Offset(size.width * 0.9, size.height * 0.06), 180,
        Paint()..color = _C.teal.withOpacity(0.06));
    canvas.drawCircle(Offset(size.width * 0.05, size.height * 0.5), 140,
        Paint()..color = _C.sky.withOpacity(0.05));
    canvas.drawCircle(Offset(size.width * 0.7, size.height * 0.92), 120,
        Paint()..color = _C.violet.withOpacity(0.05));
  }
  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
