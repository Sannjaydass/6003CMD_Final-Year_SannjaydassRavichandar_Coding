import '../../services/medicine_photo_service.dart';
import 'medicine_photo_widgets.dart';
import 'medicine_stock_card.dart';
import 'package:medictrack/design/medic_design.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/auth_service.dart';
import 'medicine_details_screen.dart';
import 'scan_medicine_screen.dart';

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
  static const safe    = MedicColors.c28715D;
  static const warn    = MedicColors.cB77A27;
  static const danger  = MedicColors.cC05256;
}

class MedicineInventoryScreen extends StatefulWidget {
  const MedicineInventoryScreen({Key? key}) : super(key: key);
  @override
  State<MedicineInventoryScreen> createState() =>
      _MedicineInventoryScreenState();
}

class _MedicineInventoryScreenState extends State<MedicineInventoryScreen>
    with SingleTickerProviderStateMixin {
  final AuthService _authSvc = AuthService();
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String _filter = 'All';
  String _sort   = 'Latest';

  // ── Reactive search: uses ValueNotifier so the search widget rebuilds
  //    independently from the rest of the screen (no full setState).
  final ValueNotifier<String> _searchNotifier = ValueNotifier('');
  final TextEditingController _searchCtrl     = TextEditingController();
  final FocusNode _searchFocus                = FocusNode();

  // Holds the full loaded list from Firestore — updated only when stream fires.
  // The search/filter view is derived from this in real-time.
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _allDocs = [];

  late AnimationController _listCtrl;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;

  @override
  void initState() {
    super.initState();
    _listCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _listCtrl.forward();
    _searchCtrl.addListener(() {
      // Directly update notifier on every keystroke — no debounce, no setState
      _searchNotifier.value = _searchCtrl.text.trim().toLowerCase();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _listCtrl.dispose();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _searchNotifier.dispose();
    super.dispose();
  }

  // ── Firestore query (no orderBy = no index needed) ────────────────────────
  Query<Map<String, dynamic>> _query(String uid) =>
      _db.collection('medicines').where('userId', isEqualTo: uid);

  // ── Sort (pure client-side) ───────────────────────────────────────────────
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _sorted(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> src) {
    final list = List.of(src);
    switch (_sort) {
      case 'Oldest':
        list.sort((a, b) {
          final ta = a.data()['scannedAt'] as Timestamp?;
          final tb = b.data()['scannedAt'] as Timestamp?;
          if (ta == null && tb == null) return 0;
          if (ta == null) return 1;
          if (tb == null) return -1;
          return ta.compareTo(tb);
        });
        break;
      case 'PotencyHigh':
        list.sort((a, b) {
          final pa = (a.data()['potency'] ?? 0) as num;
          final pb = (b.data()['potency'] ?? 0) as num;
          return pb.compareTo(pa);
        });
        break;
      case 'PotencyLow':
        list.sort((a, b) {
          final pa = (a.data()['potency'] ?? 0) as num;
          final pb = (b.data()['potency'] ?? 0) as num;
          return pa.compareTo(pb);
        });
        break;
      default: // Latest
        list.sort((a, b) {
          final ta = a.data()['scannedAt'] as Timestamp?;
          final tb = b.data()['scannedAt'] as Timestamp?;
          if (ta == null && tb == null) return 0;
          if (ta == null) return 1;
          if (tb == null) return -1;
          return tb.compareTo(ta);
        });
    }
    return list;
  }

  // ── In-memory filter + search (instant, no Firestore round-trip) ──────────
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _applyFilterAndSearch(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      String query,
      String filter,
      ) {
    final q = query.trim().toLowerCase();
    return docs.where((d) {
      final m       = d.data();
      final status  = (m['status']  ?? '').toString().toLowerCase();
      final potency = (m['potency'] ?? 0) is num
          ? (m['potency'] as num).toInt() : 0;
      final days = m['daysUntilExpiry'];
      final dInt = (days is num) ? days.toInt() : null;

      final isExpired =
          (dInt != null && dInt < 0) || status.contains('expired');
      final isLow = !isExpired &&
          (status.contains('low') ||
              status.contains('expiring') ||
              (potency < 80 && potency >= 50));

      // Status filter
      final passFilter = switch (filter) {
        'Safe'    => !isExpired && !isLow,
        'Low'     => isLow,
        'Expired' => isExpired,
        _         => true,
      };
      if (!passFilter) return false;

      // Search across 5 fields instantly
      if (q.isEmpty) return true;
      return (m['medicineName']  ?? '').toString().toLowerCase().contains(q) ||
          (m['genericName']   ?? '').toString().toLowerCase().contains(q) ||
          (m['dosage']        ?? '').toString().toLowerCase().contains(q) ||
          (m['category']      ?? '').toString().toLowerCase().contains(q) ||
          (m['manufacturer']  ?? '').toString().toLowerCase().contains(q);
    }).toList();
  }

  // ── Stats ─────────────────────────────────────────────────────────────────
  Map<String, int> _stats(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    int safe = 0, low = 0, expired = 0;
    for (final d in docs) {
      final m       = d.data();
      final status  = (m['status']  ?? '').toString().toLowerCase();
      final potency = (m['potency'] ?? 0) is num
          ? (m['potency'] as num).toInt() : 0;
      final days = m['daysUntilExpiry'];
      final dInt = (days is num) ? days.toInt() : null;
      if ((dInt != null && dInt < 0) || status.contains('expired')) expired++;
      else if (status.contains('low') || status.contains('expiring') ||
          (potency < 80 && potency >= 50)) low++;
      else safe++;
    }
    return {'total': docs.length, 'safe': safe, 'low': low, 'expired': expired};
  }

  // ── Status helpers ────────────────────────────────────────────────────────
  static Color sColor(String status, int potency, int? days) {
    final s = status.toLowerCase();
    if (days != null && days < 0)  return _C.danger;
    if (s.contains('expired'))     return _C.danger;
    if (s.contains('low') || s.contains('expiring') ||
        (potency < 80 && potency >= 50)) return _C.warn;
    return _C.safe;
  }

  static IconData sIcon(String status, int potency, int? days) {
    final s = status.toLowerCase();
    if (days != null && days < 0)  return Icons.dangerous_rounded;
    if (s.contains('expired'))     return Icons.dangerous_rounded;
    if (s.contains('low') || s.contains('expiring') ||
        (potency < 80 && potency >= 50)) return Icons.warning_rounded;
    return Icons.check_circle_rounded;
  }

  // ── Clear search ──────────────────────────────────────────────────────────
  void _clearSearch() {
    _searchCtrl.clear();
    // notifier updates automatically via listener
    _searchFocus.unfocus();
  }

  // ── Delete ────────────────────────────────────────────────────────────────
  Future<void> _deleteMedicine(String docId, String name) async {
    final ok = await showDialog<bool>(
      context: context, barrierColor: Colors.black54,
      builder: (_) => _DeleteDialog(name: name),
    );
    if (ok != true) return;
    try {
      HapticFeedback.mediumImpact();
      final medicine = await _db.collection('medicines').doc(docId).get();
      await _db.collection('medicines').doc(docId).delete();
      await MedicinePhotoService.remove(MedicinePhotoService.paths(medicine.data() ?? {}));
      if (mounted) _snack('"$name" removed');
    } catch (e) {
      if (mounted) _snack('Delete failed: $e', error: true);
    }
  }

  void _snack(String msg, {bool error = false}) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          Icon(error ? Icons.error_outline_rounded : Icons.check_circle_rounded,
              color: Colors.white, size: 15),
          const SizedBox(width: 9),
          Expanded(child: Text(msg, style: const TextStyle(
              fontWeight: FontWeight.w600, fontSize: 13))),
        ]),
        backgroundColor: _C.navy,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(14),
      ));

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final user = _authSvc.currentUser;
    if (user == null) return const _GuestState();

    return Scaffold(
      backgroundColor: _C.surface,
      body: Column(children: [
        _buildHeader(),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _query(user.uid).snapshots(),
            builder: (_, snap) {
              if (snap.hasError) return _buildError(snap.error.toString());
              if (snap.connectionState == ConnectionState.waiting &&
                  _allDocs.isEmpty) {
                return const _LoadingState();
              }

              // Update the cached list when Firestore emits
              if (snap.hasData) {
                _allDocs = _sorted(snap.data!.docs);
              }

              final st = _stats(_allDocs);

              // ── ValueListenableBuilder: only rebuilds list area on search change ──
              return ValueListenableBuilder<String>(
                valueListenable: _searchNotifier,
                builder: (_, query, __) {
                  final filtered = _applyFilterAndSearch(
                      _allDocs, query, _filter);
                  return _buildBody(_allDocs, filtered, st, query);
                },
              );
            },
          ),
        ),
      ]),
      floatingActionButton: _buildFAB(),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader() => MedicPageTitle(
    title: 'Your medicine cabinet',
    subtitle: 'A clear view of everything in your care.',
    back: false,
    trailing: _SortMenu(current: _sort, onChanged: (v) => setState(() {
      _sort = v;
      _allDocs = _sorted(_allDocs);
    })),
  );

  // ── Body ──────────────────────────────────────────────────────────────────
  Widget _buildBody(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> all,
      List<QueryDocumentSnapshot<Map<String, dynamic>>> filtered,
      Map<String, int> st,
      String query,
      ) =>
      RefreshIndicator(
        onRefresh: () async {
          HapticFeedback.mediumImpact();
          await Future.delayed(const Duration(milliseconds: 300));
        },
        color: _C.teal, backgroundColor: _C.card,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics()),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
              sliver: SliverList(delegate: SliverChildListDelegate([

                // Stats
                _StatsRow(st: st),
                const SizedBox(height: 12),

                // Health bar
                _HealthBar(st: st),
                const SizedBox(height: 14),

                // ── Reactive search bar ─────────────────────────────────
                _ReactiveSearchBar(
                  ctrl:        _searchCtrl,
                  focusNode:   _searchFocus,
                  notifier:    _searchNotifier,
                  totalCount:  all.length,
                  allDocs:     all,
                  filter:      _filter,
                  applyFilter: _applyFilterAndSearch,
                  onClear:     _clearSearch,
                ),
                const SizedBox(height: 12),

                // Filter chips — setState here only re-runs _buildBody
                // not the search widget itself
                _FilterRow(
                  selected:  _filter,
                  onChanged: (f) {
                    HapticFeedback.selectionClick();
                    setState(() => _filter = f);
                  },
                ),
                const SizedBox(height: 18),

                // List header
                _ListHeader(
                  count:  filtered.length,
                  total:  all.length,
                  query:  query,
                  filter: _filter,
                ),
                const SizedBox(height: 12),

                // Empty inventory
                if (all.isEmpty)
                  _EmptyState(onScan: () => Navigator.push(context,
                      MaterialPageRoute(
                          builder: (_) => const ScanMedicineScreen()))),

                // No results
                if (all.isNotEmpty && filtered.isEmpty)
                  _NoResults(
                    query:   query,
                    filter:  _filter,
                    onClear: () {
                      _clearSearch();
                      setState(() => _filter = 'All');
                    },
                  ),

                // Cards
                ...filtered.asMap().entries.map((e) => _AnimatedCard(
                  ctrl:  _listCtrl,
                  index: e.key,
                  child: _MedicineCard(
                    doc:         e.value,
                    searchQuery: query,
                    onTap: () async {
                      HapticFeedback.lightImpact();
                      await Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => MedicineDetailsScreen(
                                  docId: e.value.id,
                                  data:  e.value.data())));
                      if (mounted) setState(() {});
                    },
                    onDelete: () => _deleteMedicine(
                        e.value.id,
                        (e.value.data()['medicineName'] ?? '').toString()),
                  ),
                )),

              ])),
            ),
          ],
        ),
      );

  Widget _buildError(String err) => Center(child: Padding(
    padding: const EdgeInsets.all(24),
    child: _Banner(
      icon:  err.contains('index')
          ? Icons.build_circle_rounded : Icons.error_outline_rounded,
      color: err.contains('index') ? _C.amber : _C.rose,
      title: err.contains('index') ? 'Index Required' : 'Error Loading Data',
      sub:   err.contains('index')
          ? 'Check your console for the Firestore index link.'
          : 'Pull to refresh and try again.',
    ),
  ));

  Widget _buildFAB() => GestureDetector(
    onTap: () {
      HapticFeedback.mediumImpact();
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => const ScanMedicineScreen()));
    },
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
      decoration: BoxDecoration(
          color: _C.teal, borderRadius: BorderRadius.circular(22),
          boxShadow: [BoxShadow(color: _C.teal.withOpacity(0.35),
              blurRadius: 16, offset: const Offset(0, 6))]),
      child: const Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 20),
        SizedBox(width: 8),
        Text('Scan', style: TextStyle(
            color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
      ]),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// ── REACTIVE SEARCH BAR ────────────────────────────────────────────────────────
