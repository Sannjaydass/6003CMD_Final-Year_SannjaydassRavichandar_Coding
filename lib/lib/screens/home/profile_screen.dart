import 'notifications_screen.dart';
import 'package:medictrack/design/medic_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/auth_service.dart';
import '../auth/login_screen.dart';
import 'edit_profile_screen.dart';
import 'vitals_upload_screen.dart'; // ← HealthScorePanel + VitalsScoring
import 'dependants_screen.dart';

// ─── Design Tokens ────────────────────────────────────────────────────────────
class _C {
  static const navy       = MedicColors.c142F2B;
  static const navyLight  = MedicColors.c23473E;
  static const teal       = MedicColors.c28715D;
  static const tealDark   = MedicColors.c1D5849;
  static const amber      = MedicColors.cB77A27;
  static const rose       = MedicColors.cC05256;
  static const sky        = MedicColors.c477C91;
  static const violet     = MedicColors.c78659B;
  static const surface    = MedicColors.cF6F5F0;
  static const card       = MedicColors.cFFFFFF;
  static const border     = MedicColors.cE2E5DC;
  static const textPri    = MedicColors.c142F2B;
  static const textSec    = MedicColors.c63756D;
  static const textTer    = MedicColors.c83938B;
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with TickerProviderStateMixin {
  final AuthService _authService = AuthService();
  User? _currentUser;
  Map<String, dynamic>? _userData;
  bool _isLoading = true;

  late AnimationController _heroCtrl;
  late AnimationController _listCtrl;
  late Animation<double> _ringAnim;
  late Animation<double> _heroFade;

  @override
  void initState() {
    super.initState();
    _currentUser = _authService.currentUser;

    _heroCtrl = AnimationController(
        duration: const Duration(milliseconds: 1400), vsync: this);
    _listCtrl = AnimationController(
        duration: const Duration(milliseconds: 900), vsync: this);

    _ringAnim = CurvedAnimation(
        parent: _heroCtrl,
        curve: const Interval(0.3, 1.0, curve: Curves.easeOutCubic));
    _heroFade = CurvedAnimation(
        parent: _heroCtrl,
        curve: const Interval(0.0, 0.5, curve: Curves.easeIn));

    _loadUserData();
  }

  @override
  void dispose() {
    _heroCtrl.dispose();
    _listCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    if (_currentUser != null) {
      final data = await _authService.getUserData(_currentUser!.uid);
      if (mounted) {
        setState(() {
          _userData = data;
          _isLoading = false;
        });
        _heroCtrl.forward();
        await Future.delayed(const Duration(milliseconds: 300));
        if (mounted) _listCtrl.forward();
      }
    }
  }

  int get _completion {
    if (_userData == null) return 0;
    int done = 0;
    const total = 10;
    if (_userData!['fullName']?.isNotEmpty ?? false) done++;
    if (_userData!['email']?.isNotEmpty ?? false) done++;
    if (_userData!['age'] != null) done++;
    if (_userData!['phoneNumber']?.isNotEmpty ?? false) done++;
    if (_userData!['address']?.isNotEmpty ?? false) done++;
    if (_userData!['dateOfBirth']?.isNotEmpty ?? false) done++;
    if (_userData!['gender']?.isNotEmpty ?? false) done++;
    if (_userData!['emergencyContact']?.isNotEmpty ?? false) done++;
    final h = _userData!['healthInfo'] as Map<String, dynamic>? ?? {};
    if (h['bmi'] != null) done++;
    if (h['bloodType']?.isNotEmpty ?? false) done++;
    return ((done / total) * 100).round();
  }

  String _bmiCategory(double b) {
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

  Future<void> _logout() async {
    HapticFeedback.mediumImpact();
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => _LogoutDialog(),
    );
    if (ok == true) {
      await _authService.signOut();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
              (_) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const _LoadingScreen();

    final pct    = _completion;
    final health = _userData?['healthInfo'] as Map<String, dynamic>? ?? {};
    final bmi    = health['bmi'] != null
        ? (health['bmi'] as num).toDouble()
        : null;
    final conditions = List<String>.from(health['chronicConditions'] ?? []);
    final initials   = (_userData?['fullName'] as String? ?? 'U')
        .trim()
        .split(' ')
        .where((s) => s.isNotEmpty)
        .take(2)
        .map((s) => s[0].toUpperCase())
        .join();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _C.surface,
        body: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [

            // ── Hero Header ────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: FadeTransition(
                opacity: _heroFade,
                child: _HeroHeader(
                  initials:  initials,
                  userData:  _userData,
                  pct:       pct,
                  ringAnim:  _ringAnim,
                  patientIdCard: _PatientIdCard(
                    code: _userData?['patientCode'] as String? ?? '',
                    onTapDependants: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const DependantsScreen())),
                  ),
                  onEdit: () async {
                    await Navigator.push(context, MaterialPageRoute(
                        builder: (_) => const EditProfileScreen()));
                    _loadUserData();
                  },
                ),
              ),
            ),

