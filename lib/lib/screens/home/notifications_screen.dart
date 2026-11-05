import 'health_monitoring_screen.dart';
import 'dependant_dashboard_screen.dart';
import 'package:medictrack/design/medic_design.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/auth_service.dart';
import '../../services/notification_service.dart';

// ─── Design Tokens ────────────────────────────────────────────────────────────
class _C {
  static const navy     = MedicColors.c142F2B;
  static const navyMid  = MedicColors.c23473E;
  static const teal     = MedicColors.c28715D;
  static const sky      = MedicColors.c477C91;
  static const amber    = MedicColors.cB77A27;
  static const rose     = MedicColors.cC05256;
  static const violet   = MedicColors.c78659B;
  static const surface  = MedicColors.cF6F5F0;
  static const card     = MedicColors.cFFFFFF;
  static const border   = MedicColors.cE2E5DC;
  static const textPri  = MedicColors.c142F2B;
  static const textSec  = MedicColors.c63756D;
  static const textTer  = MedicColors.c83938B;
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({Key? key}) : super(key: key);

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with SingleTickerProviderStateMixin {
  final AuthService _authSvc = AuthService();
  final NotificationService _notifSvc = NotificationService();

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        duration: const Duration(milliseconds: 600), vsync: this);
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────
  String _timeAgo(dynamic ts) {
    if (ts == null || ts is! Timestamp) return '';
    final diff = DateTime.now().difference(ts.toDate());
    if (diff.inMinutes < 1)  return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24)   return '${diff.inHours}h ago';
    if (diff.inDays < 7)     return '${diff.inDays}d ago';
    final d = ts.toDate();
    return '${d.day}/${d.month}/${d.year}';
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'reminder':         return _C.teal;
      case 'reminder_advance': return _C.violet;
      case 'expiry_warning':   return _C.amber;
      case 'expiry_urgent':    return const Color(0xFFFF8C42);
      case 'expiry_expired':   return _C.rose;
      case 'test':             return _C.violet;
      case 'dependant_request':  return _C.violet;
      case 'dependant_accepted': return _C.teal;
      case 'dependant_rejected': return _C.textSec;
      case 'health_monitoring':
      case 'health_warning':     return _C.rose;
      default:                 return _C.sky;
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'reminder':         return Icons.medication_rounded;
      case 'reminder_advance': return Icons.access_time_rounded;
      case 'expiry_warning':   return Icons.warning_amber_rounded;
      case 'expiry_urgent':    return Icons.error_outline_rounded;
      case 'expiry_expired':   return Icons.dangerous_rounded;
      case 'test':             return Icons.bug_report_rounded;
      case 'dependant_request':  return Icons.person_add_alt_1_rounded;
      case 'dependant_accepted': return Icons.how_to_reg_rounded;
      case 'dependant_rejected': return Icons.person_off_rounded;
      case 'health_monitoring':
      case 'health_warning':     return Icons.monitor_heart_rounded;
      default:                 return Icons.notifications_rounded;
    }
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'reminder':         return 'Reminder';
      case 'reminder_advance': return 'Upcoming';
      case 'expiry_warning':   return 'Expiring';
      case 'expiry_urgent':    return 'Urgent';
      case 'expiry_expired':   return 'Expired';
      case 'test':             return 'Test';
      case 'dependant_request':  return 'Tracking Request';
      case 'dependant_accepted': return 'Request Accepted';
      case 'dependant_rejected': return 'Request Declined';
      case 'health_monitoring':
      case 'health_warning':     return 'Health Alert';
      default:                 return 'Alert';
    }
  }

  // ── Actions ──────────────────────────────────────────────────────────────────
  Future<void> _markAllRead(String uid) async {
    HapticFeedback.mediumImpact();
    await _notifSvc.markAllAsRead(uid);
    if (mounted) _showSnack('All notifications marked as read', isError: false);
  }

  Future<void> _clearAll(String uid) async {
    final ok = await showDialog<bool>(
      context: context, barrierColor: Colors.black54,
      builder: (_) => _ConfirmDialog(
        icon: Icons.delete_sweep_rounded, accent: _C.rose,
        title: 'Clear All Notifications?',
        body: 'This permanently deletes all notifications and cannot be undone.',
        confirmLabel: 'Clear All',
      ),
    );
    if (ok == true) {
      HapticFeedback.mediumImpact();
      await _notifSvc.deleteAllNotifications(uid);
    }
  }

  void _showSnack(String msg, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(isError ? Icons.error_outline_rounded : Icons.check_circle_rounded,
            color: Colors.white, size: 16),
        const SizedBox(width: 10),
        Expanded(child: Text(msg, style: const TextStyle(
            fontWeight: FontWeight.w600, fontSize: 13))),
      ]),
      backgroundColor: _C.navy,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.all(16),
    ));
  }

  void _handleTap(String id, Map<String, dynamic> data) {
    if (!(data['read'] ?? false)) _notifSvc.markAsRead(id);
    final alert = data['data'] is Map ? Map<String, dynamic>.from(data['data']) : <String, dynamic>{};
    if (data['type'] == 'health_monitoring' && alert['ownerId'] is String) {
      final owner = alert['ownerId'] as String;
      Navigator.push(context, MaterialPageRoute(builder: (_) => owner == _authSvc.currentUser?.uid
        ? const HealthMonitoringScreen() : DependantDashboardScreen(dependantId: owner, dependantName: 'Dependant')));
      return;
    }
    if (data['type'] == 'missed_dose' && data['dependantId'] is String) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => DependantDashboardScreen(
        dependantId: data['dependantId'] as String, dependantName: 'Dependant')));
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final user = _authSvc.currentUser;

    if (user == null) {
      return Scaffold(backgroundColor: _C.surface, body: _GuestState());
    }

    final uid = user.uid;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _C.surface,
        body: FadeTransition(
          opacity: _fadeAnim,
          child: Column(children: [
            _buildHeader(uid),
            Expanded(child: _buildList(uid)),
          ]),
        ),
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────────
  Widget _buildHeader(String uid) => MedicHeaderSurface(
    child: Stack(children: [
      Positioned.fill(child: CustomPaint(painter: _MeshPainter())),
      SafeArea(bottom: false, child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Row(children: [
          // Back
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.15)),
              ),
              child: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white, size: 17),
            ),
          ),
          const SizedBox(width: 14),

          // Title + unread count
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Notifications', style: TextStyle(fontFamily: 'serif',
                color: Colors.white, fontSize: 20,
                fontWeight: FontWeight.w700, letterSpacing: -0.4)),
            const SizedBox(height: 4),
            StreamBuilder<int>(
              stream: _notifSvc.getUnreadCount(uid),
              builder: (_, snap) {
                final n = snap.data ?? 0;
                return Row(children: [
                  Container(
                    width: 7, height: 7,
                    decoration: BoxDecoration(
                        color: n > 0 ? _C.amber : _C.teal,
                        shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    n > 0 ? '$n unread' : 'All caught up!',
                    style: TextStyle(
                        color: Colors.white.withOpacity(n > 0 ? 0.85 : 0.5),
                        fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ]);
              },
            ),
          ])),

          // Actions menu
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'mark_read') _markAllRead(uid);
              if (v == 'clear_all') _clearAll(uid);
            },
            offset: const Offset(0, 52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            color: _C.card,
            elevation: 8,
            shadowColor: Colors.black.withOpacity(0.12),
            icon: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.15)),
              ),
              child: const Icon(Icons.more_vert_rounded,
                  color: Colors.white, size: 19),
            ),
            itemBuilder: (_) => [
              PopupMenuItem<String>(
                value: 'mark_read',
                child: Row(children: [
                  Container(width: 32, height: 32,
                      decoration: BoxDecoration(
                          color: MedicColors.mint.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(9)),
                      child: const Icon(Icons.done_all_rounded,
                          color: MedicColors.mint, size: 16)),
                  const SizedBox(width: 12),
                  const Text('Mark all as read', style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600,
                      color: _C.textPri)),
                ]),
              ),
              PopupMenuItem<String>(
                value: 'clear_all',
                child: Row(children: [
                  Container(width: 32, height: 32,
                      decoration: BoxDecoration(
                          color: _C.rose.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(9)),
                      child: const Icon(Icons.delete_sweep_rounded,
                          color: _C.rose, size: 16)),
                  const SizedBox(width: 12),
                  const Text('Clear all', style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600,
                      color: _C.rose)),
                ]),
              ),
            ],
          ),
        ]),
      )),
    ]),
  );

  // ── Notifications list ───────────────────────────────────────────────────────
  Widget _buildList(String uid) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: _notifSvc.getUserNotifications(uid),
    builder: (_, snap) {
      if (snap.connectionState == ConnectionState.waiting) {
        return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(width: 34, height: 34,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: _C.teal,
                  backgroundColor: _C.teal.withOpacity(0.15))),
          const SizedBox(height: 12),
          const Text('Loading notifications…', style: TextStyle(
              color: _C.textSec, fontSize: 13, fontWeight: FontWeight.w500)),
        ]));
      }

      if (snap.hasError) {
        return _ErrorState(onRetry: () => setState(() {}));
      }

      // Sorted here (newest first) instead of in the Firestore query —
      // see the comment on NotificationService.getUserNotifications.
      final docs = List<QueryDocumentSnapshot<Map<String, dynamic>>>.of(snap.data?.docs ?? []);
      docs.sort((a, b) {
        final at = a.data()['createdAt'], bt = b.data()['createdAt'];
        final ams = at is Timestamp ? at.millisecondsSinceEpoch : 0;
        final bms = bt is Timestamp ? bt.millisecondsSinceEpoch : 0;
        return bms.compareTo(ams);
      });
      if (docs.isEmpty) return _EmptyState();

      return RefreshIndicator(
        onRefresh: () async {
          HapticFeedback.lightImpact();
          await Future.delayed(const Duration(milliseconds: 300));
        },
        color: _C.teal, backgroundColor: _C.card,
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final doc  = docs[i];
            final data = doc.data();
            return _AnimatedItem(
              index: i,
              child: _NotifCard(
                id:       doc.id,
                data:     data,
                color:    _typeColor(data['type'] ?? ''),
                icon:     _typeIcon(data['type'] ?? ''),
                label:    _typeLabel(data['type'] ?? ''),
                timeAgo:  _timeAgo(data['createdAt']),
                onTap:    () => _handleTap(doc.id, data),
                onDelete: () {
                  HapticFeedback.mediumImpact();
                  _notifSvc.deleteNotification(doc.id);
                },
              ),
            );
          },
        ),
      );
    },
  );
}