// Uses ValueListenableBuilder internally so only THIS widget rebuilds on every
// keystroke — not the parent screen, not the medicine list.
// ═══════════════════════════════════════════════════════════════════════════════
class _ReactiveSearchBar extends StatelessWidget {
  final TextEditingController ctrl;
  final FocusNode focusNode;
  final ValueNotifier<String> notifier;
  final int totalCount;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> allDocs;
  final String filter;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> Function(
      List<QueryDocumentSnapshot<Map<String, dynamic>>>, String, String) applyFilter;
  final VoidCallback onClear;

  const _ReactiveSearchBar({
    required this.ctrl,
    required this.focusNode,
    required this.notifier,
    required this.totalCount,
    required this.allDocs,
    required this.filter,
    required this.applyFilter,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: notifier,
      builder: (_, query, __) {
        final isActive = query.isNotEmpty;
        // Compute result count live from memory — zero cost
        final resultCount = isActive
            ? applyFilter(allDocs, query, filter).length
            : totalCount;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: _C.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: isActive ? _C.teal.withOpacity(0.5) : _C.border,
                width: isActive ? 1.5 : 1.0),
            boxShadow: [BoxShadow(
                color: isActive
                    ? _C.teal.withOpacity(0.08)
                    : MedicColors.forest.withOpacity(0.025),
                blurRadius: 10, offset: const Offset(0, 3))],
          ),
          child: Column(children: [

            // ── Input row ──────────────────────────────────────────────────
            Row(children: [
              Padding(
                padding: const EdgeInsets.only(left: 14),
                child: Icon(
                  Icons.search_rounded,
                  color: isActive ? _C.teal : _C.textTer,
                  size: 20,
                ),
              ),
              Expanded(
                child: TextField(
                  controller: ctrl,
                  focusNode: focusNode,
                  // onChanged fires on every keystroke — updates notifier instantly
                  onChanged: (_) {}, // notifier updated by ctrl listener in parent
                  textInputAction: TextInputAction.search,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w500,
                      color: _C.textPri),
                  decoration: const InputDecoration(
                    hintText: 'Search name, category, dosage...',
                    hintStyle: TextStyle(color: _C.textTer, fontSize: 13),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                        horizontal: 10, vertical: 13),
                    isDense: true,
                  ),
                ),
              ),

              // Clear ×
              if (isActive)
                GestureDetector(
                  onTap: onClear,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Container(
                      width: 24, height: 24,
                      decoration: BoxDecoration(
                          color: _C.teal.withOpacity(0.1),
                          shape: BoxShape.circle),
                      child: const Icon(Icons.close_rounded,
                          color: _C.teal, size: 13),
                    ),
                  ),
                )
              else
                const SizedBox(width: 12),
            ]),

