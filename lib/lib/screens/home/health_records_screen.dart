import '../../services/health_monitoring_service.dart';
import '../../services/daily_score_view.dart';
import 'health_monitoring_screen.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../design/medic_design.dart';
import '../../services/auth_service.dart';
import '../../services/health_record_trends.dart';
import 'vitals_upload_screen.dart';
import 'journal_screen.dart';

const _teal = MedicColors.green;
const _ink = MedicColors.forest;
const _muted = MedicColors.muted;
const _canvas = MedicColors.canvas;
const _rose = MedicColors.cC05256;
const _amber = MedicColors.cB77A27;

class HealthRecordsScreen extends StatefulWidget {
  const HealthRecordsScreen({super.key});
  @override
  State<HealthRecordsScreen> createState() => _HealthRecordsScreenState();
}

class _HealthRecordsScreenState extends State<HealthRecordsScreen>
    with SingleTickerProviderStateMixin {
  final _uid = AuthService().currentUser?.uid;
  late final AnimationController _entrance;
  bool _entranceStarted = false;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _recordsSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _profileSub;
  Timer? _loadTimer;
  List<HealthUpload> _uploads = [];
  Map<String, dynamic> _profile = {};
  Object? _error;
  bool _loading = true;
  HealthMetric? _filter;
  bool _mmol = false;
  bool _onlyThree = false;
  int _generation = 0;
  Completer<void>? _refreshDone;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 850));
    final uid = _uid;
    if (uid == null) { _loading = false; return; }
    _profileSub = FirebaseFirestore.instance.collection('users').doc(uid)
        .snapshots().listen((doc) {
      if (mounted) setState(() => _profile = doc.data() ?? {});
    }, onError: (Object error) { debugPrint('Records profile: $error'); });
    _listen();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _entrance.value = 1;
      _entranceStarted = true;
    } else if (!_entranceStarted) {
      _entranceStarted = true;
      _entrance.forward();
    }
  }

  Widget _reveal(Widget child, int order) => AnimatedBuilder(
    animation: _entrance, child: child, builder: (context, child) {
      final delay = math.min(order, 6) * .08;
      final phase = ((_entrance.value - delay) / (1 - delay)).clamp(0.0, 1.0).toDouble();
      final value = Curves.easeOutCubic.transform(phase);
      return Opacity(opacity: value, child: Transform.translate(
          offset: Offset(0, 18 * (1 - value)), child: child));
    });

  Future<void> _listen() async {
    if (_uid == null || !mounted) return;
    final generation = ++_generation;
    _loadTimer?.cancel();
    final old = _recordsSub;
    _recordsSub = null;
    if (old != null) await old.cancel();
    if (!mounted || generation != _generation) return;
    _loadTimer = Timer(const Duration(seconds: 15), () {
      if (!mounted || generation != _generation || !_loading) return;
      setState(() {
        _loading = false;
        _error = TimeoutException('Health records took too long to load.');
      });
      _finishRefresh();
    });
    // Reuse the existing user's vitals subcollection. No new collection or
    // dependency is required, and legacy recordedAt-only uploads still work.
    try {
      _recordsSub = FirebaseFirestore.instance.collection('users').doc(_uid)
          .collection('vitals').snapshots().listen((snapshot) {
        if (!mounted || generation != _generation) return;
        final uploads = <HealthUpload>[];
        for (final doc in snapshot.docs) {
          final data = doc.data();
          final raw = data['measuredAt'] ?? data['recordedAt'] ?? data['clientRecordedAt'];
          final at = raw is Timestamp ? raw.toDate().toLocal()
              : raw is DateTime ? raw.toLocal()
              : raw is String ? DateTime.tryParse(raw)?.toLocal() : null;
          if (at != null) uploads.add(HealthUpload(id: doc.id, at: at, data: data));
        }
        uploads.sort((a, b) {
          final order = b.at.compareTo(a.at);
          return order == 0 ? b.id.compareTo(a.id) : order;
        });
        _loadTimer?.cancel();
        setState(() { _uploads = uploads; _loading = false; _error = null; });
        _finishRefresh();
      }, onError: (Object error) => _fail(error, generation));
    } catch (error) { _fail(error, generation); }
  }

  void _fail(Object error, int generation) {
    if (!mounted || generation != _generation) return;
    debugPrint('Health records query: $error');
    _loadTimer?.cancel();
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
    setState(() { _error = null; _loading = true; });
    await _listen();
    await done.future;
  }

  @override
  void dispose() {
    ++_generation;
    _entrance.dispose();
    _loadTimer?.cancel();
    _recordsSub?.cancel();
    _profileSub?.cancel();
    _finishRefresh();
    super.dispose();
  }

  Future<void> _add() async {
    HapticFeedback.selectionClick();
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const VitalsUploadScreen()));
    // The live listener receives the upload; do not recreate it on return.
  }

  void _options() => showModalBottomSheet<void>(context: context,
      showDragHandle: true, builder: (sheetContext) => StatefulBuilder(
        builder: (context, update) => SafeArea(child: Column(
          mainAxisSize: MainAxisSize.min, children: [
            const ListTile(title: Text('Record preferences', style: TextStyle(fontWeight: FontWeight.w700))),
            SwitchListTile(title: const Text('Blood sugar in mmol/L'),
                subtitle: const Text('Convert all readings to the same display unit'),
                value: _mmol, onChanged: (value) {
              setState(() => _mmol = value); update(() {});
            }),
            SwitchListTile(title: const Text('Show only three recent uploads'),
                subtitle: const Text('Charts always compare three readings per metric'),
                value: _onlyThree, onChanged: (value) {
              setState(() => _onlyThree = value); update(() {});
            }),
            const SizedBox(height: 16),
          ],
        )),
      ));

  @override
  Widget build(BuildContext context) {
    final metrics = _filter == null ? HealthMetric.values : [_filter!];
    var visible = _uploads.where((u) => _filter == null || u.reading(_filter!) != null).toList();
    if (_onlyThree) visible = visible.take(3).toList();
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _canvas,
        floatingActionButton: _uid == null ? null : _reveal(
          FloatingActionButton.extended(
            onPressed: _add, tooltip: 'Upload health readings',
            backgroundColor: _ink, foregroundColor: MedicColors.mint,
            elevation: 4, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add reading', style: TextStyle(fontWeight: FontWeight.w700)),
          ), 3),
        body: Column(children: [
          MedicPageTitle(title: 'Health records',
            subtitle: 'Your progress, one reading at a time.',
            trailing: Container(
              decoration: BoxDecoration(color: Colors.white.withOpacity(.09),
                  borderRadius: BorderRadius.circular(14)),
              child: IconButton(tooltip: 'Record preferences', onPressed: _options,
                icon: const Icon(Icons.tune_rounded, color: MedicColors.mint, size: 21)))),
          Expanded(child: _uid == null
            ? const Center(child: Text('Sign in to view your health records.'))
            : RefreshIndicator(onRefresh: _refresh, color: _teal,
              child: ListView(physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 112), children: [
                  _reveal(SingleChildScrollView(scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      _chip('All', null), _chip('Blood pressure', HealthMetric.bloodPressure),
                      _chip('Blood sugar', HealthMetric.bloodSugar), _chip('Weight', HealthMetric.weight),
                    ])), 0),
                  const SizedBox(height: 20),
                  _reveal(_profileCard(), 1),
                  TextButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HealthMonitoringScreen())),
                    icon: const Icon(Icons.monitor_heart_outlined, size: 18), label: const Text('Daily monitoring & seven-day report')),
                  const SizedBox(height: 24),
                  if (_error != null) ...[_errorCard(), const SizedBox(height: 18)],
                  if (_loading && _uploads.isEmpty)
                    _card(const Padding(padding: EdgeInsets.all(22), child: Column(children: [
                      CircularProgressIndicator(color: _teal, strokeWidth: 2), SizedBox(height: 14),
                      Text('Gathering your health records…', style: TextStyle(color: _muted, fontSize: 12)),
                    ])))
                  else ...[
                    _reveal(_card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Row(children: [Expanded(child: MedicEyebrow('A closer look')),
                        Icon(Icons.insights_rounded, size: 19, color: _teal)]),
                      const SizedBox(height: 10),
                      const Text('Your health trends', style: TextStyle(fontFamily: 'serif',
                          fontSize: 25, color: _ink, letterSpacing: -.5)),
                      const SizedBox(height: 7),
                      const Text('Compare your latest three readings for each metric.',
                          style: TextStyle(fontSize: 12, height: 1.5, color: _muted)),
                      const SizedBox(height: 20),
                      for (final metric in metrics) _trendCard(metric),
                    ])), 2),
                    const SizedBox(height: 26),
                    _reveal(Row(children: [const Expanded(child: Text('Your timeline',
                        style: TextStyle(fontFamily: 'serif', fontSize: 24, color: _ink, letterSpacing: -.4))),
                      _badge('${visible.length} ${visible.length == 1 ? 'upload' : 'uploads'}')]), 3),
                    const SizedBox(height: 14),
                    if (visible.isEmpty) _reveal(_emptyTimeline(), 3),
                    for (var i = 0; i < visible.length; i++) ...[
                      if (i == 0 || !sameHealthDay(visible[i].at, visible[i-1].at))
                        Padding(padding: const EdgeInsets.only(top: 12, bottom: 12), child: Row(children: [
                          Container(width: 8, height: 8,
                              decoration: const BoxDecoration(color: _teal, shape: BoxShape.circle)),
                          const SizedBox(width: 10), MedicEyebrow(_day(visible[i].at)),
                        ])),
                      _reveal(_uploadCard(visible[i]), i + 3), const SizedBox(height: 12),
                    ],
                  ],
                  const SizedBox(height: 24),
                  _reveal(_journalCard(), 4),
                  const SizedBox(height: 22),
                  const Center(child: MedicEyebrow('A little care. Every day.')),
                ],
              ))),
        ]),
      ),
    );
  }

  Widget _chip(String label, HealthMetric? metric) {
    final selected = _filter == metric;
    return Padding(padding: const EdgeInsets.only(right: 8),
      child: Semantics(selected: selected, button: true,
        child: Material(color: Colors.transparent, child: InkWell(
          borderRadius: BorderRadius.circular(17),
          onTap: () { HapticFeedback.selectionClick(); setState(() => _filter = metric); },
          child: AnimatedContainer(
            duration: MediaQuery.of(context).disableAnimations ? Duration.zero : const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(color: selected ? _ink : Colors.white,
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: selected ? _ink : MedicColors.line)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (selected) ...[const Icon(Icons.check_rounded, size: 14, color: MedicColors.mint),
                const SizedBox(width: 6)],
              Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600,
                  color: selected ? MedicColors.mint : _muted)),
            ]),
          ),
        )),
      ),
    );
  }

  Widget _emptyTimeline() => _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Container(width: 56, height: 56,
      decoration: BoxDecoration(color: MedicColors.mint.withOpacity(.5), borderRadius: BorderRadius.circular(19)),
      child: const Icon(Icons.description_outlined, color: _teal, size: 27)),
    const SizedBox(height: 20),
    Text(_uploads.isEmpty ? 'Every story starts somewhere.' : 'A fresh start for ${_title(_filter!).toLowerCase()}.',
      style: const TextStyle(fontFamily: 'serif', fontSize: 23, color: _ink, height: 1.2, letterSpacing: -.4)),
    const SizedBox(height: 10),
    const Text('Add a monitor reading or your weight. Your timeline and comparisons will grow with you.',
      style: TextStyle(color: _muted, fontSize: 13, height: 1.6)),
    const SizedBox(height: 18),
    FilledButton.icon(onPressed: _add, style: FilledButton.styleFrom(
      backgroundColor: _ink, foregroundColor: MedicColors.mint,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
      icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Add your reading')),
  ]));

  Widget _journalCard() => Material(color: const Color(0xFFEAEDE3),
    borderRadius: BorderRadius.circular(24), child: InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () { HapticFeedback.selectionClick();
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const JournalScreen())); },
      child: const Padding(padding: EdgeInsets.all(20), child: Row(children: [
        Icon(Icons.menu_book_outlined, color: _teal, size: 28), SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('More than numbers', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _ink)),
          SizedBox(height: 5), Text('Capture how you feel in your journal.',
              style: TextStyle(color: _muted, fontSize: 12, height: 1.4)),
        ])), SizedBox(width: 8), Icon(Icons.arrow_forward_rounded, color: _teal, size: 19),
      ])),
    ));

  Widget _profileCard() {
    final user = AuthService().currentUser;
    final health = healthMap(_profile['healthInfo']);
    final name = (_profile['fullName'] ?? user?.displayName ?? 'Your health').toString();
    final details = <String>[];
    final age = healthNumber(_profile['age']);
    if (age != null) details.add('Age ${age.toInt()}');
    final height = healthNumber(health['height']);
    final weight = healthNumber(health['weight']);
    if (weight != null) details.add('${_number(weight)} kg');
    if (height != null) details.add('${_number(height)} cm');
    return _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const MedicEyebrow('Your personal overview'),
      const SizedBox(height: 16),
      Row(children: [CircleAvatar(radius: 25, backgroundColor: MedicColors.mint.withOpacity(.55),
          child: const Icon(Icons.person_outline_rounded, color: _teal, size: 23)),
        const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: _ink, height: 1.3)),
          const SizedBox(height: 5),
          Text(details.isEmpty ? 'Your personal health timeline' : details.join('  |  '),
              style: const TextStyle(fontSize: 11, color: _muted)),
        ]))]),
      const SizedBox(height: 22),
      LayoutBuilder(builder: (context, constraints) {
        final cards = <Widget>[
          _summary(HealthMetric.bloodPressure, HealthTrend(_uploads, HealthMetric.bloodPressure).latest),
          _summary(HealthMetric.bloodSugar, HealthTrend(_uploads, HealthMetric.bloodSugar).latest),
          _scoreSummary(),
        ];
        if (constraints.maxWidth < 280) return Column(children: [for (final item in cards) Padding(
            padding: const EdgeInsets.only(bottom: 8), child: item)]);
        return Row(children: [for (var i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(width: 8), Expanded(child: cards[i]),
        ]]);
      }),
    ]));
  }

  Widget _scoreSummary() => StreamBuilder<Map<String,dynamic>>(
    stream: _uid == null ? null : HealthMonitoringService.watch(_uid!),
    builder: (context, snap) {
      final view=DailyScoreView(snap.data??{});
      return _statTile(icon: Icons.favorite_outline_rounded, color: _teal,
        value: view.text, label: 'Today’s score', unit: '${view.coverage}/5 components');
    });

  Widget _summary(HealthMetric metric, ReadingPoint? point) => _statTile(
    icon: _icon(metric), color: _color(metric),
    value: point == null ? '—' : _value(metric, point),
    label: _shortTitle(metric), unit: _unit(metric),
  );

  Widget _statTile({required IconData icon, required Color color,
      required String value, required String label, required String unit}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 15),
    decoration: BoxDecoration(
      gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [color.withOpacity(.08), color.withOpacity(.035)]),
      borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withOpacity(.09))),
    child: Column(children: [
      Icon(icon, size: 19, color: color), const SizedBox(height: 12),
      AnimatedSwitcher(duration: MediaQuery.of(context).disableAnimations ? Duration.zero : const Duration(milliseconds: 320),
        child: FittedBox(key: ValueKey(value), fit: BoxFit.scaleDown,
          child: Text(value, style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700,
            letterSpacing: -.6, color: color)))),
      const SizedBox(height: 8), Text(label, textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 10.5, color: _ink, fontWeight: FontWeight.w600)),
      const SizedBox(height: 4), Text(unit, style: const TextStyle(fontSize: 9.5, color: _muted)),
    ]),
  );

  Widget _trendCard(HealthMetric metric) {
    final trend = HealthTrend(_uploads, metric);
    final points = trend.chartPoints;
    final latest = trend.latest;
    final divisor = metric == HealthMetric.bloodSugar && _mmol ? 18.0 : 1.0;
    return Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: _canvas, borderRadius: BorderRadius.circular(20),
        border: Border.all(color: MedicColors.line.withOpacity(.6))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(_icon(metric), color: _color(metric), size: 16), const SizedBox(width: 7),
          Expanded(child: Text(_title(metric), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: _ink))),
          Text(_unit(metric), style: const TextStyle(color: _muted, fontSize: 10))]),
        if (points.isEmpty) Padding(padding: const EdgeInsets.only(top: 14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.timeline_rounded, color: _color(metric).withOpacity(.45), size: 24),
              const SizedBox(width: 10), const Expanded(child: Text(
                'Your first reading starts the trend. Add one when you’re ready.',
                style: TextStyle(fontSize: 11.5, color: _muted, height: 1.55))),
            ]))
        else ...[
          const SizedBox(height: 12),
          Semantics(label: '${_title(metric)}: ${points.map((p) => '${_date(p.at)} ${_value(metric, p)}').join(', ')}',
            child: SizedBox(height: 166, width: double.infinity,
                child: TweenAnimationBuilder<double>(
                  key: ValueKey('${metric.name}_$_mmol${points.map((p) => '${p.upload.id}:${p.value}:${p.secondary}').join('|')}'),
                  tween: Tween(begin: 0, end: 1), curve: Curves.easeOutCubic,
                  duration: MediaQuery.of(context).disableAnimations ? Duration.zero : const Duration(milliseconds: 900),
                  builder: (context, progress, child) => CustomPaint(painter: _TrendPainter(
                    points: points, color: _color(metric), divisor: divisor, progress: progress,
                    showSecondary: metric == HealthMetric.bloodPressure)),
                ))),
          if (metric == HealthMetric.bloodPressure) const Padding(
              padding: EdgeInsets.only(bottom: 8), child: Text('● Systolic     ● Diastolic (blue)',
                style: TextStyle(fontSize: 10, color: _muted))),
          if (points.length < 3) Padding(padding: const EdgeInsets.only(bottom: 8),
              child: Text('${points.length} of 3 readings available. Add more to compare.',
                  style: const TextStyle(fontSize: 11, color: _muted))),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _badge('Highest: ${_number(trend.highest!.value / divisor)} · ${_date(trend.highest!.at)}'),
            _badge('Lowest: ${_number(trend.lowest!.value / divisor)} · ${_date(trend.lowest!.at)}'),
          ]),
          const SizedBox(height: 10),
          _comparison('Vs previous reading', latest!, trend.previous, divisor, metric),
          const SizedBox(height: 5),
          _comparison(sameHealthDay(latest!.at, DateTime.now()) ? 'Vs yesterday' : 'Vs previous day',
              latest!, trend.previousDay, divisor, metric),
          if (metric == HealthMetric.bloodPressure)
            const Padding(padding: EdgeInsets.only(top: 7), child: Text(
              'Highest / lowest refer to systolic pressure. Both values are shown in the chart.',
              style: TextStyle(fontSize: 10, color: _muted, height: 1.4))),
        ],
      ],
    ));
  }

  Widget _comparison(String title, ReadingPoint current, ReadingPoint? baseline,
      double divisor, HealthMetric metric) {
    final delta = baseline == null ? null : (current.value - baseline.value) / divisor;
    String changeText(double value) => value.abs() < .05 ? 'No change at displayed precision'
        : '${value > 0 ? '+' : '−'}${_number(value.abs())} ${_unit(metric)} ${value > 0 ? 'higher' : 'lower'}';
    var text = delta == null ? 'No reading available' : changeText(delta);
    if (metric == HealthMetric.bloodPressure && baseline != null) {
      text = 'Systolic: $text';
      final currentDiastolic = current.secondary;
      final previousDiastolic = baseline.secondary;
      text += currentDiastolic == null || previousDiastolic == null
          ? '; diastolic: unavailable'
          : '; diastolic: ${changeText(currentDiastolic - previousDiastolic)}';
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(delta == null ? Icons.remove_rounded : delta.abs() < .05 ? Icons.trending_flat_rounded
          : delta > 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
          color: _muted, size: 16), const SizedBox(width: 7),
      Expanded(child: Text('$title: $text${baseline == null ? '' : ' (${_date(baseline.at)}, ${_time(baseline.at)})'}',
          style: const TextStyle(fontSize: 11, color: _ink, height: 1.4))),
    ]);
  }

  Widget _badge(String text) => Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(color: MedicColors.mint.withOpacity(.35), borderRadius: BorderRadius.circular(10)),
    child: Text(text, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _teal)));

  Widget _uploadCard(HealthUpload upload) {
    final metrics = HealthMetric.values.where((m) => (_filter == null || _filter == m) && upload.reading(m) != null).toList();
    return _card(Column(children: [
      Row(children: [const Expanded(child: MedicEyebrow('Recorded reading')),
        Text(_time(upload.at), style: const TextStyle(fontSize: 11, color: _muted))]),
      if (healthNumber(healthMap(upload.data['hba1c'])['value']) != null) Padding(padding: const EdgeInsets.only(top: 14), child: Align(alignment: Alignment.centerLeft,
        child: Text('HbA1c lab: ${healthMap(upload.data['hba1c'])['value']}% · separate from meter glucose', style: const TextStyle(fontSize: 12, color: _ink)))),
      if (metrics.isEmpty && healthMap(upload.data['hba1c']).isEmpty) const Padding(padding: EdgeInsets.only(top: 10),
          child: Text('This upload has no supported numeric readings.')),
      for (final metric in metrics) Padding(padding: const EdgeInsets.only(top: 12), child: Row(children: [
        Container(width: 36, height: 36, decoration: BoxDecoration(color: _color(metric).withOpacity(.08),
            borderRadius: BorderRadius.circular(12)), child: Icon(_icon(metric), color: _color(metric), size: 18)),
        const SizedBox(width: 11), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_title(metric), style: const TextStyle(color: _muted, fontSize: 11)),
          const SizedBox(height: 4), Text('${_value(metric, upload.reading(metric)!)} ${_unit(metric)}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _ink)),
          if (metric == HealthMetric.bloodPressure && healthNumber(healthMap(upload.data['bloodPressure'])['pulse']) != null)
            Text('Pulse ${_number(healthNumber(healthMap(upload.data['bloodPressure'])['pulse'])!)} bpm',
                style: const TextStyle(fontSize: 10, color: _muted)),
        ])),
      ])),
      for (final key in ['bloodPressure', 'bloodSugar'])
        if ((_filter == null || (_filter == HealthMetric.bloodPressure ? key == 'bloodPressure' :
            _filter == HealthMetric.bloodSugar ? key == 'bloodSugar' : false)) &&
            healthMap(healthMap(upload.data[key])['summary'])['label'] != null)
          Padding(padding: const EdgeInsets.only(top: 14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(healthMap(healthMap(upload.data[key])['summary'])['label'].toString(),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _ink)),
            const SizedBox(height: 5), Text((healthMap(healthMap(upload.data[key])['summary'])['message'] ?? '').toString(),
              style: const TextStyle(fontSize: 11, color: _muted, height: 1.5)),
          ])),
    ]));
  }

  Widget _errorCard() {
    final permission = _error is FirebaseException && (_error as FirebaseException).code == 'permission-denied';
    return _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Could not update health records', style: TextStyle(fontWeight: FontWeight.w700, color: _ink)),
      const SizedBox(height: 6), Text(permission ? 'Your account cannot access these records. Please contact support.'
          : 'Check your connection and retry. Any loaded records remain visible.',
          style: const TextStyle(fontSize: 12, color: _muted)),
      TextButton(onPressed: _refresh, child: const Text('Retry')),
    ]));
  }

  Widget _card(Widget child) => Container(width: double.infinity, padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(26),
      border: Border.all(color: MedicColors.line.withOpacity(.75)),
      boxShadow: [BoxShadow(color: _ink.withOpacity(.025), blurRadius: 22, offset: const Offset(0, 7))]), child: child);
  String _value(HealthMetric metric, ReadingPoint point) => metric == HealthMetric.bloodPressure
      ? '${_number(point.value)}/${point.secondary == null ? '—' : _number(point.secondary!)}'
      : _number(point.value / (metric == HealthMetric.bloodSugar && _mmol ? 18 : 1));
  String _unit(HealthMetric metric) => metric == HealthMetric.bloodPressure ? 'mmHg'
      : metric == HealthMetric.bloodSugar ? (_mmol ? 'mmol/L' : 'mg/dL') : 'kg';
  String _shortTitle(HealthMetric metric) => metric == HealthMetric.bloodPressure ? 'Latest BP'
      : metric == HealthMetric.bloodSugar ? 'Latest Sugar' : 'Latest Weight';
}

