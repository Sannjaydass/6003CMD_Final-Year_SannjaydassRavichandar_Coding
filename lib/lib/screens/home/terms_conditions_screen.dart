import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../design/medic_design.dart';

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
}

/// Terms & Conditions, reached from Settings → Account. A quiet, editorial
/// reading surface consistent with the rest of the MedicTrack atelier
/// design language — no accept/decline gate, purely informational.
class TermsConditionsScreen extends StatelessWidget {
  const TermsConditionsScreen({Key? key}) : super(key: key);

  static const _sections = [
    (
      '1',
      'Purpose of Application',
      'MedicTrack is designed to support health monitoring, medication '
          'management, and general health awareness. The application is '
          'intended to help users record health information, monitor '
          'medication adherence, review health trends, and receive '
          'AI-assisted health information.',
    ),
    (
      '2',
      'AI-Assisted Health Analysis',
      'MedicTrack may use AI-assisted analysis to review the health '
          'information provided by the user and identify potential health '
          'risk indicators. AI-generated results may contain errors, '
          'inaccuracies, or incomplete information. These results should not '
          'be considered a medical diagnosis or a guaranteed prediction of '
          'future health conditions.',
    ),
    (
      '3',
      'Health Score',
      'The Health Score is a system-generated monitoring indicator designed '
          'to help users understand changes in their recorded health '
          'information over time. The score uses predefined criteria '
          'involving factors such as blood sugar, blood pressure, medication '
          'adherence, BMI, and age. The percentage values used by the system '
          'are not clinically verified or clinically validated and do not '
          'represent the actual percentage of a user’s health or the '
          'probability of having a medical condition. The Health Score is '
          'intended only to support health awareness and help users observe '
          'whether their recorded health indicators are improving or '
          'worsening.',
    ),
    (
      '4',
      'Professional Medical Advice',
      'MedicTrack does not replace doctors, pharmacists, nurses, or other '
          'qualified healthcare professionals. Users should consult a '
          'qualified healthcare professional when they have concerns about '
          'their health, medication, or treatment.',
    ),
    (
      '5',
      'Medication Adherence',
      'The medication adherence feature helps users monitor their '
          'medication-taking activities. It does not prescribe medication, '
          'determine the appropriate dosage, or replace instructions '
          'provided by a doctor or pharmacist. Users should follow the '
          'medication instructions provided by their healthcare '
          'professional.',
    ),
    (
      '6',
      'Accuracy of User Information',
      'Users are responsible for providing accurate and up-to-date '
          'information. Incorrect, incomplete, or outdated information may '
          'affect the Health Score, medication adherence information, and '
          'AI-assisted health analysis.',
    ),
    (
      '7',
      'AI Limitations',
      'AI technology may produce incorrect, inaccurate, or incomplete '
          'information. Users should cross-check important AI-generated '
          'results and health information with a qualified doctor or '
          'healthcare professional before making any decisions regarding '
          'their health or medication.',
    ),
    (
      '8',
      'Emergency Situations',
      'MedicTrack is not an emergency medical service. Users should not '
          'rely on the application during medical emergencies. If serious '
          'or emergency symptoms occur, users should seek immediate medical '
          'assistance from an appropriate healthcare facility or emergency '
          'service.',
    ),
    (
      '9',
      'User Responsibility',
      'MedicTrack is provided as a supplementary health-management tool. '
          'Users are responsible for using the information provided by the '
          'application appropriately and seeking professional medical '
          'advice when necessary.',
    ),
    (
      '10',
      'System Availability and Errors',
      'MedicTrack may experience technical errors, incorrect OCR '
          'extraction, notification failures, data processing errors, or '
          'other system limitations. Users should verify important health '
          'and medication information rather than relying solely on the '
          'application.',
    ),
    (
      '11',
      'Acceptance of Terms',
      'By using MedicTrack, users acknowledge that the application '
          'provides health monitoring and AI-assisted information for '
          'awareness purposes only. Users understand that the Health Score '
          'is not clinically validated and that AI-assisted results may '
          'contain errors. Users agree to verify important health '
          'information with a qualified healthcare professional when '
          'necessary.',
    ),
  ];