            // ── Live result strip ──────────────────────────────────────────
            if (isActive) ...[
              Container(height: 1, color: _C.teal.withOpacity(0.12)),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 9),
                child: Row(children: [
                  // Animated result pill
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 150),
                    transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim, child: child),
                    child: Container(
                      key: ValueKey('$resultCount-$query'),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(
                          color: resultCount == 0
                              ? _C.rose.withOpacity(0.1)
                              : _C.teal.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10)),
                      child: Text(
                        resultCount == 0
                            ? 'No results'
                            : '$resultCount result${resultCount == 1 ? '' : 's'}',
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w700,
                            color: resultCount == 0 ? _C.rose : _C.teal),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                    'for "$query"',
                    style: const TextStyle(fontSize: 11, color: _C.textTer),
                    overflow: TextOverflow.ellipsis,
                  )),
                  GestureDetector(
                    onTap: onClear,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(
                          color: _C.surface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _C.border)),
                      child: const Text('Clear', style: TextStyle(
                          fontSize: 11, color: _C.textSec,
                          fontWeight: FontWeight.w700)),
                    ),
                  ),
                ]),
              ),
            ],
          ]),
        );
      },
    );
  }
}

// ─── Sort Menu ────────────────────────────────────────────────────────────────
class _SortMenu extends StatelessWidget {
  final String current;
  final ValueChanged<String> onChanged;
  const _SortMenu({required this.current, required this.onChanged});

