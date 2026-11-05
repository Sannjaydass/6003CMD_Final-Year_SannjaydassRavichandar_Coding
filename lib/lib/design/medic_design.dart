import 'package:flutter/material.dart';

/// MedicTrack Atelier: all screen palettes resolve to these shared tokens.
abstract class MedicColors {
  static const forest = Color(0xFF142F2B);
  static const green = Color(0xFF28715D);
  static const canvas = Color(0xFFF6F5F0);
  static const mint = Color(0xFFD5E9BC);
  static const ink = Color(0xFF142F2B);
  static const muted = Color(0xFF63756D);
  static const line = Color(0xFFE2E5DC);
  static const c142F2B = forest;
  static const c1D5849 = Color(0xFF1D5849);
  static const c23473E = Color(0xFF23473E);
  static const c28715D = green;
  static const c477C91 = Color(0xFF477C91);
  static const c4CAF50 = Color(0xFF4CAF50);
  static const c63756D = muted;
  static const c78659B = Color(0xFF78659B);
  static const c83938B = Color(0xFF83938B);
  static const cB77A27 = Color(0xFFB77A27);
  static const cC05256 = Color(0xFFC05256);
  static const cE2E5DC = line;
  static const cF6F5F0 = canvas;
  static const cFFFFFF = Color(0xFFFFFFFF);
 }

/// The app's real brand mark — a square "glass chip" badge that frames the
/// full-color `assets/applogo.png` so it reads cleanly at any size, on both
/// the dark forest headers and the light canvas screens. Used everywhere the
/// old generic "+" tile used to appear — splash screen, login header, home
/// header, section headers — so swapping the asset updates all of them from
/// one place.
///
/// `applogo.png` ships already cropped to just the icon mark (no wordmark
/// text) and padded to a square transparent canvas, so BoxFit.contain here
/// never stretches or crops it — it just scales.
class MedicMark extends StatelessWidget {
  final double size;
  final bool light;
  const MedicMark({super.key, this.size = 48, this.light = false});
  @override
  Widget build(BuildContext context) => Container(
    width: size, height: size,
    padding: EdgeInsets.all(size * .14),
    decoration: BoxDecoration(
      color: light ? Colors.white.withOpacity(.14) : Colors.white,
      borderRadius: BorderRadius.circular(size * .3),
      border: Border.all(
        color: light ? Colors.white.withOpacity(.24) : MedicColors.line,
        width: 1,
      ),
      boxShadow: light ? null : [
        BoxShadow(color: MedicColors.forest.withOpacity(.12),
            blurRadius: size * .32, offset: Offset(0, size * .1)),
      ],
    ),
    child: Image.asset(
      'assets/applogo.png',
      fit: BoxFit.contain,
      // Falls back to a heart glyph only if the asset is missing from
      // pubspec.yaml / the assets folder, so a bad path never crashes the
      // splash/login/home screens — it just looks like a placeholder until
      // the asset is wired up correctly.
      errorBuilder: (_, __, ___) => Icon(Icons.favorite_rounded,
          color: light ? Colors.white : MedicColors.forest, size: size * .5),
    ),
  );
}

/// Animated hero version of [MedicMark] for the splash screen: scales and
/// fades in with a soft elastic settle, then eases into a slow continuous
/// "breathing" pulse (with a faint radial glow behind it) so the splash
/// doesn't feel static while auth/session checks run in the background.
/// Fully self-contained — owns its own tickers, so it drops into any screen
/// without that screen needing its own AnimationController.
class MedicMarkHero extends StatefulWidget {
  final double size;
  const MedicMarkHero({super.key, this.size = 96});
  @override
  State<MedicMarkHero> createState() => _MedicMarkHeroState();
}

