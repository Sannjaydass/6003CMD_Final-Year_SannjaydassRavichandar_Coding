import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:medictrack/design/medic_design.dart';
import '../../services/auth_service.dart';
import '../home/home_screen.dart';
import 'onboarding_setup_screen.dart';
import 'login_screen.dart';

// ─── Design Tokens ────────────────────────────────────────────────────────────
class _C {
  static const navy    = MedicColors.c142F2B;
  static const teal    = MedicColors.c28715D;
  static const amber   = MedicColors.cB77A27;
  static const rose    = MedicColors.cC05256;
}

/// Shown right after signup (and whenever a verified-only screen is blocked
/// by an unverified session — see HomeScreen's routing). The account
/// already exists and the person is already signed in at this point; they
/// just can't reach the rest of the app until they click the link Firebase
/// just emailed them. This screen gives them a live "I've verified" check,
/// a resend button with a short cooldown so it can't be spammed, and a way
/// back out if they want to use a different email.
class VerifyEmailScreen extends StatefulWidget {
  final String email;
  // Where to land once verification is confirmed. 'patient' signups go
  // through the onboarding wizard; 'dependant' signups and ordinary
  // logins go straight to the dashboard.
  final String accountType;
  const VerifyEmailScreen({super.key, required this.email, this.accountType = 'patient'});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> with SingleTickerProviderStateMixin {
  final _auth = AuthService();
  bool _checking = false;
  bool _resending = false;
  int _cooldown = 0;
  Timer? _cooldownTimer;
  Timer? _autoCheckTimer;

  late final AnimationController _fadeCtrl =
      AnimationController(duration: const Duration(milliseconds: 500), vsync: this)..forward();
  late final Animation<double> _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);

  @override
  void initState() {
    super.initState();
    // Quietly re-checks every few seconds so someone who verifies from
    // their email app and swipes straight back to MedicTrack lands on
    // their dashboard without having to remember to tap "Continue".
    _autoCheckTimer = Timer.periodic(const Duration(seconds: 4), (_) => _checkVerified(silent: true));
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _autoCheckTimer?.cancel();
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _startCooldown() {
    setState(() => _cooldown = 30);
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      if (_cooldown <= 1) { t.cancel(); setState(() => _cooldown = 0); }
      else { setState(() => _cooldown -= 1); }
    });
  }

  Future<void> _resend() async {
    setState(() => _resending = true);
    final result = await _auth.resendVerificationEmailForCurrentUser();
    if (!mounted) return;
    setState(() => _resending = false);
    _snack(result['message'], error: !result['success']);
    if (result['success'] == true) _startCooldown();
  }

  Future<void> _checkVerified({bool silent = false}) async {
    if (_checking) return;
    setState(() => _checking = true);
    final verified = await _auth.checkEmailVerified();
    if (!mounted) return;
    setState(() => _checking = false);
    if (verified) {
      _autoCheckTimer?.cancel();
      HapticFeedback.mediumImpact();
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => widget.accountType == 'patient'
            ? const OnboardingSetupScreen() : const HomeScreen()),
        (_) => false,
      );
    } else if (!silent) {
      _snack("Still not verified — tap the link in the email first.", error: true);
    }
  }

  Future<void> _useDifferentAccount() async {
    await _auth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  void _snack(String msg, {required bool error}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(error ? Icons.error_outline_rounded : Icons.check_circle_rounded,
            color: Colors.white, size: 16),
        const SizedBox(width: 10),
        Expanded(child: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
      ]),
      backgroundColor: error ? _C.rose : _C.navy,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.all(16),
    ));
  }

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.light,
    child: Scaffold(
      backgroundColor: _C.navy,
      body: SafeArea(child: Center(child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: FadeTransition(opacity: _fadeAnim,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const MedicMarkHero(size: 88),
            const SizedBox(height: 32),
            const Text('Verify your email', style: TextStyle(
                fontFamily: 'serif', color: Colors.white, fontSize: 28,
                letterSpacing: -.6)),
            const SizedBox(height: 12),
            Text.rich(TextSpan(children: [
              const TextSpan(text: "We've sent a verification link to "),
              TextSpan(text: widget.email, style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
              const TextSpan(text: '. Open it, then come back here — this screen updates itself once it\'s confirmed.'),
            ]), textAlign: TextAlign.center, style: const TextStyle(
                color: Color(0xFFCDDCD4), fontSize: 13.5, height: 1.6)),
            const SizedBox(height: 36),
            SizedBox(width: double.infinity, height: 54, child: ElevatedButton(
              onPressed: _checking ? null : () => _checkVerified(),
              style: ElevatedButton.styleFrom(backgroundColor: _C.teal,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
              child: _checking
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text("I've verified — Continue", style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
            )),
            const SizedBox(height: 14),
            TextButton(
              onPressed: (_resending || _cooldown > 0) ? null : _resend,
              child: Text(
                _cooldown > 0 ? 'Resend email (${_cooldown}s)'
                    : _resending ? 'Sending…' : 'Resend verification email',
                style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
            const SizedBox(height: 24),
            TextButton(
              onPressed: _useDifferentAccount,
              child: const Text('Use a different account',
                  style: TextStyle(color: Colors.white38, fontSize: 12.5)),
            ),
          ]),
        ),
      ))),
    ),
  );
}
