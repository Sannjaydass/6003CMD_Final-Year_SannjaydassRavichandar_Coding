import 'package:medictrack/design/medic_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../home/home_screen.dart';
import 'signup_screen.dart';
import '../../services/auth_service.dart';

// ─── Design Tokens ────────────────────────────────────────────────────────────
class _C {
  static const navy      = MedicColors.c142F2B;
  static const navyMid   = MedicColors.c23473E;
  static const teal      = MedicColors.c28715D;
  static const tealDark  = MedicColors.c1D5849;
  static const sky       = MedicColors.c477C91;
  static const amber     = MedicColors.cB77A27;
  static const rose      = MedicColors.cC05256;
  static const surface   = MedicColors.cF6F5F0;
  static const card      = MedicColors.cFFFFFF;
  static const border    = MedicColors.cE2E5DC;
  static const textPri   = MedicColors.c142F2B;
  static const textSec   = MedicColors.c63756D;
  static const textTer   = MedicColors.c83938B;
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey           = GlobalKey<FormState>();
  final _emailCtrl         = TextEditingController();
  final _passwordCtrl      = TextEditingController();
  final AuthService _auth  = AuthService();

  bool _obscure         = true;
  bool _loading         = false;
  bool _rememberMe      = false;
  bool _autoLoggingIn   = false;

  static const _kRemember  = 'remember_me';
  static const _kEmail     = 'saved_email';
  static const _kPassword  = 'saved_password';

  late AnimationController _animCtrl;
  late Animation<double>   _fadeAnim;
  late Animation<Offset>   _slideAnim;

  // ── Lifecycle ───────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);