// ─── Notification Card ────────────────────────────────────────────────────────
class _NotifCard extends StatelessWidget {
  final String id, timeAgo, label;
  final Map<String, dynamic> data;
  final Color color;
  final IconData icon;
  final VoidCallback onTap, onDelete;

  const _NotifCard({
    required this.id, required this.data, required this.color,
    required this.icon, required this.label, required this.timeAgo,
    required this.onTap, required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final title  = data['title']  ?? 'Notification';
    final body   = data['body']   ?? '';
    final read   = data['read']   ?? false;

    return Dismissible(
      key: ValueKey(id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDelete(),
      background: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
            color: _C.rose.withOpacity(0.12),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _C.rose.withOpacity(0.25))),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 22),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.delete_outline_rounded, color: _C.rose, size: 22),
          const SizedBox(height: 4),
          const Text('Delete', style: TextStyle(
              color: _C.rose, fontSize: 10, fontWeight: FontWeight.w700)),
        ]),
      ),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: read ? _C.card : color.withOpacity(0.03),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: read ? _C.border : color.withOpacity(0.25),
              width: read ? 1 : 1.5,
            ),
            boxShadow: [BoxShadow(
              color: read
                  ? Colors.black.withOpacity(0.03)
                  : color.withOpacity(0.08),
              blurRadius: 12, offset: const Offset(0, 4),
            )],
          ),
          child: Row(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Icon container
            Container(
              width: 46, height: 46,
              decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(13)),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),

            // Content
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [

              // Title row
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Text(title, style: TextStyle(
                    fontSize: 14,
                    fontWeight: read ? FontWeight.w600 : FontWeight.w700,
                    color: _C.textPri, letterSpacing: -0.2),
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 8),
                // Unread dot
                if (!read)
                  Container(
                    width: 8, height: 8,
                    margin: const EdgeInsets.only(top: 3),
                    decoration: BoxDecoration(
                        color: color, shape: BoxShape.circle,
                        boxShadow: [BoxShadow(
                            color: color.withOpacity(0.4),
                            blurRadius: 4, spreadRadius: 1)]),
                  ),
              ]),
              const SizedBox(height: 5),

              Text(body, style: const TextStyle(
                  fontSize: 12, color: _C.textSec,
                  fontWeight: FontWeight.w400, height: 1.45),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 8),

              // Footer: type chip + time
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                      color: color.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(label, style: TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w700, color: color)),
                ),
                const SizedBox(width: 8),
                Text(timeAgo, style: const TextStyle(
                    fontSize: 11, color: _C.textTer, fontWeight: FontWeight.w400)),
                const Spacer(),
                Icon(Icons.chevron_right_rounded, color: _C.textTer, size: 16),
              ]),
            ])),
          ]),
        ),
      ),
    );
  }
}

