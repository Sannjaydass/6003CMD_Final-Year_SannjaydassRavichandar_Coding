import 'dose_history_screen.dart';
import 'reminder_diagnostics_screen.dart';
import 'package:medictrack/design/medic_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/auth_service.dart';
import '../../services/storage_service.dart';
import '../auth/login_screen.dart';
import 'terms_conditions_screen.dart';

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

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with SingleTickerProviderStateMixin {
  final AuthService _authSvc    = AuthService();
  final StorageService _storageSvc = StorageService();
  final FirebaseFirestore _db   = FirebaseFirestore.instance;

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  // ── Notification toggles ─────────────────────────────────────────────────
  bool _notifMedicine = true;
  bool _notifExpiry   = true;
  bool _loadingNotif  = false;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        duration: const Duration(milliseconds: 700), vsync: this);
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeIn);
    _fadeCtrl.forward();
    _loadNotifPrefs();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // NOTIFICATION PREFERENCES — stored in Firestore under users/{uid}/settings
  // ═══════════════════════════════════════════════════════════════════════════
  Future<void> _loadNotifPrefs() async {
    final user = _authSvc.currentUser;
    if (user == null) return;
    try {
      final doc = await _db
          .collection('users')
          .doc(user.uid)
          .collection('settings')
          .doc('notifications')
          .get();
      if (doc.exists && mounted) {
        final d = doc.data()!;
        setState(() {
          _notifMedicine = d['medicineReminders'] ?? true;
          _notifExpiry   = d['expiryAlerts']      ?? true;
        });
      }
    } catch (_) {}
  }

  Future<void> _saveNotifPref(String key, bool value) async {
    final user = _authSvc.currentUser;
    if (user == null) return;
    setState(() => _loadingNotif = true);
    try {
      await _db
          .collection('users')
          .doc(user.uid)
          .collection('settings')
          .doc('notifications')
          .set({key: value}, SetOptions(merge: true));
      _snack(value ? 'Notification enabled' : 'Notification disabled',
          color: value ? _C.teal : _C.amber);
    } catch (e) {
      _snack('Failed to save: $e', color: _C.rose);
    }
    if (mounted) setState(() => _loadingNotif = false);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CHANGE PASSWORD
  // ═══════════════════════════════════════════════════════════════════════════
  Future<void> _showChangePassword() async {
    final currCtrl    = TextEditingController();
    final newCtrl     = TextEditingController();
    final confirmCtrl = TextEditingController();

    await showDialog(
      context: context,
      barrierColor: Colors.black54,
      barrierDismissible: false,
      builder: (_) => _ChangePasswordDialog(
        currCtrl: currCtrl,
        newCtrl: newCtrl,
        confirmCtrl: confirmCtrl,
        authSvc: _authSvc,
        onSuccess: () => _snack('Password changed successfully!'),
      ),
    );

    currCtrl.dispose();
    newCtrl.dispose();
    confirmCtrl.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELP CENTER
  // ═══════════════════════════════════════════════════════════════════════════
  void _showHelpCenter() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _HelpCenterSheet(),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SEND FEEDBACK
  // ═══════════════════════════════════════════════════════════════════════════
  Future<void> _showSendFeedback() async {
    await showDialog(
      context: context,
      barrierColor: Colors.black54,
      barrierDismissible: false,
      builder: (_) => _FeedbackDialog(
        db: _db,
        user: _authSvc.currentUser,
        onSuccess: () => _snack('Feedback submitted — thank you!'),
        onError: (e) => _snack(e, color: _C.rose),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LOGOUT & DELETE
  // ═══════════════════════════════════════════════════════════════════════════
  Future<void> _handleLogout() async {
    HapticFeedback.mediumImpact();
    final ok = await showDialog<bool>(
      context: context, barrierColor: Colors.black54,
      builder: (_) => _SimpleConfirm(
        icon: Icons.logout_rounded, accent: _C.rose,
        title: 'Sign out?',
        body: 'You will need to sign back in to access your account.',
        confirmLabel: 'Sign Out',
      ),
    );
    if (ok != true) return;
    await _authSvc.signOut();
    await _storageSvc.clearLoginData();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
    }
  }

  Future<void> _handleDeleteAccount() async {
    final ok = await showDialog<bool>(
      context: context, barrierColor: Colors.black54,
      builder: (_) => _SimpleConfirm(
        icon: Icons.delete_forever_rounded, accent: _C.rose,
        title: 'Delete Account?',
        body: 'This permanently deletes all your data and cannot be undone.',
        confirmLabel: 'Delete Account',
      ),
    );
    if (ok != true) return;
    final result = await _authSvc.deleteAccount();
    if (mounted) {
      if (result['success']) {
        Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
      } else {
        _snack(result['message'], color: _C.rose);
      }
    }
  }

  // ── Snack ─────────────────────────────────────────────────────────────────
  void _snack(String msg, {Color color = _C.teal}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(
          color == _C.rose  ? Icons.error_outline_rounded
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
    ));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final user = _authSvc.currentUser;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _C.surface,
        body: FadeTransition(
          opacity: _fadeAnim,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: _buildHeader(user)),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                sliver: SliverList(delegate: SliverChildListDelegate([

                  ListTile(leading: const Icon(Icons.notifications_active_outlined), title: const Text('Reminder check'),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReminderDiagnosticsScreen()))),
                  ListTile(leading: const Icon(Icons.fact_check_outlined), title: const Text('Dose history & adherence'),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DoseHistoryScreen()))),
                  ListTile(leading: const Icon(Icons.people_outline), title: const Text('Medication sharing'),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MedicationSharingScreen()))),
                  // ── Account ───────────────────────────────────────────
                  _SectionLabel('Account', Icons.shield_outlined),
                  const SizedBox(height: 12),
                  _SettingsCard(children: [
                    _TappableTile(
                      icon: Icons.lock_outline_rounded,
                      label: 'Change Password',
                      subtitle: 'Update your login password',
                      accent: _C.sky,
                      onTap: _showChangePassword,
                    ),
                    _Divider(),
                    _TappableTile(
                      icon: Icons.privacy_tip_outlined,
                      label: 'Privacy Policy',
                      subtitle: 'Read our privacy terms',
                      accent: _C.teal,
                      onTap: () => _snack('Privacy Policy coming soon', color: _C.amber),
                    ),
                    _Divider(),
                    _TappableTile(
                      icon: Icons.description_outlined,
                      label: 'Terms & Conditions',
                      subtitle: 'View terms of service',
                      accent: _C.violet,
                      isLast: true,
                      onTap: () => Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const TermsConditionsScreen())),
                    ),
                  ]),
                  const SizedBox(height: 28),

                  // ── Notifications ─────────────────────────────────────
                  _SectionLabel('Notifications', Icons.notifications_outlined),
                  const SizedBox(height: 12),
                  _SettingsCard(children: [
                    // Medicine Reminders toggle
                    _ToggleTile(
                      icon: Icons.medication_outlined,
                      label: 'Medicine Reminders',
                      subtitle: 'Alerts for scheduled doses',
                      accent: _C.teal,
                      value: _notifMedicine,
                      loading: _loadingNotif,
                      onChanged: (v) {
                        HapticFeedback.selectionClick();
                        setState(() => _notifMedicine = v);
                        _saveNotifPref('medicineReminders', v);
                      },
                    ),
                    _Divider(),
                    // Expiry Alerts toggle
                    _ToggleTile(
                      icon: Icons.warning_amber_rounded,
                      label: 'Expiry Alerts',
                      subtitle: 'Notify when medicines expire soon',
                      accent: _C.amber,
                      value: _notifExpiry,
                      loading: _loadingNotif,
                      isLast: true,
                      onChanged: (v) {
                        HapticFeedback.selectionClick();
                        setState(() => _notifExpiry = v);
                        _saveNotifPref('expiryAlerts', v);
                      },
                    ),
                  ]),

                  // Notification status banner
                  if (!_notifMedicine || !_notifExpiry) ...[
                    const SizedBox(height: 8),
                    _InfoBanner(
                      icon: Icons.info_outline_rounded,
                      color: _C.amber,
                      text: 'Some notifications are disabled. '
                          'You may miss important medicine alerts.',
                    ),
                  ],
                  const SizedBox(height: 28),

                  // ── Support ───────────────────────────────────────────
                  _SectionLabel('Support', Icons.help_outline_rounded),
                  const SizedBox(height: 12),
                  _SettingsCard(children: [
                    _TappableTile(
                      icon: Icons.help_center_outlined,
                      label: 'Help Center',
                      subtitle: 'Browse FAQs and guides',
                      accent: _C.sky,
                      onTap: _showHelpCenter,
                    ),
                    _Divider(),
                    _TappableTile(
                      icon: Icons.feedback_outlined,
                      label: 'Send Feedback',
                      subtitle: 'Share your thoughts with us',
                      accent: _C.violet,
                      isLast: true,
                      onTap: _showSendFeedback,
                    ),
                  ]),
                  const SizedBox(height: 28),

                  // ── Danger Zone ───────────────────────────────────────
                  _SectionLabel('Danger Zone', Icons.warning_outlined, danger: true),
                  const SizedBox(height: 12),
                  _SettingsCard(children: [
                    _TappableTile(
                      icon: Icons.logout_rounded,
                      label: 'Sign Out',
                      subtitle: 'Log out from your account',
                      accent: _C.rose,
                      isDanger: true,
                      onTap: _handleLogout,
                    ),
                    _Divider(),
                    _TappableTile(
                      icon: Icons.delete_forever_rounded,
                      label: 'Delete Account',
                      subtitle: 'Permanently remove all your data',
                      accent: _C.rose,
                      isDanger: true,
                      isLast: true,
                      onTap: _handleDeleteAccount,
                    ),
                  ]),
                  const SizedBox(height: 36),

                  // ── Version ───────────────────────────────────────────
                  Center(child: Column(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: _C.teal.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: _C.teal.withOpacity(0.2)),
                      ),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.medical_services_rounded,
                            color: _C.teal, size: 14),
                        SizedBox(width: 6),
                        Text('MedicTrack · v1.0.0',
                            style: TextStyle(
                                color: _C.teal, fontSize: 12,
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
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader(User? user) => MedicPageTitle(
    title: 'Make yourself at home',
    subtitle: user?.email ?? 'Your account, preferences and support.',
    back: false,
    trailing: const Icon(Icons.tune_rounded, color: MedicColors.mint),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// ── SHARED CARD & TILE COMPONENTS ─────────────────────────────────────────────
// ═══════════════════════════════════════════════════════════════════════════════

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: _C.card, borderRadius: BorderRadius.circular(24),
      border: Border.all(color: _C.border),
      boxShadow: [BoxShadow(color: MedicColors.forest.withOpacity(0.025),
          blurRadius: 12, offset: const Offset(0, 3))],
    ),
    child: Column(children: children),
  );
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      const Divider(height: 1, indent: 70, endIndent: 18, color: _C.border);
}