            // ── Content ────────────────────────────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
              sliver: SliverList(
                delegate: SliverChildListDelegate([

                  // ── Quick Stats ──────────────────────────────────────────
                  _Animated(ctrl: _listCtrl, i: 1,
                      child: _QuickStats(healthInfo: health, bmi: bmi)),
                  const SizedBox(height: 28),

                  // ── Personal section ─────────────────────────────────────
                  _Animated(ctrl: _listCtrl, i: 1,
                      child: const _SectionHeader(
                          label: 'Personal',
                          icon: Icons.person_outline_rounded)),
                  const SizedBox(height: 12),
                  _Animated(ctrl: _listCtrl, i: 2,
                      child: _InfoGroup(items: [
                        _InfoRow(
                            icon: Icons.badge_outlined, label: 'Full Name',
                            value: _userData?['fullName'], accent: _C.teal),
                        _InfoRow(
                            icon: Icons.phone_outlined, label: 'Phone',
                            value: _userData?['phoneNumber'], accent: _C.sky),
                        _InfoRow(
                            icon: Icons.cake_outlined, label: 'Date of Birth',
                            value: _userData?['dateOfBirth'], accent: _C.amber),
                        _InfoRow(
                            icon: Icons.wc_outlined, label: 'Gender',
                            value: _userData?['gender'],
                            accent: _C.rose, isLast: true),
                      ])),
                  const SizedBox(height: 28),

                  // ── Account section ──────────────────────────────────────
                  _Animated(ctrl: _listCtrl, i: 3,
                      child: const _SectionHeader(
                          label: 'Account',
                          icon: Icons.shield_outlined)),
                  const SizedBox(height: 12),
                  _Animated(ctrl: _listCtrl, i: 4,
                      child: _InfoGroup(items: [
                        _InfoRow(
                            icon: Icons.cake_outlined, label: 'Age',
                            value: _userData?['age']?.toString(), accent: _C.teal),
                        _InfoRow(
                            icon: Icons.location_on_outlined, label: 'Address',
                            value: _userData?['address'], accent: _C.sky),
                        _InfoRow(
                            icon: Icons.emergency_outlined,
                            label: 'Emergency Contact',
                            value: _userData?['emergencyContact'],
                            accent: _C.rose, isLast: true),
                      ])),
                  const SizedBox(height: 28),

                  // ── Health section header ─────────────────────────────────
                  _Animated(ctrl: _listCtrl, i: 5,
                      child: Row(children: [
                        const _SectionHeader(
                            label: 'Health',
                            icon: Icons.favorite_border_rounded),
                        const Spacer(),
                        _EditPill(onTap: () async {
                          await Navigator.push(context, MaterialPageRoute(
                              builder: (_) => const EditProfileScreen()));
                          _loadUserData();
                        }),
                      ])),
                  const SizedBox(height: 12),

                  // ── Health Score Panel ────────────────────────────────────
                  _Animated(ctrl: _listCtrl, i: 6,
                      child: HealthScorePanel(
                        userData: _userData,
                        onTapScanVitals: () async {
                          await Navigator.push(context, MaterialPageRoute(
                              builder: (_) => const VitalsUploadScreen()));
                          _loadUserData();
                        },
                      )),
                  const SizedBox(height: 12),

                  // ── Body Metrics (BMI, Blood Type, Conditions) ────────────
                  _Animated(ctrl: _listCtrl, i: 7,
                      child: _HealthPanel(
                        bmi:         bmi,
                        bmiCategory: bmi != null ? _bmiCategory(bmi) : null,
                        bmiColor:    bmi != null ? _bmiColor(bmi)    : null,
                        bloodType:   health['bloodType'],
                        conditions:  conditions,
                        otherIllness: health['otherIllness'],
                        healthInfo:  health,
                      )),
                  const SizedBox(height: 32),

                  // ── Settings section ─────────────────────────────────────
                  _Animated(ctrl: _listCtrl, i: 8,
                      child: const _SectionHeader(
                          label: 'Settings',
                          icon: Icons.tune_rounded)),
                  const SizedBox(height: 12),
                  _Animated(ctrl: _listCtrl, i: 9,
                      child: _ActionGroup(items: [
                        _ActionTile(
                          icon: Icons.edit_outlined, label: 'Edit Profile',
                          subtitle: 'Update your information', accent: _C.teal,
                          onTap: () async {
                            await Navigator.push(context, MaterialPageRoute(
                                builder: (_) => const EditProfileScreen()));
                            _loadUserData();
                          },
                        ),
                        _ActionTile(
                          icon: Icons.monitor_heart_rounded,
                          label: 'Upload Vitals',
                          subtitle: 'Blood pressure & blood sugar',
                          accent: _C.rose,
                          onTap: () async {
                            await Navigator.push(context, MaterialPageRoute(
                                builder: (_) => const VitalsUploadScreen()));
                            _loadUserData();
                          },
                        ),
                        _ActionTile(
                          icon: Icons.people_alt_rounded,
                          label: 'Dependants',
                          subtitle: 'Track family members you’ve added',
                          accent: _C.amber,
                          onTap: () => Navigator.push(context, MaterialPageRoute(
                              builder: (_) => const DependantsScreen())),
                        ),
                        _ActionTile(
                          icon: Icons.lock_outline_rounded,
                          label: 'Change Password',
                          subtitle: 'Update your security',
                          accent: _C.sky,
                          onTap: () {},
                        ),
                        _ActionTile(
                          icon: Icons.notifications_outlined,
                          label: 'Notifications',
                          subtitle: 'Manage alerts & reminders',
                          accent: _C.amber,
                          onTap: () {},
                        ),
                        _ActionTile(
                          icon: Icons.help_outline_rounded,
                          label: 'Help & Support',
                          subtitle: 'FAQ, contact us',
                          accent: _C.violet,
                          onTap: () {},
                          isLast: true,
                        ),
                      ])),
                  const SizedBox(height: 14),
                  _Animated(ctrl: _listCtrl, i: 10,
                      child: _LogoutButton(onTap: _logout)),
                  const SizedBox(height: 20),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Loading Screen ───────────────────────────────────────────────────────────
class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _C.navy,
    body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(width: 44, height: 44,
          child: CircularProgressIndicator(strokeWidth: 2.5, color: _C.teal,
              backgroundColor: _C.teal.withOpacity(0.2))),
      const SizedBox(height: 20),
      const Text('Loading profile...',
          style: TextStyle(color: _C.teal, fontSize: 14, letterSpacing: 0.5)),
    ])),
  );
}