  static const _opts = [
    ('Latest',      'Latest',    Icons.schedule_rounded),
    ('Oldest',      'Oldest',    Icons.history_rounded),
    ('PotencyHigh', 'Potency ↑', Icons.trending_up_rounded),
    ('PotencyLow',  'Potency ↓', Icons.trending_down_rounded),
  ];

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    onSelected: onChanged,
    offset: const Offset(0, 50),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    color: _C.card,
    elevation: 8,
    shadowColor: Colors.black.withOpacity(0.1),
    icon: Container(
      width: 38, height: 38,
      decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: Colors.white.withOpacity(0.15))),
      child: const Icon(Icons.sort_rounded, color: Colors.white, size: 18),
    ),
    itemBuilder: (_) => _opts.map((t) {
      final (val, label, icon) = t;
      final on = current == val;
      return PopupMenuItem<String>(
        value: val,
        child: Row(children: [
          Container(width: 30, height: 30,
              decoration: BoxDecoration(
                  color: on ? _C.teal.withOpacity(0.12) : _C.surface,
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, size: 15,
                  color: on ? _C.teal : _C.textSec)),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: TextStyle(
              fontSize: 13,
              fontWeight: on ? FontWeight.w700 : FontWeight.w500,
              color: on ? _C.teal : _C.textPri))),
          if (on)
            const Icon(Icons.check_rounded, size: 14, color: _C.teal),
        ]),
      );
    }).toList(),
  );
}