// Standard tappable row
class _TappableTile extends StatelessWidget {
  final IconData icon;
  final String label, subtitle;
  final Color accent;
  final bool isLast, isDanger;
  final VoidCallback onTap;

  const _TappableTile({
    required this.icon, required this.label, required this.subtitle,
    required this.accent, required this.onTap,
    this.isLast = false, this.isDanger = false,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: () { HapticFeedback.selectionClick(); onTap(); },
      borderRadius: isLast
          ? const BorderRadius.only(
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20))
          : BorderRadius.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(children: [
          Container(width: 38, height: 38,
              decoration: BoxDecoration(
                  color: accent.withOpacity(isDanger ? 0.08 : 0.1),
                  borderRadius: BorderRadius.circular(11)),
              child: Icon(icon, color: accent, size: 19)),
          const SizedBox(width: 14),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700,
                color: isDanger ? _C.rose : _C.textPri)),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(
                fontSize: 11, color: _C.textTer, fontWeight: FontWeight.w400)),
          ])),
          Icon(Icons.chevron_right_rounded,
              color: isDanger ? _C.rose.withOpacity(0.4) : _C.textTer, size: 18),
        ]),
      ),
    ),
  );
}

// Toggle row with Switch
class _ToggleTile extends StatelessWidget {
  final IconData icon;
  final String label, subtitle;
  final Color accent;
  final bool value, loading;
  final bool isLast;
  final ValueChanged<bool> onChanged;