// ─── Hero Header ─────────────────────────────────────────────────────────────
class _HeroHeader extends StatelessWidget {
  final String initials;
  final Map<String, dynamic>? userData;
  final int pct;
  final Animation<double> ringAnim;
  final VoidCallback onEdit;
  final Widget patientIdCard;
  const _HeroHeader({required this.initials, required this.userData,
    required this.pct, required this.ringAnim, required this.onEdit, required this.patientIdCard});

  @override
  Widget build(BuildContext context) {
    final name = (userData?['fullName'] ?? 'Your profile').toString();
    final email = (userData?['email'] ?? '').toString();
    final photo = userData?['profileImage'];
    Widget initialsView() => Center(child: Text(initials,
        style: const TextStyle(color: MedicColors.forest, fontSize: 28, fontFamily: 'serif')));
    return MedicHeaderSurface(child: SafeArea(bottom: false,
      child: Padding(padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [const Expanded(child: MedicEyebrow('Your personal care space', light: true)),
            IconButton(tooltip: 'Notifications', onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const NotificationsScreen())),
                icon: const Icon(Icons.notifications_none_rounded, color: Colors.white)),
          ]),
          const SizedBox(height: 18),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 76, height: 76, clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(color: MedicColors.mint, borderRadius: BorderRadius.circular(25)),
                child: photo is String && photo.isNotEmpty
                    ? Image.network(photo, fit: BoxFit.cover, errorBuilder: (_, __, ___) => initialsView())
                    : initialsView()),
            const SizedBox(width: 18),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(fontFamily: 'serif', fontSize: 28,
                  height: 1.15, color: Colors.white, letterSpacing: -.6)),
              const SizedBox(height: 8),
              Text(email, style: const TextStyle(color: Color(0xFFCDDCD4), fontSize: 12),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
            ])),
          ]),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(child: Text('Profile details · $pct% complete',
                style: const TextStyle(color: Color(0xFFCDDCD4), fontSize: 12))),
            TextButton(onPressed: onEdit,
                style: TextButton.styleFrom(foregroundColor: MedicColors.mint),
                child: const Text('Edit profile')),
          ]),
          const SizedBox(height: 4),
          ClipRRect(borderRadius: BorderRadius.circular(8), child: AnimatedBuilder(
              animation: ringAnim,
              builder: (_, __) => LinearProgressIndicator(
                  value: (ringAnim.value * pct / 100).clamp(0.0, 1.0), minHeight: 5,
                  backgroundColor: Colors.white12, color: MedicColors.mint))),
          const SizedBox(height: 18),
          const Divider(color: Colors.white24, height: 1),
          patientIdCard,
        ]),
      ),
    ));
  }
}