    _animCtrl = AnimationController(
        duration: const Duration(milliseconds: 900), vsync: this);
    _fadeAnim  = CurvedAnimation(parent: _animCtrl, curve: Curves.easeIn);
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero)
        .animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));
    _animCtrl.forward();

    _checkAutoLogin();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  // ── Auto-login ──────────────────────────────────────────────────────────────
  Future<void> _checkAutoLogin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final remember = prefs.getBool(_kRemember) ?? false;
      if (!remember) return;

      final email    = prefs.getString(_kEmail)    ?? '';
      final password = prefs.getString(_kPassword) ?? '';

      if (email.isEmpty || password.isEmpty) {
        if (mounted) setState(() {
          _rememberMe = remember;
          _emailCtrl.text    = email;
          _passwordCtrl.text = password;
        });
        return;
      }

      if (mounted) setState(() {
        _autoLoggingIn = true;
        _rememberMe    = true;
        _emailCtrl.text    = email;
        _passwordCtrl.text = password;
      });

      await _performAutoLogin(email, password);
    } catch (_) {
      if (mounted) setState(() => _autoLoggingIn = false);
    }
  }

  Future<void> _performAutoLogin(String email, String password) async {
    try {
      final result = await _auth.signIn(email: email, password: password);
      if (!mounted) return;
      if (result['success']) {
        await _navigateAfterLogin();
      } else if (result['emailNotVerified'] == true) {
        // Credentials are still correct — just stop the auto-login spinner
        // and let them pick up the resend flow from the ordinary login
        // form, instead of wiping the saved "remember me" credentials for
        // what isn't actually a wrong-password/expired-session failure.
        setState(() => _autoLoggingIn = false);
        _handleUnverifiedLogin(email, password);
      } else {
        await _clearSaved();
        setState(() { _autoLoggingIn = false; _rememberMe = false; _passwordCtrl.clear(); });
        _showSnack('Session expired. Please sign in again.', color: _C.amber);
      }
    } catch (_) {
      if (mounted) setState(() => _autoLoggingIn = false);
    }
  }

  Future<void> _saveCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    if (_rememberMe) {
      await prefs.setBool(_kRemember,  true);
      await prefs.setString(_kEmail,    _emailCtrl.text.trim());
      await prefs.setString(_kPassword, _passwordCtrl.text.trim());
    } else {
      await _clearSaved();
    }
  }

  Future<void> _clearSaved() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kRemember, false);
    await prefs.remove(_kEmail);
    await prefs.remove(_kPassword);
  }

  // ── Login ───────────────────────────────────────────────────────────────────
  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    HapticFeedback.mediumImpact();
    setState(() => _loading = true);

    final result = await _auth.signIn(
      email:    _emailCtrl.text.trim(),
      password: _passwordCtrl.text.trim(),
    );

    if (!mounted) return;
    if (result['success']) {
      await _saveCredentials();
      await _navigateAfterLogin();
    } else {
      setState(() => _loading = false);
      if (result['emailNotVerified'] == true) {
        _handleUnverifiedLogin(_emailCtrl.text.trim(), _passwordCtrl.text.trim());
      } else {
        _showSnack(result['message'], color: _C.rose);
      }
    }
  }

  Future<void> _navigateAfterLogin() async {
    final user = _auth.currentUser;
    if (user == null) return;
    if (!mounted) return;
    setState(() => _loading = false);
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()));
  }

  // ── Forgot password ─────────────────────────────────────────────────────────
  Future<void> _handleForgotPassword() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      _showSnack('Enter your email address first', color: _C.amber);
      return;
    }
    setState(() => _loading = true);
    final result = await _auth.resetPassword(email: email);
    if (mounted) {
      setState(() => _loading = false);
      _showSnack(result['message'],
          color: result['success'] ? _C.teal : _C.rose);
    }
  }

  // ── Snack ───────────────────────────────────────────────────────────────────
  void _showSnack(String msg, {required Color color, SnackBarAction? action}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(
          color == _C.rose ? Icons.error_outline_rounded
              : color == _C.amber ? Icons.info_outline_rounded
              : Icons.check_circle_rounded,
          color: Colors.white, size: 16,
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(msg, style: const TextStyle(
            fontWeight: FontWeight.w600, fontSize: 13))),
      ]),
      backgroundColor: _C.navy,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.all(16),
      duration: action != null ? const Duration(seconds: 6) : const Duration(seconds: 4),
      action: action,
    ));
  }

  /// Account exists and the password was correct, but the email link
  /// hasn't been clicked yet. Offers a one-tap "Resend" right on the snack
  /// instead of sending the person hunting for another way to get the
  /// email again.
  void _handleUnverifiedLogin(String email, String password) {
    _showSnack('Please verify your email before signing in.', color: _C.amber,
      action: SnackBarAction(
        label: 'RESEND', textColor: Colors.white,
        onPressed: () async {
          final result = await _auth.resendVerificationEmail(email: email, password: password);
          if (!mounted) return;
          _showSnack(result['message'], color: result['success'] ? _C.teal : _C.rose);
        },
      ));
  }

  @override
  Widget build(BuildContext context) {
    if (_autoLoggingIn) return _AutoLoginScreen(email: _emailCtrl.text,
      onCancel: () => setState(() => _autoLoggingIn = false));
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(backgroundColor: MedicColors.canvas,
        body: SafeArea(child: Center(child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
            child: FadeTransition(opacity: _fadeAnim,
              child: SlideTransition(position: _slideAnim,
              child: Form(key: _formKey, child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [MedicMark(size: 44), SizedBox(width: 12),
                  Text('MedicTrack', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20, letterSpacing: -.6))]),
                const SizedBox(height: 28),
                Container(width: double.infinity, clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(color: MedicColors.forest, borderRadius: BorderRadius.circular(30)),
                  child: Stack(children: [
                    const Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: MedicOrbitPainter()))),
                    const Padding(padding: EdgeInsets.all(26), child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start, children: [
                      MedicEyebrow('Welcome to everyday care', light: true),
                      SizedBox(height: 22),
                      Text('A calmer way\nto care for you.', style: TextStyle(
                        fontFamily: 'serif', fontSize: 34, height: 1.12, letterSpacing: -.8, color: Colors.white)),
                      SizedBox(height: 18),
                      Text('Medicines, reminders and health insights.\nTogether in one thoughtful space.',
                        style: TextStyle(color: Color(0xFFCDDCD4), fontSize: 13, height: 1.6)),
                    ])),
                  ])),
                const SizedBox(height: 30),
                const Text('Welcome back', style: TextStyle(fontFamily: 'serif', fontSize: 28, color: MedicColors.ink)),
                const SizedBox(height: 6),
                const Text('Sign in to your personal care space.', style: TextStyle(color: MedicColors.muted, fontSize: 14)),
                const SizedBox(height: 24),
                _InputField(controller: _emailCtrl, label: 'Email address', hint: 'you@example.com',
                  icon: Icons.alternate_email_rounded, accent: MedicColors.green,
                  keyboard: TextInputType.emailAddress,
                  validator: (v) => v == null || v.trim().isEmpty ? 'Enter your email address' :
                    !v.contains('@') ? 'Enter a valid email address' : null),
                const SizedBox(height: 16),
                _InputField(controller: _passwordCtrl, label: 'Password', hint: 'Enter your password',
                  icon: Icons.lock_outline_rounded, accent: MedicColors.green, obscure: _obscure,
                  suffixIcon: IconButton(tooltip: _obscure ? 'Show password' : 'Hide password',
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      color: MedicColors.muted, size: 21)),
                  validator: (v) => v == null || v.isEmpty ? 'Enter your password' : null),
                const SizedBox(height: 12),
                Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 16, children: [
                    _RememberMeToggle(value: _rememberMe, onChanged: (v) => setState(() => _rememberMe = v)),
                    TextButton(onPressed: _loading ? null : _handleForgotPassword,
                      child: const Text('Forgot password?')),
                  ]),
                const SizedBox(height: 18),
                SizedBox(width: double.infinity, height: 56, child: ElevatedButton(
                  onPressed: _loading ? null : _handleLogin,
                  style: ElevatedButton.styleFrom(backgroundColor: MedicColors.forest,
                    foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
                  child: _loading ? const SizedBox(width: 22, height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) :
                    const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text('Sign in', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      SizedBox(width: 12), Icon(Icons.arrow_forward_rounded, size: 19),
                    ]))),
                const SizedBox(height: 20),
                Center(child: Wrap(crossAxisAlignment: WrapCrossAlignment.center,
                  alignment: WrapAlignment.center, children: [
                    const Text('New to MedicTrack?', style: TextStyle(color: MedicColors.muted, fontSize: 13)),
                    TextButton(onPressed: _loading ? null : () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const SignupScreen())), child: const Text('Create an account')),
                  ])),
              ])),
              ),
            ),
          ),
        ))),
      ),
    );
  }
}

