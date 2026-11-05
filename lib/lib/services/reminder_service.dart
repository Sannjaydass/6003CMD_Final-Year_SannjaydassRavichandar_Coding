import 'package:cloud_firestore/cloud_firestore.dart';
import 'dependant_service.dart';

class ReminderService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DependantService _dependantSvc = DependantService();

  /// Create a new reminder with scheduled notifications
  Future<String?> createReminder({
    required String userId,
    required String medicineId,
    required String medicineName,
    required String dosage,
    required List<String> times,
    required String frequency,
    required String takenFor,
    String? personName,
    bool enabled = true,
    String? notes,
  }) async {
    try {
      print('📝 Creating reminder for $medicineName');

      // Create the reminder document
      final reminderDoc = await _firestore.collection('reminders').add({
        'userId': userId,
        'medicineId': medicineId,
        'medicineName': medicineName,
        'dosage': dosage,
        'times': times,
        'frequency': frequency,
        'takenFor': takenFor,
        'personName': personName,
        'enabled': enabled,
        'notes': notes,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'lastTaken': null,
        'notificationsEnabled': true,
      });

      print('✅ Reminder created with ID: ${reminderDoc.id}');

      // Schedule notifications for this reminder
      if (enabled) {
        await _scheduleNotifications(
          reminderId: reminderDoc.id,
          userId: userId,
          medicineName: medicineName,
          dosage: dosage,
          times: times,
          frequency: frequency,
          takenFor: takenFor,
          personName: personName,
        );
      }

      return reminderDoc.id;
    } catch (e) {
      print('❌ Error creating reminder: $e');
      return null;
    }
  }

  /// Schedule notifications for a reminder
  Future<void> _scheduleNotifications({
    required String reminderId,
    required String userId,
    required String medicineName,
    required String dosage,
    required List<String> times,
    required String frequency,
    required String takenFor,
    String? personName,
  }) async {
    try {
      print('📅 Scheduling notifications for reminder: $reminderId');

      // Get user's FCM tokens
      final userTokensDoc = await _firestore.collection('user_tokens').doc(userId).get();

      List<String> tokens = [];

      if (!userTokensDoc.exists) {
        print('⚠️ No user_tokens document found for user: $userId');
        print('⚠️ Will create scheduled_notifications without tokens (will be updated when user opens app)');
        // Continue anyway - the Cloud Function will fetch tokens later
      } else {
        final data = userTokensDoc.data();
        tokens = List<String>.from(data?['tokens'] ?? []);
        print('📱 Found ${tokens.length} FCM tokens for user');
      }

      if (tokens.isEmpty) {
        print('⚠️ No FCM tokens found - notifications will be created but may not be sent until tokens are available');
      }

      final now = DateTime.now();
      final takenForDisplay = takenFor == 'Other' && personName != null
          ? personName
          : takenFor == 'Myself'
          ? 'yourself'
          : 'your ${takenFor.toLowerCase()}';

      int scheduledCount = 0;

      for (final timeStr in times) {
        print('⏰ Processing time: $timeStr');

        final scheduledTime = _parseTimeString(timeStr, now);
        if (scheduledTime == null) {
          print('⚠️ Could not parse time: $timeStr');
          continue;
        }

        print('📆 Scheduled time: $scheduledTime');

        // Calculate advance notification time (10 minutes before)
        final advanceTime = scheduledTime.subtract(const Duration(minutes: 10));

        // Create advance notification (10 minutes before)
        await _firestore.collection('scheduled_notifications').add({
          'userId': userId,
          'reminderId': reminderId,
          'medicineId': null,
          'tokens': tokens, // May be empty - Cloud Function will handle this
          'title': '⏰ Upcoming Medicine Reminder',
          'body': 'In 10 minutes: Take $medicineName ${dosage.isNotEmpty ? "($dosage)" : ""} for $takenForDisplay',
          'scheduledTime': Timestamp.fromDate(advanceTime),
          'type': 'reminder_advance',
          'data': {
            'reminderId': reminderId,
            'medicineName': medicineName,
            'dosage': dosage,
            'time': timeStr,
            'type': 'reminder_advance',
            'userId': userId,
          },
          'status': 'pending',
          'recurring': true,
          'frequency': frequency,
          'originalTime': timeStr,
          'createdAt': FieldValue.serverTimestamp(),
        });

        print('✅ Created advance notification for $advanceTime');

        // Create on-time notification
        await _firestore.collection('scheduled_notifications').add({
          'userId': userId,
          'reminderId': reminderId,
          'medicineId': null,
          'tokens': tokens, // May be empty - Cloud Function will handle this
          'title': '💊 Time for Your Medicine',
          'body': 'Take $medicineName ${dosage.isNotEmpty ? "($dosage)" : ""} now for $takenForDisplay',
          'scheduledTime': Timestamp.fromDate(scheduledTime),
          'type': 'reminder',
          'data': {
            'reminderId': reminderId,
            'medicineName': medicineName,
            'dosage': dosage,
            'time': timeStr,
            'type': 'reminder',
            'userId': userId,
          },
          'status': 'pending',
          'recurring': true,
          'frequency': frequency,
          'originalTime': timeStr,
          'createdAt': FieldValue.serverTimestamp(),
        });

        print('✅ Created on-time notification for $scheduledTime');
        scheduledCount += 2;
      }

      print('🎉 Scheduled $scheduledCount notifications for reminder: $reminderId');
    } catch (e) {
      print('❌ Error scheduling notifications: $e');
    }
  }

  /// Parse time string like "8:00 AM" or "2:30 PM" to DateTime
  DateTime? _parseTimeString(String timeStr, DateTime baseDate) {
    try {
      final cleanTime = timeStr.trim().toUpperCase();
      final isPM = cleanTime.contains('PM');
      final isAM = cleanTime.contains('AM');

      String timeOnly = cleanTime
          .replaceAll('AM', '')
          .replaceAll('PM', '')
          .replaceAll(' ', '')
          .trim();

      final parts = timeOnly.split(':');
      if (parts.isEmpty) return null;

      int hour = int.tryParse(parts[0]) ?? 0;
      final minute = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;

      // Convert to 24-hour format
      if (isPM && hour != 12) {
        hour += 12;
      } else if (isAM && hour == 12) {
        hour = 0;
      }

      var scheduledTime = DateTime(
        baseDate.year,
        baseDate.month,
        baseDate.day,
        hour,
        minute,
      );

      // If the time has already passed today, schedule for tomorrow
      if (scheduledTime.isBefore(DateTime.now())) {
        scheduledTime = scheduledTime.add(const Duration(days: 1));
        print('⏭️ Time already passed, scheduling for tomorrow');
      }

      return scheduledTime;
    } catch (e) {
      print('❌ Error parsing time string: $timeStr - $e');
      return null;
    }
  }

  /// Update reminder
  Future<bool> updateReminder({
    required String reminderId,
    List<String>? times,
    String? frequency,
    bool? enabled,
    String? notes,
    String? takenFor,
    String? personName,
  }) async {
    try {
      final updateData = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (times != null) updateData['times'] = times;
      if (frequency != null) updateData['frequency'] = frequency;
      if (enabled != null) updateData['enabled'] = enabled;
      if (notes != null) updateData['notes'] = notes;
      if (takenFor != null) updateData['takenFor'] = takenFor;
      if (personName != null) updateData['personName'] = personName;

      await _firestore.collection('reminders').doc(reminderId).update(updateData);

      if (enabled != null || times != null || frequency != null) {
        await _rescheduleNotifications(reminderId, enabled ?? true);
      }

      return true;
    } catch (e) {
      print('❌ Error updating reminder: $e');
      return false;
    }
  }

  /// Reschedule notifications when reminder is updated
  Future<void> _rescheduleNotifications(String reminderId, bool enabled) async {
    try {
      // Delete existing scheduled notifications for this reminder
      final existingNotifs = await _firestore
          .collection('scheduled_notifications')
          .where('reminderId', isEqualTo: reminderId)
          .where('status', isEqualTo: 'pending')
          .get();

      for (final doc in existingNotifs.docs) {
        await doc.reference.delete();
      }

      print('🗑️ Deleted ${existingNotifs.docs.length} existing notifications');

      if (enabled) {
        final reminderDoc = await _firestore.collection('reminders').doc(reminderId).get();
        if (reminderDoc.exists) {
          final data = reminderDoc.data()!;
          await _scheduleNotifications(
            reminderId: reminderId,
            userId: data['userId'],
            medicineName: data['medicineName'],
            dosage: data['dosage'] ?? '',
            times: List<String>.from(data['times'] ?? []),
            frequency: data['frequency'] ?? 'Daily',
            takenFor: data['takenFor'] ?? 'Myself',
            personName: data['personName'],
          );
        }
      }
    } catch (e) {
      print('❌ Error rescheduling notifications: $e');
    }
  }

  /// Delete reminder and its notifications
  Future<bool> deleteReminder(String reminderId) async {
    try {
      final notifs = await _firestore
          .collection('scheduled_notifications')
          .where('reminderId', isEqualTo: reminderId)
          .get();

      for (final doc in notifs.docs) {
        await doc.reference.delete();
      }

      await _firestore.collection('reminders').doc(reminderId).delete();

      print('✅ Deleted reminder and ${notifs.docs.length} notifications');
      return true;
    } catch (e) {
      print('❌ Error deleting reminder: $e');
      return false;
    }
  }

  /// Get reminders for a specific medicine
  Stream<QuerySnapshot<Map<String, dynamic>>> getMedicineReminders(
      String userId,
      String medicineId,
      ) {
    return _firestore
        .collection('reminders')
        .where('userId', isEqualTo: userId)
        .where('medicineId', isEqualTo: medicineId)
        .snapshots();
  }

  /// Get all active reminders for user
  Stream<QuerySnapshot<Map<String, dynamic>>> getUserReminders(String userId) {
    return _firestore
        .collection('reminders')
        .where('userId', isEqualTo: userId)
        .where('enabled', isEqualTo: true)
        .snapshots();
  }

  /// Get all reminders for user (including disabled)
  Stream<QuerySnapshot<Map<String, dynamic>>> getAllUserReminders(String userId) {
    return _firestore
        .collection('reminders')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  /// Mark medicine as taken
  Future<bool> markAsTaken(String reminderId, {String? time}) async {
    try {
      await _firestore.collection('reminders').doc(reminderId).update({
        'lastTaken': FieldValue.serverTimestamp(),
      });

      final reminderDoc = await _firestore.collection('reminders').doc(reminderId).get();
      final reminderData = reminderDoc.data();

      await _firestore.collection('medicine_intake_log').add({
        'reminderId': reminderId,
        'medicineId': reminderData?['medicineId'],
        'medicineName': reminderData?['medicineName'],
        'dosage': reminderData?['dosage'],
        'userId': reminderData?['userId'],
        'takenAt': FieldValue.serverTimestamp(),
        'scheduledTime': time,
        'takenFor': reminderData?['takenFor'],
      });

      return true;
    } catch (e) {
      print('❌ Error marking as taken: $e');
      return false;
    }
  }

  /// Skip a scheduled dose. Also notifies anyone tracking this user (their
  /// "guardians" via the Dependants feature) that a dose was missed —
  /// fulfilling the "guardian notified if medication is missed" requirement
  /// for doses the user explicitly marks as skipped from inside the app.
  ///
  /// Note: fully automatic detection of a dose the user simply never opened
  /// the app to acknowledge would need a server-side scheduled job (e.g. a
  /// Cloud Function comparing `scheduled_notifications` against
  /// `medicine_intake_log`) since this Flutter client has no background
  /// execution of its own — that mechanism is out of scope for the lib/
  /// code here and would be deployed alongside the existing Cloud Functions
  /// that already send the scheduled push notifications.
  Future<bool> skipDose(String reminderId, {String? time, String? reason}) async {
    try {
      final reminderDoc = await _firestore.collection('reminders').doc(reminderId).get();
      final reminderData = reminderDoc.data();
      final userId = reminderData?['userId'] as String?;
      final medicineName = reminderData?['medicineName'] as String? ?? 'medicine';

      await _firestore.collection('medicine_intake_log').add({
        'reminderId': reminderId,
        'medicineId': reminderData?['medicineId'],
        'medicineName': reminderData?['medicineName'],
        'dosage': reminderData?['dosage'],
        'userId': userId,
        'skippedAt': FieldValue.serverTimestamp(),
        'scheduledTime': time,
        'skipped': true,
        'skipReason': reason,
      });

      if (userId != null) {
        await _notifyGuardiansOfMissedDose(
          userId: userId,
          medicineName: medicineName,
          time: time,
          reason: reason,
        );
      }

      return true;
    } catch (e) {
      print('❌ Error skipping dose: $e');
      return false;
    }
  }

  /// Fan out a "missed dose" alert to everyone tracking [userId] as a
  /// dependant (see DependantService.notifyTrackers).
  Future<void> _notifyGuardiansOfMissedDose({
    required String userId,
    required String medicineName,
    String? time,
    String? reason,
  }) async {
    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();
      final name = userDoc.data()?['fullName'] ?? 'User';
      final body = reason != null && reason.trim().isNotEmpty
          ? 'Missed a dose of $medicineName${time != null ? ' ($time)' : ''} — $reason'
          : 'Missed a dose of $medicineName${time != null ? ' ($time)' : ''}';

      await _dependantSvc.notifyTrackers(
        ownerId: userId,
        ownerName: name,
        title: '💊 Missed medication',
        body: body,
        type: 'health_warning',
        data: {'medicineName': medicineName, 'scheduledTime': time},
      );
    } catch (e) {
      print('❌ Error notifying guardians of missed dose: $e');
    }
  }
}