  const _ToggleTile({
    required this.icon, required this.label, required this.subtitle,
    required this.accent, required this.value, required this.onChanged,
    this.loading = false, this.isLast = false,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
    child: Row(children: [
      Container(width: 38, height: 38,
          decoration: BoxDecoration(
              color: accent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(11)),
          child: Icon(icon, color: accent, size: 19)),
      const SizedBox(width: 14),
      Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(
            fontSize: 14, fontWeight: FontWeight.w700, color: _C.textPri)),
        const SizedBox(height: 2),
        Text(subtitle, style: const TextStyle(
            fontSize: 11, color: _C.textTer, fontWeight: FontWeight.w400)),
      ])),
      if (loading)
        SizedBox(width: 22, height: 22,
            child: CircularProgressIndicator(
                strokeWidth: 2.2, color: accent,
                backgroundColor: accent.withOpacity(0.15)))
      else
        Transform.scale(
          scale: 0.85,
          child: Switch(
            value: value,
            onChanged: onChanged,
            activeColor: Colors.white,
            activeTrackColor: accent,
            inactiveThumbColor: Colors.white,
            inactiveTrackColor: _C.border,
            trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
          ),
        ),
    ]),
  );
}

// Info/warning banner
class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _InfoBanner({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2))),
    child: Row(children: [
      Icon(icon, color: color, size: 15),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: TextStyle(
          fontSize: 11, color: color, fontWeight: FontWeight.w500, height: 1.4))),
    ]),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// ── HELP CENTER BOTTOM SHEET ────────────────────────────────────────────────────
