import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../design/medic_design.dart';
import '../../services/dose_service.dart';
import '../../services/notification_service.dart';

/// All reminder delivery is FCM-only (see dose_service.dart / functions/index.js)
/// — no on-device alarm is armed by this app. This screen checks the pieces
/// that pipeline actually depends on: notification permission (so a pushed
/// notification can display), an FCM token on file (so the Cloud Function
/// knows where to push), and that upcoming dose_events exist to push about.
class ReminderDiagnosticsScreen extends StatefulWidget {
  const ReminderDiagnosticsScreen({super.key});
  @override
  State<ReminderDiagnosticsScreen> createState() => _ReminderDiagnosticsScreenState();
}

class _ReminderDiagnosticsScreenState extends State<ReminderDiagnosticsScreen> {
  bool _busy = true;
  bool? _permGranted;
  int? _tokenCount;
  int? _upcomingCount;
  String? _syncError;
  String? _checkError;

  @override
  void initState() { super.initState(); _check(); }

  /// Firestore's "missing composite index" error carries a direct console
  /// link to create it — surfacing that link as a button (instead of a wall
  /// of raw error text) is the difference between a dead end and a one-tap fix.
  String? get _indexLink {
    final e = _checkError;
    if (e == null) return null;
    final match = RegExp(r'https://\S+').firstMatch(e);
    return match?.group(0);
  }