// ─── Stats Row ────────────────────────────────────────────────────────────────
class _StatsRow extends StatelessWidget {
  final Map<String, int> st;
  const _StatsRow({required this.st});
  @override
  Widget build(BuildContext context) => Column(children: [
    Row(children: [
      _Stat('${st['total'] ?? 0}', 'All medicines', Icons.medication_outlined, _C.sky),
      const SizedBox(width: 12),
      _Stat('${st['safe'] ?? 0}', 'Marked safe', Icons.check_circle_outline_rounded, _C.teal),
    ]),
    const SizedBox(height: 12),
    Row(children: [
      _Stat('${st['low'] ?? 0}', 'Needs attention', Icons.error_outline_rounded, _C.amber),
      const SizedBox(width: 12),
      _Stat('${st['expired'] ?? 0}', 'Expired', Icons.event_busy_outlined, _C.rose),
    ]),
  ]);
}

class _Stat extends StatelessWidget {
  final String value, label;
  final IconData icon;
  final Color color;
  const _Stat(this.value, this.label, this.icon, this.color);
  @override
  Widget build(BuildContext context) => Expanded(child: Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(color: _C.card, borderRadius: BorderRadius.circular(24)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Icon(icon, color: color, size: 22), const Spacer(),
        Text(value, style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w500, color: _C.textPri))]),
      const SizedBox(height: 12),
      Text(label, style: const TextStyle(fontSize: 12, color: _C.textSec)),
    ]),
  ));
}

// ─── Health Bar ───────────────────────────────────────────────────────────────
class _HealthBar extends StatelessWidget {
  final Map<String, int> st;
  const _HealthBar({required this.st});

  @override
  Widget build(BuildContext context) {
    final total = st['total']   ?? 0;
    final safe  = st['safe']    ?? 0;
    final low   = st['low']     ?? 0;
    final exp   = st['expired'] ?? 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: _C.card, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _C.border),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03),
              blurRadius: 8, offset: const Offset(0, 2))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 28, height: 28,
              decoration: BoxDecoration(
                  color: _C.teal.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.insights_rounded, color: _C.teal, size: 14)),
          const SizedBox(width: 9),
          const Text('Inventory Health', style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w700, color: _C.textPri)),
          const Spacer(),
          if (total > 0)
            Text('$total items', style: const TextStyle(
                fontSize: 11, color: _C.textTer, fontWeight: FontWeight.w500)),
        ]),
        if (total == 0) ...[
          const SizedBox(height: 10),
          const Text('No medicines yet',
              style: TextStyle(color: _C.textTer, fontSize: 12)),
        ] else ...[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: SizedBox(height: 7, child: Row(children: [
              if (safe > 0) Expanded(flex: safe, child: Container(color: _C.teal)),
              if (low  > 0) Expanded(flex: low,  child: Container(color: _C.amber)),
              if (exp  > 0) Expanded(flex: exp,  child: Container(color: _C.rose)),
            ])),
          ),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            _Leg(_C.teal,  'Safe',    safe, total),
            _Leg(_C.amber, 'Caution', low,  total),
            _Leg(_C.rose,  'Expired', exp,  total),
          ]),
        ],
      ]),
    );
  }
}

class _Leg extends StatelessWidget {
  final Color color;
  final String label;
  final int count, total;
  const _Leg(this.color, this.label, this.count, this.total);

  @override
  Widget build(BuildContext context) {
    final pct = total > 0 ? ((count / total) * 100).round() : 0;
    return Row(children: [
      Container(width: 7, height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 5),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(
            fontSize: 9, color: _C.textTer, fontWeight: FontWeight.w600)),
        Text('$count ($pct%)', style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w700, color: color)),
      ]),
    ]);
  }
}

// ─── Filter Row ───────────────────────────────────────────────────────────────
class _FilterRow extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;
  const _FilterRow({required this.selected, required this.onChanged});

  static const _chips = [
    ('All',     Icons.all_inclusive_rounded, _C.sky),
    ('Safe',    Icons.verified_rounded,      _C.teal),
    ('Low',     Icons.warning_rounded,       _C.amber),
    ('Expired', Icons.dangerous_rounded,     _C.rose),
  ];

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(children: _chips.map((t) {
      final (label, icon, color) = t;
      final on = selected == label;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onTap: () => onChanged(label),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
                color: on ? color : _C.card,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: on ? color : _C.border),
                boxShadow: on ? [BoxShadow(color: color.withOpacity(0.2),
                    blurRadius: 8, offset: const Offset(0, 3))] : []),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 13, color: on ? Colors.white : _C.textSec),
              const SizedBox(width: 5),
              Text(label, style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700,
                  color: on ? Colors.white : _C.textSec)),
            ]),
          ),
        ),
      );
    }).toList()),
  );
}

// ─── List Header ─────────────────────────────────────────────────────────────
class _ListHeader extends StatelessWidget {
  final int count, total;
  final String query, filter;
  const _ListHeader({required this.count, required this.total,
    required this.query, required this.filter});

