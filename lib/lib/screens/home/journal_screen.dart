import 'dart:async';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../design/medic_design.dart';

const _moods = [
  _Mood('Great', Icons.sentiment_very_satisfied_rounded, MedicColors.green),
  _Mood('Good', Icons.sentiment_satisfied_alt_rounded, MedicColors.c477C91),
  _Mood('Okay', Icons.sentiment_neutral_rounded, MedicColors.cB77A27),
  _Mood('Bad', Icons.sentiment_dissatisfied_rounded, MedicColors.cC05256),
  _Mood('Terrible', Icons.sentiment_very_dissatisfied_rounded, MedicColors.c78659B),
];
const _symptomOptions = ['Headache', 'Dizziness', 'Fatigue', 'Nausea', 'Chest Pain',
  'Shortness of Breath', 'Blurred Vision', 'Joint Pain', 'Insomnia', 'Anxiety'];

class _Mood {
  final String label;
  final IconData icon;
  final Color color;
  const _Mood(this.label, this.icon, this.color);
}

Map<String, dynamic> _map(Object? value) => value is Map
    ? Map<String, dynamic>.from(value) : <String, dynamic>{};
DateTime? _date(Object? value) => value is Timestamp ? value.toDate().toLocal()
    : value is DateTime ? value.toLocal()
    : value is String ? DateTime.tryParse(value)?.toLocal() : null;
String _time(DateTime date) {
  final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
  return '$hour:${date.minute.toString().padLeft(2, '0')} ${date.hour < 12 ? 'AM' : 'PM'}';
}
String _day(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(date.year, date.month, date.day);
  if (day == today) return 'Today';
  if (day == DateTime(now.year, now.month, now.day - 1)) return 'Yesterday';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}