class _NavBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _NavBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 40, height: 40,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Icon(icon, color: Colors.white.withOpacity(0.85), size: 20),
    ),
  );
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  const _Chip({required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    decoration: BoxDecoration(
      color: color.withOpacity(0.15),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: color.withOpacity(0.3)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: color, size: 13),
      const SizedBox(width: 5),
      Flexible(child: Text(text, overflow: TextOverflow.ellipsis,
          style: TextStyle(color: color, fontSize: 12,
              fontWeight: FontWeight.w600))),
    ]),
  );
}

class _CompletionBar extends StatelessWidget {
  final int pct;
  const _CompletionBar({required this.pct});

  Color get _color {
    if (pct >= 80) return _C.teal;
    if (pct >= 50) return _C.amber;
    return _C.rose;
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.07),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: Colors.white.withOpacity(0.1)),
    ),
    child: Row(children: [
      Icon(pct >= 80 ? Icons.verified_rounded : Icons.info_outline_rounded,
          color: _color, size: 18),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Profile Completion',
              style: TextStyle(color: Colors.white.withOpacity(0.7),
                  fontSize: 12, fontWeight: FontWeight.w500)),
          const Spacer(),
          Text('$pct%', style: TextStyle(
              color: _color, fontSize: 13, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct / 100,
            backgroundColor: Colors.white.withOpacity(0.1),
            valueColor: AlwaysStoppedAnimation<Color>(_color),
            minHeight: 5,
          ),
        ),
      ])),
    ]),
  );
}

// ─── Patient ID card (share to be added as a dependant) ───────────────────────
class _PatientIdCard extends StatelessWidget {
  final String code;
  final VoidCallback onTapDependants;
  const _PatientIdCard({required this.code, required this.onTapDependants});

  void _copy(BuildContext context) {
    if (code.isEmpty) return;
    Clipboard.setData(ClipboardData(text: code));
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('Patient ID copied', style: TextStyle(
          fontWeight: FontWeight.w600, fontSize: 13)),
      backgroundColor: _C.navy,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.only(top: 16),
    child: Row(children: [
      Container(width: 44, height: 44,
          decoration: BoxDecoration(
              color: MedicColors.mint.withOpacity(0.15), borderRadius: BorderRadius.circular(13)),
          child: const Icon(Icons.badge_rounded, color: MedicColors.mint, size: 22)),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Your Patient ID', style: TextStyle(
            color: Colors.white.withOpacity(0.6), fontSize: 11, fontWeight: FontWeight.w600)),
        const SizedBox(height: 3),
        Text(code.isNotEmpty ? code : '—', style: const TextStyle(
            color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: 3)),
      ])),
      GestureDetector(
        onTap: () => _copy(context),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(11)),
          child: const Icon(Icons.copy_rounded, color: Colors.white, size: 17),
        ),
      ),
      const SizedBox(width: 8),
      GestureDetector(
        onTap: onTapDependants,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: MedicColors.mint.withOpacity(0.18), borderRadius: BorderRadius.circular(11)),
          child: const Icon(Icons.people_alt_rounded, color: MedicColors.mint, size: 17),
        ),
      ),
    ]),
  );
}

// ─── Quick Stats ──────────────────────────────────────────────────────────────
class _QuickStats extends StatelessWidget {
  final Map<String, dynamic> healthInfo;
  final double? bmi;
  const _QuickStats({required this.healthInfo, required this.bmi});

