import 'daily_health_score_card.dart';
import 'health_monitoring_screen.dart';
import 'dart:async';
import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'dose_history_screen.dart';
import 'health_records_screen.dart';
import 'health_score_breakdown_screen.dart';
import 'dependant_dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../design/medic_design.dart';
import '../../services/auth_service.dart';
import '../../services/notification_service.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';
import 'scan_medicine_screen.dart';
import 'medicine_inventory_screen.dart';
import 'medicine_details_screen.dart';
import 'notifications_screen.dart';
import 'safe_disposal_screen.dart';
import 'dependants_screen.dart';
import 'health_analysis_screen.dart';
import 'vitals_upload_screen.dart';
import 'journal_screen.dart';
import '../../services/dose_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _auth = AuthService();
  final _notifications = NotificationService();
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _medicineSubscription;
  AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> _medicineSnapshot =
  const AsyncSnapshot.nothing();
  Timer? _medicineLoadTimer;
  int _medicineGeneration = 0;
  Stream<int>? _unreadCount;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _userDoc;
  int _tab = 0;
  String _name = 'there';
  StreamSubscription<RemoteMessage>? _pushTap;
  StreamSubscription<String>? _tokenRefresh;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _accountTypeSub;
  // 'patient' or 'dependant' — a dependant/caregiver account (see the
  // role picker added to signup) never gets prompted for its own vitals
  // or a health score; it's gated out of the dashboard sections below.
  String _accountType = 'patient';
  @override
  void initState() {
    super.initState();
    final user = _auth.currentUser;
    if (user != null) {
      _watchMedicines(user.uid);
      _unreadCount = _notifications.getUnreadCount(user.uid);
      _userDoc = FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots();
      _accountTypeSub = _userDoc!.listen((doc) {
        final type = doc.data()?['accountType']?.toString() ?? 'patient';
        if (mounted && type != _accountType) setState(() => _accountType = type);
      });
      _loadName();
      _notifications.onTap = _handleNotification;
      _pushTap = FirebaseMessaging.onMessageOpenedApp.listen((m) => _handleNotification(jsonEncode(m.data)));
      _tokenRefresh = FirebaseMessaging.instance.onTokenRefresh.listen((_) {
        final uid = _auth.currentUser?.uid;
        if (uid != null) _notifications.saveTokenToFirestore(uid);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkLaunch());
      _notifications.saveTokenToFirestore(user.uid).catchError((Object e) {
        debugPrint('Notification token could not be refreshed: $e');
      });
    }
  }

  // One listener supplies overview, reminders and cabinet. The timer only
  // watches the first result; an unchanged live query is not a failure.
  Future<void> _watchMedicines(String uid, {bool notify = false}) async {
    final generation = ++_medicineGeneration;
    _medicineLoadTimer?.cancel();
    final previous = _medicineSubscription;
    _medicineSubscription = null;

    void reset() {
      _medicineSnapshot = _medicineSnapshot.hasData
          ? AsyncSnapshot.withData(
          ConnectionState.waiting, _medicineSnapshot.data!)
          : const AsyncSnapshot.waiting();
    }

    if (notify && mounted) {
      setState(reset);
    } else {
      reset();
    }

    try {
      if (previous != null) await previous.cancel();
      if (!mounted || generation != _medicineGeneration) return;

      _medicineLoadTimer = Timer(const Duration(seconds: 15), () {
        if (!mounted || generation != _medicineGeneration ||
            _medicineSnapshot.hasData || _medicineSnapshot.hasError) return;
        setState(() {
          _medicineSnapshot = AsyncSnapshot.withError(
            ConnectionState.active,
            TimeoutException('Medicine records are taking too long to load.'),
          );
        });
        // Keep listening so a delayed result can still recover the screen.
      });

      _medicineSubscription = FirebaseFirestore.instance
          .collection('medicines')
          .where('userId', isEqualTo: uid)
          .snapshots()
          .listen((snapshot) {
        if (!mounted || generation != _medicineGeneration) return;
        _medicineLoadTimer?.cancel();
        setState(() {
          _medicineSnapshot =
              AsyncSnapshot.withData(ConnectionState.active, snapshot);
        });
      }, onError: (Object error, StackTrace stack) {
        _setMedicineError(error, stack, generation);
      }, onDone: () {
        if (!mounted || generation != _medicineGeneration) return;
        _medicineLoadTimer?.cancel();
        if (!_medicineSnapshot.hasData && !_medicineSnapshot.hasError) {
          _setMedicineError(
            StateError('Medicine listener closed before returning records.'),
            StackTrace.current,
            generation,
          );
        }
      });
    } catch (error, stack) {
      _setMedicineError(error, stack, generation);
    }
  }

  void _setMedicineError(Object error, StackTrace stack, int generation) {
    if (!mounted || generation != _medicineGeneration) return;
    _medicineLoadTimer?.cancel();
    debugPrint('Medicine query failed: $error');
    setState(() {
      _medicineSnapshot =
          AsyncSnapshot.withError(ConnectionState.active, error, stack);
    });
  }

  String _medicineErrorText(Object? error) {
    if (error is TimeoutException) {
      return 'This is taking longer than expected. Check your connection and retry.';
    }
    if (error is FirebaseException) {
      switch (error.code) {
        case 'permission-denied':
          return 'Your account cannot access these records. Please contact support.';
        case 'unauthenticated':
          return 'Your session has expired. Please sign in again.';
        case 'unavailable':
          return 'The medicine service is currently unreachable. Check your connection and retry.';
        case 'failed-precondition':
          return 'Your medicine records are temporarily unavailable. Please retry.';
      }
    }
    return 'Your records could not be loaded. Please retry.';
  }

  Future<void> _checkLaunch() async {
    final local = await _notifications.localPlugin.getNotificationAppLaunchDetails();
    if (!mounted) return;
    if (local?.didNotificationLaunchApp == true) _handleNotification(local?.notificationResponse?.payload);
    final push = await FirebaseMessaging.instance.getInitialMessage();
    if (mounted && push != null) _handleNotification(jsonEncode(push.data));
  }

  void _handleNotification(String? payload) {
    if (!mounted || payload == null) return;
    if (payload.startsWith('dose:')) {
      _open(DoseHistoryScreen(medicineId: payload.substring(5)));
      return;
    }
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      if (data['type'] == 'health_monitoring' && data['ownerId'] is String) {
        final owner = data['ownerId'] as String;
        _open(owner == _auth.currentUser?.uid ? const HealthMonitoringScreen() : DependantDashboardScreen(dependantId: owner, dependantName: 'Dependant'));
        return;
      }
      if (data['type'] == 'missed_dose' && data['dependantId'] is String) {
        _open(DependantDashboardScreen(dependantId: data['dependantId'] as String, dependantName: 'Dependant'));
      }
    } catch (_) { /* Non-dose notification payload. */ }
  }

  @override
  void dispose() {
    ++_medicineGeneration;
    _medicineLoadTimer?.cancel();
    _medicineSubscription?.cancel();
    _notifications.onTap = null;
    _pushTap?.cancel();
    _tokenRefresh?.cancel();
    _accountTypeSub?.cancel();
    super.dispose();
  }

  Future<void> _loadName() async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      final data = await _auth.getUserData(user.uid);
      if (!mounted) return;
      final value = (data?['fullName'] ?? user.displayName ?? 'there').toString().trim();
      setState(() => _name = value.isEmpty ? 'there' : value.split(' ').first);
    } catch (_) { /* Greeting is optional; the dashboard remains usable. */ }
  }

  void _retryMedicines() {
    final uid = _auth.currentUser?.uid;
    if (uid != null) _watchMedicines(uid, notify: true);
  }

  Future<void> _refreshDashboard() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || !mounted) return;
    await _watchMedicines(uid, notify: true);
    await _loadName().timeout(
      const Duration(seconds: 10),
      onTimeout: () {},
    );
  }

  Future<void> _openHealthScore() async {
    HapticFeedback.selectionClick();
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const HealthScoreBreakdownScreen()));
    if (mounted) await _refreshDashboard();
  }

  void _open(Widget page) {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: _tab == 0 ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
    child: Scaffold(
      backgroundColor: MedicColors.canvas,
      body: IndexedStack(index: _tab, children: [
        _dashboard(), const MedicineInventoryScreen(),
        const ProfileScreen(), const SettingsScreen(),
      ]),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(color: Colors.white,
            border: Border(top: BorderSide(color: MedicColors.line))),
        child: SafeArea(top: false, child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          child: Row(children: [
            _nav(0, Icons.space_dashboard_outlined, 'Today'),
            _nav(1, Icons.medication_outlined, 'Medicines'),
            _nav(2, Icons.person_outline_rounded, 'My health'),
            _nav(3, Icons.tune_rounded, 'Settings'),
          ]),
        )),
      ),
    ),
  );

  Widget _nav(int index, IconData icon, String label) {
    final selected = index == _tab;
    return Expanded(child: Semantics(selected: selected, button: true,
      child: InkWell(borderRadius: BorderRadius.circular(20),
        onTap: () { HapticFeedback.selectionClick(); setState(() => _tab = index); },
        child: Padding(padding: const EdgeInsets.symmetric(vertical: 5),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              AnimatedContainer(duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
                  decoration: BoxDecoration(color: selected ? MedicColors.forest : Colors.transparent,
                      borderRadius: BorderRadius.circular(18)),
                  child: Icon(icon, size: 22, color: selected ? MedicColors.mint : MedicColors.muted)),
              const SizedBox(height: 5),
              Text(label, maxLines: 1, style: TextStyle(fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? MedicColors.forest : MedicColors.muted)),
            ])),
      ),
    ));
  }

  Widget _dashboard() {
    if (_auth.currentUser == null) {
      return const SafeArea(child: Center(child: Text('Sign in to see your care dashboard.')));
    }
    final now = DateTime.now();
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final greeting = now.hour < 12 ? 'Good morning' : now.hour < 17 ? 'Good afternoon' : 'Good evening';
    return SafeArea(bottom: false, child: RefreshIndicator(
      onRefresh: _refreshDashboard,
      color: MedicColors.green,
      child: ListView(physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 28), children: [
            MedicFadeIn(child: Row(children: [const MedicMark(size: 42), const SizedBox(width: 10),
              const Expanded(child: Text('MedicTrack', style: TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 18, letterSpacing: -.6))),
              StreamBuilder<int>(stream: _unreadCount,
                  builder: (context, snapshot) => Stack(children: [
                    IconButton.filledTonal(
                        style: IconButton.styleFrom(backgroundColor: Colors.white),
                        tooltip: 'Notifications', onPressed: () => _open(const NotificationsScreen()),
                        icon: const Icon(Icons.notifications_none_rounded, color: MedicColors.forest)),
                    if ((snapshot.data ?? 0) > 0)
                      Positioned(right: 10, top: 9, child: Container(width: 8, height: 8,
                          decoration: const BoxDecoration(color: Color(0xFFC05256), shape: BoxShape.circle))),
                  ])),
            ])),
            const SizedBox(height: 30),
            MedicFadeIn(delay: const Duration(milliseconds: 80),
              child: MedicEyebrow('${days[now.weekday - 1]} / ${now.day} ${months[now.month - 1]}')),
            const SizedBox(height: 10),
            MedicFadeIn(delay: const Duration(milliseconds: 150),
              child: Text('$greeting,\n$_name.', style: const TextStyle(fontFamily: 'serif',
                fontSize: 38, height: 1.12, letterSpacing: -1.2, color: MedicColors.forest))),
            const SizedBox(height: 10),
            MedicFadeIn(delay: const Duration(milliseconds: 220),
              child: const Text('A little care. Every day.', style: TextStyle(color: MedicColors.muted, fontSize: 14))),
            const SizedBox(height: 24),
            _pendingRecheckBanner(),
            _healthScoreSection(),
            const SizedBox(height: 14),
            if (_accountType != 'dependant') ...[
              const MonitoringLaunchCard(),
              const SizedBox(height: 20),
            ],
            _quickActionsRow(),
            const SizedBox(height: 24),
            _overview(),
            const SizedBox(height: 24),
            _section('Your care toolkit'),
            const SizedBox(height: 14),
            LayoutBuilder(builder: (context, constraints) => Wrap(spacing: 12, runSpacing: 12,
                children: [
                  _tool(constraints.maxWidth, 'Scan medicine', 'Add a label or photo', Icons.document_scanner_outlined,
                      const Color(0xFFE3ECD8), () => _open(const ScanMedicineScreen())),
                  // Health insights / Add vitals are patient-only — a
                  // dependant/caregiver account only manages medicines.
                  if (_accountType != 'dependant')
                    _tool(constraints.maxWidth, 'Health insights', 'Explore your records', Icons.insights_rounded,
                        const Color(0xFFECE6F1), () => _open(const HealthAnalysisScreen())),
                  _tool(constraints.maxWidth, 'Family care', 'Care, together', Icons.people_outline_rounded,
                      const Color(0xFFF2E8D8), () => _open(const DependantsScreen())),
                  if (_accountType != 'dependant')
                    _tool(constraints.maxWidth, 'Add vitals', 'Keep details up to date', Icons.monitor_heart_outlined,
                        const Color(0xFFE0EBEE), () => _open(const VitalsUploadScreen())),
                ])),
            const SizedBox(height: 28),
            _section('Your reminders', action: 'Record doses', onTap: () => _open(const DoseHistoryScreen())),
            const SizedBox(height: 12),
            _reminderList(),
            const SizedBox(height: 28),
            _section('Medicine cabinet', action: 'View all', onTap: () => setState(() => _tab = 1)),
            const SizedBox(height: 12),
            _recentMedicines(),
            const SizedBox(height: 20),
            Material(color: const Color(0xFFEAEDE3), borderRadius: BorderRadius.circular(22),
                child: InkWell(borderRadius: BorderRadius.circular(22),
                    onTap: () => _open(const SafeDisposalScreen()),
                    child: const Padding(padding: EdgeInsets.all(18), child: Row(children: [
                      Icon(Icons.eco_outlined, color: MedicColors.green, size: 28), SizedBox(width: 14),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Care beyond the cabinet', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                        SizedBox(height: 4), Text('Explore safe medicine disposal', style: TextStyle(fontSize: 12, color: MedicColors.muted)),
                      ])), SizedBox(width: 8), Icon(Icons.arrow_forward_rounded, size: 18),
                    ])))),
            const SizedBox(height: 24),
            const Center(child: MedicEyebrow('Your health. Thoughtfully organised.')),
          ]),
    ));
  }

  Widget _section(String title, {String? action, VoidCallback? onTap}) => Row(children: [
    Expanded(child: Text(title, style: const TextStyle(fontSize: 20,
        fontFamily: 'serif', color: MedicColors.forest, letterSpacing: -.3))),
    if (action != null) TextButton(onPressed: onTap, child: Text(action)),
  ]);

  Widget _tool(double width, String title, String subtitle, IconData icon, Color tint, VoidCallback onTap) =>
      SizedBox(width: width < 330 ? width : (width - 12) / 2,
          child: Material(color: Colors.white, borderRadius: BorderRadius.circular(24),
            child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(24),
              child: Padding(padding: const EdgeInsets.all(18),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [Container(padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(15)),
                        child: Icon(icon, size: 23, color: MedicColors.forest)), const Spacer(),
                      const Icon(Icons.north_east_rounded, size: 16, color: MedicColors.muted)]),
                    const SizedBox(height: 18),
                    Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 5),
                    Text(subtitle, style: const TextStyle(fontSize: 12, height: 1.35, color: MedicColors.muted)),
                  ])),
            ),
          ));

  bool _needsReview(Map<String, dynamic> data) {
    final status = (data['status'] ?? '').toString().toLowerCase();
    final days = data['daysUntilExpiry'];
    return status.contains('expired') || status.contains('low') || status.contains('expiring') ||
        (days is num && days <= 30);
  }

  Widget _healthScoreSection() => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: _userDoc, builder: (context, snap) {
      final data = snap.data?.data() ?? {};
      // Dependant/caregiver accounts manage someone else's medicines and
      // are never asked for their own vitals or a health score — see the
      // account-type picker added to signup.
      if (data['accountType'] == 'dependant') return const SizedBox.shrink();
      final latestBp = data['latestBP'] as Map<String, dynamic>?;
      final latestSugar = data['latestSugar'] as Map<String, dynamic>?;
      return Column(mainAxisSize: MainAxisSize.min, children: [
        DailyHealthScoreCard(onTap: _openHealthScore),
        const SizedBox(height: 12),
            IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: _vitalCard('Blood Pressure', Icons.favorite_rounded, MedicColors.cC05256,
                  latestBp == null ? null : '${latestBp['systolic']}/${latestBp['diastolic'] ?? '—'}',
                  'mmHg', latestBp?['condition'] as String?, latestBp?['recordedAt'] as Timestamp?)),
              const SizedBox(width: 10),
              Expanded(child: _vitalCard('Blood Sugar', Icons.water_drop_rounded, MedicColors.c477C91,
                  latestSugar == null ? null : (latestSugar['unit'] == 'mg/dL'
                      ? '${(latestSugar['value'] as num?)?.toInt() ?? '—'}'
                      : (latestSugar['valueMmol'] as num?)?.toStringAsFixed(1) ?? '—'),
                  latestSugar?['unit'] as String? ?? 'mg/dL',
                  latestSugar?['condition'] as String?, latestSugar?['recordedAt'] as Timestamp?)),
            ])),
      ]);
    });

  Widget _vitalCard(String title, IconData icon, Color color, String? value, String unit,
      String? condition, Timestamp? recordedAt) {
    final updated = recordedAt == null ? null : _agoLabel(recordedAt.toDate());
    return Material(color: Colors.white, borderRadius: BorderRadius.circular(22),
        child: InkWell(borderRadius: BorderRadius.circular(22),
          onTap: () => _open(const VitalsUploadScreen()),
          child: Container(padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), border: Border.all(color: MedicColors.line)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [Container(width: 28, height: 28, alignment: Alignment.center,
                    decoration: BoxDecoration(color: color.withOpacity(.12), borderRadius: BorderRadius.circular(9)),
                    child: Icon(icon, size: 14, color: color)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(title, style: const TextStyle(fontSize: 11.5, color: MedicColors.muted),
                      overflow: TextOverflow.ellipsis)),
                ]),
                const SizedBox(height: 10),
                Text(value ?? '—', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
                    color: MedicColors.forest)),
                Text(unit, style: const TextStyle(fontSize: 11, color: MedicColors.muted)),
                const SizedBox(height: 8),
                if (value != null) Wrap(spacing: 6, runSpacing: 4, children: [
                  if (condition != null) Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: const Color(0xFFE3ECD8), borderRadius: BorderRadius.circular(20)),
                      child: Text(condition, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                          color: MedicColors.green))),
                  if (updated != null) Text(updated, style: const TextStyle(fontSize: 10, color: MedicColors.muted)),
                ]) else const Text('Tap to add a reading', style: TextStyle(fontSize: 10.5, color: MedicColors.muted)),
              ])),
        ));
  }

  String _agoLabel(DateTime at) {
    final diff = DateTime.now().difference(at);
    if (diff.inMinutes < 60) return 'Updated ${diff.inMinutes}m ago';
    if (diff.inHours < 24) return 'Updated ${diff.inHours}h ago';
    return 'Updated ${diff.inDays}d ago';
  }

  // ── Quick Actions: Records (health uploads), Medicines (cabinet), Disposal,
  // Guardian (caregivers), Journal — matches the reference dashboard layout.
  Widget _quickActionsRow() => Column(mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        _section('Quick Actions'),
        const SizedBox(height: 14),
        SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(
            mainAxisSize: MainAxisSize.min, children: [
          _quickAction('Records', Icons.description_outlined, const Color(0xFFE3ECD8), MedicColors.green,
                  () => _open(const HealthRecordsScreen())),
          _quickAction('Medicines', Icons.medication_outlined, const Color(0xFFE3ECD8), MedicColors.green,
                  () => setState(() => _tab = 1)),
          _quickAction('Disposal', Icons.recycling_rounded, const Color(0xFFFBF1D8), MedicColors.cB77A27,
                  () => _open(const SafeDisposalScreen())),
          _quickAction('Guardian', Icons.shield_outlined, const Color(0xFFFCE8E6), MedicColors.cC05256,
                  () => _open(const DependantsScreen())),
          _quickAction('Journal', Icons.menu_book_outlined, const Color(0xFFE0EBEE), MedicColors.c477C91,
                  () => _open(const JournalScreen())),
        ])),
      ]);

  Widget _quickAction(String label, IconData icon, Color tint, Color fg, VoidCallback onTap) => Padding(
      padding: const EdgeInsets.only(right: 18),
      child: InkWell(onTap: () { HapticFeedback.selectionClick(); onTap(); }, borderRadius: BorderRadius.circular(18),
          child: Column(children: [
            Container(width: 52, height: 52, alignment: Alignment.center,
                decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
                child: Icon(icon, size: 22, color: fg)),
            const SizedBox(height: 7),
            Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: MedicColors.ink)),
          ])));

  Widget _overview() {
    final snapshot = _medicineSnapshot;
    final docs = snapshot.data?.docs;
    final ready = docs != null && !snapshot.hasError;
    final count = ready ? docs.length.toString() : '—';
    final review = ready ? docs.where((doc) => _needsReview(doc.data())).length.toString() : '—';
    return Container(clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: MedicColors.forest, borderRadius: BorderRadius.circular(28)),
        child: Stack(children: [
          const Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: MedicOrbitPainter()))),
          Padding(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [Expanded(child: MedicEyebrow('Your care overview', light: true)),
              Icon(Icons.favorite_border_rounded, color: MedicColors.mint, size: 20)]),
            const SizedBox(height: 18),
            const Text('Small steps.\nBetter routines.', style: TextStyle(fontFamily: 'serif',
                color: Colors.white, fontSize: 29, height: 1.15, letterSpacing: -.5)),
            const SizedBox(height: 24),
            Row(children: [
              Expanded(child: _metric(count, 'Saved medicines')),
              Container(height: 44, width: 1, color: Colors.white24),
              const SizedBox(width: 24),
              Expanded(child: _metric(review, 'To review')),
            ]),
            const SizedBox(height: 18),
            Text(snapshot.hasError ? _medicineErrorText(snapshot.error) :
            ready ? 'Based on your saved medicine records.' : 'Loading your medicine records…',
                style: const TextStyle(color: Color(0xFFCDDCD4), fontSize: 11, height: 1.4)),
          ])),
        ]));
  }

  Widget _metric(String value, String label) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(value, style: const TextStyle(color: MedicColors.mint, fontSize: 32, fontWeight: FontWeight.w500)),
    const SizedBox(height: 3), Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
  ]);

  // A high/low BP or sugar reading leaves a `pendingRecheck` marker on the
  // user doc (see VitalsUploadScreen._handleRecheckFlow). Previously the
  // only place that showed it was the one-time countdown sheet right after
  // saving — if the person tapped "I'll recheck later" (or just closed the
  // app) that reminder was gone for good with no way to come back to it.
  // This dashboard banner reads the same marker directly, so it keeps
  // showing — with a live countdown, then a ready-to-recheck button — until
  // the recheck is actually done, no matter when they reopen the app.
  Widget _pendingRecheckBanner() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _userDoc,
      builder: (context, snap) {
        final data = snap.data?.data() ?? {};
        if (data['accountType'] == 'dependant') return const SizedBox.shrink();
        final pending = data['pendingRecheck'];
        if (pending is! Map) return const SizedBox.shrink();
        final type = pending['type']?.toString();
        final dueAt = (pending['dueAt'] as Timestamp?)?.toDate();
        final firstVitalsId = pending['firstVitalsId']?.toString();
        if (type == null || dueAt == null || firstVitalsId == null) return const SizedBox.shrink();
        final label = type == 'bloodPressure' ? 'blood pressure' : 'blood sugar';
        final ready = !DateTime.now().isBefore(dueAt);
        return Padding(padding: const EdgeInsets.only(bottom: 14), child: Container(
          width: double.infinity, padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: ready ? const Color(0xFFFCE8E6) : const Color(0xFFFBF1D8),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: ready ? MedicColors.cC05256 : MedicColors.cB77A27)),
          child: Row(children: [
            Icon(ready ? Icons.error_rounded : Icons.timer_outlined,
                color: ready ? MedicColors.cC05256 : MedicColors.cB77A27, size: 26),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(ready ? 'Time to recheck your $label' : 'Recheck your $label soon',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5,
                      color: ready ? MedicColors.cC05256 : MedicColors.cB77A27)),
              const SizedBox(height: 3),
              Text(ready ? 'Your earlier reading was outside reference range.'
                  : 'Ready at ${dueAt.hour.toString().padLeft(2, '0')}:${dueAt.minute.toString().padLeft(2, '0')}.',
                  style: const TextStyle(fontSize: 12, color: MedicColors.muted)),
            ])),
            const SizedBox(width: 8),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: ready ? MedicColors.cC05256 : MedicColors.cB77A27,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8)),
              onPressed: !ready ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) =>
                  VitalsUploadScreen(recheckOf: firstVitalsId, recheckType: type))),
              child: Text(ready ? 'Recheck' : 'Waiting…', style: const TextStyle(fontSize: 12.5)),
            ),
          ]),
        ));
      },
    );
  }

  Widget _reminderList() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return _message('Make room for a routine',
        'Open a medicine to set your first reminder.', Icons.schedule_rounded);
    // Doses due right now (or overdue) get a one-tap "Taken" button right
    // here on the dashboard — previously the only way to confirm a dose
    // was to open the medicine record first, which the schedule-only list
    // below didn't offer.
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: DoseService.instance.events(uid)
          .where('dueAt', isGreaterThanOrEqualTo: Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 1))))
          .snapshots(),
      builder: (context, doseSnap) {
        final now = DateTime.now();
        final due = (doseSnap.data?.docs ?? []).where((e) {
          final d = e.data();
          if (d['status'] == 'cancelled' || d['status'] == 'taken') return false;
          final at = (d['dueAt'] as Timestamp?)?.toDate();
          return at != null && !at.isAfter(now);
        }).toList()
          ..sort((a, b) => (b.data()['dueAt'] as Timestamp).compareTo(a.data()['dueAt'] as Timestamp));
        if (due.isNotEmpty) {
          return Column(children: due.take(3).map((doc) =>
              Padding(padding: const EdgeInsets.only(bottom: 8),
                  child: _dueDoseTile(uid, doc))).toList());
        }
        return _scheduleList();
      },
    );
  }

  Widget _dueDoseTile(String uid, QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final at = (d['dueAt'] as Timestamp).toDate();
    final overdue = DateTime.now().difference(at) > const Duration(minutes: 10);
    return Material(color: Colors.white, borderRadius: BorderRadius.circular(20),
        child: Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(20),
            border: Border.all(color: overdue ? MedicColors.cC05256 : MedicColors.line, width: overdue ? 1.4 : 1)),
          padding: const EdgeInsets.all(16), child: Row(children: [
            Container(padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: overdue ? const Color(0xFFFCE8E6) : const Color(0xFFE3ECD8),
                    borderRadius: BorderRadius.circular(15)),
                child: Icon(overdue ? Icons.error_rounded : Icons.schedule_rounded,
                    color: overdue ? MedicColors.cC05256 : MedicColors.forest, size: 22)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text((d['medicineName'] ?? 'Medicine reminder').toString(), maxLines: 1,
                  overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 5),
              Text('Due ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}'
                  '${overdue ? ' · please confirm now' : ''}',
                  style: TextStyle(fontSize: 12, color: overdue ? MedicColors.cC05256 : MedicColors.muted, height: 1.4)),
            ])),
            const SizedBox(width: 8),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: overdue ? MedicColors.cC05256 : MedicColors.forest,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: _busyDoses.contains(doc.id) ? null : () => _markDoseTaken(uid, doc.id),
              icon: const Icon(Icons.check_rounded, size: 16),
              label: const Text('Taken', style: TextStyle(fontSize: 12.5)),
            ),
          ])));
  }

  final Set<String> _busyDoses = {};
  Future<void> _markDoseTaken(String uid, String eventId) async {
    if (_busyDoses.contains(eventId)) return;
    setState(() => _busyDoses.add(eventId));
    try {
      await DoseService.instance.record(uid, eventId, 'taken');
      HapticFeedback.mediumImpact();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not confirm dose: $e')));
    } finally {
      if (mounted) setState(() => _busyDoses.remove(eventId));
    }
  }

  Widget _scheduleList() {
    final snapshot = _medicineSnapshot;
    if (snapshot.hasError) return _message('Reminders are unavailable',
        _medicineErrorText(snapshot.error), Icons.cloud_off_outlined,
        action: 'Retry', onTap: _retryMedicines);
    if (!snapshot.hasData) return _loading();
    final docs = snapshot.data!.docs.where((doc) => doc.data()['trackingEnabled'] == true).toList();
    if (docs.isEmpty) return _message('Make room for a routine',
        'Open a medicine to set your first reminder.', Icons.schedule_rounded);
    return Column(children: docs.take(3).map((doc) {
      final data = doc.data();
      final times = data['scheduleTimes'];
      final schedule = times is List && times.isNotEmpty ? times.join(' · ') : 'View schedule in medicine details';
      return Padding(padding: const EdgeInsets.only(bottom: 8),
          child: _recordTile(Icons.schedule_rounded, (data['medicineName'] ?? 'Medicine reminder').toString(),
              schedule, const Color(0xFFE3ECD8), () => setState(() => _tab = 1)));
    }).toList());
  }

  Widget _recentMedicines() {
    final snapshot = _medicineSnapshot;
    if (snapshot.hasError) return _message('Unable to load medicines',
        _medicineErrorText(snapshot.error), Icons.cloud_off_outlined,
        action: 'Retry', onTap: _retryMedicines);
    if (!snapshot.hasData) return _loading();
    final docs = List<QueryDocumentSnapshot<Map<String, dynamic>>>.of(snapshot.data!.docs);
    docs.sort((a, b) {
      final at = a.data()['scannedAt']; final bt = b.data()['scannedAt'];
      return (bt is Timestamp ? bt.millisecondsSinceEpoch : 0)
          .compareTo(at is Timestamp ? at.millisecondsSinceEpoch : 0);
    });
    if (docs.isEmpty) return _message('Your cabinet starts here',
        'Scan a medicine label to add your first item.', Icons.medication_outlined,
        action: 'Scan medicine', onTap: () => _open(const ScanMedicineScreen()));
    return Column(children: docs.take(3).map((doc) {
      final data = doc.data();
      final dose = (data['dosage'] ?? '').toString();
      return Padding(padding: const EdgeInsets.only(bottom: 8), child: _recordTile(
          Icons.medication_outlined, (data['medicineName'] ?? 'Medicine').toString(),
          [if (dose.isNotEmpty) dose, _needsReview(data) ? 'Review details' : 'View medicine details'].join(' · '),
          _needsReview(data) ? const Color(0xFFF2E8D8) : const Color(0xFFE0EBEE),
              () => _open(MedicineDetailsScreen(docId: doc.id, data: data))));
    }).toList());
  }

  Widget _recordTile(IconData icon, String title, String subtitle, Color tint, VoidCallback onTap) =>
      Material(color: Colors.white, borderRadius: BorderRadius.circular(20),
          child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(20),
            child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [
              Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: tint,
                  borderRadius: BorderRadius.circular(15)), child: Icon(icon, color: MedicColors.forest, size: 22)),
              const SizedBox(width: 14), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 5), Text(subtitle, style: const TextStyle(fontSize: 12, color: MedicColors.muted, height: 1.4)),
              ])), const SizedBox(width: 8), const Icon(Icons.chevron_right_rounded, color: MedicColors.muted, size: 18),
            ])),
          ));

  Widget _loading() => const Padding(padding: EdgeInsets.all(24),
      child: Center(child: CircularProgressIndicator(strokeWidth: 2)));

  Widget _message(String title, String subtitle, IconData icon, {String? action, VoidCallback? onTap}) =>
      Container(width: double.infinity, padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24),
              border: Border.all(color: MedicColors.line)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: MedicColors.green, size: 28), const SizedBox(height: 14),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            const SizedBox(height: 6), Text(subtitle, style: const TextStyle(color: MedicColors.muted, fontSize: 13, height: 1.5)),
            if (action != null) ...[const SizedBox(height: 12), OutlinedButton(onPressed: onTap, child: Text(action))],
          ]));
}