// ═══════════════════════════════════════════════════════════════════════════════
class _HelpCenterSheet extends StatefulWidget {
  @override
  State<_HelpCenterSheet> createState() => _HelpCenterSheetState();
}

class _HelpCenterSheetState extends State<_HelpCenterSheet> {
  int? _openIndex;

  static const _faqs = [
    (
    'How do I scan a medicine?',
    'Tap the Scan button on the home screen or inventory page. '
        'Point your camera at the medicine label or barcode. '
        'The app will automatically extract the medicine name, expiry date, and other details.'
    ),
    (
    'How is the potency score calculated?',
    'The potency score is calculated based on the days remaining until expiry. '
        'A medicine with more than 180 days left scores 100%. '
        'The score decreases proportionally as the expiry date approaches. '
        'Expired medicines are shown as 0%.'
    ),
    (
    'What do the colour indicators mean?',
    'Green (Safe): Medicine is within expiry and potency is above 80%.\n'
        'Amber (Caution): Medicine is expiring within 30 days or potency is between 50-80%.\n'
        'Red (Expired): Medicine has passed its expiry date or potency is below 50%.'
    ),
    (
    'How do I safely dispose of expired medicines?',
    'Navigate to Safe Disposal from the home screen. '
        'Select the expired medicine from your inventory, and the AI assistant '
        'will provide step-by-step disposal instructions specific to that medicine type.'
    ),
    (
    'Can I change my notification settings?',
    'Yes! Go to Settings → Notifications. '
        'You can toggle Medicine Reminders and Expiry Alerts independently. '
        'Your preferences are saved to your account.'
    ),
    (
    'How do I update my health profile?',
    'Tap your profile avatar on the home screen. '
        'You can update your BMI, blood type, chronic conditions, '
        'and other health information that the AI uses for personalised analysis.'
    ),
    (
    'Is my data secure?',
    'All your data is stored securely in Firebase with industry-standard encryption. '
        'Your health information is never shared with third parties. '
        'You can delete your account and all associated data at any time from Settings.'
    ),
    (
    'Why does the AI analysis show "unreadable response"?',
    'This usually happens with non-English languages due to special characters. '
        'Try running the analysis again. If the issue persists, '
        'switch to English and try once more.'
    ),
  ];

  @override
  Widget build(BuildContext context) => Container(
    height: MediaQuery.of(context).size.height * 0.88,
    decoration: const BoxDecoration(
        color: _C.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    child: Column(children: [
      // Handle
      Container(
          margin: const EdgeInsets.only(top: 12, bottom: 4),
          width: 36, height: 4,
          decoration: BoxDecoration(
              color: _C.border, borderRadius: BorderRadius.circular(2))),

      // Header
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 12),
        child: Row(children: [
          Container(width: 44, height: 44,
              decoration: BoxDecoration(
                  color: _C.sky.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: _C.sky.withOpacity(0.25))),
              child: const Icon(Icons.help_center_outlined,
                  color: _C.sky, size: 22)),
          const SizedBox(width: 12),
          const Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Help Center', style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.w700, color: _C.textPri,
                letterSpacing: -0.4)),
            Text('Frequently asked questions',
                style: TextStyle(fontSize: 12, color: _C.textSec)),
          ])),
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(width: 34, height: 34,
                decoration: BoxDecoration(
                    color: _C.surface, borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.close_rounded,
                    color: _C.textSec, size: 18)),
          ),
        ]),
      ),
      const Divider(height: 1, color: _C.border),

      // FAQ list
      Expanded(child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
        itemCount: _faqs.length,
        itemBuilder: (_, i) {
          final (q, a) = _faqs[i];
          final isOpen = _openIndex == i;
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
                color: isOpen ? _C.sky.withOpacity(0.04) : _C.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: isOpen ? _C.sky.withOpacity(0.3) : _C.border,
                    width: isOpen ? 1.5 : 1.0)),
            child: Column(children: [
              // Question row
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _openIndex = isOpen ? null : i);
                },
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(children: [
                    Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(
                          color: isOpen
                              ? _C.sky.withOpacity(0.15) : _C.border.withOpacity(0.5),
                          shape: BoxShape.circle),
                      child: Icon(
                        isOpen ? Icons.remove_rounded : Icons.add_rounded,
                        color: isOpen ? _C.sky : _C.textTer, size: 16,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(q, style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700,
                        color: isOpen ? _C.sky : _C.textPri, height: 1.3))),
                  ]),
                ),
              ),
              // Answer (animated)
              AnimatedCrossFade(
                firstChild: const SizedBox(height: 0, width: double.infinity),
                secondChild: Padding(
                  padding: const EdgeInsets.fromLTRB(54, 0, 14, 14),
                  child: Text(a, style: const TextStyle(
                      fontSize: 12, color: _C.textSec, height: 1.6)),
                ),
                crossFadeState: isOpen
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 220),
              ),
            ]),
          );
        },
      )),
    ]),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// ── SEND FEEDBACK DIALOG ────────────────────────────────────────────────────────
