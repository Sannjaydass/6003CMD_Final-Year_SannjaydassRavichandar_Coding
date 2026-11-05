import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Handles the "Dependants" feature: a single-role user can ask to track
/// another user's health data by their unique Patient ID. The target user
/// must explicitly accept before any data becomes visible — this keeps
/// health data private by default.
///
/// Firestore shape:
///   users/{uid}.patientCode              – short shareable ID (e.g. "7K3PQ2")
///   dependant_requests/{id}              – { fromUserId, fromUserName,
///                                             toUserId, toUserCode, toUserName,
///                                             status: pending|accepted|rejected,
///                                             createdAt, respondedAt }
///   users/{toUserId}/dependants/{fromId} – people `toUserId` allows to view
///                                           THEM (i.e. fromId tracks toUserId)
///   users/{fromUserId}/trackers/{toId}   – wait, see below for direction
///
/// To keep the two lookups simple and symmetric:
///   users/{ownerId}/trackers/{trackerId}   → trackerId is ALLOWED to view ownerId's data
///   users/{trackerId}/dependants/{ownerId} → mirror entry so trackerId can list who they track
class DependantService {
  static final DependantService _instance = DependantService._internal();
  factory DependantService() => _instance;
  DependantService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Look a user up by their shareable Patient ID (case-insensitive).
  Future<Map<String, dynamic>?> findUserByCode(String code) async {
    final normalized = code.trim().toUpperCase();
    if (normalized.isEmpty) return null;
    final q = await _db
        .collection('users')
        .where('patientCode', isEqualTo: normalized)
        .limit(1)
        .get();
    if (q.docs.isEmpty) return null;
    final doc = q.docs.first;
    return {'uid': doc.id, ...doc.data()};
  }

  /// Send a request to track someone by their Patient ID.
  Future<Map<String, dynamic>> sendRequest(String targetCode) async {
    final me = _auth.currentUser;
    if (me == null) return {'success': false, 'message': 'Not logged in'};

    final target = await findUserByCode(targetCode);
    if (target == null) {
      return {'success': false, 'message': 'No user found with that ID'};
    }
    final targetUid = target['uid'] as String;
    if (targetUid == me.uid) {
      return {'success': false, 'message': "You can't add yourself as a dependant"};
    }

    // Already tracking?
    final existingLink = await _db
        .collection('users').doc(targetUid)
        .collection('trackers').doc(me.uid).get();
    if (existingLink.exists) {
      return {'success': false, 'message': 'You already track this person'};
    }

    // Already have a pending request?
    final existingReq = await _db.collection('dependant_requests')
        .where('fromUserId', isEqualTo: me.uid)
        .where('toUserId', isEqualTo: targetUid)
        .where('status', isEqualTo: 'pending')
        .limit(1).get();
    if (existingReq.docs.isNotEmpty) {
      return {'success': false, 'message': 'Request already sent — waiting for approval'};
    }

    final myData = await _db.collection('users').doc(me.uid).get();
    final myName = myData.data()?['fullName'] ?? me.displayName ?? 'A MedicTrack user';

    final reqRef = await _db.collection('dependant_requests').add({
      'fromUserId': me.uid,
      'fromUserName': myName,
      'toUserId': targetUid,
      'toUserCode': target['patientCode'],
      'toUserName': target['fullName'] ?? 'User',
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'respondedAt': null,
    });

    await _notify(
      userId: targetUid,
      title: 'New dependant request',
      body: '$myName wants to track your health data on MedicTrack.',
      type: 'dependant_request',
      data: {'requestId': reqRef.id, 'fromUserId': me.uid, 'fromUserName': myName},
    );

    return {'success': true, 'message': 'Request sent to ${target['fullName'] ?? 'user'}'};
  }

  /// Incoming requests where *I* am the one being asked about.
  ///
  /// NOTE: deliberately no `.orderBy('createdAt', ...)` here. Combining it
  /// with the two `.where(...)` equality filters above needs a Firestore
  /// composite index that was never created, so the query silently returned
  /// nothing — which is why an accepted/rejected request never showed up on
  /// the "Requests" tab even though `sendRequest()` had written it. Sorting
  /// now happens client-side in dependants_screen.dart instead.
  Stream<QuerySnapshot<Map<String, dynamic>>> incomingRequests(String uid) {
    return _db.collection('dependant_requests')
        .where('toUserId', isEqualTo: uid)
        .where('status', isEqualTo: 'pending')
        .snapshots();
  }

  /// Requests *I* sent that are still pending. Same note as above re: no
  /// `.orderBy()` in the Firestore query.
  Stream<QuerySnapshot<Map<String, dynamic>>> outgoingRequests(String uid) {
    return _db.collection('dependant_requests')
        .where('fromUserId', isEqualTo: uid)
        .where('status', isEqualTo: 'pending')
        .snapshots();
  }