class _MedicMarkHeroState extends State<MedicMarkHero> with TickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
      duration: const Duration(milliseconds: 900), vsync: this)..forward();
  late final AnimationController _pulse = AnimationController(
      duration: const Duration(milliseconds: 2600), vsync: this)..repeat(reverse: true);
  late final Animation<double> _scaleIn =
      CurvedAnimation(parent: _entrance, curve: Curves.elasticOut);
  late final Animation<double> _fadeIn =
      CurvedAnimation(parent: _entrance, curve: Curves.easeOut);
  late final Animation<double> _breathe = Tween(begin: .97, end: 1.05)
      .animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));

  @override
  void dispose() { _entrance.dispose(); _pulse.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([_entrance, _pulse]),
    builder: (_, child) => Opacity(
      opacity: _fadeIn.value.clamp(0, 1),
      child: Transform.scale(scale: _scaleIn.value * _breathe.value, child: child),
    ),
    child: Stack(alignment: Alignment.center, children: [
      Container(width: widget.size * 1.8, height: widget.size * 1.8,
        decoration: BoxDecoration(shape: BoxShape.circle,
          gradient: RadialGradient(colors: [
            MedicColors.mint.withOpacity(.22), Colors.transparent,
          ]))),
      MedicMark(size: widget.size, light: true),
    ]),
  );
}

/// Drop-in entrance animation: fades and slides [child] up/in once when
/// first built, optionally after [delay]. Fully self-contained (owns its
/// own ticker), so any screen can wrap existing widgets in this without
/// adding an AnimationController to that screen's State class — the easiest
/// way to bring staggered-reveal polish to screens that don't already have
/// one, without rewiring their lifecycle.
class MedicFadeIn extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;
  final double offsetY;
  const MedicFadeIn({super.key, required this.child,
    this.delay = Duration.zero, this.duration = const Duration(milliseconds: 420),
    this.offsetY = 14});
  @override
  State<MedicFadeIn> createState() => _MedicFadeInState();
}

class _MedicFadeInState extends State<MedicFadeIn> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(duration: widget.duration, vsync: this);
  late final Animation<double> _curve = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _ctrl.forward();
    } else {
      Future.delayed(widget.delay, () { if (mounted) _ctrl.forward(); });
    }
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _curve,
    builder: (_, child) => Opacity(opacity: _curve.value,
      child: Transform.translate(offset: Offset(0, widget.offsetY * (1 - _curve.value)), child: child)),
    child: widget.child,
  );
}

class MedicEyebrow extends StatelessWidget {
  final String text;
  final bool light;
  const MedicEyebrow(this.text, {super.key, this.light = false});
  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(),
    style: TextStyle(fontSize: 10, letterSpacing: 2.2, fontWeight: FontWeight.w700,
      color: light ? MedicColors.mint : MedicColors.muted));
}

/// Shared sculpted header. Existing screen actions remain in the child.
class MedicHeaderSurface extends StatelessWidget {
  final Widget child;
  const MedicHeaderSurface({super.key, required this.child});
  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: const BoxDecoration(
      color: MedicColors.forest,
      borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
    ),
    child: Stack(children: [
      const Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: MedicOrbitPainter()))),
      child,
    ]),
  );
}

class MedicOrbitPainter extends CustomPainter {
  const MedicOrbitPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()..color = MedicColors.mint.withOpacity(.10)
      ..style = PaintingStyle.stroke..strokeWidth = 1;
    final center = Offset(size.width * .96, size.height * .18);
    for (final r in [65.0, 100.0, 135.0, 170.0]) {
      canvas.drawCircle(center, r, pen);
    }
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class MedicPageTitle extends StatelessWidget {
  final String title, subtitle;
  final Widget? trailing;
  final bool back;
  const MedicPageTitle({super.key, required this.title, required this.subtitle,
    this.trailing, this.back = true});
  @override
  Widget build(BuildContext context) => MedicHeaderSurface(
    child: SafeArea(bottom: false, child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 26),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (back) ...[
            IconButton(onPressed: () => Navigator.maybePop(context),
              tooltip: 'Back', icon: const Icon(Icons.arrow_back_rounded, color: Colors.white)),
            const SizedBox(width: 4),
          ] else ...[const MedicMark(size: 32, light: true), const SizedBox(width: 10)],
          const Expanded(child: MedicEyebrow('MedicTrack / your care', light: true)),
          if (trailing != null) trailing!,
        ]),
        const SizedBox(height: 18),
        Text(title, style: const TextStyle(fontFamily: 'serif', fontSize: 30,
          height: 1.12, color: Colors.white, letterSpacing: -.7)),
        const SizedBox(height: 8),
        Text(subtitle, style: const TextStyle(color: Color(0xFFCDDCD4), fontSize: 13, height: 1.4)),
      ]),
    )),
  );
}