// ═══════════════════════════════════════════════════════════════════════════════
class _FeedbackDialog extends StatefulWidget {
  final FirebaseFirestore db;
  final User? user;
  final VoidCallback onSuccess;
  final ValueChanged<String> onError;
  const _FeedbackDialog({
    required this.db, required this.user,
    required this.onSuccess, required this.onError,
  });

  @override
  State<_FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<_FeedbackDialog> {
  final TextEditingController _ctrl = TextEditingController();
  int _rating   = 0;       // 1–5 star rating
  String _category = 'General';
  bool _loading = false;
  String? _error;

  static const _categories = ['General', 'Bug Report', 'Feature Request', 'UI/UX', 'Performance'];

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _submit() async {
    if (_rating == 0) {
      setState(() => _error = 'Please select a star rating');
      return;
    }
    if (_ctrl.text.trim().length < 10) {
      setState(() => _error = 'Please write at least 10 characters');
      return;
    }

    setState(() { _loading = true; _error = null; });

    try {
      await widget.db.collection('feedback').add({
        'userId':    widget.user?.uid ?? 'anonymous',
        'email':     widget.user?.email ?? '',
        'category':  _category,
        'rating':    _rating,
        'message':   _ctrl.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'platform':  'Android/iOS',
        'version':   '1.0.0',
      });
      if (!mounted) return;
      Navigator.pop(context);
      widget.onSuccess();
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = 'Failed to submit: $e'; });
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: _C.card,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(22),
      child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [

            // Header
            Row(children: [
              Container(width: 44, height: 44,
                  decoration: BoxDecoration(
                      color: _C.violet.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: _C.violet.withOpacity(0.25))),
                  child: const Icon(Icons.feedback_outlined,
                      color: _C.violet, size: 21)),
              const SizedBox(width: 12),
              const Expanded(child: Text('Send Feedback', style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700,
                  color: _C.textPri, letterSpacing: -0.3))),
              GestureDetector(
                onTap: _loading ? null : () => Navigator.pop(context),
                child: Container(width: 30, height: 30,
                    decoration: BoxDecoration(color: _C.surface,
                        borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.close_rounded, color: _C.textTer, size: 17)),
              ),
            ]),
            const SizedBox(height: 6),
            const Text('We read every piece of feedback.',
                style: TextStyle(fontSize: 12, color: _C.textSec)),
            const SizedBox(height: 18),

