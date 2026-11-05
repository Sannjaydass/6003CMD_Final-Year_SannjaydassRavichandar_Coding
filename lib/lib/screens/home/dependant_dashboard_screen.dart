import 'health_monitoring_screen.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dose_history_screen.dart';

/// Medication access is checked live and enforced again by Firestore rules.
class DependantDashboardScreen extends StatelessWidget {
  final String dependantId, dependantName;
  const DependantDashboardScreen({super.key, required this.dependantId, required this.dependantName});
  @override
  Widget build(BuildContext context) {
    final viewer = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(appBar: AppBar(title: Text(dependantName)),
      body: viewer == null ? const Center(child: Text('Sign in first.')) :
      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('users').doc(dependantId).collection('trackers').doc(viewer).snapshots(),
        builder: (context, permission) {
          if (permission.hasError) return const Center(child: Text('Access unavailable. Ask the patient to check sharing permissions.'));
          if (!permission.hasData) return const Center(child: CircularProgressIndicator());
          if (!permission.data!.exists) return const Center(child: Text('This tracking connection is no longer active.'));
          final sharing = permission.data!.data()?['shareMedication'] == true;
          return ListView(padding: const EdgeInsets.all(20), children: [
            Text('Your care overview', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 12),
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance.collection('users').doc(dependantId).snapshots(),
              builder: (context, snap) {
                if (snap.hasError) return const Text('Profile readings unavailable.');
                if (!snap.hasData) return const LinearProgressIndicator();
                final d = snap.data!.data() ?? {};
                final h = d['healthInfo'] as Map<String, dynamic>? ?? {};
                final bp = d['latestBP'] as Map<String, dynamic>? ?? {};
                final sugar = d['latestSugar'] as Map<String, dynamic>? ?? {};
                final height = (h['height'] as num?)?.toDouble();
                final weight = (h['weight'] as num?)?.toDouble();
                final bmi = height != null && height > 0 && weight != null
                  ? weight / ((height / 100) * (height / 100)) : (h['bmi'] as num?)?.toDouble();
                Widget metric(String title, String value, dynamic score) => Card(child: ListTile(
                  title: Text(title), subtitle: Text(value),
                  trailing: score is num ? Text('${score.round()}/100\nrecorded score', textAlign: TextAlign.end) : null));
                return Column(children: [
                  metric('Blood pressure', bp.isEmpty ? 'No reading recorded' : '${bp['systolic'] ?? '—'}/${bp['diastolic'] ?? '—'} mmHg', bp['score']),
                  metric('Blood glucose', sugar.isEmpty ? 'No reading recorded' : '${sugar['value'] ?? '—'} ${sugar['unit'] ?? ''}', sugar['score']),
                  metric('BMI', bmi?.toStringAsFixed(1) ?? 'Height and weight not recorded', null),
                  const Padding(padding: EdgeInsets.all(10), child: Text('These are recorded readings and app scores, not a diagnosis. Missing readings are not scored.')),
                ]);
              }),
            const SizedBox(height: 16),
            if (sharing) FilledButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => HealthMonitoringScreen(ownerId: dependantId))),
              icon: const Icon(Icons.monitor_heart_outlined), label: const Text('View daily monitoring & seven-day report')),
            if (sharing) DoseHistoryPanel(key: ValueKey(dependantId), uid: dependantId)
            else const Card(child: Padding(padding: EdgeInsets.all(20), child: Text(
              'Medication history is private. The patient can enable it in Settings → Medication sharing. Once enabled, taken and missed doses and the recorded adherence score appear here.'))),
          ]);
        }));
  }
}
