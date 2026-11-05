import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../design/medic_design.dart';
import '../../services/dose_service.dart';

class DoseHistoryScreen extends StatelessWidget {
  final String? medicineId;
  const DoseHistoryScreen({super.key, this.medicineId});
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
        backgroundColor: MedicColors.canvas,
        body: uid == null
            ? const _SignInPrompt(title: 'Dose history', message: 'Sign in to view doses.')
            : CustomScrollView(slivers: [
          const SliverToBoxAdapter(child: MedicPageTitle(
              title: 'Dose history', subtitle: 'Every dose, confirmed or missed, in one place')),
          SliverPadding(padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              sliver: SliverToBoxAdapter(
                  child: DoseHistoryPanel(uid: uid, medicineId: medicineId, canRecord: true))),
        ]));
  }
}

class _SignInPrompt extends StatelessWidget {
  final String title, message;
  const _SignInPrompt({required this.title, required this.message});
  @override
  Widget build(BuildContext context) => CustomScrollView(slivers: [
    SliverToBoxAdapter(child: MedicPageTitle(title: title, subtitle: ' ')),
    SliverFillRemaining(hasScrollBody: false,
        child: Center(child: Padding(padding: const EdgeInsets.all(32),
            child: Text(message, style: const TextStyle(color: MedicColors.muted))))),
  ]);
}

class DoseHistoryPanel extends StatefulWidget {
  final String uid;
  final String? medicineId;
  final bool canRecord;
  const DoseHistoryPanel({super.key, required this.uid, this.medicineId, this.canRecord = false});
  @override
  State<DoseHistoryPanel> createState() => _DoseHistoryPanelState();
}