// ─── Auto-login screen ────────────────────────────────────────────────────────
class _AutoLoginScreen extends StatelessWidget {
  final String email;
  final VoidCallback onCancel;
  const _AutoLoginScreen({required this.email, required this.onCancel});

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.light,
    child: Scaffold(
      backgroundColor: _C.navy,
      body: Stack(children: [
        Positioned.fill(child: CustomPaint(painter: _BgPainter())),
        Center(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: MedicFadeIn(duration: const Duration(milliseconds: 500),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Brand mark — same animated hero used on the splash screen, so
            // this hand-off screen reads as a continuation of it rather
            // than a different, generic "loading" screen.
            const MedicMarkHero(size: 84),
            const SizedBox(height: 28),
            const Text('Signing you in…', style: TextStyle(
                color: Colors.white, fontSize: 22,
                fontWeight: FontWeight.w700, letterSpacing: -0.4)),
            const SizedBox(height: 8),
            Text(email, style: TextStyle(
                color: Colors.white.withOpacity(0.4),
                fontSize: 13, fontWeight: FontWeight.w500)),
            const SizedBox(height: 36),

            // Progress — no `value` set, so Flutter animates this bar on
            // its own (indeterminate), matching how long sign-in actually
            // takes instead of faking a fixed-length fill.
            SizedBox(width: 200,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    backgroundColor: Colors.white.withOpacity(0.08),
                    valueColor: const AlwaysStoppedAnimation<Color>(_C.teal),
                    minHeight: 3,
                  ),
                )),
            const SizedBox(height: 40),

            // Cancel
            GestureDetector(
              onTap: onCancel,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withOpacity(0.12)),
                ),
                child: Text('Cancel', style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            ),
          ]),
        ))),
      ]),
    ),
  );
}