  @override
  Widget build(BuildContext context) {
    final bmiVal = bmi?.toStringAsFixed(1) ?? '—';
    final blood  = healthInfo['bloodType'] as String? ?? '—';
    final height = healthInfo['height']?.toString() ?? '—';
    final weight = healthInfo['weight']?.toString() ?? '—';

    return Row(children: [
      Expanded(child: _StatChip(
          value: bmiVal, label: 'BMI',
          icon: Icons.monitor_weight_outlined, color: _C.teal)),
      const SizedBox(width: 10),
      Expanded(child: _StatChip(
          value: blood, label: 'Blood',
          icon: Icons.bloodtype_outlined, color: _C.rose)),
      const SizedBox(width: 10),
      Expanded(child: _StatChip(
          value: height == '—' ? height : '${height}cm', label: 'Height',
          icon: Icons.height_rounded, color: _C.sky)),
      const SizedBox(width: 10),
      Expanded(child: _StatChip(
          value: weight == '—' ? weight : '${weight}kg', label: 'Weight',
          icon: Icons.fitness_center_rounded, color: _C.amber)),
    ]);
  }
}

class _StatChip extends StatelessWidget {
  final String value, label;
  final IconData icon;
  final Color color;
  const _StatChip({required this.value, required this.label,
    required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
    decoration: BoxDecoration(
      color: _C.card,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: _C.border),
      boxShadow: [BoxShadow(color: MedicColors.forest.withOpacity(0.025),
          blurRadius: 10, offset: const Offset(0, 3))],
    ),
    child: Column(children: [
      Container(width: 34, height: 34,
          decoration: BoxDecoration(
              color: color.withOpacity(0.12), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 17)),
      const SizedBox(height: 8),
      Text(value, style: const TextStyle(
          fontSize: 13, fontWeight: FontWeight.w700,
          color: _C.textPri, letterSpacing: -0.2),
          maxLines: 1, overflow: TextOverflow.ellipsis),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(
          fontSize: 10, color: _C.textTer, fontWeight: FontWeight.w500),
          maxLines: 1, overflow: TextOverflow.ellipsis),
    ]),
  );
}

// ─── Section Header ───────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String label;
  final IconData icon;
  const _SectionHeader({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) => Row(children: [
    Container(width: 32, height: 32,
        decoration: BoxDecoration(
            color: _C.teal.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: _C.teal, size: 17)),
    const SizedBox(width: 10),
    Text(label, style: const TextStyle(
        fontSize: 16, fontWeight: FontWeight.w700,
        color: _C.textPri, letterSpacing: -0.3)),
  ]);
}

class _EditPill extends StatelessWidget {
  final VoidCallback onTap;
  const _EditPill({required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: _C.teal.withOpacity(0.1),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _C.teal.withOpacity(0.3)),
      ),
      child: const Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.edit_outlined, color: _C.teal, size: 13),
        SizedBox(width: 5),
        Text('Edit', style: TextStyle(
            color: _C.teal, fontSize: 12, fontWeight: FontWeight.w700)),
      ]),
    ),
  );
}

// ─── Info Group ───────────────────────────────────────────────────────────────
class _InfoGroup extends StatelessWidget {
  final List<_InfoRow> items;
  const _InfoGroup({required this.items});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: _C.card, borderRadius: BorderRadius.circular(24),
      border: Border.all(color: _C.border),
      boxShadow: [BoxShadow(color: MedicColors.forest.withOpacity(0.025),
          blurRadius: 12, offset: const Offset(0, 3))],
    ),
    child: Column(children: items),
  );
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;
  final Color accent;
  final bool isLast;

  const _InfoRow({required this.icon, required this.label,
    required this.value, required this.accent, this.isLast = false});

  @override
  Widget build(BuildContext context) {
    final has = value != null && value!.isNotEmpty;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(children: [
          Container(width: 36, height: 36,
              decoration: BoxDecoration(
                  color: accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: accent, size: 18)),
          const SizedBox(width: 14),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(
                fontSize: 11, color: _C.textTer,
                fontWeight: FontWeight.w600, letterSpacing: 0.3)),
            const SizedBox(height: 3),
            Text(has ? value! : 'Not set',
                maxLines: 2, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                    color: has ? _C.textPri : _C.textTer)),
          ])),
          Container(width: 7, height: 7,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: has ? _C.teal : _C.border)),
        ]),
      ),
      if (!isLast)
        Divider(height: 1, indent: 68, endIndent: 18, color: _C.border),
    ]);
  }
}

// ─── Health Panel (BMI + Blood Type + Conditions + Notes) ────────────────────
class _HealthPanel extends StatelessWidget {
  final double? bmi;
  final String? bmiCategory, bloodType, otherIllness;
  final Color? bmiColor;
  final List<String> conditions;
  final Map<String, dynamic> healthInfo;

