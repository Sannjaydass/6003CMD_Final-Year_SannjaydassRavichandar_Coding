import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'notification_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final NotificationService _notificationService = NotificationService();

  // Get current user
  User? get currentUser => _auth.currentUser;

  // Auth state changes stream
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Generates a short, human-shareable Patient ID (e.g. "7K3PQ2") used so
  /// another MedicTrack user can find this account and request to track it
  /// as a dependant. Retries on the rare collision.
  Future<String> _generateUniquePatientCode() async {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no O/0/I/1 ambiguity
    final rnd = Random.secure();
    for (int attempt = 0; attempt < 8; attempt++) {
      final code = List.generate(6, (_) => chars[rnd.nextInt(chars.length)]).join();
      final existing = await _firestore
          .collection('users')
          .where('patientCode', isEqualTo: code)
          .limit(1)
          .get();
      if (existing.docs.isEmpty) return code;
    }
    // Extremely unlikely fallback: timestamp-derived code.
    return 'U${DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase()}'
        .substring(0, 6);
  }

  // Sign up with email and password.
  // MedicTrack has a single account role — every user signs up the same
  // way and provides the basics needed to compute their Health Score
  // straight away: age, height and weight.
  Future<Map<String, dynamic>> signUp({
    required String email,
    required String password,
    required String fullName,
    // Age/height/weight are now OPTIONAL at signup — forcing every health
    // detail before an account can even be created is bad onboarding for a
    // Play Store app. A person can create the account first and fill these
    // in later from Profile / the health-score setup steps.
    int? age,
    double? height,
    double? weight,
    // 'patient' (default) tracks their own vitals/medicines/health score.
    // 'dependant' is for someone managing a patient's medicines on their
    // behalf (e.g. a caregiver creating their OWN login) — their account
    // does not get asked for personal vitals or a health score at all.
    String accountType = 'patient',
    // Only meaningful for accountType == 'patient'. Free-text condition
    // names, e.g. ['Diabetes', 'Hypertension'].
    List<String> conditions = const [],
  }) async {
    try {
      print('📝 Creating account for: $email');

      // Create user account
      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      User? user = userCredential.user;

      if (user != null) {
        // Update display name
        await user.updateDisplayName(fullName);

        final patientCode = await _generateUniquePatientCode();
        final hasVitals = height != null && height > 0 && weight != null && weight > 0;
        final bmi = hasVitals ? weight! / ((height! / 100) * (height / 100)) : null;

        // Store user data in Firestore
        await _firestore.collection('users').doc(user.uid).set({
          'uid': user.uid,
          'email': email,
          'fullName': fullName,
          if (age != null) 'age': age,
          'patientCode': patientCode,
          'accountType': accountType,
          if (accountType == 'patient' && conditions.isNotEmpty) 'conditions': conditions,
          if (hasVitals) 'healthInfo': {
            'height': height,
            'weight': weight,
            'bmi': bmi,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          'createdAt': FieldValue.serverTimestamp(),
          // true only once age + height + weight are all on file — this is
          // what the "finish setting up your health score" step on the
          // dashboard checks, instead of forcing everything at signup.
          'profileComplete': age != null && hasVitals,
          'notificationsEnabled': true,
          'fcmTokens': [],
        });

        print('✅ User document created');

        // Send the verification email right away. The account IS created
        // and the person stays signed in (Firebase does that automatically
        // after createUserWithEmailAndPassword) — they just can't reach the
        // rest of the app until they click the link, which VerifyEmailScreen
        // enforces. A failed send here doesn't fail the whole signup; the
        // "Resend email" button on that screen covers a flaky first send.
        try {
          await user.sendEmailVerification();
          print('📧 Verification email sent to $email');
        } catch (e) {
          print('⚠️ Could not send verification email: $e');
        }

        // Save FCM token for push notifications
        print('💾 Saving FCM token...');
        await _notificationService.saveTokenToFirestore(user.uid);

        // Subscribe to general notifications topic
        await _notificationService.subscribeToTopic('all_users');

        return {
          'success': true,
          'message': 'Account created successfully!',
          'user': user,
          'needsVerification': !user.emailVerified,
        };
      }

      return {
        'success': false,
        'message': 'Failed to create account',
      };
    } on FirebaseAuthException catch (e) {
      String errorMessage;

      switch (e.code) {
        case 'weak-password':
          errorMessage = 'The password is too weak. Use at least 6 characters.';
          break;
        case 'email-already-in-use':
          errorMessage = 'This email is already registered. Please login.';
          break;
        case 'invalid-email':
          errorMessage = 'Invalid email address format.';
          break;
        case 'operation-not-allowed':
          errorMessage = 'Email/password accounts are not enabled.';
          break;
        default:
          errorMessage = e.message ?? 'An error occurred during signup.';
      }

      print('❌ Signup error: $errorMessage');
      return {
        'success': false,
        'message': errorMessage,
      };
    } catch (e) {
      print('❌ Signup error: $e');
      return {
        'success': false,
        'message': 'An unexpected error occurred: ${e.toString()}',
      };
    }
  }

  // Sign in with email and password
  Future<Map<String, dynamic>> signIn({
    required String email,
    required String password,
  }) async {
    try {
      print('🔐 Signing in: $email');

      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      User? rawUser = userCredential.user;

      if (rawUser != null) {
        // Reload first — emailVerified can be stale on the cached User
        // object if verification happened in a different app session.
        await rawUser.reload();
        final User? user = _auth.currentUser;

        if (user == null) {
          return {'success': false, 'message': 'Login failed'};
        }

        if (!user.emailVerified) {
          print('⛔ Login blocked — email not verified: $email');
          // Sign back out immediately: this app only lets verified emails
          // reach the rest of the app, so there's no reason to leave a
          // session open here. resendVerificationEmail() below re-signs-in
          // briefly on its own when the person taps "Resend" on the login
          // screen, so nothing is lost by signing out now.
          await _auth.signOut();
          return {
            'success': false,
            'emailNotVerified': true,
            'email': email,
            'message': 'Please verify your email before signing in. '
                'Check your inbox (and spam folder) for the verification link.',
          };
        }

        print('✅ Login successful for user: ${user.uid}');

        // Update last login time
        await _firestore.collection('users').doc(user.uid).update({
          'lastLogin': FieldValue.serverTimestamp(),
        }).catchError((e) {
          print('⚠️ Could not update lastLogin: $e');
        });

        // Save/Update FCM token for push notifications
        print('💾 Saving FCM token...');
        await _notificationService.saveTokenToFirestore(user.uid);

        // Subscribe to topics
        await _notificationService.subscribeToTopic('all_users');

        return {
          'success': true,
          'message': 'Login successful!',
          'user': user,
        };
      }

      return {
        'success': false,
        'message': 'Login failed',
      };
    } on FirebaseAuthException catch (e) {
      String errorMessage;

      switch (e.code) {
        case 'user-not-found':
          errorMessage = 'No account found with this email.';
          break;
        case 'wrong-password':
          errorMessage = 'Incorrect password. Please try again.';
          break;
        case 'invalid-email':
          errorMessage = 'Invalid email address format.';
          break;
        case 'user-disabled':
          errorMessage = 'This account has been disabled.';
          break;
        case 'too-many-requests':
          errorMessage = 'Too many failed attempts. Please try again later.';
          break;
        case 'invalid-credential':
          errorMessage = 'Invalid email or password. Please try again.';
          break;
        default:
          errorMessage = e.message ?? 'An error occurred during login.';
      }

      print('❌ Login error: $errorMessage');
      return {
        'success': false,
        'message': errorMessage,
      };
    } catch (e) {
      print('❌ Login error: $e');
      return {
        'success': false,
        'message': 'An unexpected error occurred: ${e.toString()}',
      };
    }
  }

  // Sign out
  Future<void> signOut() async {
    try {
      final user = _auth.currentUser;

      if (user != null) {
        print('🚪 Signing out user: ${user.uid}');

        // Remove FCM token before signing out
        await _notificationService.removeToken(user.uid);

        // Unsubscribe from topics
        await _notificationService.unsubscribeFromTopic('all_users');
      }

      await _auth.signOut();
      print('✅ Sign out successful');
    } catch (e) {
      print('❌ Error during sign out: $e');
      await _auth.signOut();
    }
  }

  /// Re-sends the verification email for an account that hasn't clicked it
  /// yet. Used two ways: (1) from the login screen, after a sign-in attempt
  /// comes back with `emailNotVerified: true` — there's no session at that
  /// point (signIn() already signed out), so this briefly re-authenticates
  /// with the email+password already in the form, fires the email, then
  /// signs out again; (2) from VerifyEmailScreen right after signup, where
  /// the person is already signed in — pass the same credentials again (the
  /// signup form still has them) and this takes the same path either way.
  Future<Map<String, dynamic>> resendVerificationEmail({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        return {'success': false, 'message': 'Could not sign in to resend the verification email.'};
      }
      await user.reload();
      if (_auth.currentUser?.emailVerified ?? false) {
        await _auth.signOut();
        return {
          'success': false,
          'alreadyVerified': true,
          'message': 'This email is already verified — try signing in again.',
        };
      }
      await user.sendEmailVerification();
      await _auth.signOut();
      return {
        'success': true,
        'message': 'Verification email sent. Check your inbox (and spam folder).',
      };
    } on FirebaseAuthException catch (e) {
      return {
        'success': false,
        'message': e.message ?? 'Could not resend the verification email.',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'An unexpected error occurred: ${e.toString()}',
      };
    }
  }

  /// Re-sends the verification email for the user who is CURRENTLY signed
  /// in — the simple case, used by VerifyEmailScreen right after signup
  /// where a session already exists and no password re-entry is needed.
  Future<Map<String, dynamic>> resendVerificationEmailForCurrentUser() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return {'success': false, 'message': 'No account is signed in.'};
      }
      await user.sendEmailVerification();
      return {
        'success': true,
        'message': 'Verification email sent. Check your inbox (and spam folder).',
      };
    } on FirebaseAuthException catch (e) {
      return {
        'success': false,
        'message': e.message ?? 'Could not resend the verification email.',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'An unexpected error occurred: ${e.toString()}',
      };
    }
  }

  /// Reloads the currently signed-in user from Firebase and reports whether
  /// their email is verified now — what VerifyEmailScreen's "I've verified
  /// — Continue" button calls to check without requiring a fresh sign-in.
  Future<bool> checkEmailVerified() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    await user.reload();
    return _auth.currentUser?.emailVerified ?? false;
  }

  // Password reset
  Future<Map<String, dynamic>> resetPassword({required String email}) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      return {
        'success': true,
        'message': 'Password reset email sent! Check your inbox.',
      };
    } on FirebaseAuthException catch (e) {
      String errorMessage;

      switch (e.code) {
        case 'user-not-found':
          errorMessage = 'No account found with this email.';
          break;
        case 'invalid-email':
          errorMessage = 'Invalid email address format.';
          break;
        default:
          errorMessage = e.message ?? 'Failed to send reset email.';
      }

      return {
        'success': false,
        'message': errorMessage,
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'An unexpected error occurred: ${e.toString()}',
      };
    }
  }

  // Get user data from Firestore
  Future<Map<String, dynamic>?> getUserData(String uid) async {
    try {
      DocumentSnapshot doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists) {
        return doc.data() as Map<String, dynamic>?;
      }
      return null;
    } catch (e) {
      print('Error getting user data: $e');
      return null;
    }
  }

  // Update user profile
  Future<bool> updateUserProfile({
    required String uid,
    String? fullName,
    String? phoneNumber,
  }) async {
    try {
      Map<String, dynamic> updateData = {};

      if (fullName != null) updateData['fullName'] = fullName;
      if (phoneNumber != null) updateData['phoneNumber'] = phoneNumber;

      updateData['updatedAt'] = FieldValue.serverTimestamp();

      await _firestore.collection('users').doc(uid).update(updateData);

      if (fullName != null) {
        await _auth.currentUser?.updateDisplayName(fullName);
      }

      return true;
    } catch (e) {
      print('Error updating profile: $e');
      return false;
    }
  }

  // Check if user is logged in
  bool isLoggedIn() {
    return _auth.currentUser != null;
  }

  // Delete account
  Future<Map<String, dynamic>> deleteAccount() async {
    try {
      User? user = _auth.currentUser;
      if (user != null) {
        final uid = user.uid;

        // Remove FCM token
        await _notificationService.removeToken(uid);

        // Unsubscribe from topics
        await _notificationService.unsubscribeFromTopic('all_users');

        // Delete all user's notifications
        await _notificationService.deleteAllNotifications(uid);

        // Delete user's reminders
        final reminders = await _firestore
            .collection('reminders')
            .where('userId', isEqualTo: uid)
            .get();
        for (final doc in reminders.docs) {
          await doc.reference.delete();
        }

        // Delete user's scheduled notifications
        final scheduledNotifs = await _firestore
            .collection('scheduled_notifications')
            .where('userId', isEqualTo: uid)
            .get();
        for (final doc in scheduledNotifs.docs) {
          await doc.reference.delete();
        }

        // Delete user's medicines
        final medicines = await _firestore
            .collection('medicines')
            .where('userId', isEqualTo: uid)
            .get();
        for (final doc in medicines.docs) {
          await doc.reference.delete();
        }

        // Delete user tokens document
        await _firestore.collection('user_tokens').doc(uid).delete();

        // Delete dependant links (both directions) and pending requests
        final trackers = await _firestore.collection('users').doc(uid).collection('trackers').get();
        for (final doc in trackers.docs) {
          await doc.reference.delete();
          await _firestore.collection('users').doc(doc.id).collection('dependants').doc(uid).delete();
        }
        final dependants = await _firestore.collection('users').doc(uid).collection('dependants').get();
        for (final doc in dependants.docs) {
          await doc.reference.delete();
          await _firestore.collection('users').doc(doc.id).collection('trackers').doc(uid).delete();
        }
        for (final field in ['fromUserId', 'toUserId']) {
          final reqs = await _firestore
              .collection('dependant_requests')
              .where(field, isEqualTo: uid)
              .get();
          for (final doc in reqs.docs) {
            await doc.reference.delete();
          }
        }

        // Delete user data from Firestore
        await _firestore.collection('users').doc(uid).delete();

        // Delete authentication account
        await user.delete();

        return {
          'success': true,
          'message': 'Account deleted successfully',
        };
      }
      return {
        'success': false,
        'message': 'No user logged in',
      };
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        return {
          'success': false,
          'message': 'Please log out and log in again before deleting your account.',
          'requiresReauth': true,
        };
      }
      return {
        'success': false,
        'message': 'Error deleting account: ${e.message}',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Error deleting account: ${e.toString()}',
      };
    }
  }

  // Add this method to your existing AuthService class