// ─── Animated list item ───────────────────────────────────────────────────────
class _AnimatedItem extends StatelessWidget {
  final int index;
  final Widget child;
  const _AnimatedItem({required this.index, required this.child});

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0.0, end: 1.0),
    duration: Duration(milliseconds: 200 + (index * 40).clamp(0, 400)),
    curve: Curves.easeOutQuart,
    builder: (_, v, c) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, 14 * (1 - v)), child: c)),
    child: child,
  );
}

// ─── Empty State ──────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(child: Column(
      mainAxisSize: MainAxisSize.min, children: [
    Container(
      width: 80, height: 80,
      decoration: BoxDecoration(
          color: _C.teal.withOpacity(0.08),
          borderRadius: BorderRadius.circular(24)),
      child: const Icon(Icons.notifications_off_outlined,
          color: _C.teal, size: 36),
    ),
    const SizedBox(height: 20),
    const Text('No Notifications', style: TextStyle(
        fontSize: 20, fontWeight: FontWeight.w700,
        color: _C.textPri, letterSpacing: -0.4)),
    const SizedBox(height: 8),
    const Text("You're all caught up!\nNew alerts will appear here.",
        textAlign: TextAlign.center,
        style: TextStyle(
            color: _C.textSec, fontSize: 13, height: 1.6)),
  ]));
}

