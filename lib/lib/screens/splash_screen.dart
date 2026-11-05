import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../design/medic_design.dart';
import 'auth/login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  Timer? _timer;

  // Drives the slow radar-style sweep behind the logo and the staggered
  // reveal of the eyebrow/title/tagline below it. One controller for the
  // whole screen keeps the motion coordinated instead of several clocks
  // drifting out of sync.
  late final AnimationController _bgCtrl = AnimationController(
      duration: const Duration(seconds: 9), vsync: this)..repeat();
  late final AnimationController _revealCtrl = AnimationController(
      duration: const Duration(milliseconds: 1100), vsync: this)..forward();

  @override
  void initState() {
    super.initState();
    // Long enough for the elastic logo settle + staggered text reveal to
    // finish reading comfortably before handing off to the login screen.
    _timer = Timer(const Duration(milliseconds: 2300), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(PageRouteBuilder(
        pageBuilder: (_, __, ___) => const LoginScreen(),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 350),
      ));
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _bgCtrl.dispose();
    _revealCtrl.dispose();
    super.dispose();
  }

  /// A single 0→1 reveal value sliced into per-item windows so the eyebrow,
  /// title and tagline fade/slide in one after another instead of all at
  /// once — a cheap way to stagger without a separate controller per line.
  double _stagger(double t, double start, double end) =>
      Curves.easeOut.transform(((t - start) / (end - start)).clamp(0.0, 1.0));

  Widget _revealItem({required double start, required double end, required Widget child}) =>
      AnimatedBuilder(
        animation: _revealCtrl,
        builder: (_, c) {
          final v = _stagger(_revealCtrl.value, start, end);
          return Opacity(opacity: v,
              child: Transform.translate(offset: Offset(0, 14 * (1 - v)), child: c));
        },
        child: child,
      );

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.light,
    child: Scaffold(backgroundColor: MedicColors.forest,
      body: Stack(children: [
        Positioned.fill(child: AnimatedBuilder(
          animation: _bgCtrl,
          builder: (_, __) => CustomPaint(painter: _SplashOrbitPainter(_bgCtrl.value)),
        )),
        SafeArea(child: Padding(padding: const EdgeInsets.all(28),
          child: Column(children: [
            Align(alignment: Alignment.centerLeft,
              child: _revealItem(start: 0.0, end: 0.45,
                child: const MedicEyebrow('Everyday care, considered.', light: true))),
            Expanded(child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const MedicMarkHero(size: 104),
              const SizedBox(height: 30),
              _revealItem(start: 0.15, end: 0.65,
                child: const Text('MedicTrack', style: TextStyle(color: Colors.white,
                  fontFamily: 'serif', fontSize: 42, letterSpacing: -1))),
              const SizedBox(height: 12),
              _revealItem(start: 0.35, end: 0.9,
                child: const Text('A little care. Every day.',
                  style: TextStyle(color: Color(0xFFCDDCD4), fontSize: 15))),
            ]))),
            const SizedBox(width: 22, height: 22,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: MedicColors.mint)),
            const SizedBox(height: 22),
            _revealItem(start: 0.5, end: 1.0,
              child: const MedicEyebrow('Your personal care companion', light: true)),
          ]))),
      ])),
  );
}

/// Splash-only animated take on the shared [MedicOrbitPainter]: the same
/// quiet concentric rings, but slowly sweeping like a radar so the launch
/// screen feels alive instead of a static image. Kept local to this file —
/// [MedicOrbitPainter] itself stays untouched so every other screen that
/// shares it via [MedicHeaderSurface] is unaffected.
class _SplashOrbitPainter extends CustomPainter {
  final double t; // 0..1, looping
  const _SplashOrbitPainter(this.t);
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * .96, size.height * .18);
    final ringPen = Paint()..color = MedicColors.mint.withOpacity(.10)
      ..style = PaintingStyle.stroke..strokeWidth = 1;
    for (final r in [65.0, 100.0, 135.0, 170.0]) {
      canvas.drawCircle(center, r, ringPen);
    }
    // A soft sweeping arc layered on top of the static rings — subtle, not
    // a literal radar scanline, just enough motion to read as "alive".
    final sweepPen = Paint()..style = PaintingStyle.stroke..strokeWidth = 2
      ..shader = SweepGradient(
        startAngle: 0, endAngle: 6.28318,
        transform: GradientRotation(t * 6.28318),
        colors: [Colors.transparent, MedicColors.mint.withOpacity(.26), Colors.transparent],
        stops: const [0.0, 0.08, 0.22],
      ).createShader(Rect.fromCircle(center: center, radius: 170));
    canvas.drawCircle(center, 170, sweepPen);
  }
  @override
  bool shouldRepaint(covariant _SplashOrbitPainter oldDelegate) => oldDelegate.t != t;
}