// This is the changePassword method to add to auth_service.dart

  /// Change user password
  /// Requires re-authentication with current password before changing
  Future<Map<String, dynamic>> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return {
          'success': false,
          'message': 'No user logged in',
        };
      }

      // Get user email
      final email = user.email;
      if (email == null) {
        return {
          'success': false,
          'message': 'User email not found',
        };
      }

      // Re-authenticate user with current password
      final credential = EmailAuthProvider.credential(
        email: email,
        password: currentPassword,
      );

      try {
        await user.reauthenticateWithCredential(credential);
      } on FirebaseAuthException catch (e) {
        if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
          return {
            'success': false,
            'message': 'Current password is incorrect',
          };
        }
        return {
          'success': false,
          'message': 'Authentication failed: ${e.message}',
        };
      }

      // Update password
      await user.updatePassword(newPassword);

      return {
        'success': true,
        'message': 'Password changed successfully',
      };
    } on FirebaseAuthException catch (e) {
      String message;
      switch (e.code) {
        case 'weak-password':
          message = 'The new password is too weak';
          break;
        case 'requires-recent-login':
          message = 'Please log out and log in again before changing password';
          break;
        default:
          message = e.message ?? 'Failed to change password';
      }
      return {
        'success': false,
        'message': message,
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'An error occurred: $e',
      };
    }
  }
  
}