String _title(HealthMetric metric) => metric == HealthMetric.bloodPressure ? 'Blood Pressure'
    : metric == HealthMetric.bloodSugar ? 'Blood Sugar' : 'Weight';
Color _color(HealthMetric metric) => metric == HealthMetric.bloodPressure ? _rose
    : metric == HealthMetric.bloodSugar ? _teal : _amber;
IconData _icon(HealthMetric metric) => metric == HealthMetric.bloodPressure ? Icons.favorite_border_rounded
    : metric == HealthMetric.bloodSugar ? Icons.water_drop_outlined : Icons.monitor_weight_outlined;
String _number(double value) => (value - value.round()).abs() < .000001
    ? value.round().toString() : value.toStringAsFixed(1);
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
String _date(DateTime date) => '${date.day} ${_months[date.month - 1]}';
String _day(DateTime date) => '${_date(date)} ${date.year}'.toUpperCase();
String _time(DateTime date) => '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

class _TrendPainter extends CustomPainter {
  final List<ReadingPoint> points;
  final Color color;
  final double divisor;
  final bool showSecondary;
  final double progress;
  const _TrendPainter({required this.points, required this.color,
    required this.divisor, required this.showSecondary, this.progress = 1});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty || size.width < 90) return;
    final values = points.map((p) => p.value / divisor).toList();
    final secondary = showSecondary ? points.map((p) => p.secondary).whereType<double>().toList() : <double>[];
    final all = [...values, ...secondary];
    final low = all.reduce(math.min);
    final high = all.reduce(math.max);
    final padding = math.max((high - low) * .22, math.max(high.abs() * .04, 1.0));
    final minY = math.max(0.0, low - padding);
    final maxY = high + padding;
    const left = 37.0;
    final right = size.width - 25;
    const top = 20.0;
    final bottom = size.height - 37;
    double x(int i) => points.length == 1 ? (left + right) / 2
        : left + (right-left) * i / (points.length-1);
    double y(double value) => bottom - (value-minY) / (maxY-minY) * (bottom-top);
    for (var i = 0; i < 3; i++) {
      final value = minY + (maxY-minY) * i / 2;
      canvas.drawLine(Offset(left, y(value)), Offset(right, y(value)), Paint()..color = MedicColors.line.withOpacity(.55));
      _text(canvas, _number(value), Offset(0, y(value)-5), _muted, 9);
    }
    void series(List<double?> numbers, Color tone) {
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(left - 8, 0, left + (right - left) * progress + 8, size.height));
      final pen = Paint()..color = tone..strokeWidth = 2.2..style = PaintingStyle.stroke;
      final path = Path();
      var connected = false;
      for (var i = 0; i < numbers.length; i++) {
        final value = numbers[i];
        if (value == null) { connected = false; continue; }
        if (connected) { path.lineTo(x(i), y(value)); }
        else { path.moveTo(x(i), y(value)); connected = true; }
      }
      canvas.drawPath(path, pen);
      for (var i = 0; i < numbers.length; i++) {
        final value = numbers[i];
        if (value == null) continue;
        final at = Offset(x(i), y(value));
        canvas.drawCircle(at, 4, Paint()..color = Colors.white);
        canvas.drawCircle(at, 4, pen);
      }
      canvas.restore();
    }
    series(values.map<double?>((v) => v).toList(), color);
    if (showSecondary) series(points.map((p) => p.secondary).toList(), MedicColors.c477C91);
    for (var i = 0; i < points.length; i++) {
      final value = values[i];
      _text(canvas, _number(value), Offset(x(i), y(value)-17), color, 10, center: true);
      _text(canvas, _date(points[i].at), Offset(x(i), bottom+10), _muted, 9, center: true);
      _text(canvas, _time(points[i].at), Offset(x(i), bottom+22), _muted, 8, center: true);
    }
  }

  void _text(Canvas canvas, String text, Offset at, Color color, double fontSize, {bool center = false}) {
    final painter = TextPainter(text: TextSpan(text: text, style: TextStyle(
        color: color, fontSize: fontSize, fontWeight: FontWeight.w500)), textDirection: TextDirection.ltr)..layout();
    painter.paint(canvas, Offset(at.dx - (center ? painter.width/2 : 0), at.dy));
  }
  @override
  bool shouldRepaint(covariant _TrendPainter old) => old.points != points ||
      old.color != color || old.divisor != divisor || old.showSecondary != showSecondary || old.progress != progress;
}