/// Existing journal documents remain compatible at users/{uid}/journal.
class JournalScreen extends StatefulWidget {
  const JournalScreen({super.key});
  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> with SingleTickerProviderStateMixin {
  final _uid = FirebaseAuth.instance.currentUser?.uid;
  late final AnimationController _entrance;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _entries = [];
  Timer? _loadingTimer;
  bool _started = false;
  bool _loading = true;
  Object? _error;
  int _generation = 0;
  Completer<void>? _refreshDone;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    if (_uid == null) { _loading = false; } else { _listen(); }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) { _entrance.value = 1; _started = true; }
    else if (!_started) { _started = true; _entrance.forward(); }
  }

  Future<void> _listen() async {
    if (_uid == null || !mounted) return;
    final generation = ++_generation;
    _loadingTimer?.cancel();
    final previous = _subscription;
    _subscription = null;
    if (previous != null) await previous.cancel();
    if (!mounted || generation != _generation) return;
    _loadingTimer = Timer(const Duration(seconds: 15), () {
      if (mounted && generation == _generation && _loading) {
        _fail(TimeoutException('Journal loading timed out.'), generation);
      }
    });
    try {
      _subscription = FirebaseFirestore.instance.collection('users').doc(_uid)
          .collection('journal').orderBy('createdAt', descending: true)
          .snapshots().listen((snapshot) {
        if (!mounted || generation != _generation) return;
        _loadingTimer?.cancel();
        setState(() { _entries = snapshot.docs; _loading = false; _error = null; });
        _finishRefresh();
      }, onError: (Object error) => _fail(error, generation));
    } catch (error) { _fail(error, generation); }
  }

  void _fail(Object error, int generation) {
    if (!mounted || generation != _generation) return;
    debugPrint('Health journal query: $error');
    _loadingTimer?.cancel();
    setState(() { _error = error; _loading = false; });
    _finishRefresh();
  }
  void _finishRefresh() {
    final done = _refreshDone;
    if (done != null && !done.isCompleted) done.complete();
    _refreshDone = null;
  }
  Future<void> _refresh() async {
    if (_uid == null) return;
    _finishRefresh();
    final done = Completer<void>();
    _refreshDone = done;
    setState(() { _loading = true; _error = null; });
    await _listen();
    await done.future;
  }

  @override
  void dispose() {
    ++_generation;
    _loadingTimer?.cancel();
    _subscription?.cancel();
    _finishRefresh();
    _entrance.dispose();
    super.dispose();
  }

  Widget _reveal(Widget child, int order) => AnimatedBuilder(animation: _entrance,
    child: child, builder: (context, child) {
      final delay = math.min(order, 6) * .075;
      final phase = ((_entrance.value - delay) / (1 - delay)).clamp(0.0, 1.0).toDouble();
      final value = Curves.easeOutCubic.transform(phase);
      return Opacity(opacity: value, child: Transform.translate(offset: Offset(0, 18*(1-value)), child: child));
    });

  Future<void> _newEntry() async {
    final uid = _uid;
    if (uid == null) return;
    HapticFeedback.selectionClick();
    final saved = await showModalBottomSheet<bool>(context: context, isScrollControlled: true,
      useSafeArea: true, backgroundColor: Colors.transparent,
      builder: (_) => _NewEntrySheet(uid: uid));
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Your journal entry has been saved.'),
        backgroundColor: MedicColors.forest, behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))));
    }
  }

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.light,
    child: Scaffold(backgroundColor: MedicColors.canvas,
      floatingActionButton: _uid == null ? null : _reveal(FloatingActionButton.extended(
        onPressed: _newEntry, backgroundColor: MedicColors.forest, foregroundColor: MedicColors.mint,
        icon: const Icon(Icons.add_rounded), label: const Text('New entry', style: TextStyle(fontWeight: FontWeight.w700)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))), 2),
      body: Column(children: [
        const MedicPageTitle(title: 'Health journal', subtitle: 'Track your daily wellbeing and symptoms.'),
        Expanded(child: _uid == null
          ? const Center(child: Text('Sign in to keep a journal.', style: TextStyle(color: MedicColors.muted)))
          : RefreshIndicator(onRefresh: _refresh, color: MedicColors.green,
            child: CustomScrollView(physics: const AlwaysScrollableScrollPhysics(), slivers: [
              SliverPadding(padding: const EdgeInsets.fromLTRB(22, 20, 22, 0),
                sliver: SliverToBoxAdapter(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _reveal(_weekSummary(), 0), const SizedBox(height: 26),
                  _reveal(Row(children: [const Expanded(child: Text('Recent entries',
                    style: TextStyle(fontFamily: 'serif', fontSize: 24, color: MedicColors.forest, letterSpacing: -.4))),
                    Text('${_entries.length} ${_entries.length == 1 ? 'entry' : 'entries'}',
                      style: const TextStyle(fontSize: 11, color: MedicColors.muted))]), 1),
                  const SizedBox(height: 14),
                  if (_error != null) ...[_errorCard(), const SizedBox(height: 14)],
                  if (_loading && _entries.isEmpty) _surface(const Padding(
                    padding: EdgeInsets.all(22), child: Column(children: [
                      CircularProgressIndicator(strokeWidth: 2, color: MedicColors.green), SizedBox(height: 14),
                      Text('Opening your journal…', style: TextStyle(fontSize: 12, color: MedicColors.muted)),
                    ]))),
                  if (!_loading && _entries.isEmpty && _error == null) _reveal(_emptyCard(), 2),
                ]))),
              SliverPadding(padding: const EdgeInsets.fromLTRB(22, 0, 22, 0),
                sliver: SliverList(delegate: SliverChildBuilderDelegate((context, index) =>
                  Padding(padding: const EdgeInsets.only(bottom: 14),
                    child: _reveal(_entryCard(_entries[index]), index+2)), childCount: _entries.length))),
              const SliverPadding(padding: EdgeInsets.fromLTRB(22, 20, 22, 112),
                sliver: SliverToBoxAdapter(child: Center(child: MedicEyebrow('Make room for how you feel.')))),
            ]))),
      ])),
  );

  Widget _weekSummary() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = DateTime(now.year, now.month, now.day - (now.weekday - 1));
    final end = DateTime(start.year, start.month, start.day + 7);
    final thisWeek = _entries.where((entry) {
      final at = _date(entry.data()['createdAt']) ?? _date(entry.data()['clientCreatedAt']);
      return at != null && !at.isBefore(start) && at.isBefore(end);
    }).toList();
    final counts = {for (final mood in _moods) mood.label:
      thisWeek.where((entry) => entry.data()['mood'] == mood.label).length};
    final loggedToday = _entries.any((entry) {
      final at = _date(entry.data()['createdAt']) ?? _date(entry.data()['clientCreatedAt']);
      return at != null && DateTime(at.year, at.month, at.day) == today;
    });
    return _surface(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Row(children: [Expanded(child: MedicEyebrow('This week')),
        Icon(Icons.auto_stories_outlined, color: MedicColors.green, size: 20)]),
      const SizedBox(height: 13),
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        AnimatedSwitcher(duration: MediaQuery.of(context).disableAnimations ? Duration.zero : const Duration(milliseconds: 320),
          child: Text(_loading && _entries.isEmpty ? '—' : '${thisWeek.length}',
            key: ValueKey('${thisWeek.length}_$_loading'), style: const TextStyle(
              fontFamily: 'serif', fontSize: 43, height: 1, letterSpacing: -1, color: MedicColors.forest))),
        const SizedBox(width: 9), Padding(padding: const EdgeInsets.only(bottom: 5), child: Text(
          thisWeek.length == 1 ? 'entry' : 'entries', style: const TextStyle(color: MedicColors.muted, fontSize: 13))),
      ]),
      const SizedBox(height: 15),
      if (_loading && _entries.isEmpty) const Text('Gathering your reflections…',
        style: TextStyle(fontSize: 12, color: MedicColors.muted))
      else if (thisWeek.isEmpty) const Text('A moment of reflection can make a difference.',
        style: TextStyle(fontSize: 12, color: MedicColors.muted, height: 1.5))
      else Wrap(spacing: 8, runSpacing: 8, children: [
        for (final mood in _moods) if (counts[mood.label]! > 0) _moodPill(mood, '${counts[mood.label]} ${mood.label}'),
      ]),
      const SizedBox(height: 16), const Divider(height: 1, color: MedicColors.line), const SizedBox(height: 12),
      Row(children: [Icon(loggedToday ? Icons.check_circle_outline_rounded : Icons.edit_note_rounded,
          color: MedicColors.green, size: 17), const SizedBox(width: 8),
        Expanded(child: Text(loggedToday ? 'You made time for yourself today.' : 'How are you feeling today?',
          style: const TextStyle(color: MedicColors.muted, fontSize: 11.5, height: 1.4))),
      ]),
    ]));
  }

  Widget _moodPill(_Mood mood, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(color: mood.color.withOpacity(.09), borderRadius: BorderRadius.circular(12)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(mood.icon, color: mood.color, size: 15),
      const SizedBox(width: 5), Text(label, style: TextStyle(color: mood.color, fontSize: 11, fontWeight: FontWeight.w600))]));

  Widget _emptyCard() => _surface(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Container(width: 55, height: 55, decoration: BoxDecoration(color: MedicColors.mint.withOpacity(.55),
      borderRadius: BorderRadius.circular(18)), child: const Icon(Icons.edit_note_rounded, color: MedicColors.green, size: 29)),
    const SizedBox(height: 18), const Text('Your space to reflect.', style: TextStyle(
      fontFamily: 'serif', fontSize: 25, color: MedicColors.forest, letterSpacing: -.5)),
    const SizedBox(height: 9), const Text('Keep a note of your mood, symptoms, and the little things that shape your day.',
      style: TextStyle(fontSize: 13, height: 1.6, color: MedicColors.muted)),
    const SizedBox(height: 18), FilledButton.icon(onPressed: _newEntry,
      style: FilledButton.styleFrom(backgroundColor: MedicColors.forest, foregroundColor: MedicColors.mint,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
      icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Write your first entry')),
  ]));

  Widget _errorCard() => _surface(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('Your journal could not be refreshed.', style: TextStyle(fontWeight: FontWeight.w700, color: MedicColors.forest)),
    const SizedBox(height: 8), Text(_error is FirebaseException && (_error as FirebaseException).code == 'permission-denied'
      ? 'Your account cannot access these entries. Please contact support.' : 'Check your connection and try again.',
      style: const TextStyle(fontSize: 12, color: MedicColors.muted, height: 1.5)),
    TextButton(onPressed: _refresh, child: const Text('Retry')),
  ]));

  Widget _entryCard(QueryDocumentSnapshot<Map<String, dynamic>> document) {
    final data = document.data();
    final knownMood = _moods.where((m) => m.label == data['mood']).toList();
    final mood = knownMood.isEmpty ? null : knownMood.first;
    final color = mood?.color ?? MedicColors.muted;
    final moodLabel = mood?.label ?? (data['mood']?.toString() ?? 'Not recorded');
    final at = _date(data['createdAt']) ?? _date(data['clientCreatedAt']);
    final symptoms = data['symptoms'] is List
        ? (data['symptoms'] as List).whereType<String>().toList() : <String>[];
    final notes = (data['notes'] ?? '').toString().trim();
    final bp = data['bpSnapshot']?.toString();
    final sugar = data['sugarSnapshot']?.toString();
    final sugarUnit = data['sugarUnit']?.toString();
    return _surface(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Container(width: 46, height: 46,
        decoration: BoxDecoration(color: color.withOpacity(.10), borderRadius: BorderRadius.circular(16)),
        child: Icon(mood?.icon ?? Icons.edit_note_rounded, color: color, size: 24)),
        const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(at == null ? 'Saving entry…' : _day(at), style: const TextStyle(fontSize: 16,
            fontWeight: FontWeight.w700, color: MedicColors.forest)),
          const SizedBox(height: 4), Text(at == null ? 'Waiting to sync' : _time(at),
            style: const TextStyle(fontSize: 11.5, color: MedicColors.muted)),
        ])),
        Flexible(child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: color.withOpacity(.09), borderRadius: BorderRadius.circular(12)),
          child: Text(moodLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)))),
      ]),
      if (notes.isNotEmpty) ...[const SizedBox(height: 17),
        Text(notes, style: const TextStyle(fontSize: 13.5, height: 1.65, color: MedicColors.ink))],
      if (symptoms.isNotEmpty) ...[const SizedBox(height: 14),
        Wrap(spacing: 7, runSpacing: 7, children: symptoms.map((symptom) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: MedicColors.canvas, borderRadius: BorderRadius.circular(10)),
          child: Text(symptom, style: const TextStyle(fontSize: 10.5, color: MedicColors.muted)))).toList())],
      if (bp != null || sugar != null) ...[
        const Padding(padding: EdgeInsets.symmetric(vertical: 15), child: Divider(height: 1, color: MedicColors.line)),
        Wrap(spacing: 16, runSpacing: 10, children: [
          if (bp != null) _reading(Icons.favorite_border_rounded, MedicColors.cC05256, 'BP $bp mmHg'),
          if (sugar != null) _reading(Icons.water_drop_outlined, MedicColors.c477C91,
            'Sugar $sugar${sugarUnit == null ? '' : ' $sugarUnit'}'),
        ]),
        const SizedBox(height: 8), const Text('Readings on file when this entry was saved',
          style: TextStyle(fontSize: 9.5, color: MedicColors.muted)),
      ],
    ]));
  }
  Widget _reading(IconData icon, Color color, String label) => Row(mainAxisSize: MainAxisSize.min,
    children: [Icon(icon, size: 15, color: color), const SizedBox(width: 5),
      Flexible(child: Text(label, style: const TextStyle(fontSize: 11, color: MedicColors.muted)))]);
}

