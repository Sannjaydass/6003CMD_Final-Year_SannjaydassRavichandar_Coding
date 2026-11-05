import 'package:medictrack/design/medic_design.dart';
import 'package:flutter/material.dart';
import '../home/home_screen.dart';
import '../home/scan_medicine_screen.dart';
import '../home/vitals_upload_screen.dart';

// ─── Design Tokens ────────────────────────────────────────────────────────────
class _C {
  static const navy    = MedicColors.c142F2B;
  static const teal    = MedicColors.c28715D;
  static const surface = MedicColors.cF6F5F0;
  static const card    = MedicColors.cFFFFFF;
  static const border  = MedicColors.cE2E5DC;
  static const textPri = MedicColors.c142F2B;
  static const textSec = MedicColors.c63756D;
}

/// Shown ONCE, right after a 'patient' account is created (never for a
/// 'dependant'/caregiver account — see signup_screen.dart's role picker).
/// This replaces the old approach of forcing every health detail into the
/// signup form itself: the account already exists by this point, and every
/// step here is skippable, so the person reaches their dashboard quickly
/// either way instead of being blocked by a long required form up front.
class OnboardingSetupScreen extends StatefulWidget {
  const OnboardingSetupScreen({super.key});
  @override
  State<OnboardingSetupScreen> createState() => _OnboardingSetupScreenState();
}

class _OnboardingSetupScreenState extends State<OnboardingSetupScreen> {
  final _controller = PageController();
  int _step = 0;
  static const _total = 3;

  void _finish() {
    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()), (_) => false);
  }

  void _next() {
    if (_step == _total - 1) { _finish(); return; }
    _controller.nextPage(duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _C.navy,
    body: SafeArea(child: Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(24, 20, 24, 8), child: Row(children: [
        for (var i = 0; i < _total; i++) Expanded(child: Container(
          height: 4, margin: EdgeInsets.only(right: i == _total - 1 ? 0 : 6),
          decoration: BoxDecoration(
            color: i <= _step ? _C.teal : Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(3)),
        )),
      ])),
      Padding(padding: const EdgeInsets.fromLTRB(24, 8, 24, 0), child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Step ${_step + 1} of $_total', style: TextStyle(
              color: Colors.white.withOpacity(0.55), fontSize: 12, fontWeight: FontWeight.w600)),
          TextButton(onPressed: _finish, child: const Text('Skip setup',
              style: TextStyle(color: Colors.white70, fontSize: 12))),
        ],
      )),
      Expanded(child: PageView(
        controller: _controller,
        physics: const NeverScrollableScrollPhysics(),
        onPageChanged: (i) => setState(() => _step = i),
        children: [
          _StepCard(
            icon: Icons.medication_outlined,
            title: 'Add your first medicine',
            body: 'Scan a label or enter one manually so MedicTrack can start reminding you '
                'when it\'s time to take it. You can add more any time later.',
            actionLabel: 'Scan a medicine',
            onAction: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const ScanMedicineScreen()));
              if (mounted) _next();
            },
            onSkip: _next,
          ),
          _StepCard(
            icon: Icons.favorite_outline_rounded,
            title: 'Add a blood pressure or sugar reading',
            body: 'This is what powers your daily health score and the seven-day report. '
                'Add one now, or skip and do it whenever you next check your vitals.',
            actionLabel: 'Add a reading',
            onAction: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const VitalsUploadScreen()));
              if (mounted) _next();
            },
            onSkip: _next,
          ),
          _StepCard(
            icon: Icons.insights_rounded,
            title: 'Your health score, explained',
            body: 'Once you have age, height, weight and a reading or two on file, your dashboard '
                'shows a daily score out of 100 and a seven-day report — built from blood pressure, '
                'blood sugar, dose adherence, BMI and age. Nothing here replaces your doctor.',
            actionLabel: 'Go to my dashboard',
            onAction: _finish,
            onSkip: _finish,
          ),
        ],
      )),
    ])),
  );
}

class _StepCard extends StatelessWidget {
  final IconData icon;
  final String title, body, actionLabel;
  final VoidCallback onAction, onSkip;
  const _StepCard({required this.icon, required this.title, required this.body,
    required this.actionLabel, required this.onAction, required this.onSkip});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: 56, height: 56,
          decoration: BoxDecoration(color: _C.teal.withOpacity(0.18), shape: BoxShape.circle),
          child: Icon(icon, color: _C.teal, size: 26)),
      const SizedBox(height: 22),
      Text(title, style: const TextStyle(fontFamily: 'serif', fontSize: 26, height: 1.2, color: Colors.white)),
      const SizedBox(height: 12),
      Text(body, style: TextStyle(fontSize: 13.5, height: 1.6, color: Colors.white.withOpacity(0.7))),
      const Spacer(),
      SizedBox(width: double.infinity, child: FilledButton(
        style: FilledButton.styleFrom(backgroundColor: _C.teal, padding: const EdgeInsets.symmetric(vertical: 16)),
        onPressed: onAction,
        child: Text(actionLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
      )),
      const SizedBox(height: 10),
      SizedBox(width: double.infinity, child: TextButton(
        onPressed: onSkip,
        child: const Text('Not now', style: TextStyle(color: Colors.white70)),
      )),
    ]),
  );
}