  const _HealthPanel({required this.bmi, required this.bmiCategory,
    required this.bmiColor, required this.bloodType, required this.conditions,
    required this.otherIllness, required this.healthInfo});

  @override
  Widget build(BuildContext context) => Column(children: [

    // BMI card
    Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _C.card, borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _C.border),
        boxShadow: [BoxShadow(color: MedicColors.forest.withOpacity(0.025),
            blurRadius: 12, offset: const Offset(0, 3))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 36, height: 36,
              decoration: BoxDecoration(
                  color: (bmiColor ?? _C.textTer).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.monitor_weight_outlined,
                  color: bmiColor ?? _C.textTer, size: 18)),
          const SizedBox(width: 12),
          const Text('Body Mass Index', style: TextStyle(
              fontSize: 14, fontWeight: FontWeight.w700, color: _C.textPri)),
          const Spacer(),
          if (bmi != null && bmiCategory != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: bmiColor!.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(24)),
              child: Text(bmiCategory!, style: TextStyle(
                  color: bmiColor, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
        ]),
        if (bmi != null) ...[
          const SizedBox(height: 16),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(bmi!.toStringAsFixed(1), style: TextStyle(
                fontSize: 40, fontWeight: FontWeight.w700,
                color: bmiColor, letterSpacing: -1.5)),
            const SizedBox(width: 8),
            const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: Text('kg/m²', style: TextStyle(
                  color: _C.textSec, fontSize: 13, fontWeight: FontWeight.w500)),
            ),
            const Spacer(),
            if (healthInfo['height'] != null && healthInfo['weight'] != null)
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                _Mini('${healthInfo['height']} cm', 'Height'),
                const SizedBox(height: 4),
                _Mini('${healthInfo['weight']} kg', 'Weight'),
              ]),
          ]),
          const SizedBox(height: 14),
          _BmiScale(bmi: bmi!),
        ] else
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text('Add height & weight to calculate BMI',
                style: TextStyle(color: _C.textTer, fontSize: 13)),
          ),
      ]),
    ),
    const SizedBox(height: 12),

    // Blood Type + Conditions row
    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(flex: 2, child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: _C.card, borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _C.border),
            boxShadow: [BoxShadow(color: MedicColors.forest.withOpacity(0.025),
                blurRadius: 12, offset: const Offset(0, 3))]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 36, height: 36,
              decoration: BoxDecoration(
                  color: _C.rose.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.bloodtype_outlined, color: _C.rose, size: 18)),
          const SizedBox(height: 12),
          Text(bloodType ?? '—', style: TextStyle(
              fontSize: 28, fontWeight: FontWeight.w700,
              color: bloodType != null ? _C.rose : _C.textTer,
              letterSpacing: -0.5)),
          const SizedBox(height: 2),
          const Text('Blood Type', style: TextStyle(
              fontSize: 11, color: _C.textTer,
              fontWeight: FontWeight.w600, letterSpacing: 0.3)),
        ]),
      )),
      const SizedBox(width: 10),
      Expanded(flex: 3, child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: _C.card, borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _C.border),
            boxShadow: [BoxShadow(color: MedicColors.forest.withOpacity(0.025),
                blurRadius: 12, offset: const Offset(0, 3))]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 36, height: 36,
                decoration: BoxDecoration(
                    color: _C.violet.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.health_and_safety_outlined,
                    color: _C.violet, size: 18)),
            const Spacer(),
            if (conditions.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: _C.violet.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10)),
                child: Text('${conditions.length}',
                    style: const TextStyle(color: _C.violet,
                        fontSize: 12, fontWeight: FontWeight.w700)),
              ),
          ]),
          const SizedBox(height: 10),
          const Text('Conditions', style: TextStyle(
              fontSize: 11, color: _C.textTer,
              fontWeight: FontWeight.w600, letterSpacing: 0.3)),
          const SizedBox(height: 8),
          if (conditions.isEmpty)
            const Text('None reported', style: TextStyle(
                color: _C.textTer, fontSize: 13, fontWeight: FontWeight.w500))
          else
            Wrap(spacing: 5, runSpacing: 5,
                children: conditions.take(4).map((c) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                      color: _C.violet.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(c, style: const TextStyle(
                      color: _C.violet, fontSize: 11,
                      fontWeight: FontWeight.w600)),
                )).toList()),
        ]),
      )),
    ]),

    // Medical notes
    if (otherIllness != null && otherIllness!.isNotEmpty) ...[
      const SizedBox(height: 10),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _C.amber.withOpacity(0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _C.amber.withOpacity(0.2)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.note_alt_outlined, color: _C.amber, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Medical Notes', style: TextStyle(
                fontSize: 11, color: _C.textSec,
                fontWeight: FontWeight.w700, letterSpacing: 0.3)),
            const SizedBox(height: 4),
            Text(otherIllness!, style: const TextStyle(
                fontSize: 13, color: _C.textPri,
                fontWeight: FontWeight.w500, height: 1.5)),
          ])),
        ]),
      ),
    ],
  ]);
}

