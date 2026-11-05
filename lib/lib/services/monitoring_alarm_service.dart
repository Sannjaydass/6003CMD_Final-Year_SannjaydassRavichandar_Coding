import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'health_monitoring_service.dart';

/// Foreground audio only. Background alerts use the OS notification channel;
/// this service does not bypass silent mode, DND or volume restrictions.
class MonitoringAlarmService extends ChangeNotifier with WidgetsBindingObserver {
  static final instance = MonitoringAlarmService._();
  MonitoringAlarmService._();
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription? _auth, _state, _settings;
  String? _uid, _event, _dismissed;
  int _generation=0;
  bool _enabled = true, _resumed = true;
  Map<String, dynamic>? _pending;
  bool active = false;
  String message = '', audioStatus = '';
  void start() {
    if (_auth != null) return;
    WidgetsBinding.instance.addObserver(this);
    _resumed = WidgetsBinding.instance.lifecycleState == null || WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _auth = FirebaseAuth.instance.authStateChanges().listen((user) async {
      final generation=++_generation;
      await _state?.cancel(); await _settings?.cancel(); await stop();
      if(generation!=_generation)return;
      _uid=user?.uid; _pending=null; _event=null; _enabled=true;
      final uid=_uid; if(uid==null)return;
      _dismissed=(await SharedPreferences.getInstance()).getString('monitoring_dismissed_$uid');
      if (_uid != uid || generation!=_generation) return;
      _settings=FirebaseFirestore.instance.doc('users/$uid/settings/monitoring').snapshots().listen((snap) {
        _enabled=snap.data()?['alarmEnabled'] != false;
        if(!_enabled) { stop(); } else { _consider(); }
      }, onError: (Object _) {});
      _state=HealthMonitoringService.watch(uid).listen((snap) { _pending=snap; _consider(); }, onError: (Object _) {});
    });
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed=state==AppLifecycleState.resumed;
    if(!_resumed) { stop(); } else { _consider(); }
  }
  Future<void> _consider() async {
    final data=_pending;if(data==null||!_enabled||!_resumed||data['liveUrgent']!=true)return;
    final id=data['urgentReadingAt']==null?null:'$_uid:${data['urgentReadingAt']}';
    final at=DateTime.tryParse('${data['urgentReadingAt']}');
    if(id==null||id==_dismissed||id==_event||at==null||DateTime.now().difference(at).inMinutes>=15||at.isAfter(DateTime.now()))return;
    _event=id;active=true;message=HealthMonitoringService.map(data['analysis'])['action']?.toString()??'A new reading needs urgent review.';
    audioStatus='Starting alarm…';notifyListeners();
    try {
      await _player.setReleaseMode(ReleaseMode.loop);
      if (!active || !_resumed || !_enabled) return;
      await _player.play(AssetSource('audio/health_alert.wav'),volume:1);
      if (!active || !_resumed || !_enabled) { await _player.stop(); return; }
      if(active) audioStatus='Alarm playback started · volume follows device settings';
    } catch (_) { audioStatus='Audio unavailable · read the urgent guidance below'; }
    notifyListeners();
  }
  Future<void> stop({bool dismiss = false}) async {
    if(dismiss && _uid!=null && _event!=null) {
      _dismissed=_event;(await SharedPreferences.getInstance()).setString('monitoring_dismissed_$_uid',_event!);
    }
    active=false;await _player.stop();notifyListeners();
  }
}