            // Error banner
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: _C.rose.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _C.rose.withOpacity(0.25))),
                child: Row(children: [
                  const Icon(Icons.error_outline_rounded, color: _C.rose, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!, style: const TextStyle(
                      fontSize: 12, color: _C.rose, fontWeight: FontWeight.w500))),
                ]),
              ),
              const SizedBox(height: 14),
            ],

            // Star rating
            const Text('How would you rate your experience?',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                    color: _C.textSec)),
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(5, (i) {
              final filled = i < _rating;
              return GestureDetector(
                onTap: () { HapticFeedback.selectionClick(); setState(() => _rating = i + 1); },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    filled ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: filled ? _C.amber : _C.border,
                    size: 36,
                  ),
                ),
              );
            })),
            if (_rating > 0) ...[
              const SizedBox(height: 6),
              Center(child: Text(
                ['', 'Poor', 'Fair', 'Good', 'Great', 'Excellent!'][_rating],
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700,
                    color: _rating <= 2 ? _C.rose : _rating == 3 ? _C.amber : _C.teal),
              )),
            ],
            const SizedBox(height: 16),

            // Category picker
            const Text('Category', style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: _C.textSec)),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: _categories.map((cat) {
                final on = _category == cat;
                return GestureDetector(
                  onTap: () { HapticFeedback.selectionClick(); setState(() => _category = cat); },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                        color: on ? _C.violet : _C.surface,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: on ? _C.violet : _C.border)),
                    child: Text(cat, style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700,
                        color: on ? Colors.white : _C.textSec)),
                  ),
                );
              }).toList()),
            ),
            const SizedBox(height: 14),

            // Message field
            const Text('Your message', style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: _C.textSec)),
            const SizedBox(height: 6),
            Container(
              decoration: BoxDecoration(
                  color: _C.surface, borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _C.border, width: 1.5)),
              child: TextField(
                controller: _ctrl,
                maxLines: 5,
                maxLength: 500,
                style: const TextStyle(fontSize: 13, color: _C.textPri, height: 1.5),
                decoration: const InputDecoration(
                  hintText: 'Tell us what you think, what could be better, '
                      'or report a bug...',
                  hintStyle: TextStyle(color: _C.textTer, fontSize: 12, height: 1.5),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(14),
                  counterStyle: TextStyle(color: _C.textTer, fontSize: 10),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Buttons
            Row(children: [
              Expanded(child: GestureDetector(
                onTap: _loading ? null : () => Navigator.pop(context),
                child: Container(height: 46,
                    decoration: BoxDecoration(color: _C.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _C.border)),
                    child: const Center(child: Text('Cancel', style: TextStyle(
                        fontWeight: FontWeight.w700, color: _C.textSec, fontSize: 14)))),
              )),
              const SizedBox(width: 12),
              Expanded(child: GestureDetector(
                onTap: _loading ? null : _submit,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  height: 46,
                  decoration: BoxDecoration(
                      color: _loading ? _C.violet.withOpacity(0.6) : _C.violet,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: _loading ? [] : [BoxShadow(
                          color: _C.violet.withOpacity(0.3), blurRadius: 10,
                          offset: const Offset(0, 4))]),
                  child: Center(child: _loading
                      ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.2,
                          color: Colors.white))
                      : const Text('Submit', style: TextStyle(
                      fontWeight: FontWeight.w700, color: Colors.white, fontSize: 14))),
                ),
              )),
            ]),
          ]),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// ── CHANGE PASSWORD DIALOG ──────────────────────────────────────────────────────
// ═══════════════════════════════════════════════════════════════════════════════
class _ChangePasswordDialog extends StatefulWidget {
  final TextEditingController currCtrl, newCtrl, confirmCtrl;
  final AuthService authSvc;
  final VoidCallback onSuccess;
  const _ChangePasswordDialog({
    required this.currCtrl, required this.newCtrl, required this.confirmCtrl,
    required this.authSvc, required this.onSuccess,
  });

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  bool _showCurr    = false;
  bool _showNew     = false;
  bool _showConfirm = false;
  bool _loading     = false;
  String? _error;

  // Live password strength
  int _strength = 0; // 0-4
  String _strengthLabel = '';
  Color _strengthColor  = _C.border;

  void _checkStrength(String pw) {
    int score = 0;
    if (pw.length >= 6)                         score++;
    if (pw.length >= 10)                        score++;
    if (RegExp(r'[A-Z]').hasMatch(pw))          score++;
    if (RegExp(r'[0-9]').hasMatch(pw))          score++;
    if (RegExp(r'[!@#\$%^&*(),.?":{}|<>]').hasMatch(pw)) score++;

    final labels = ['', 'Very Weak', 'Weak', 'Fair', 'Strong', 'Very Strong'];
    final colors = [_C.border, _C.rose, _C.amber, _C.amber, _C.teal, _C.teal];
    setState(() {
      _strength      = score;
      _strengthLabel = score > 0 ? labels[score] : '';
      _strengthColor = colors[score];
    });
  }