// ─── Error State ──────────────────────────────────────────────────────────────
class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(child: Column(
      mainAxisSize: MainAxisSize.min, children: [
    Container(
      width: 80, height: 80,
      decoration: BoxDecoration(
          color: _C.rose.withOpacity(0.08),
          borderRadius: BorderRadius.circular(24)),
      child: const Icon(Icons.cloud_off_outlined, color: _C.rose, size: 36),
    ),
    const SizedBox(height: 20),
    const Text('Notifications could not load', style: TextStyle(
        fontSize: 18, fontWeight: FontWeight.w700,
        color: _C.textPri, letterSpacing: -0.4)),
    const SizedBox(height: 8),
    const Padding(padding: EdgeInsets.symmetric(horizontal: 32), child: Text(
        'Check your connection and try again.',
        textAlign: TextAlign.center,
        style: TextStyle(color: _C.textSec, fontSize: 13, height: 1.6))),
    const SizedBox(height: 16),
    OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
  ]));
}

// ─── Guest State ──────────────────────────────────────────────────────────────
class _GuestState extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(child: Column(
      mainAxisSize: MainAxisSize.min, children: [
    Container(width: 64, height: 64,
        decoration: BoxDecoration(
            color: _C.teal.withOpacity(0.1), shape: BoxShape.circle),
        child: const Icon(Icons.lock_outline_rounded, color: _C.teal, size: 30)),
    const SizedBox(height: 18),
    const Text('Not Logged In', style: TextStyle(
        fontSize: 18, fontWeight: FontWeight.w700, color: _C.textPri)),
    const SizedBox(height: 6),
    const Text('Please log in to view notifications',
        style: TextStyle(color: _C.textSec, fontSize: 13)),
  ]));
}

// ─── Confirm Dialog ───────────────────────────────────────────────────────────
class _ConfirmDialog extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String title, body, confirmLabel;
  const _ConfirmDialog({required this.icon, required this.accent,
    required this.title, required this.body, required this.confirmLabel});

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: _C.card,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    child: Padding(padding: const EdgeInsets.all(24), child: Column(
        mainAxisSize: MainAxisSize.min, children: [
      Container(width: 52, height: 52,
          decoration: BoxDecoration(
              color: accent.withOpacity(0.1), shape: BoxShape.circle),
          child: Icon(icon, color: accent, size: 24)),
      const SizedBox(height: 16),
      Text(title, textAlign: TextAlign.center, style: const TextStyle(
          fontSize: 17, fontWeight: FontWeight.w700,
          color: _C.textPri, letterSpacing: -0.3)),
      const SizedBox(height: 8),
      Text(body, textAlign: TextAlign.center, style: const TextStyle(
          fontSize: 13, color: _C.textSec, height: 1.5)),
      const SizedBox(height: 22),
      Row(children: [
        Expanded(child: GestureDetector(
          onTap: () => Navigator.pop(context, false),
          child: Container(height: 44,
              decoration: BoxDecoration(color: _C.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _C.border)),
              child: const Center(child: Text('Cancel', style: TextStyle(
                  fontWeight: FontWeight.w700, color: _C.textSec, fontSize: 13)))),
        )),
        const SizedBox(width: 12),
        Expanded(child: GestureDetector(
          onTap: () => Navigator.pop(context, true),
          child: Container(height: 44,
              decoration: BoxDecoration(
                  color: accent, borderRadius: BorderRadius.circular(12)),
              child: Center(child: Text(confirmLabel, style: const TextStyle(
                  fontWeight: FontWeight.w700, color: Colors.white, fontSize: 13)))),
        )),
      ]),
    ])),
  );
}

// ─── Mesh Painter ─────────────────────────────────────────────────────────────
class _MeshPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(Offset(size.width * 0.9, size.height * 0.15), 90,
        Paint()..color = _C.teal.withOpacity(0.07));
    canvas.drawCircle(Offset(size.width * 0.05, size.height * 0.82), 65,
        Paint()..color = _C.violet.withOpacity(0.06));
  }
  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}