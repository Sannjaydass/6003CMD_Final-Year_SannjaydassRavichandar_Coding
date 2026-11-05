import 'package:medictrack/design/medic_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/auth_service.dart';
import '../../services/dependant_service.dart';
import 'add_dependant_screen.dart';
import 'dependant_dashboard_screen.dart';

// ─── Design Tokens ────────────────────────────────────────────────────────────
class _C {
  static const navy    = MedicColors.c142F2B;
  static const teal    = MedicColors.c28715D;
  static const sky     = MedicColors.c477C91;
  static const amber   = MedicColors.cB77A27;
  static const rose    = MedicColors.cC05256;
  static const violet  = MedicColors.c78659B;
  static const surface = MedicColors.cF6F5F0;
  static const card    = MedicColors.cFFFFFF;
  static const border  = MedicColors.cE2E5DC;
  static const textPri = MedicColors.c142F2B;
  static const textSec = MedicColors.c63756D;
  static const textTer = MedicColors.c83938B;
}

class DependantsScreen extends StatefulWidget {
  const DependantsScreen({Key? key}) : super(key: key);

  @override
  State<DependantsScreen> createState() => _DependantsScreenState();
}

class _DependantsScreenState extends State<DependantsScreen>
    with SingleTickerProviderStateMixin {
  final _authSvc = AuthService();
  final _depSvc = DependantService();
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _openAdd() async {
    HapticFeedback.mediumImpact();
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => const AddDependantScreen()));
  }

  Future<void> _respond(String requestId, bool accept) async {
    HapticFeedback.mediumImpact();
    final result = await _depSvc.respondToRequest(requestId: requestId, accept: accept);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(result['message'], style: const TextStyle(
          fontWeight: FontWeight.w600, fontSize: 13)),
      backgroundColor: _C.navy,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(14),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final uid = _authSvc.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(body: Center(child: Text('Please log in')));
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _C.surface,
        body: Column(children: [
          _buildHeader(),
          Expanded(child: TabBarView(
            controller: _tabCtrl,
            children: [
              _buildDependantsTab(uid),
              _buildRequestsTab(uid),
            ],
          )),
        ]),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _openAdd,
          backgroundColor: _C.teal,
          icon: const Icon(Icons.person_add_alt_1_rounded, color: Colors.white),
          label: const Text('Add Dependant', style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }

  Widget _buildHeader() => MedicHeaderSurface(
    child: Stack(children: [
      Positioned.fill(child: CustomPaint(painter: _MeshPainter())),
      SafeArea(bottom: false, child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
          child: Row(children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.15))),
                child: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: Colors.white, size: 17),
              ),
            ),
            const SizedBox(width: 14),
            const Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Dependants', style: TextStyle(fontFamily: 'serif',
                  color: Colors.white, fontSize: 22,
                  fontWeight: FontWeight.w700, letterSpacing: -0.5)),
              SizedBox(height: 2),
              Text('Track a family member’s health, with their consent',
                  style: TextStyle(color: Colors.white70, fontSize: 12)),
            ])),
          ]),
        ),
        TabBar(
          controller: _tabCtrl,
          indicatorColor: _C.teal,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          tabs: const [
            Tab(text: 'My Dependants'),
            Tab(text: 'Requests'),
          ],
        ),
      ])),
    ]),
  );

  // ── My Dependants tab ──────────────────────────────────────────────────────
  Widget _buildDependantsTab(String uid) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: _depSvc.myDependants(uid),
    builder: (_, snap) {
      if (snap.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator(strokeWidth: 2.5, color: _C.teal));
      }
      final docs = snap.data?.docs ?? [];
      if (docs.isEmpty) {
        return _EmptyState(
          icon: Icons.people_outline_rounded,
          title: 'No Dependants Yet',
          subtitle: 'Add someone by their Patient ID to start tracking their health once they accept.',
          onTap: _openAdd,
          actionLabel: 'Add Dependant',
        );
      }
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
        itemCount: docs.length,
        itemBuilder: (_, i) {
          final d = docs[i].data();
          final depId = d['dependantId'] as String? ?? docs[i].id;
          final name = d['dependantName'] as String? ?? 'User';
          final code = d['dependantCode'] as String? ?? '';
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _PersonCard(
              name: name,
              subtitle: code.isNotEmpty ? 'ID: $code' : 'Tracking',
              trailingIcon: Icons.chevron_right_rounded,
              onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => DependantDashboardScreen(
                      dependantId: depId, dependantName: name))),
              onLongPress: () => _confirmRemove(uid, depId, name),
            ),
          );
        },
      );
    },
  );

  Future<void> _confirmRemove(String uid, String depId, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _C.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Stop tracking $name?', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: const Text('You will no longer be able to view their health dashboard.',
            style: TextStyle(fontSize: 13, color: _C.textSec)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Remove', style: TextStyle(color: _C.rose))),
        ],
      ),
    );
    if (ok == true) {
      await _depSvc.removeDependant(ownerId: depId, trackerId: uid);
    }
  }

  // Sorting is done here instead of in the Firestore query — see the
  // comment on DependantService.incomingRequests/outgoingRequests.
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _sortedByCreatedAt(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final sorted = List<QueryDocumentSnapshot<Map<String, dynamic>>>.of(docs);
    sorted.sort((a, b) {
      final at = a.data()['createdAt'], bt = b.data()['createdAt'];
      final ams = at is Timestamp ? at.millisecondsSinceEpoch : 0;
      final bms = bt is Timestamp ? bt.millisecondsSinceEpoch : 0;
      return bms.compareTo(ams);
    });
    return sorted;
  }

  // ── Requests tab ───────────────────────────────────────────────────────────
  Widget _buildRequestsTab(String uid) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Incoming', style: TextStyle(
          fontSize: 13, fontWeight: FontWeight.w700, color: _C.textSec, letterSpacing: 0.3)),
      const SizedBox(height: 10),
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _depSvc.incomingRequests(uid),
        builder: (_, snap) {
          final docs = _sortedByCreatedAt(snap.data?.docs ?? []);
          if (snap.connectionState == ConnectionState.waiting) {
            return const Padding(padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2.5, color: _C.teal)));
          }
          if (docs.isEmpty) {
            return _MiniEmpty(text: 'No one has requested to track you.');
          }
          return Column(children: docs.map((doc) {
            final d = doc.data();
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _RequestCard(
                name: d['fromUserName'] ?? 'A user',
                onAccept: () => _respond(doc.id, true),
                onReject: () => _respond(doc.id, false),
              ),
            );
          }).toList());
        },
      ),
      const SizedBox(height: 26),
      const Text('Sent', style: TextStyle(
          fontSize: 13, fontWeight: FontWeight.w700, color: _C.textSec, letterSpacing: 0.3)),
      const SizedBox(height: 10),
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _depSvc.outgoingRequests(uid),
        builder: (_, snap) {
          final docs = _sortedByCreatedAt(snap.data?.docs ?? []);
          if (docs.isEmpty) return _MiniEmpty(text: 'You have no pending requests.');
          return Column(children: docs.map((doc) {
            final d = doc.data();
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _PersonCard(
                name: d['toUserName'] ?? 'User',
                subtitle: 'Waiting for approval',
                trailingIcon: Icons.hourglass_top_rounded,
                trailingColor: _C.amber,
              ),
            );
          }).toList());
        },
      ),
    ]),
  );
}