class _Mini extends StatelessWidget {
  final String value, label;
  const _Mini(this.value, this.label);
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(value, style: const TextStyle(
            fontSize: 13, fontWeight: FontWeight.w700, color: _C.textPri)),
        Text(label, style: const TextStyle(fontSize: 10, color: _C.textTer)),
      ]);
}

class _BmiScale extends StatelessWidget {
  final double bmi;
  const _BmiScale({required this.bmi});

  @override
  Widget build(BuildContext context) {
    final pos = ((bmi - 15) / 25).clamp(0.0, 1.0);
    return Column(children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(height: 8, child: Row(children: [
          Expanded(flex: 2, child: Container(color: _C.sky)),
          Expanded(flex: 3, child: Container(color: _C.teal)),
          Expanded(flex: 2, child: Container(color: _C.amber)),
          Expanded(flex: 2, child: Container(color: _C.rose)),
        ])),
      ),
      const SizedBox(height: 6),
      LayoutBuilder(builder: (_, c) => Stack(children: [
        const SizedBox(height: 14),
        Positioned(
          left: (c.maxWidth * pos - 6).clamp(0.0, c.maxWidth - 12),
          child: Container(width: 12, height: 12,
              decoration: BoxDecoration(
                  color: Colors.white, shape: BoxShape.circle,
                  border: Border.all(color: _C.textPri, width: 2.5))),
        ),
      ])),
      const SizedBox(height: 2),
      const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('15',   style: TextStyle(fontSize: 10, color: _C.textTer)),
        Text('18.5', style: TextStyle(fontSize: 10, color: _C.textTer)),
        Text('25',   style: TextStyle(fontSize: 10, color: _C.textTer)),
        Text('30',   style: TextStyle(fontSize: 10, color: _C.textTer)),
        Text('40',   style: TextStyle(fontSize: 10, color: _C.textTer)),
      ]),
    ]);
  }
}

// ─── Action Group ─────────────────────────────────────────────────────────────
class _ActionGroup extends StatelessWidget {
  final List<_ActionTile> items;
  const _ActionGroup({required this.items});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: _C.card, borderRadius: BorderRadius.circular(24),
      border: Border.all(color: _C.border),
      boxShadow: [BoxShadow(color: MedicColors.forest.withOpacity(0.025),
          blurRadius: 12, offset: const Offset(0, 3))],
    ),
    child: Column(children: items),
  );
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label, subtitle;
  final Color accent;
  final VoidCallback onTap;
  final bool isLast;

  const _ActionTile({required this.icon, required this.label,
    required this.subtitle, required this.accent, required this.onTap,
    this.isLast = false});

  @override
  Widget build(BuildContext context) => Column(children: [
    Material(color: Colors.transparent,
        child: InkWell(
          onTap: () { HapticFeedback.selectionClick(); onTap(); },
          borderRadius: isLast
              ? const BorderRadius.only(
              bottomLeft:  Radius.circular(20),
              bottomRight: Radius.circular(20))
              : BorderRadius.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
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
                    fontSize: 14, fontWeight: FontWeight.w700,
                    color: _C.textPri)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(
                    fontSize: 12, color: _C.textTer,
                    fontWeight: FontWeight.w400)),
              ])),
              const Icon(Icons.chevron_right_rounded,
                  color: _C.textTer, size: 20),
            ]),
          ),
        )),
    if (!isLast)
      Divider(height: 1, indent: 70, endIndent: 18, color: _C.border),
  ]);
}

// ─── Logout Button ────────────────────────────────────────────────────────────
class _LogoutButton extends StatelessWidget {
  final VoidCallback onTap;
  const _LogoutButton({required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: _C.rose.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _C.rose.withOpacity(0.25)),
        ),
        child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.logout_rounded, color: _C.rose, size: 20),
          SizedBox(width: 10),
          Text('Sign Out', style: TextStyle(
              color: _C.rose, fontSize: 15,
              fontWeight: FontWeight.w700, letterSpacing: 0.2)),
        ]),
      ),
    ),
  );
}