// ─── Input Field ──────────────────────────────────────────────────────────────
class _InputField extends StatelessWidget {
  final TextEditingController controller;
  final String label, hint;
  final IconData icon;
  final Color accent;
  final TextInputType? keyboard;
  final bool obscure;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;

  const _InputField({
    required this.controller, required this.label, required this.hint,
    required this.icon, required this.accent,
    this.keyboard, this.obscure = false, this.suffixIcon, this.validator,
  });

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: _C.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _C.border, width: 1.5),
    ),
    child: TextFormField(
      controller:    controller,
      keyboardType:  keyboard,
      obscureText:   obscure,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
          color: _C.textPri),
      decoration: InputDecoration(
        labelText:   label,
        hintText:    hint,
        labelStyle:  TextStyle(color: accent, fontSize: 12,
            fontWeight: FontWeight.w700),
        hintStyle:   const TextStyle(color: _C.textTer, fontSize: 13),
        prefixIcon:  Padding(
          padding: const EdgeInsets.all(12),
          child: Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
                color: accent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(9)),
            child: Icon(icon, color: accent, size: 17),
          ),
        ),
        suffixIcon:  suffixIcon != null
            ? Padding(
          padding: const EdgeInsets.only(right: 4),
          child: suffixIcon,
        ) : null,
        border:             InputBorder.none,
        contentPadding: const EdgeInsets.fromLTRB(0, 15, 16, 15),
        errorStyle: const TextStyle(fontSize: 11, color: _C.rose),
      ),
      validator: validator,
    ),
  );
}

// ─── Remember Me Toggle ───────────────────────────────────────────────────────
class _RememberMeToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _RememberMeToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () { HapticFeedback.selectionClick(); onChanged(!value); },
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: value ? _C.teal.withOpacity(0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: value ? _C.teal.withOpacity(0.4) : _C.border,
            width: 1.5),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
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
        const SizedBox(width: 8),
        Text('Remember me', style: TextStyle(
            color: value ? _C.teal : _C.textSec,
            fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    ),
  );
}

// ─── Sign In Button ───────────────────────────────────────────────────────────
class _SignInButton extends StatelessWidget {
  final bool loading;
  final VoidCallback onTap;
  const _SignInButton({required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: loading ? null : onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: 54,
      decoration: BoxDecoration(
        color: loading ? _C.teal.withOpacity(0.6) : _C.teal,
        borderRadius: BorderRadius.circular(16),
        boxShadow: loading ? [] : [
          BoxShadow(color: _C.teal.withOpacity(0.35),
              blurRadius: 20, offset: const Offset(0, 8)),
        ],
      ),
      child: Center(child: loading
          ? const SizedBox(width: 22, height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
          : const Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.login_rounded, color: Colors.white, size: 20),
        SizedBox(width: 10),
        Text('Sign In', style: TextStyle(
            color: Colors.white, fontSize: 16,
            fontWeight: FontWeight.w700, letterSpacing: 0.3)),
      ])),
    ),
  );
}

// ─── Background Painter ───────────────────────────────────────────────────────
class _BgPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(Offset(size.width * 0.88, size.height * 0.08), 200,
        Paint()..color = _C.teal.withOpacity(0.07));
    canvas.drawCircle(Offset(size.width * 0.05, size.height * 0.6), 160,
        Paint()..color = _C.sky.withOpacity(0.05));
    canvas.drawCircle(Offset(size.width * 0.75, size.height * 0.88), 120,
        Paint()..color = _C.teal.withOpacity(0.05));
  }
  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}