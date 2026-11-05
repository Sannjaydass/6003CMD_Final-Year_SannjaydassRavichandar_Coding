import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  FlutterLocalNotificationsPlugin get localPlugin => _localNotifications;

  void Function(String?)? onTap;

  bool _initialized = false;

  /// Initialize the notification service
  Future<void> initialize() async {
    if (_initialized) return;

    print('🔔 Initializing NotificationService...');

    // Initialise local delivery even if remote push registration is unavailable.
    await _initializeLocalNotifications();
    try { await _requestPermission(); }
    catch (_) { print('Remote notification permission check unavailable; use Reminder check.'); }

    // Set up message handlers
    _setupMessageHandlers();

    _initialized = true;
    print('✅ NotificationService initialized');
  }

  /// Request notification permissions
  Future<bool> _requestPermission() async {
    print('📱 Requesting notification permission...');

    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
      announcement: true,
      criticalAlert: false,
    );

    final granted = settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;

    print('📱 Notification permission granted: $granted');
    return granted;
  }

  /// Initialize local notifications plugin
  Future<void> _initializeLocalNotifications() async {
    print('📱 Initializing local notifications...');

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // Create notification channels for Android
    if (Platform.isAndroid) {
      const channel = AndroidNotificationChannel(
        'medicine_reminders',
        'Medicine Reminders',
        description: 'Notifications for medicine reminders',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      );
      // Separate, higher-urgency channel for the +10-minute "still not
      // confirmed" alert the Cloud Functions worker sends (functions/index.js
      // -> buildMessage kind: 'late'). Android requires a channel to exist
      // before a push naming it will display, so this must be created here
      // even though nothing locally schedules into it.
      const alertChannel = AndroidNotificationChannel(
        'medicine_alerts',
        'Medicine Alerts',
        description: 'Urgent alerts for medicine doses that have not been confirmed',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );

      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(channel);
      await androidPlugin?.createNotificationChannel(alertChannel);
      await androidPlugin?.createNotificationChannel(const AndroidNotificationChannel('health_urgent', 'Urgent health readings',
        description: 'New readings needing urgent review', importance: Importance.max, playSound: true, enableVibration: true));

      print('✅ Android notification channels created');
    }
  }

  /// Handle notification tap
  void _onNotificationTapped(NotificationResponse response) {
    onTap?.call(response.payload);
  }

  /// Set up FCM message handlers
  void _setupMessageHandlers() {
    // Handle foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Handle notification taps when app is in background
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

    // Check if app was opened from notification
    _checkInitialMessage();

    print('✅ Message handlers set up');
  }

  /// Handle foreground messages
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    print('📩 Received foreground message: ${message.messageId}');
    print('📩 Title: ${message.notification?.title}');
    print('📩 Body: ${message.notification?.body}');

    final notification = message.notification;

    if (notification != null) {
      if (message.data['type'] == 'health_monitoring' && message.data['severity'] == 'urgent') {
        await _localNotifications.show(7301, notification.title, notification.body,
          const NotificationDetails(android: AndroidNotificationDetails('health_urgent', 'Urgent health readings',
            importance: Importance.max, priority: Priority.max, playSound: true, enableVibration: true),
            iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true)), payload: jsonEncode(message.data));
        return;
      }
      await showLocalNotification(
        title: notification.title ?? 'Medicine Reminder',
        body: notification.body ?? 'Time to take your medicine',
        payload: jsonEncode(message.data),
      );
    }
  }

  /// Handle when notification is tapped and app opens
  void _handleMessageOpenedApp(RemoteMessage message) {
    print('📩 Message opened app: ${message.messageId}');
  }

  /// Check if app was opened from terminated state via notification
  Future<void> _checkInitialMessage() async {
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      print('📩 App opened from notification: ${initialMessage.messageId}');
    }
  }

  /// Get FCM token for the device
  Future<String?> getToken() async {
    try {
      final token = await _messaging.getToken();
      print('📱 FCM Token obtained: ${token?.substring(0, 20)}...');
      return token;
    } catch (e) {
      print('❌ Error getting FCM token: $e');
      return null;
    }
  }

  /// Save FCM token to Firestore for a user
  /// THIS IS THE CRITICAL METHOD - FIXED TO ALWAYS CREATE THE DOCUMENT
  Future<void> saveTokenToFirestore(String userId) async {
    try {
      print('💾 Saving FCM token for user: $userId');

      // Get the FCM token
      final token = await getToken();

      if (token == null || token.isEmpty) {
        print('❌ No FCM token available - cannot save');
        return;
      }

      print('📱 Token to save: ${token.substring(0, 20)}...');

      // IMPORTANT: Use set with merge:true to create document if it doesn't exist
      // This ensures the document is always created
      final userTokenRef = _firestore.collection('user_tokens').doc(userId);

      // First, try to get the existing document
      final existingDoc = await userTokenRef.get();

      if (existingDoc.exists) {
        // Document exists, update it
        print('📄 user_tokens document exists, updating...');
        await userTokenRef.update({
          'tokens': FieldValue.arrayUnion([token]),
          'platform': Platform.isAndroid ? 'android' : 'ios',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        // Document doesn't exist, create it
        print('📄 user_tokens document does not exist, creating...');
        await userTokenRef.set({
          'userId': userId,
          'tokens': [token],
          'platform': Platform.isAndroid ? 'android' : 'ios',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      print('✅ FCM token saved to user_tokens collection');

      // Also update users collection (optional, but good for backup)
      try {
        await _firestore.collection('users').doc(userId).update({
          'fcmTokens': FieldValue.arrayUnion([token]),
          'lastTokenUpdate': FieldValue.serverTimestamp(),
        });
        print('✅ FCM token also saved to users collection');
      } catch (e) {
        print('⚠️ Could not update users collection (might not exist): $e');
      }

      print('✅ FCM token saved successfully for user: $userId');
    } catch (e) {
      print('❌ Error saving FCM token: $e');
      print('❌ Stack trace: ${StackTrace.current}');
    }
  }

  /// Remove FCM token when user logs out
  Future<void> removeToken(String userId) async {
    try {
      final token = await getToken();
      if (token == null) return;

      // Check if document exists before updating
      final docRef = _firestore.collection('user_tokens').doc(userId);
      final doc = await docRef.get();

      if (doc.exists) {
        await docRef.update({
          'tokens': FieldValue.arrayRemove([token]),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        print('✅ FCM token removed from user_tokens');
      }

      // Also remove from users collection
      try {
        await _firestore.collection('users').doc(userId).update({
          'fcmTokens': FieldValue.arrayRemove([token]),
        });
      } catch (e) {
        print('⚠️ Could not update users collection: $e');
      }

      print('✅ FCM token removed for user: $userId');
    } catch (e) {
      print('❌ Error removing FCM token: $e');
    }
  }

  /// Show a local notification
  Future<void> showLocalNotification({
    required String title,
    required String body,
    String? payload,
    int id = 0,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'medicine_reminders',
      'Medicine Reminders',
      channelDescription: 'Notifications for medicine reminders',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      icon: '@mipmap/ic_launcher',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(id, title, body, details, payload: payload);
    print('✅ Local notification shown: $title');
  }

  /// Get notifications for a user.
  ///
  /// NOTE: this deliberately does NOT combine `.where('userId', ...)` with
  /// `.orderBy('createdAt', ...)` in the same Firestore query. That
  /// combination needs a composite index to be created in the Firestore
  /// console first; without it the query fails silently (the stream just
  /// never emits data), which is exactly why the Notifications screen could
  /// show "No Notifications" in the body while the unread-count header
  /// (a single-field query, which doesn't need an index) still showed
  /// unread messages. Sorting is done in the UI after the single-field
  /// query loads instead.
  Stream<QuerySnapshot<Map<String, dynamic>>> getUserNotifications(String userId, {int limit = 50}) {
    // No .limit() here either — the limit is applied in the UI AFTER
    // sorting by date (see notifications_screen.dart), since limiting
    // before an in-memory sort would arbitrarily cut off whichever docs
    // Firestore happened to return first, not the most recent ones.
    return _firestore
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .snapshots();
  }

  /// Get unread notification count
  Stream<int> getUnreadCount(String userId) {
    return _firestore
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .where('read', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  /// Mark notification as read
  Future<void> markAsRead(String notificationId) async {
    try {
      await _firestore.collection('notifications').doc(notificationId).update({
        'read': true,
        'readAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('❌ Error marking notification as read: $e');
    }
  }

  /// Mark all notifications as read
  Future<void> markAllAsRead(String userId) async {
    try {
      final batch = _firestore.batch();
      final notifications = await _firestore
          .collection('notifications')
          .where('userId', isEqualTo: userId)
          .where('read', isEqualTo: false)
          .get();

      for (final doc in notifications.docs) {
        batch.update(doc.reference, {
          'read': true,
          'readAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();
      print('✅ Marked ${notifications.docs.length} notifications as read');
    } catch (e) {
      print('❌ Error marking all notifications as read: $e');
    }
  }

  /// Delete a notification
  Future<void> deleteNotification(String notificationId) async {
    try {
      await _firestore.collection('notifications').doc(notificationId).delete();
    } catch (e) {
      print('❌ Error deleting notification: $e');
    }
  }

  /// Delete all notifications for a user
  Future<void> deleteAllNotifications(String userId) async {
    try {
      final batch = _firestore.batch();
      final notifications = await _firestore
          .collection('notifications')
          .where('userId', isEqualTo: userId)
          .get();

      for (final doc in notifications.docs) {
        batch.delete(doc.reference);
      }

      await batch.commit();
      print('✅ Deleted ${notifications.docs.length} notifications');
    } catch (e) {
      print('❌ Error deleting all notifications: $e');
    }
  }

  /// Subscribe to a topic
  Future<void> subscribeToTopic(String topic) async {
    try {
      await _messaging.subscribeToTopic(topic);
      print('✅ Subscribed to topic: $topic');
    } catch (e) {
      print('❌ Error subscribing to topic: $e');
    }
  }

  /// Unsubscribe from a topic
  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _messaging.unsubscribeFromTopic(topic);
      print('✅ Unsubscribed from topic: $topic');
    } catch (e) {
      print('❌ Error unsubscribing from topic: $e');
    }
  }

  /// Test method to manually trigger token save (for debugging)
  Future<bool> debugSaveToken(String userId) async {
    print('🔧 DEBUG: Manually saving token for user: $userId');

    try {
      final token = await getToken();
      if (token == null) {
        print('❌ DEBUG: No token available');
        return false;
      }

      print('📱 DEBUG: Token = ${token.substring(0, 30)}...');

      await _firestore.collection('user_tokens').doc(userId).set({
        'userId': userId,
        'tokens': [token],
        'platform': Platform.isAndroid ? 'android' : 'ios',
        'debugSaved': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      print('✅ DEBUG: Token saved successfully!');
      return true;
    } catch (e) {
      print('❌ DEBUG: Error saving token: $e');
      return false;
    }
  }
}