// ─── Logout Dialog ────────────────────────────────────────────────────────────
class _LogoutDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: _C.card,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 56, height: 56,
            decoration: BoxDecoration(
                color: _C.rose.withOpacity(0.1), shape: BoxShape.circle),
            child: const Icon(Icons.logout_rounded, color: _C.rose, size: 26)),
        const SizedBox(height: 18),
        const Text('Sign out?', style: TextStyle(
            fontSize: 20, fontWeight: FontWeight.w700, color: _C.textPri)),
        const SizedBox(height: 8),
        const Text('You will need to sign back in to\naccess your account.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _C.textSec, fontSize: 14, height: 1.5)),
        const SizedBox(height: 24),
        Row(children: [
          Expanded(child: GestureDetector(
            onTap: () => Navigator.pop(context, false),
            child: Container(height: 46,
                decoration: BoxDecoration(
                    color: _C.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _C.border)),
                child: const Center(child: Text('Cancel', style: TextStyle(
                    fontWeight: FontWeight.w600, color: _C.textSec,
                    fontSize: 14)))),
          )),
          const SizedBox(width: 12),
          Expanded(child: GestureDetector(
            onTap: () => Navigator.pop(context, true),
            child: Container(height: 46,
                decoration: BoxDecoration(
                    color: _C.rose,
                    borderRadius: BorderRadius.circular(14)),
                child: const Center(child: Text('Sign Out', style: TextStyle(
                    fontWeight: FontWeight.w700, color: Colors.white,
                    fontSize: 14)))),
          )),
        ]),
      ]),
    ),
  );
}

// ─── Animated List Item ───────────────────────────────────────────────────────
class _Animated extends StatelessWidget {
  final AnimationController ctrl;
  final int i;
  final Widget child;
  const _Animated({required this.ctrl, required this.i, required this.child});

  @override
  Widget build(BuildContext context) {
    final start = (i * 0.08).clamp(0.0, 0.8);
    final end   = (start + 0.4).clamp(0.0, 1.0);
    final anim  = CurvedAnimation(
        parent: ctrl,
        curve: Interval(start, end, curve: Curves.easeOutQuart));
    return AnimatedBuilder(
      animation: anim,
      builder: (_, c) => Transform.translate(
        offset: Offset(0, 20 * (1 - anim.value)),
        child: Opacity(opacity: anim.value.clamp(0.0, 1.0), child: c),
      ),
      child: child,
    );
  }
}

// ─── Ring Painter ─────────────────────────────────────────────────────────────
class _RingPainter extends CustomPainter {
  final double progress;
  final Color color, trackColor;
  const _RingPainter({required this.progress, required this.color,
    required this.trackColor});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 4;
    canvas.drawCircle(c, r, Paint()
      ..color = trackColor ..strokeWidth = 5
      ..style = PaintingStyle.stroke ..strokeCap = StrokeCap.round);
    canvas.drawArc(Rect.fromCircle(center: c, radius: r),
        -1.5708, 2 * 3.14159 * progress, false,
        Paint()..color = color ..strokeWidth = 5
          ..style = PaintingStyle.stroke ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress || old.color != color;
}

// ─── Mesh Background Painter ──────────────────────────────────────────────────
class _MeshPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(Offset(size.width * 0.85, size.height * 0.15), 140,
        Paint()..color = _C.teal.withOpacity(0.08));
    canvas.drawCircle(Offset(size.width * 0.1, size.height * 0.8), 100,
        Paint()..color = const Color(0xFF4FACFE).withOpacity(0.06));
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ─── Progress Ring Painter (external compatibility) ───────────────────────────
class ProgressRingPainter extends CustomPainter {
  final double progress;
  final List<Color> gradientColors;
  ProgressRingPainter({required this.progress, required this.gradientColors});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;
    canvas.drawCircle(c, r, Paint()
      ..color = Colors.white.withOpacity(0.3) ..strokeWidth = 8
      ..style = PaintingStyle.stroke ..strokeCap = StrokeCap.round);
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawArc(rect, -3.14 / 2, 2 * 3.14 * progress, false,
        Paint()
          ..shader = SweepGradient(
              colors: gradientColors,
              startAngle: -3.14 / 2,
              endAngle: 3.14 * 2 - 3.14 / 2).createShader(rect)
          ..strokeWidth = 8
          ..style = PaintingStyle.stroke ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}