class _DoseHistoryPanelState extends State<DoseHistoryPanel> {
  late Stream<QuerySnapshot<Map<String, dynamic>>> _stream;
  Timer? _clock;
  String _filter = 'All';
  final Set<String> _busy = {};
  @override
  void initState() {
    super.initState(); _bind();
    _clock = Timer.periodic(const Duration(minutes: 1), (_) { if (mounted) setState(() {}); });
  }
  @override
  void didUpdateWidget(covariant DoseHistoryPanel old) {
    super.didUpdateWidget(old); if (old.uid != widget.uid) _bind();
  }
  void _bind() {
    _stream = DoseService.instance.events(widget.uid).where('dueAt',
        isGreaterThanOrEqualTo: Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 30))))
        .orderBy('dueAt', descending: true).snapshots();
  }
  @override
  void dispose() { _clock?.cancel(); super.dispose(); }
  Future<void> _record(String id, String status) async {
    setState(() => _busy.add(id));
    try { await DoseService.instance.record(widget.uid, id, status); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
    finally { if (mounted) setState(() => _busy.remove(id)); }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _stream, builder: (context, snap) {
    if (snap.hasError) return _message('Dose records are unavailable',
        'Check your connection and sharing permission.', Icons.cloud_off_outlined);
    if (!snap.hasData) return const Padding(padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: MedicColors.green)));
    final now = DateTime.now();
    final records = snap.data!.docs.where((e) => e.data()['status'] != 'cancelled' &&
        (widget.medicineId == null || e.data()['medicineId'] == widget.medicineId)).toList();
    final due = records.where((e) => DoseService.eligible(e.data(), now)).toList();
    final taken = due.where((e) => e.data()['status'] == 'taken').length;
    final missed = due.length - taken;
    final pct = due.isEmpty ? null : (100 * taken / due.length).round();
    final alertCount = records.where((e) => DoseService.isAlert(e.data(), now)).length;
    final visible = records.where((e) {
      final d = e.data(); final at = (d['dueAt'] as Timestamp).toDate();
      if (at.isAfter(now.add(const Duration(days: 1)))) return false;
      return _filter == 'All' || DoseService.status(d, now) == _filter.toLowerCase();
    }).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _adherenceCard(pct, taken, missed, alertCount),
      const SizedBox(height: 14),
      _noteCard('A dose becomes an urgent alert 10 minutes after its scheduled time if it '
          'still hasn’t been confirmed, and is automatically recorded as missed after 20 '
          'minutes — there’s no manual "skipped" option. It does not prove the medicine '
          'was not taken. Future doses and doses within the grace period are excluded from '
          'the score. History begins when tracking is activated.'),
      const SizedBox(height: 16),
      Wrap(spacing: 8, children: ['All', 'Missed', 'Taken'].map((f) => ChoiceChip(
          label: Text(f), selected: _filter == f,
          selectedColor: MedicColors.forest,
          labelStyle: TextStyle(color: _filter == f ? Colors.white : MedicColors.forest,
              fontWeight: FontWeight.w600, fontSize: 12.5),
          backgroundColor: Colors.white,
          side: BorderSide(color: _filter == f ? MedicColors.forest : MedicColors.line),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          onSelected: (_) => setState(() => _filter = f))).toList()),
      const SizedBox(height: 14),
      if (visible.isEmpty) _message('No dose records in this view', 'Try a different filter.',
          Icons.inbox_outlined),
      ...visible.map((e) {
        final d = e.data(); final at = (d['dueAt'] as Timestamp).toDate().toLocal();
        final status = DoseService.status(d, now);
        final alert = DoseService.isAlert(d, now);
        final actionable = widget.canRecord && !at.isAfter(now) && status != 'taken';
        return Padding(padding: const EdgeInsets.only(bottom: 10),
            child: _doseTile(context, e.id, d, at, status, alert, actionable));
      }),
    ]);
  });

  Widget _adherenceCard(int? pct, int taken, int missed, int alertCount) => Container(
      width: double.infinity, clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: MedicColors.forest, borderRadius: BorderRadius.circular(26)),
      child: Stack(children: [
        const Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: MedicOrbitPainter()))),
        Padding(padding: const EdgeInsets.all(22), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          const MedicEyebrow('Recorded adherence · 30 days', light: true),
          const SizedBox(height: 10),
          Text(pct == null ? 'No doses due yet' : '$pct%',
              style: const TextStyle(color: Colors.white, fontSize: 40, fontFamily: 'serif',
                  letterSpacing: -1)),
          const SizedBox(height: 10),
          Wrap(spacing: 18, runSpacing: 6, children: [
            _statChip(Icons.check_circle_rounded, MedicColors.mint, '$taken taken'),
            _statChip(Icons.cancel_rounded, const Color(0xFFE79791), '$missed missed'),
            if (alertCount > 0) _statChip(Icons.error_rounded, const Color(0xFFE79791),
                '$alertCount alert${alertCount == 1 ? '' : 's'} now'),
          ]),
        ])),
      ]));

  Widget _statChip(IconData icon, Color color, String label) => Row(mainAxisSize: MainAxisSize.min,
      children: [Icon(icon, size: 15, color: color), const SizedBox(width: 5),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 12.5))]);

  Widget _noteCard(String text) => Container(width: double.infinity, padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: MedicColors.line)),
      child: Text(text, style: const TextStyle(fontSize: 11.5, height: 1.55, color: MedicColors.muted)));

  Widget _doseTile(BuildContext context, String id, Map<String, dynamic> d, DateTime at,
      String status, bool alert, bool actionable) {
    final taken = status == 'taken';
    final tint = alert ? const Color(0xFFFCE8E6) : taken ? const Color(0xFFE3ECD8)
        : status == 'missed' ? const Color(0xFFFBF1D8) : const Color(0xFFEFF2EA);
    final iconColor = alert ? MedicColors.cC05256 : taken ? MedicColors.green
        : status == 'missed' ? MedicColors.cB77A27 : MedicColors.muted;
    final icon = alert ? Icons.error_rounded : taken ? Icons.check_circle_rounded
        : status == 'missed' ? Icons.cancel_rounded : Icons.schedule_rounded;
    return Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
            border: Border.all(color: alert ? MedicColors.cC05256 : MedicColors.line, width: alert ? 1.4 : 1)),
        child: Padding(padding: const EdgeInsets.all(16), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 40, height: 40, alignment: Alignment.center,
                decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(13)),
                child: Icon(icon, size: 19, color: iconColor)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (alert) const Padding(padding: EdgeInsets.only(bottom: 3),
                  child: Text('ALERT — PLEASE CONFIRM NOW', style: TextStyle(
                      color: MedicColors.cC05256, fontWeight: FontWeight.w800, fontSize: 10.5, letterSpacing: .6))),
              Text('${d['medicineName']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
              const SizedBox(height: 2),
              Text('${d['dosage']} · ${d['assignedToName'] ?? 'Me'}',
                  style: const TextStyle(fontSize: 12, color: MedicColors.muted)),
              const SizedBox(height: 4),
              Text('${at.day}/${at.month}/${at.year} · '
                  '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(fontSize: 11.5, color: MedicColors.muted)),
              if (d['lateConfirmation'] == true) const Padding(padding: EdgeInsets.only(top: 2),
                  child: Text('Confirmed after the grace period',
                      style: TextStyle(fontSize: 11, color: MedicColors.cB77A27, fontStyle: FontStyle.italic))),
            ])),
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(20)),
                child: Text(status.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800,
                    letterSpacing: .4, color: iconColor))),
          ]),
          if (actionable) Padding(padding: const EdgeInsets.only(top: 12), child: Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                      backgroundColor: alert ? MedicColors.cC05256 : MedicColors.forest,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                  onPressed: _busy.contains(id) ? null : () => _record(id, 'taken'),
                  icon: const Icon(Icons.check_rounded, size: 17), label: const Text('Taken')))),
        ])));
  }

  Widget _message(String title, String subtitle, IconData icon) => Container(
      width: double.infinity, padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22),
          border: Border.all(color: MedicColors.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: MedicColors.green, size: 26), const SizedBox(height: 12),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 5), Text(subtitle, style: const TextStyle(color: MedicColors.muted, fontSize: 12.5)),
      ]));
}