// ─── Shared bits ──────────────────────────────────────────────────────────────
class _PersonCard extends StatelessWidget {
  final String name, subtitle;
  final IconData trailingIcon;
  final Color? trailingColor;
  final VoidCallback? onTap, onLongPress;
  const _PersonCard({required this.name, required this.subtitle,
    required this.trailingIcon, this.trailingColor, this.onTap, this.onLongPress});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    onLongPress: onLongPress,
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: _C.card, borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _C.border),
          boxShadow: [BoxShadow(color: MedicColors.forest.withOpacity(0.025),
              blurRadius: 10, offset: const Offset(0, 3))]),
      child: Row(children: [
        Container(width: 44, height: 44,
            decoration: BoxDecoration(color: _C.teal.withOpacity(0.12), shape: BoxShape.circle),
            child: Center(child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'U',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: _C.teal)))),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _C.textPri)),
          const SizedBox(height: 3),
          Text(subtitle, style: const TextStyle(fontSize: 12, color: _C.textSec)),
        ])),
        Icon(trailingIcon, color: trailingColor ?? _C.textTer, size: 20),
      ]),
    ),
  );
}

class _RequestCard extends StatelessWidget {
  final String name;
  final VoidCallback onAccept, onReject;
  const _RequestCard({required this.name, required this.onAccept, required this.onReject});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
        color: _C.card, borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _C.amber.withOpacity(0.3), width: 1.5),
        boxShadow: [BoxShadow(color: MedicColors.forest.withOpacity(0.025),
            blurRadius: 10, offset: const Offset(0, 3))]),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 44, height: 44,
            decoration: BoxDecoration(color: _C.amber.withOpacity(0.14), shape: BoxShape.circle),
            child: Center(child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'U',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: _C.amber)))),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _C.textPri)),
          const SizedBox(height: 3),
          const Text('Wants to track your health data', style: TextStyle(fontSize: 12, color: _C.textSec)),
        ])),
      ]),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: GestureDetector(
          onTap: onReject,
          child: Container(height: 42,
              decoration: BoxDecoration(color: _C.surface, borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _C.border)),
              child: const Center(child: Text('Decline', style: TextStyle(
                  color: _C.textSec, fontWeight: FontWeight.w700, fontSize: 13)))),
        )),
        const SizedBox(width: 10),
        Expanded(child: GestureDetector(
          onTap: onAccept,
          child: Container(height: 42,
              decoration: BoxDecoration(color: _C.teal, borderRadius: BorderRadius.circular(12)),
              child: const Center(child: Text('Accept', style: TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)))),
        )),
      ]),
    ]),
  );
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title, subtitle, actionLabel;
  final VoidCallback onTap;
  const _EmptyState({required this.icon, required this.title, required this.subtitle,
    required this.onTap, required this.actionLabel});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 76, height: 76,
            decoration: BoxDecoration(color: _C.teal.withOpacity(0.1), borderRadius: BorderRadius.circular(24)),
            child: Icon(icon, size: 36, color: _C.teal)),
        const SizedBox(height: 18),
        Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: _C.textPri)),
        const SizedBox(height: 8),
        Text(subtitle, textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: _C.textSec, height: 1.5)),
        const SizedBox(height: 20),
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            decoration: BoxDecoration(color: _C.teal, borderRadius: BorderRadius.circular(14)),
            child: Text(actionLabel, style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
          ),
        ),
      ]),
    ),
  );
}

class _MiniEmpty extends StatelessWidget {
  final String text;
  const _MiniEmpty({required this.text});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: _C.card, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _C.border)),
    child: Text(text, style: const TextStyle(fontSize: 12.5, color: _C.textTer)),
  );
}

class _MeshPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(Offset(size.width * 0.88, size.height * 0.18), 130,
        Paint()..color = _C.teal.withOpacity(0.07));
    canvas.drawCircle(Offset(size.width * 0.05, size.height * 0.9), 90,
        Paint()..color = _C.sky.withOpacity(0.06));
  }
  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