  Future<void> _submit() async {
    final curr    = widget.currCtrl.text.trim();
    final next    = widget.newCtrl.text.trim();
    final confirm = widget.confirmCtrl.text.trim();

    if (curr.isEmpty)    { setState(() => _error = 'Enter your current password'); return; }
    if (next.isEmpty)    { setState(() => _error = 'Enter a new password'); return; }
    if (next.length < 6) { setState(() => _error = 'Password must be at least 6 characters'); return; }
    if (next != confirm) { setState(() => _error = 'New passwords do not match'); return; }
    if (curr == next)    { setState(() => _error = 'New password must differ from current'); return; }

    setState(() { _loading = true; _error = null; });
    final result = await widget.authSvc.changePassword(
        currentPassword: curr, newPassword: next);
    if (!mounted) return;
    if (result['success']) {
      Navigator.pop(context);
      widget.onSuccess();
    } else {
      setState(() { _loading = false; _error = result['message']; });
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: _C.card,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [

            // Header
            Row(children: [
              Container(width: 44, height: 44,
                  decoration: BoxDecoration(
                      color: _C.sky.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: _C.sky.withOpacity(0.25))),
                  child: const Icon(Icons.lock_outline_rounded, color: _C.sky, size: 21)),
              const SizedBox(width: 12),
              const Expanded(child: Text('Change Password', style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700,
                  color: _C.textPri, letterSpacing: -0.3))),
              GestureDetector(
                onTap: _loading ? null : () => Navigator.pop(context),
                child: Container(width: 30, height: 30,
                    decoration: BoxDecoration(color: _C.surface,
                        borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.close_rounded,
                        color: _C.textTer, size: 17)),
              ),
            ]),
            const SizedBox(height: 6),
            const Text('Enter your current password and choose a new one.',
                style: TextStyle(fontSize: 12, color: _C.textSec, height: 1.5)),
            const SizedBox(height: 20),

            // Error banner
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: _C.rose.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _C.rose.withOpacity(0.25))),
                child: Row(children: [
                  const Icon(Icons.error_outline_rounded, color: _C.rose, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!, style: const TextStyle(
                      fontSize: 12, color: _C.rose, fontWeight: FontWeight.w500))),
                ]),
              ),
              const SizedBox(height: 14),
            ],

            // Current password
            _PwField(
              ctrl: widget.currCtrl, label: 'Current Password',
              hint: 'Enter current password', obscure: !_showCurr,
              onToggle: () => setState(() => _showCurr = !_showCurr),
            ),
            const SizedBox(height: 12),

            // New password + live strength meter
            _PwField(
              ctrl: widget.newCtrl, label: 'New Password',
              hint: 'Min. 6 characters', obscure: !_showNew,
              onToggle: () => setState(() => _showNew = !_showNew),
              onChanged: _checkStrength,
            ),

            // Strength bar
            if (_strength > 0) ...[
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: _strength / 5,
                    backgroundColor: _C.border,
                    valueColor: AlwaysStoppedAnimation<Color>(_strengthColor),
                    minHeight: 4,
                  ),
                )),
                const SizedBox(width: 10),
                Text(_strengthLabel, style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w700,
                    color: _strengthColor)),
              ]),
            ],
            const SizedBox(height: 12),

            // Confirm password
            _PwField(
              ctrl: widget.confirmCtrl, label: 'Confirm New Password',
              hint: 'Re-enter new password', obscure: !_showConfirm,
              onToggle: () => setState(() => _showConfirm = !_showConfirm),
            ),

            // Match indicator
            if (widget.confirmCtrl.text.isNotEmpty) ...[
              const SizedBox(height: 6),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: widget.confirmCtrl,
                builder: (_, val, __) {
                  final match = widget.newCtrl.text == val.text;
                  if (val.text.isEmpty) return const SizedBox();
                  return Row(children: [
                    Icon(match
                        ? Icons.check_circle_rounded
                        : Icons.cancel_rounded,
                        color: match ? _C.teal : _C.rose, size: 14),
                    const SizedBox(width: 5),
                    Text(match ? 'Passwords match' : 'Passwords do not match',
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w600,
                            color: match ? _C.teal : _C.rose)),
                  ]);
                },
              ),
            ],
            const SizedBox(height: 14),

            // Requirements hint
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: _C.sky.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _C.sky.withOpacity(0.2))),
              child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.info_outline_rounded, color: _C.sky, size: 15),
                SizedBox(width: 8),
                Expanded(child: Text(
                  '• At least 6 characters\n'
                      '• Mix uppercase, numbers & symbols for a stronger password\n'
                      '• Must differ from current password',
                  style: TextStyle(fontSize: 11, color: _C.textSec, height: 1.6),
                )),
              ]),
            ),
            const SizedBox(height: 20),

            // Buttons
            Row(children: [
              Expanded(child: GestureDetector(
                onTap: _loading ? null : () => Navigator.pop(context),
                child: Container(height: 46,
                    decoration: BoxDecoration(color: _C.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _C.border)),
                    child: const Center(child: Text('Cancel', style: TextStyle(
                        fontWeight: FontWeight.w700, color: _C.textSec, fontSize: 14)))),
              )),
              const SizedBox(width: 12),
              Expanded(child: GestureDetector(
                onTap: _loading ? null : _submit,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  height: 46,
                  decoration: BoxDecoration(
                      color: _loading ? _C.sky.withOpacity(0.6) : _C.sky,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: _loading ? [] : [BoxShadow(
                          color: _C.sky.withOpacity(0.3), blurRadius: 10,
                          offset: const Offset(0, 4))]),
                  child: Center(child: _loading
                      ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.2,
                          color: Colors.white))
                      : const Text('Update Password', style: TextStyle(
                      fontWeight: FontWeight.w700, color: Colors.white, fontSize: 13))),
                ),
              )),
            ]),
          ]),
    ),
  );
}