Widget _surface(Widget child) => Container(width: double.infinity, padding: const EdgeInsets.all(20),
  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(26),
    border: Border.all(color: MedicColors.line.withOpacity(.75)),
    boxShadow: [BoxShadow(color: MedicColors.forest.withOpacity(.025), blurRadius: 22, offset: const Offset(0, 7))]),
  child: child);

class _NewEntrySheet extends StatefulWidget {
  final String uid;
  const _NewEntrySheet({required this.uid});
  @override
  State<_NewEntrySheet> createState() => _NewEntrySheetState();
}
class _NewEntrySheetState extends State<_NewEntrySheet> {
  _Mood? _mood;
  final _symptoms = <String>{};
  final _notes = TextEditingController();
  bool _saving = false;
  late final DocumentReference<Map<String, dynamic>> _entryReference;

  @override
  void initState() {
    super.initState();
    // Reuse one document ID for retries, including a delayed offline write.
    _entryReference = FirebaseFirestore.instance.collection('users').doc(widget.uid).collection('journal').doc();
  }
  @override
  void dispose() { _notes.dispose(); super.dispose(); }

  Future<void> _save() async {
    final mood = _mood;
    if (_saving || mood == null) return;
    if (FirebaseAuth.instance.currentUser?.uid != widget.uid) {
      _message('Please sign in again before saving.'); return;
    }
    FocusScope.of(context).unfocus();
    final symptoms = _symptoms.toList();
    final notes = _notes.text.trim();
    setState(() => _saving = true);
    try {
      final db = FirebaseFirestore.instance;
      Map<String, dynamic> profile = {};
      try { profile = (await db.collection('users').doc(widget.uid).get()
          .timeout(const Duration(seconds: 5))).data() ?? {}; }
      catch (error) { debugPrint('Optional journal vital snapshots: $error'); }
      final bp = _map(profile['latestBP']);
      final sugar = _map(profile['latestSugar']);
      final rawSugar = sugar['value'];
      final unit = sugar['unit']?.toString();
      final sugarValue = rawSugar is num ? rawSugar.toDouble()
          : (sugar['valueMmol'] is num && unit == 'mmol/L') ? (sugar['valueMmol'] as num).toDouble() : null;
      String number(double value) => value == value.roundToDouble() ? value.toInt().toString() : value.toStringAsFixed(1);
      await _entryReference.set({
        'mood': mood.label, 'symptoms': symptoms, 'notes': notes,
        'bpSnapshot': bp['systolic'] == null ? null : '${bp['systolic']}/${bp['diastolic'] ?? '—'}',
        'sugarSnapshot': sugarValue == null ? null : number(sugarValue),
        'sugarUnit': sugarValue == null ? null : unit,
        'bpSnapshotAt': bp['measuredAt'] ?? bp['recordedAt'],
        'sugarSnapshotAt': sugar['measuredAt'] ?? sugar['recordedAt'],
        'clientCreatedAt': Timestamp.now(), 'createdAt': FieldValue.serverTimestamp(),
      }).timeout(const Duration(seconds: 15));
      if (mounted) { HapticFeedback.mediumImpact(); Navigator.of(context).pop(true); }
    } on TimeoutException {
      _message('Saving is taking longer than expected. Check your connection before retrying.');
    } catch (error) {
      debugPrint('Journal entry save: $error');
      _message('Could not save your entry. Please try again.');
    } finally { if (mounted) setState(() => _saving = false); }
  }
  void _message(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text),
      backgroundColor: MedicColors.forest, behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.of(context).disableAnimations;
    final duration = reducedMotion ? Duration.zero : const Duration(milliseconds: 220);
    return PopScope(canPop: !_saving, child: AnimatedPadding(duration: duration, curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(top: false, child: Container(
        decoration: const BoxDecoration(color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
        child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 38, height: 4, margin: const EdgeInsets.only(bottom: 17),
              decoration: BoxDecoration(color: MedicColors.line, borderRadius: BorderRadius.circular(4)))),
            Row(children: [const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              MedicEyebrow('A moment for yourself'), SizedBox(height: 7),
              Text('New journal entry', style: TextStyle(fontFamily: 'serif', fontSize: 26,
                letterSpacing: -.6, color: MedicColors.forest)),
            ])), IconButton(tooltip: 'Close', onPressed: _saving ? null : () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded, color: MedicColors.muted))]),
            const SizedBox(height: 23),
            const Text('How are you feeling today?', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: MedicColors.forest)),
            const SizedBox(height: 13),
            LayoutBuilder(builder: (context, constraints) {
              final columns = constraints.maxWidth < 300 || MediaQuery.of(context).textScaleFactor > 1.3 ? 3 : 5;
              final width = (constraints.maxWidth - (columns-1)*8) / columns;
              return Wrap(spacing: 8, runSpacing: 8, children: _moods.map((mood) {
                final selected = _mood == mood;
                return SizedBox(width: width, child: Semantics(selected: selected, button: true, label: mood.label,
                  child: Material(color: Colors.transparent, child: InkWell(
                    borderRadius: BorderRadius.circular(17),
                    onTap: _saving ? null : () { HapticFeedback.selectionClick(); setState(() => _mood = mood); },
                    child: AnimatedContainer(duration: duration, curve: Curves.easeOutCubic,
                      padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 3),
                      decoration: BoxDecoration(color: selected ? mood.color.withOpacity(.10) : MedicColors.canvas,
                        borderRadius: BorderRadius.circular(17), border: Border.all(
                          color: selected ? mood.color.withOpacity(.6) : MedicColors.line, width: selected ? 1.5 : 1)),
                      child: Column(children: [AnimatedScale(scale: selected ? 1.12 : 1, duration: duration,
                        child: Icon(mood.icon, size: 26, color: mood.color)), const SizedBox(height: 8),
                        Text(mood.label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600,
                          color: selected ? mood.color : MedicColors.muted)),
                      ]),
                    ),
                  )),
                ));
              }).toList());
            }),
            const SizedBox(height: 25),
            const Text('Any symptoms?', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: MedicColors.forest)),
            const SizedBox(height: 5), const Text('Optional · select everything that applies',
              style: TextStyle(color: MedicColors.muted, fontSize: 11)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: _symptomOptions.map((symptom) {
              final selected = _symptoms.contains(symptom);
              return Semantics(selected: selected, button: true, child: Material(color: Colors.transparent,
                child: InkWell(borderRadius: BorderRadius.circular(14),
                  onTap: _saving ? null : () { HapticFeedback.selectionClick();
                    setState(() => selected ? _symptoms.remove(symptom) : _symptoms.add(symptom)); },
                  child: AnimatedContainer(duration: duration, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(color: selected ? MedicColors.forest : MedicColors.canvas,
                      borderRadius: BorderRadius.circular(14), border: Border.all(color: selected ? MedicColors.forest : MedicColors.line)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (selected) ...[const Icon(Icons.check_rounded, size: 13, color: MedicColors.mint), const SizedBox(width: 5)],
                      Text(symptom, style: TextStyle(fontSize: 11.5,
                        color: selected ? MedicColors.mint : MedicColors.muted, fontWeight: FontWeight.w500)),
                    ]),
                  ),
                )));
            }).toList()),
            const SizedBox(height: 25), const Text('Notes', style: TextStyle(
              fontSize: 14, fontWeight: FontWeight.w700, color: MedicColors.forest)),
            const SizedBox(height: 10),
            TextField(controller: _notes, enabled: !_saving, minLines: 4, maxLines: 7, maxLength: 3000,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(fontSize: 13, height: 1.6, color: MedicColors.ink),
              decoration: InputDecoration(hintText: 'Write about how you feel, any observations…',
                hintStyle: const TextStyle(fontSize: 12.5, color: MedicColors.muted),
                filled: true, fillColor: MedicColors.canvas, contentPadding: const EdgeInsets.all(16),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18),
                  borderSide: const BorderSide(color: MedicColors.green)))),
            const SizedBox(height: 15),
            SizedBox(width: double.infinity, child: FilledButton(
              onPressed: _mood == null || _saving ? null : _save,
              style: FilledButton.styleFrom(backgroundColor: MedicColors.forest, foregroundColor: MedicColors.mint,
                disabledBackgroundColor: MedicColors.line, disabledForegroundColor: MedicColors.muted,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17))),
              child: AnimatedSwitcher(duration: duration, child: _saving
                ? const SizedBox(key: ValueKey('saving'), width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: MedicColors.mint))
                : const Row(key: ValueKey('ready'), mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.check_rounded, size: 19), SizedBox(width: 8),
                  Text('Save entry', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ])))),
            const SizedBox(height: 10),
            Center(child: Text(_mood == null ? 'Select a mood to save your entry.' : 'Small reflections. Meaningful patterns.',
              style: const TextStyle(fontSize: 10.5, color: MedicColors.muted))),
          ])),
      ))));
  }
}