  Future<void> _check() async {
    setState(() { _busy = true; _checkError = null; });
    try {
      await DoseService.instance.refresh();
      final permGranted = await Permission.notification.isGranted;

      final uid = FirebaseAuth.instance.currentUser?.uid;
      var tokenCount = 0;
      var upcomingCount = 0;
      if (uid != null) {
        final tokenDoc = await FirebaseFirestore.instance.collection('user_tokens').doc(uid).get();
        tokenCount = (tokenDoc.data()?['tokens'] as List?)?.length ?? 0;

        final now = Timestamp.now();
        final soon = Timestamp.fromMillisecondsSinceEpoch(now.millisecondsSinceEpoch + 8 * 24 * 60 * 60 * 1000);
        final upcoming = await DoseService.instance.events(uid)
            .where('status', isEqualTo: 'planned')
            .where('dueAt', isGreaterThanOrEqualTo: now)
            .where('dueAt', isLessThanOrEqualTo: soon)
            .get();
        upcomingCount = upcoming.docs.length;
      }

      if (mounted) setState(() {
        _permGranted = permGranted;
        _tokenCount = tokenCount;
        _upcomingCount = upcomingCount;
        _syncError = DoseService.instance.lastError;
      });
    } catch (e) { if (mounted) setState(() => _checkError = '$e'); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _requestPermissionAndReregister() async {
    try {
      await Permission.notification.request();
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) await NotificationService().saveTokenToFirestore(uid);
      await _check();
    } catch (e) { if (mounted) setState(() => _checkError = '$e'); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: MedicColors.canvas,
      body: CustomScrollView(slivers: [
        SliverToBoxAdapter(child: MedicPageTitle(
            title: 'Reminder check', subtitle: 'Make sure dose alerts can reach this device')),
        SliverPadding(padding: const EdgeInsets.fromLTRB(20, 20, 20, 32), sliver: SliverList(
          delegate: SliverChildListDelegate([
            if (_checkError != null) _errorCard(_checkError!, _indexLink)
            else _statusCard(),
            const SizedBox(height: 10),
            if (_syncError != null) _noteCard(Icons.sync_problem_rounded, _syncError!, warn: true),
            const SizedBox(height: 20),
            FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: MedicColors.forest,
                    padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16))),
                onPressed: _busy ? null : _requestPermissionAndReregister,
                icon: const Icon(Icons.notifications_active_outlined),
                label: const Text('Allow notifications & refresh FCM token')),
            const SizedBox(height: 10),
            OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: MedicColors.forest,
                    side: const BorderSide(color: MedicColors.line),
                    padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16))),
                onPressed: _busy ? null : _check,
                icon: _busy ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh_rounded),
                label: const Text('Re-check')),
            const SizedBox(height: 4),
            TextButton(onPressed: () => openAppSettings(),
                child: const Text('Open device app settings')),
            const SizedBox(height: 16),
            _noteCard(Icons.cloud_outlined,
                'Reminders are pushed by a Cloud Function (FCM), not a phone alarm, so '
                    'they arrive even if MedicTrack is fully closed. If the checks above '
                    'look right but nothing is arriving, the Cloud Functions worker '
                    '(functions/index.js) likely isn’t deployed yet — check its logs with '
                    '"firebase functions:log --only sendDoseReminders".'),
          ]),
        )),
      ]));

  Widget _statusCard() => Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22),
          border: Border.all(color: MedicColors.line)),
      child: Column(children: [
        _statusRow(
            icon: Icons.notifications_outlined,
            title: 'Device notifications',
            value: _busy && _permGranted == null ? 'Checking…'
                : _permGranted == true ? 'Allowed' : 'Blocked — tap below to allow',
            ok: _permGranted == true, loading: _busy && _permGranted == null),
        const Divider(height: 1, color: MedicColors.line),
        _statusRow(
            icon: Icons.phonelink_ring_outlined,
            title: 'FCM tokens on file',
            value: _busy && _tokenCount == null ? 'Checking…'
                : _tokenCount == 0 ? 'None — the Cloud Function has nowhere to push'
                : '$_tokenCount registered',
            ok: (_tokenCount ?? 0) > 0, loading: _busy && _tokenCount == null),
        const Divider(height: 1, color: MedicColors.line),
        _statusRow(
            icon: Icons.event_available_outlined,
            title: 'Upcoming scheduled doses',
            value: _busy && _upcomingCount == null ? 'Checking…'
                : '$_upcomingCount in the next 8 days',
            ok: (_upcomingCount ?? 0) > 0, loading: _busy && _upcomingCount == null,
            isLast: true),
      ]));

  Widget _statusRow({required IconData icon, required String title, required String value,
    required bool ok, bool loading = false, bool isLast = false}) => Padding(
      padding: const EdgeInsets.all(16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Container(width: 42, height: 42, alignment: Alignment.center,
            decoration: BoxDecoration(
                color: loading ? MedicColors.line.withOpacity(.6)
                    : ok ? const Color(0xFFE3ECD8) : const Color(0xFFFCE8E6),
                borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, size: 20, color: loading ? MedicColors.muted
                : ok ? MedicColors.green : MedicColors.cC05256)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 3),
          Text(value, style: TextStyle(fontSize: 12.5, height: 1.35,
              color: loading ? MedicColors.muted : ok ? MedicColors.green : MedicColors.cC05256)),
        ])),
        if (!loading) Icon(ok ? Icons.check_circle_rounded : Icons.error_rounded,
            size: 20, color: ok ? MedicColors.green : MedicColors.cC05256),
      ]));

  Widget _noteCard(IconData icon, String text, {bool warn = false}) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: warn ? const Color(0xFFFCF3E3) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: warn ? const Color(0xFFEBD9AF) : MedicColors.line)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 19, color: warn ? MedicColors.cB77A27 : MedicColors.muted),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: TextStyle(fontSize: 12.5, height: 1.5,
            color: warn ? const Color(0xFF7A5A16) : MedicColors.muted))),
      ]));

  Widget _errorCard(String message, String? link) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: const Color(0xFFFCE8E6), borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFF0B8B2))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: const [
          Icon(Icons.error_outline_rounded, color: MedicColors.cC05256, size: 20),
          SizedBox(width: 8),
          Text('Check failed', style: TextStyle(fontWeight: FontWeight.w800, color: MedicColors.cC05256)),
        ]),
        const SizedBox(height: 10),
        Text(message, style: const TextStyle(fontSize: 12, height: 1.5, color: Color(0xFF7A2E29))),
        if (link != null) ...[
          const SizedBox(height: 14),
          Wrap(spacing: 10, runSpacing: 8, children: [
            FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: MedicColors.cC05256),
                onPressed: () => launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_new_rounded, size: 17),
                label: const Text('Create the missing index')),
            OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: MedicColors.cC05256,
                    side: const BorderSide(color: MedicColors.cC05256)),
                onPressed: () => Clipboard.setData(ClipboardData(text: link)),
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('Copy link')),
          ]),
          const SizedBox(height: 10),
          const Text('This is a one-time setup step — Firestore needs an index for this '
              'query. Tap above, sign in with the same Firebase account, then come back '
              'and re-check (it can take a few minutes to finish building).',
              style: TextStyle(fontSize: 11.5, height: 1.5, color: Color(0xFF7A2E29))),
        ],
      ]));
}