class MedicationSharingScreen extends StatelessWidget {
  const MedicationSharingScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
        backgroundColor: MedicColors.canvas,
        body: uid == null
            ? const _SignInPrompt(title: 'Medication sharing', message: 'Sign in first.')
            : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance.collection('users').doc(uid).collection('trackers').snapshots(),
            builder: (context, snap) => CustomScrollView(slivers: [
              const SliverToBoxAdapter(child: MedicPageTitle(
                  title: 'Medication sharing', subtitle: 'Choose what your caregivers can see')),
              SliverPadding(padding: const EdgeInsets.fromLTRB(20, 20, 20, 32), sliver: SliverList(
                delegate: SliverChildListDelegate([
                  Container(width: double.infinity, padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: MedicColors.line)),
                      child: const Text('Choose which accepted caregivers can see medicine names, dose '
                          'history and adherence, and receive 10-minute alert and missed-dose notifications. '
                          'You can revoke access here.',
                          style: TextStyle(fontSize: 12.5, height: 1.5, color: MedicColors.muted))),
                  const SizedBox(height: 16),
                  if (snap.hasError) _emptyCard('Could not load sharing permissions', Icons.cloud_off_outlined)
                  else if (!snap.hasData) const Padding(padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: MedicColors.green)))
                  else if (snap.data!.docs.isEmpty) _emptyCard('No accepted caregivers yet', Icons.people_outline_rounded)
                    else ...snap.data!.docs.map((d) => Padding(padding: const EdgeInsets.only(bottom: 10),
                          child: _trackerTile(context, d))),
                ]),
              )),
            ])));
  }

  Widget _trackerTile(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final sharing = d.data()['shareMedication'] == true;
    return Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
            border: Border.all(color: MedicColors.line)),
        child: SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            activeColor: MedicColors.green,
            secondary: Container(width: 42, height: 42, alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: sharing ? const Color(0xFFE3ECD8) : MedicColors.line.withOpacity(.6),
                    borderRadius: BorderRadius.circular(14)),
                child: Icon(Icons.shield_outlined, size: 19,
                    color: sharing ? MedicColors.green : MedicColors.muted)),
            title: Text('${d.data()['trackerName'] ?? 'Caregiver'}',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
            subtitle: const Text('Share medication history and alerts',
                style: TextStyle(fontSize: 12, color: MedicColors.muted)),
            value: sharing,
            onChanged: (v) async {
              try { await d.reference.update({'shareMedication': v}); }
              catch (_) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Could not update sharing. Please retry.'))); }
            }));
  }

  Widget _emptyCard(String text, IconData icon) => Container(
      width: double.infinity, padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22),
          border: Border.all(color: MedicColors.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: MedicColors.green, size: 26), const SizedBox(height: 10),
        Text(text, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: MedicColors.muted)),
      ]));
}