  /// Accept or reject an incoming request.
  Future<Map<String, dynamic>> respondToRequest({
    required String requestId,
    required bool accept,
  }) async {
    final me = _auth.currentUser;
    if (me == null) return {'success': false, 'message': 'Not logged in'};

    final reqDoc = await _db.collection('dependant_requests').doc(requestId).get();
    if (!reqDoc.exists) return {'success': false, 'message': 'Request not found'};
    final req = reqDoc.data()!;
    if (req['toUserId'] != me.uid) {
      return {'success': false, 'message': 'Unauthorized'};
    }
    if (req['status'] != 'pending') {
      return {'success': false, 'message': 'Request already handled'};
    }

    final fromUserId = req['fromUserId'] as String;
    final fromUserName = req['fromUserName'] ?? 'User';

    await _db.collection('dependant_requests').doc(requestId).update({
      'status': accept ? 'accepted' : 'rejected',
      'respondedAt': FieldValue.serverTimestamp(),
    });

    if (accept) {
      final myData = await _db.collection('users').doc(me.uid).get();
      final myName = myData.data()?['fullName'] ?? 'User';
      final myCode = myData.data()?['patientCode'];

      final batch = _db.batch();
      // fromUserId is now allowed to view me (the owner)
      batch.set(
        _db.collection('users').doc(me.uid).collection('trackers').doc(fromUserId),
        {
          'trackerId': fromUserId,
          'trackerName': fromUserName,
          'addedAt': FieldValue.serverTimestamp(),
        },
      );
      // mirror entry so fromUserId can list who they track
      batch.set(
        _db.collection('users').doc(fromUserId).collection('dependants').doc(me.uid),
        {
          'dependantId': me.uid,
          'dependantName': myName,
          'dependantCode': myCode,
          'addedAt': FieldValue.serverTimestamp(),
        },
      );
      await batch.commit();
    }

    await _notify(
      userId: fromUserId,
      title: accept ? 'Request accepted' : 'Request declined',
      body: accept
          ? 'You can now track this person\'s health data.'
          : 'Your dependant request was declined.',
      type: accept ? 'dependant_accepted' : 'dependant_rejected',
      data: {'requestId': requestId, 'toUserId': me.uid},
    );

    return {'success': true, 'message': accept ? 'Request accepted' : 'Request declined'};
  }

  /// People I am tracking (my dependants).
  Stream<QuerySnapshot<Map<String, dynamic>>> myDependants(String uid) {
    return _db.collection('users').doc(uid).collection('dependants')
        .orderBy('addedAt', descending: true)
        .snapshots();
  }

  /// People who are allowed to track ME (my "guardians"/trackers) — used to
  /// fan out missed-dose / worsening-health alerts.
  Stream<QuerySnapshot<Map<String, dynamic>>> myTrackers(String uid) {
    return _db.collection('users').doc(uid).collection('trackers')
        .orderBy('addedAt', descending: true)
        .snapshots();
  }

  Future<List<Map<String, dynamic>>> myTrackersOnce(String uid) async {
    final q = await _db.collection('users').doc(uid).collection('trackers').get();
    return q.docs.map((d) => d.data()).toList();
  }

  /// Remove a dependant link (either side can sever it).
  Future<void> removeDependant({required String ownerId, required String trackerId}) async {
    final batch = _db.batch();
    batch.delete(_db.collection('users').doc(ownerId).collection('trackers').doc(trackerId));
    batch.delete(_db.collection('users').doc(trackerId).collection('dependants').doc(ownerId));
    await batch.commit();
  }

  /// Fan out a notification to everyone tracking [ownerId] — used for
  /// "guardian notified if medication missed" / "warning if health worsens".
  Future<void> notifyTrackers({
    required String ownerId,
    required String ownerName,
    required String title,
    required String body,
    required String type,
    Map<String, dynamic>? data,
  }) async {
    final trackers = await myTrackersOnce(ownerId);
    for (final t in trackers) {
      final trackerId = t['trackerId'] as String?;
      if (trackerId == null) continue;
      await _notify(
        userId: trackerId,
        title: title,
        body: '$ownerName — $body',
        type: type,
        data: {...?data, 'dependantId': ownerId, 'dependantName': ownerName},
      );
    }
  }

  Future<void> _notify({
    required String userId,
    required String title,
    required String body,
    required String type,
    Map<String, dynamic>? data,
  }) async {
    await _db.collection('notifications').add({
      'userId': userId,
      'title': title,
      'body': body,
      'type': type,
      'data': data ?? {},
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