// ─── Password Field ───────────────────────────────────────────────────────────
class _PwField extends StatelessWidget {
  final TextEditingController ctrl;
  final String label, hint;
  final bool obscure;
  final VoidCallback onToggle;
  final ValueChanged<String>? onChanged;
  const _PwField({
    required this.ctrl, required this.label, required this.hint,
    required this.obscure, required this.onToggle, this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: const TextStyle(
        fontSize: 12, fontWeight: FontWeight.w700,
        color: _C.textSec, letterSpacing: 0.2)),
    const SizedBox(height: 6),
    Container(
      decoration: BoxDecoration(
          color: _C.surface, borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _C.border, width: 1.5)),
      child: TextField(
        controller: ctrl,
        obscureText: obscure,
        onChanged: onChanged,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
            color: _C.textPri),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: _C.textTer, fontSize: 13),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          suffixIcon: IconButton(
            onPressed: onToggle,
            icon: Icon(obscure ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
                color: _C.textTer, size: 18),
          ),
        ),
      ),
    ),
  ]);
}

// ─── Simple Confirm Dialog ────────────────────────────────────────────────────
class _SimpleConfirm extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String title, body, confirmLabel;
  const _SimpleConfirm({required this.icon, required this.accent,
    required this.title, required this.body, required this.confirmLabel});

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: _C.card,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    child: Padding(padding: const EdgeInsets.all(24), child: Column(
        mainAxisSize: MainAxisSize.min, children: [
      Container(width: 52, height: 52,
          decoration: BoxDecoration(
              color: accent.withOpacity(0.1), shape: BoxShape.circle),
          child: Icon(icon, color: accent, size: 24)),
      const SizedBox(height: 16),
      Text(title, textAlign: TextAlign.center, style: const TextStyle(
          fontSize: 17, fontWeight: FontWeight.w700,
          color: _C.textPri, letterSpacing: -0.3)),
      const SizedBox(height: 8),
      Text(body, textAlign: TextAlign.center, style: const TextStyle(
          fontSize: 13, color: _C.textSec, height: 1.5)),
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
              decoration: BoxDecoration(color: accent,
                  borderRadius: BorderRadius.circular(12)),
              child: Center(child: Text(confirmLabel, style: const TextStyle(
                  fontWeight: FontWeight.w700, color: Colors.white, fontSize: 13)))),
        )),
      ]),
    ])),
  );
}

// ─── Section Label ────────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool danger;
  const _SectionLabel(this.label, this.icon, {this.danger = false});

  @override
  Widget build(BuildContext context) => Row(children: [
    Container(width: 30, height: 30,
        decoration: BoxDecoration(
            color: (danger ? _C.rose : _C.teal).withOpacity(0.1),
            borderRadius: BorderRadius.circular(9)),
        child: Icon(icon, color: danger ? _C.rose : _C.teal, size: 16)),
    const SizedBox(width: 9),
    Text(label, style: TextStyle(
        fontSize: 15, fontWeight: FontWeight.w700,
        color: danger ? _C.rose : _C.textPri, letterSpacing: -0.3)),
  ]);
}

// ─── Mesh Painter ─────────────────────────────────────────────────────────────
class _MeshPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(Offset(size.width * 0.9, size.height * 0.1), 120,
        Paint()..color = _C.teal.withOpacity(0.07));
    canvas.drawCircle(Offset(size.width * 0.05, size.height * 0.88), 90,
        Paint()..color = _C.sky.withOpacity(0.06));
  }
  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}