  @override
  Widget build(BuildContext context) {
    final searching = query.isNotEmpty;
    final filtering = filter != 'All';
    return Row(children: [
      Container(width: 28, height: 28,
          decoration: BoxDecoration(
              color: _C.teal.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8)),
          child: const Icon(Icons.medication_rounded, color: _C.teal, size: 14)),
      const SizedBox(width: 8),
      Text(
        searching || filtering ? 'Results' : 'Your Medicines',
        style: const TextStyle(
            fontSize: 14, fontWeight: FontWeight.w700,
            color: _C.textPri, letterSpacing: -0.2),
      ),
      const Spacer(),
      // Animated count badge
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: Container(
          key: ValueKey(count),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
              color: _C.teal.withOpacity(0.1),
              borderRadius: BorderRadius.circular(14)),
          child: Text(
            (searching || filtering) ? '$count / $total' : '$count items',
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: _C.teal),
          ),
        ),
      ),
    ]);
  }
}

// ─── Medicine Card ────────────────────────────────────────────────────────────
class _MedicineCard extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final String searchQuery;
  final VoidCallback onTap, onDelete;
  const _MedicineCard({required this.doc, required this.searchQuery,
    required this.onTap, required this.onDelete});

  Widget _hl(String text, String q) {
    if (q.isEmpty) return Text(text, style: const TextStyle(
        fontSize: 15, fontWeight: FontWeight.w700, color: _C.textPri,
        letterSpacing: -0.2), maxLines: 1, overflow: TextOverflow.ellipsis);
    final lo  = text.toLowerCase();
    final idx = lo.indexOf(q.toLowerCase());
    if (idx < 0) return Text(text, style: const TextStyle(
        fontSize: 15, fontWeight: FontWeight.w700, color: _C.textPri,
        letterSpacing: -0.2), maxLines: 1, overflow: TextOverflow.ellipsis);
    return RichText(
      maxLines: 1, overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
            color: _C.textPri, letterSpacing: -0.2),
        children: [
          if (idx > 0) TextSpan(text: text.substring(0, idx)),
          TextSpan(text: text.substring(idx, idx + q.length),
              style: const TextStyle(color: _C.teal,
                  backgroundColor: Color(0xFFE0FBF5))),
          if (idx + q.length < text.length)
            TextSpan(text: text.substring(idx + q.length)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m       = doc.data();
    final name    = (m['medicineName'] ?? 'Unknown').toString();
    final generic = (m['genericName']  ?? '').toString();
    final dosage  = (m['dosage']       ?? '').toString();
    final expiry  = (m['expiryDate']   ?? '').toString();
    final potency = (m['potency'] ?? 0) is num
        ? (m['potency'] as num).toInt() : 0;
    final status  = (m['status'] ?? 'Unknown').toString();
    final days    = m['daysUntilExpiry'];
    final dInt    = (days is num) ? days.toInt() : null;

    final c = _MedicineInventoryScreenState.sColor(status, potency, dInt);
    final i = _MedicineInventoryScreenState.sIcon(status, potency, dInt);

    return Dismissible(
      key: ValueKey(doc.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async { onDelete(); return false; },
      background: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
            color: _C.rose.withOpacity(0.09),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _C.rose.withOpacity(0.25))),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.delete_outline_rounded, color: _C.rose, size: 20),
          SizedBox(height: 3),
          Text('Delete', style: TextStyle(
              color: _C.rose, fontSize: 10, fontWeight: FontWeight.w700)),
        ]),
      ),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
              color: _C.card, borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _C.border),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.035),
                  blurRadius: 8, offset: const Offset(0, 2))]),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(children: [
              Row(children: [
                MedicinePhoto(key: ValueKey('${doc.id}:${MedicinePhotoService.paths(m).join()}'),
                  path: MedicinePhotoService.paths(m).isEmpty ? null : MedicinePhotoService.paths(m).first, size: 62),
                const SizedBox(width: 12),
                Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _hl(name, searchQuery),
                  const SizedBox(height: 3),
                  if (generic.isNotEmpty || dosage.isNotEmpty)
                    Text([if (generic.isNotEmpty) generic,
                      if (dosage.isNotEmpty) dosage].join(' · '),
                        style: const TextStyle(fontSize: 11, color: _C.textSec,
                            fontWeight: FontWeight.w500),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                ])),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                  decoration: BoxDecoration(
                      color: c.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: c.withOpacity(0.2))),
                  child: Column(children: [
                    Icon(i, color: c, size: 13),
                    const SizedBox(height: 2),
                    Text('$potency%', style: TextStyle(
                        color: c, fontWeight: FontWeight.w700, fontSize: 11)),
                  ]),
                ),
              ]),

              const SizedBox(height: 12),
              Wrap(spacing: 7, runSpacing: 6, children: [
                Text((m['frequencyLabel'] ?? 'Schedule not set').toString(), style: const TextStyle(fontSize: 11, color: _C.textSec)),
                for (final time in (m['scheduleTimes'] is List ? m['scheduleTimes'] as List : const []).take(4))
                  Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(color: _C.surface, borderRadius: BorderRadius.circular(6)),
                    child: Text('$time', style: const TextStyle(fontSize: 10, color: _C.textSec))),
              ]),
              if (MedicineStockCard.number(m['remainingPills']) != null && (MedicineStockCard.number(m['totalPills']) ?? 0) > 0) ...[
                const SizedBox(height: 12),
                Row(children: [Expanded(child: Text('${MedicineStockCard.display(MedicineStockCard.number(m['remainingPills'])!)} pills left',
                  style: const TextStyle(fontSize: 11, color: _C.teal, fontWeight: FontWeight.w700))),
                  Text('${MedicineStockCard.display(MedicineStockCard.number(m['totalPills'])!)} total', style: const TextStyle(fontSize: 10, color: _C.textTer))]),
                const SizedBox(height: 7),
                ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(minHeight: 5,
                  value: (MedicineStockCard.number(m['remainingPills'])! / MedicineStockCard.number(m['totalPills'])!).clamp(0.0, 1.0),
                  color: _C.teal, backgroundColor: _C.border)),
              ],
              const SizedBox(height: 10),
              Container(height: 1, color: _C.border),
              const SizedBox(height: 10),

              Row(children: [
                Icon(Icons.event_outlined, color: _C.textTer, size: 12),
                const SizedBox(width: 4),
                Text(expiry.isEmpty ? 'No expiry' : expiry,
                    style: const TextStyle(fontSize: 11, color: _C.textSec,
                        fontWeight: FontWeight.w500)),
                if (dInt != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                        color: c.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(7)),
                    child: Text(dInt < 0
                        ? '${dInt.abs()}d overdue' : '${dInt}d left',
                        style: TextStyle(fontSize: 9,
                            fontWeight: FontWeight.w700, color: c)),
                  ),
                ],
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: c.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(7)),
                  child: Text(status, style: TextStyle(
                      fontSize: 9, fontWeight: FontWeight.w700, color: c)),
                ),
                const SizedBox(width: 5),
                const Icon(Icons.chevron_right_rounded, color: _C.textTer, size: 16),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

