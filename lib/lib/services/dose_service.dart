import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'notification_service.dart';

/// Daily schedules use the device's IANA timezone. History is never inferred
/// from today's edited schedule.
///
/// Delivery is FCM-only by design: this service's job is purely to keep
/// `users/{uid}/dose_events` filled with the next ~8 days of due doses (with
/// `advanceSentAt`/`exactSentAt` left null). The Cloud Functions worker
/// (`functions/index.js` → `sendDoseReminders`) is the only thing that
/// actually sends a notification — it polls that collection every minute
/// and pushes a real FCM message 10 minutes before and at the exact time.
/// No `flutter_local_notifications.zonedSchedule` / device alarm is armed
/// here on purpose, so a reminder is never dependent on this app process,
/// an OS alarm surviving battery optimisation, or a reboot.
class DoseService with WidgetsBindingObserver {
  static final instance = DoseService._();
  DoseService._();
  final db = FirebaseFirestore.instance;
  StreamSubscription? _meds;
  StreamSubscription? _prefs;
  Future<void> _queue = Future.value();
  String? _uid;
  String? lastError;
  bool _started = false;
  CollectionReference<Map<String, dynamic>> events(String uid) =>
      db.collection('users').doc(uid).collection('dose_events');

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    FirebaseAuth.instance.authStateChanges().listen((user) async {
      await _meds?.cancel();
      await _prefs?.cancel();
      _uid = user?.uid;
      if (user == null) return;
      // FCM token registration is the only delivery-critical piece the
      // client must do — the Cloud Function reads user_tokens to know
      // where to push.
      unawaited(NotificationService().saveTokenToFirestore(user.uid));
      _prefs = db.collection('users').doc(user.uid).collection('settings').doc('notifications')
        .snapshots().listen((_) => refresh(), onError: (Object e) { lastError = 'Could not read reminder preferences: $e'; });
      _meds = db.collection('medicines').where('userId', isEqualTo: user.uid)
          .snapshots().listen((_) => refresh(), onError: (Object e) {
        lastError = 'Could not read medicine schedules: $e';
      });
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  Future<void> refresh() {
    _queue = _queue.then((_) => _sync()).catchError((Object e) {
      lastError = 'Reminder sync failed: $e';
    });
    return _queue;
  }

  Future<void> _sync() async {
    final uid = _uid;
    if (uid == null) return;
    tzdata.initializeTimeZones();
    final zone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(zone));
    final snap = await db.collection('medicines').where('userId', isEqualTo: uid).get();
    if (_uid != uid) return;
    final prefs = await db.collection('users').doc(uid).collection('settings').doc('notifications').get();
    final enabled = prefs.data()?['medicineReminders'] != false;
    final now = tz.TZDateTime.now(tz.local);
    final desired = <String, Map<String, dynamic>>{};
    final plans = <String, String>{};
    for (final doc in snap.docs) {
      final m = doc.data();
      if (m['trackingEnabled'] != true) continue;
      final times = (m['scheduleTimes'] as List? ?? []).map((v) => '$v').toSet().toList()..sort();
      for (final time in times) {
        if (!RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(time)) {
          throw FormatException('Invalid time for ${m['medicineName']}: $time. Use HH:mm.');
        }
      }
      final signature = jsonEncode([times, zone, m['assignedTo'], m['medicineName'], m['dosage']]);
      plans[doc.id] = signature;
      var since = (m['dosePlanSince'] as Timestamp?)?.toDate();
      if (m['dosePlanSignature'] != signature || since == null) {
        since = now;
        await doc.reference.update({'dosePlanSignature': signature,
          'dosePlanSince': Timestamp.fromDate(since), 'doseTimezone': zone});
      }
      for (final time in times) {
        final parts = time.split(':').map(int.parse).toList();
        var next = tz.TZDateTime(tz.local, now.year, now.month, now.day, parts[0], parts[1]);
        if (!next.isAfter(now)) next = tz.TZDateTime(tz.local, now.year, now.month, now.day + 1, parts[0], parts[1]);
        desired['${doc.id}:$time'] = {'date': next, 'name': m['medicineName'] ?? 'Medicine',
          'dosage': m['dosage'] ?? '', 'medicineId': doc.id};
        for (var day = 0; day < 8; day++) {
          final due = tz.TZDateTime(tz.local, now.year, now.month, now.day + day, parts[0], parts[1]);
          if (due.isBefore(since) || due.isBefore(now)) continue;
          if (_uid != uid) return;
          final ref = events(uid).doc('${doc.id}_${due.millisecondsSinceEpoch}');
          await db.runTransaction((tx) async {
            final existing = await tx.get(ref);
            if (!existing.exists || existing.data()?['status'] == 'cancelled' ||
                (existing.data()?['status'] == 'planned' && existing.data()?['plan'] != signature)) {
              tx.set(ref, {'medicineId': doc.id, 'medicineName': m['medicineName'] ?? 'Medicine',
                'dosage': m['dosage'] ?? '', 'assignedTo': m['assignedTo'] ?? 'me',
                'assignedToName': m['assignedToName'] ?? 'Me', 'scheduledTime': time,
                'dueAt': Timestamp.fromDate(due), 'status': 'planned', 'plan': signature,
                // Explicit nulls (not omitted) so the Cloud Functions FCM worker's
                // collectionGroup queries — which filter on `advanceSentAt == null`
                // / `lateSentAt == null` / `exactSentAt == null` — can match this
                // doc before it's sent. `lateSentAt` backs the +10-minute "still
                // not confirmed" urgent alert push (see functions/index.js).
                'advanceSentAt': null, 'exactSentAt': null, 'lateSentAt': null,
                'createdAt': FieldValue.serverTimestamp()});
            }
          });
        }
      }
    }
    // Remove only future planned events invalidated by a schedule edit/deletion.
    final future = await events(uid).where('dueAt', isGreaterThan: Timestamp.fromDate(now)).get();
    final byId = {for (final d in snap.docs) d.id: d.data()};
    for (final e in future.docs) {
      final d = e.data(); final m = byId[d['medicineId']];
      final valid = m != null && m['trackingEnabled'] == true &&
          (m['scheduleTimes'] as List? ?? []).contains(d['scheduledTime']) && d['plan'] == plans[d['medicineId']];
      if (!valid && d['status'] == 'planned') await e.reference.update({'status': 'cancelled'});
    }
    if (_uid != uid) return;
    if (enabled && desired.length > 60) throw StateError('More than 60 daily reminder slots. Reduce the number of schedules.');
    // Delivery itself is entirely server-side from here: the dose_events
    // docs written above (with advanceSentAt/exactSentAt left null) are all
    // sendDoseReminders needs to push the 10-minutes-before and exact-time
    // FCM notifications. The `medicineReminders` preference read above is
    // honoured server-side too (sendDoseReminders checks the same
    // settings/notifications doc before pushing), so turning it off here
    // still silences pushes even though the dose_events themselves keep
    // being written (dose_history/health-analysis still need them for
    // adherence tracking regardless of whether reminders are on).
    lastError = null;
  }

  // A dose is given a 20-minute grace window after its due time before it's
  // treated as missed — the same window the Cloud Functions worker
  // (functions/index.js -> sweepMissedDoses) uses to actually write
  // status: 'missed' server-side. This client-side fallback just means the
  // UI doesn't have to wait for that sweep to display "missed" correctly.
  static const missedGrace = Duration(minutes: 20);
  // A dose still unrecorded 10 minutes past due is shown as an urgent
  // "alert" state in the UI (and gets a second, more urgent FCM push from
  // the server) even though its Firestore status is still 'planned' —
  // this is purely a display/urgency tier, not a status value.
  static const alertGrace = Duration(minutes: 10);

  static String status(Map<String, dynamic> d, DateTime now) {
    final value = d['status'] as String? ?? 'planned';
    final due = (d['dueAt'] as Timestamp?)?.toDate();
    if (value == 'planned' && due != null && now.isAfter(due.add(missedGrace))) return 'missed';
    return value;
  }

  /// True once a still-unconfirmed dose is 10+ minutes overdue (but under
  /// the 20-minute missed threshold) — the UI's cue to switch to the red
  /// "respond now" treatment described in the reminder spec.
  static bool isAlert(Map<String, dynamic> d, DateTime now) {
    final due = (d['dueAt'] as Timestamp?)?.toDate();
    if (due == null || status(d, now) != 'planned') return false;
    return now.isAfter(due.add(alertGrace));
  }

  static bool eligible(Map<String, dynamic> d, DateTime now) {
    final due = (d['dueAt'] as Timestamp?)?.toDate();
    return due != null && !due.isAfter(now) &&
        ['taken', 'missed'].contains(status(d, now));
  }

  /// Records a dose as taken. There is no manual "skipped" option by
  /// design — a dose a person doesn't confirm within the grace window is
  /// automatically recorded as missed (by the Cloud Functions sweep, or by
  /// this client's own `status()` fallback for display), rather than
  /// relying on someone to proactively say they didn't take it.
  Future<void> record(String uid, String eventId, String value) async {
    if (FirebaseAuth.instance.currentUser?.uid != uid || value != 'taken') {
      throw StateError('Only the owner can confirm a dose as taken.');
    }
    final ref = events(uid).doc(eventId);
    await db.runTransaction((tx) async {
      final snap = await tx.get(ref); final d = snap.data();
      if (d == null || d['status'] == 'cancelled') throw StateError('Dose is no longer active.');
      if ((d['dueAt'] as Timestamp).toDate().isAfter(DateTime.now())) throw StateError('This dose is not due yet.');
      if (d['status'] == 'taken') return;
      final medicineId = d['medicineId'];
      DocumentReference<Map<String, dynamic>>? medicineRef;
      Map<String, dynamic>? medicine;
      if (medicineId is String && medicineId.isNotEmpty) {
        medicineRef = db.collection('medicines').doc(medicineId);
        medicine = (await tx.get(medicineRef)).data();
      }
      double? number(Object? value) {
        final n = value is num ? value.toDouble() : double.tryParse('$value');
        return n != null && n.isFinite ? n : null;
      }
      final remaining = number(medicine?['remainingPills']);
      final perDose = number(medicine?['pillsPerDose']);
      final tracked = medicine?['userId'] == uid && remaining != null && remaining >= 0 && perDose != null && perDose > 0;
      if (tracked && medicineRef != null) {
        tx.update(medicineRef, {'remainingPills': (remaining! - perDose!).clamp(0.0, double.infinity),
          'stockUpdatedAt': FieldValue.serverTimestamp()});
      }
      tx.update(ref, {'status': value, 'recordedAt': FieldValue.serverTimestamp(),
        if (tracked) 'stockDeducted': perDose,
        'lateConfirmation': status(d, DateTime.now()) == 'missed'});
    });
  }
}