  static const _disclaimer =
      'MedicTrack is designed for health monitoring, medication management, '
      'and health awareness purposes only. The AI-assisted health analysis '
      'and risk indications provided by the application are based on the '
      'information entered or captured by the user and may contain errors, '
      'inaccuracies, or incomplete information. AI-generated results should '
      'not be considered a medical diagnosis, treatment recommendation, or '
      'confirmation that a user has or will develop a particular health '
      'condition.\n\n'
      'The medication adherence information is intended to help users '
      'monitor their medication-taking activities and should not be used '
      'to change, stop, or adjust prescribed medication without '
      'professional advice.\n\n'
      'Users should always verify important health information and '
      'AI-generated results with a qualified doctor or other healthcare '
      'professional before making decisions about their health, '
      'medication, or treatment. In case of an emergency or serious '
      'symptoms, users should seek immediate professional medical '
      'assistance rather than relying on MedicTrack.\n\n'
      'The MedicTrack Health Score is a system-generated indicator for '
      'health monitoring and awareness only. The percentage score is based '
      'on predefined criteria and has not been clinically validated. It '
      'does not provide a medical diagnosis or accurately determine your '
      'medical condition. AI-assisted results may also contain errors. '
      'Please cross-check important results with a qualified doctor or '
      'healthcare professional. Do not change, stop, or start any '
      'medication based solely on the information provided by MedicTrack.';

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.light,
    child: Scaffold(
      backgroundColor: _C.surface,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          const SliverToBoxAdapter(
            child: MedicPageTitle(
              title: 'Terms & Conditions',
              subtitle: 'How MedicTrack supports your care, and where its '
                  'limits are.',
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 44),
            sliver: SliverList(delegate: SliverChildListDelegate([
              // Intro note
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _C.card,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: _C.border),
                  boxShadow: [BoxShadow(color: MedicColors.forest.withOpacity(0.025),
                      blurRadius: 12, offset: const Offset(0, 3))],
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(width: 34, height: 34,
                      decoration: BoxDecoration(
                          color: _C.teal.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.spa_outlined, color: _C.teal, size: 17)),
                  const SizedBox(width: 12),
                  Expanded(child: Text(
                    'Please read these terms carefully. They explain what '
                    'MedicTrack does, what it does not do, and how to use '
                    'it safely alongside professional medical care.',
                    style: TextStyle(fontSize: 12.5, color: _C.textSec, height: 1.6),
                  )),
                ]),
              ),
              const SizedBox(height: 24),

              // Numbered sections
              for (final s in _sections) ...[
                _TermsSection(number: s.$1, title: s.$2, body: s.$3),
                const SizedBox(height: 18),
              ],

              const SizedBox(height: 6),

              // Medical disclaimer — highlighted
              _DisclaimerCard(text: _disclaimer),

              const SizedBox(height: 32),

              // Footer
              Center(child: Column(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: _C.teal.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: _C.teal.withOpacity(0.2)),
                  ),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.medical_services_rounded, color: _C.teal, size: 14),
                    SizedBox(width: 6),
                    Text('MedicTrack · v1.0.0',
                        style: TextStyle(color: _C.teal, fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ]),
                ),
                const SizedBox(height: 6),
                const Text('© 2026 MedicTrack. All rights reserved.',
                    style: TextStyle(color: _C.textTer, fontSize: 11)),
              ])),
            ])),
          ),
        ],
      ),
    ),
  );
}

// ─── Section ──────────────────────────────────────────────────────────────────
class _TermsSection extends StatelessWidget {
  final String number, title, body;
  const _TermsSection({required this.number, required this.title, required this.body});

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 30, height: 30,
        margin: const EdgeInsets.only(top: 2),
        decoration: BoxDecoration(
          color: MedicColors.forest,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Center(child: Text(number, style: const TextStyle(
            fontFamily: 'serif', color: MedicColors.mint,
            fontSize: 13, fontWeight: FontWeight.w700))),
      ),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(
            fontFamily: 'serif', fontSize: 17, height: 1.25,
            color: _C.textPri, letterSpacing: -0.2)),
        const SizedBox(height: 6),
        Text(body, style: const TextStyle(
            fontSize: 13, color: _C.textSec, height: 1.65)),
      ])),
    ],
  );
}

// ─── Disclaimer card ────────────────────────────────────────────────────────────
class _DisclaimerCard extends StatelessWidget {
  final String text;
  const _DisclaimerCard({required this.text});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: _C.amber.withOpacity(0.06),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: _C.amber.withOpacity(0.28), width: 1.3),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 34, height: 34,
            decoration: BoxDecoration(
                color: _C.amber.withOpacity(0.14),
                borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.health_and_safety_outlined, color: _C.amber, size: 18)),
        const SizedBox(width: 12),
        const Expanded(child: Text('Medical Disclaimer', style: TextStyle(
            fontFamily: 'serif', fontSize: 18, color: _C.textPri, letterSpacing: -0.3))),
      ]),
      const SizedBox(height: 14),
      Text(text, style: const TextStyle(fontSize: 12.5, color: _C.textSec, height: 1.7)),
    ]),
  );
}