// ─── Animated Card ────────────────────────────────────────────────────────────
class _AnimatedCard extends StatelessWidget {
  final AnimationController ctrl;
  final int index;
  final Widget child;
  const _AnimatedCard({required this.ctrl, required this.index, required this.child});

  @override
  Widget build(BuildContext context) {
    final start = (index * 0.05).clamp(0.0, 0.8);
    final end   = (start + 0.4).clamp(0.0, 1.0);
    final anim  = CurvedAnimation(
        parent: ctrl,
        curve: Interval(start, end, curve: Curves.easeOutQuart));
    return AnimatedBuilder(
      animation: anim,
      builder: (_, c) => Transform.translate(
        offset: Offset(0, 14 * (1 - anim.value)),
        child: Opacity(opacity: anim.value.clamp(0.0, 1.0), child: c),
      ),
      child: child,
    );
  }
}

// ─── No Results ───────────────────────────────────────────────────────────────
class _NoResults extends StatelessWidget {
  final String query, filter;
  final VoidCallback onClear;
  const _NoResults({required this.query, required this.filter,
    required this.onClear});

  @override
  Widget build(BuildContext context) {
    final hasQ = query.isNotEmpty;
    final hasF = filter != 'All';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: _C.card, borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _C.border)),
      child: Row(children: [
        Container(width: 36, height: 36,
            decoration: BoxDecoration(
                color: _C.sky.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.search_off_rounded, color: _C.sky, size: 17)),
        const SizedBox(width: 12),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('No Results', style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w700, color: _C.textPri)),
          const SizedBox(height: 2),
          Text(
            hasQ && hasF ? 'No "$query" in $filter category'
                : hasQ  ? 'No medicine matches "$query"'
                : 'No medicines in $filter category',
            style: const TextStyle(fontSize: 11, color: _C.textSec),
          ),
        ])),
        GestureDetector(
          onTap: onClear,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
                color: _C.teal.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8)),
            child: const Text('Clear', style: TextStyle(
                color: _C.teal, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
    );
  }
}

// ─── Delete Dialog ────────────────────────────────────────────────────────────
class _DeleteDialog extends StatelessWidget {
  final String name;
  const _DeleteDialog({required this.name});

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: _C.card,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    child: Padding(padding: const EdgeInsets.all(22), child: Column(
        mainAxisSize: MainAxisSize.min, children: [
      Container(width: 48, height: 48,
          decoration: BoxDecoration(
              color: _C.rose.withOpacity(0.1), shape: BoxShape.circle),
          child: const Icon(Icons.delete_outline_rounded, color: _C.rose, size: 22)),
      const SizedBox(height: 14),
      const Text('Delete Medicine?', style: TextStyle(
          fontSize: 17, fontWeight: FontWeight.w700, color: _C.textPri)),
      const SizedBox(height: 7),
      Text('Remove "$name"?\nThis cannot be undone.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, color: _C.textSec, height: 1.5)),
      const SizedBox(height: 18),
      Row(children: [
        Expanded(child: GestureDetector(
          onTap: () => Navigator.pop(context, false),
          child: Container(height: 42,
              decoration: BoxDecoration(color: _C.surface,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: _C.border)),
              child: const Center(child: Text('Cancel', style: TextStyle(
                  fontWeight: FontWeight.w700, color: _C.textSec, fontSize: 13)))),
        )),
        const SizedBox(width: 10),
        Expanded(child: GestureDetector(
          onTap: () => Navigator.pop(context, true),
          child: Container(height: 42,
              decoration: BoxDecoration(
                  color: _C.rose, borderRadius: BorderRadius.circular(11)),
              child: const Center(child: Text('Delete', style: TextStyle(
                  fontWeight: FontWeight.w700, color: Colors.white, fontSize: 13)))),
        )),
      ]),
    ])),
  );
}

// ─── Empty State ──────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final VoidCallback onScan;
  const _EmptyState({required this.onScan});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(28),
    decoration: BoxDecoration(
        color: _C.card, borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _C.border)),
    child: Column(children: [
      Container(width: 60, height: 60,
          decoration: BoxDecoration(
              color: _C.teal.withOpacity(0.1),
              borderRadius: BorderRadius.circular(22)),
          child: const Icon(Icons.qr_code_scanner_rounded, size: 30, color: _C.teal)),
      const SizedBox(height: 14),
      const Text('No Medicines Yet', style: TextStyle(
          fontSize: 18, fontWeight: FontWeight.w700, color: _C.textPri)),
      const SizedBox(height: 6),
      const Text('Scan a medicine label to start\nbuilding your inventory',
          textAlign: TextAlign.center,
          style: TextStyle(color: _C.textSec, fontSize: 12, height: 1.5)),
      const SizedBox(height: 18),
      GestureDetector(
        onTap: onScan,
        child: Container(
          width: double.infinity, height: 46,
          decoration: BoxDecoration(color: _C.teal,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: _C.teal.withOpacity(0.3),
                  blurRadius: 12, offset: const Offset(0, 5))]),
          child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text('Scan Your First Medicine', style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
          ]),
        ),
      ),
    ]),
  );
}

// ─── Shared widgets ───────────────────────────────────────────────────────────
class _Banner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title, sub;
  const _Banner({required this.icon, required this.color,
    required this.title, required this.sub});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
        color: color.withOpacity(0.06), borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2))),
    child: Row(children: [
      Container(width: 36, height: 36,
          decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color, size: 18)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(
            fontSize: 13, fontWeight: FontWeight.w700, color: _C.textPri)),
        const SizedBox(height: 2),
        Text(sub, style: const TextStyle(fontSize: 11, color: _C.textSec)),
      ])),
    ]),
  );
}

class _GuestState extends StatelessWidget {
  const _GuestState();
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _C.surface,
    body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 60, height: 60,
          decoration: BoxDecoration(
              color: _C.teal.withOpacity(0.1), shape: BoxShape.circle),
          child: const Icon(Icons.lock_outline_rounded, size: 28, color: _C.teal)),
      const SizedBox(height: 16),
      const Text('Not Logged In', style: TextStyle(
          fontSize: 18, fontWeight: FontWeight.w700, color: _C.textPri)),
      const SizedBox(height: 5),
      const Text('Please login to view your medicines',
          style: TextStyle(color: _C.textSec, fontSize: 12)),
    ])),
  );
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();
  @override
  Widget build(BuildContext context) => Center(child: Column(
      mainAxisSize: MainAxisSize.min, children: [
    SizedBox(width: 34, height: 34,
        child: CircularProgressIndicator(strokeWidth: 2.5, color: _C.teal,
            backgroundColor: _C.teal.withOpacity(0.15))),
    const SizedBox(height: 12),
    const Text('Loading medicines...', style: TextStyle(
        color: _C.textSec, fontSize: 12, fontWeight: FontWeight.w500)),
  ]));
}

// ─── Mesh Painter ─────────────────────────────────────────────────────────────
class _MeshPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(Offset(size.width * 0.88, size.height * 0.2), 90,
        Paint()..color = _C.teal.withOpacity(0.07));
    canvas.drawCircle(Offset(size.width * 0.05, size.height * 0.8), 65,
        Paint()..color = _C.sky.withOpacity(0.06));
  }
  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}