import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_core/firebase_core.dart';
import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'local_monitoring_engine.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

class HealthMonitoringService {
  static final _feeds=<String,_MonitoringFeed>{};
  static Stream<Map<String,dynamic>> watch(String uid)=>Stream.multi((sink){
    final feed=_feeds.putIfAbsent(uid,()=>_MonitoringFeed(uid));feed.users++;
    final sub=feed.output.stream.listen(sink.add,onError:sink.addError);
    if(feed.latest!=null)sink.add(feed.latest!);
    if(feed.users==1)feed.start();
    sink.onCancel=()async{await sub.cancel();if(--feed.users==0){_feeds.remove(uid);await feed.close();}};
  });
  static Future<Map<String,String>> registerAndCheckPush() async {
    final uid=FirebaseAuth.instance.currentUser?.uid;
    if(uid==null)throw StateError('Sign in before enabling notifications.');
    final messaging=FirebaseMessaging.instance;
    final permission=await messaging.requestPermission(alert:true,badge:true,sound:true);
    final token=await messaging.getToken().timeout(const Duration(seconds:15));
    final result=<String,String>{'Notification permission':permission.authorizationStatus.name,
      'Device token':token==null||token.isEmpty?'Unavailable':'Available','Device registration':'Not registered',
      'Firebase project':Firebase.app().options.projectId};
    if(token!=null&&token.isNotEmpty){
      await FirebaseFirestore.instance.doc('user_tokens/$uid').set({'userId':uid,'tokens':FieldValue.arrayUnion([token]),
        'updatedAt':FieldValue.serverTimestamp()},SetOptions(merge:true)).timeout(const Duration(seconds:15));
      result['Device registration']='Saved';
    }
    return result;
  }
  static String errorMessage(Object error) {
    final code=error is FirebaseFunctionsException?error.code:error is FirebaseException?error.code:'unknown';
    switch(code){
      case 'not-found':case 'unimplemented':return 'Push monitoring is not configured yet. Saved records remain available.';
      case 'unauthenticated':return 'Push refresh could not verify your session or App Check. Sign in again; saved records remain available.';
      case 'permission-denied':return 'Access was denied. Check the patient’s sharing permissions.';
      case 'unavailable':case 'deadline-exceeded':return 'Push refresh is temporarily unavailable. Showing saved records.';
      case 'failed-precondition':return 'The monitoring service needs configuration. Showing saved records.';
      default:return 'Push refresh could not finish ($code). Showing saved records when accessible.';
    }
  }
  static Future<void> refresh({String? ownerId}) async {
    await FirebaseFunctions.instanceFor(region: 'asia-southeast1').httpsCallable('refreshHealthMonitoring',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 15))).call({'ownerId': ownerId});
  }
  static Map<String, dynamic> map(Object? v) => v is Map ? Map<String, dynamic>.from(v) : {};
  static List<Map<String, dynamic>> days(Map<String, dynamic> state) =>
      (state['days'] is List ? state['days'] as List : const []).map(map).toList();
  static String value(Object? v) => v is num ? (v == v.roundToDouble() ? '${v.toInt()}' : v.toStringAsFixed(1)) : '—';
  static String reportText(Map<String, dynamic> state) {
    final days = HealthMonitoringService.days(state); final analysis = map(state['analysis']), summary = map(state['summary']);
    final out = StringBuffer('MEDICTRACK · 7-DAY HEALTH MONITORING REPORT\n');
    out.writeln('Timezone: ${state['timeZone'] ?? 'Unknown'}');
    if (days.isNotEmpty) out.writeln('Period: ${days.first['date']} to ${days.last['date']}');
    out.writeln('Status: ${analysis['title'] ?? 'Unavailable'}');
    out.writeln('Average available daily app score: ${value(summary['averageScore'])}/100 (${summary['scoreDays'] ?? 0} observed days)');
    out.writeln('Doses confirmed: ${summary['taken'] ?? 0}/${summary['due'] ?? 0} eligible due (${value(summary['adherence'])}%)');
    out.writeln('Mean daily glucose: ${value(summary['glucoseAverage'])} mg/dL; mean BP: ${value(summary['systolicAverage'])}/${value(summary['diastolicAverage'])} mmHg.');
    out.writeln('Above-reference days: glucose ${summary['aboveReferenceGlucoseDays'] ?? 0}, BP ${summary['aboveReferencePressureDays'] ?? 0}');
    out.writeln('Urgent-reading days: ${(summary['urgentDays'] as List? ?? []).join(', ')}');
    out.writeln('High readings + unconfirmed doses: ${(summary['cooccurrenceDays'] as List? ?? []).join(', ')} (co-occurrence, not causation)');
    out.writeln('\nDAILY LOG · latest measurement per metric/day');
    for (final day in days) {
      final p=map(day['pressure']), g=map(day['glucose']), a=map(day['a1c']);
      out.writeln('${day['date']} · score ${value(day['score'])}/100 · ${day['coverage']}/5 components');
      out.writeln('Glucose: ${value(g['value'])} mg/dL · ${g['context'] ?? 'not recorded'} · ${g['label'] ?? 'unavailable'}');
      out.writeln('BP: ${value(p['systolic'])}/${value(p['diastolic'])} mmHg · ${p['label'] ?? 'unavailable'}');
      final daily = map(day['dailyAnalysis']);
      out.writeln('Daily status: ${daily['title'] ?? 'Not assessed'}');
      for (final flag in (daily['flags'] as List? ?? [])) out.writeln(map(flag)['text'] ?? '');
      out.writeln('Doses ${day['taken']}/${day['due']} eligible due · ${day['missed']} unconfirmed · ${day['pending']} pending');
      out.writeln('BMI ${value(day['bmi'])} · age ${value(day['age'])} · HbA1c lab ${value(a['value'])}%');
    }
    out.writeln('\nOBSERVED PATTERNS');
    for (final flag in (analysis['flags'] is List ? analysis['flags'] as List : const [])) out.writeln(map(flag)['text'] ?? '');
    out.writeln(analysis['action'] ?? '');out.writeln('\n${analysis['note'] ?? ''}');
    out.writeln('Cross-check with your healthcare team. Do not change or catch up medication doses based on this report. Serious symptoms need immediate emergency help.');
    return out.toString();
  }
}


class _MonitoringFeed {
  final String uid;
  _MonitoringFeed(this.uid);
  final output=StreamController<Map<String,dynamic>>.broadcast();
  final subs=<StreamSubscription>[];
  int users=0;
  Map<String,dynamic>? latest,server,profile,settings;
  List<Map<String,dynamic>>? vitals,doses;
  Object? localError;
  Timer? debounce,tick;
  bool closed=false;
  void start(){
    final db=FirebaseFirestore.instance;
    void failed(Object e){localError=e;_queue();}
    subs.add(db.doc('users/$uid/monitoring_state/current').snapshots().listen((s){server=s.data();_queue();},onError:(Object e){debugPrint('Monitoring state read: ${e is FirebaseException?e.code:e.runtimeType}');_queue();}));
    subs.add(db.doc('users/$uid').snapshots().listen((s){profile=s.data()??{};_queue();},onError:failed));
    subs.add(db.collection('users/$uid/vitals').where('recordedAt',isGreaterThanOrEqualTo:Timestamp.fromDate(DateTime.now().subtract(const Duration(days:35))))
      .snapshots().listen((s){vitals=s.docs.map((d)=><String,dynamic>{'id':d.id,...d.data()}).toList();_queue();},onError:failed));
    subs.add(db.collection('users/$uid/dose_events').where('dueAt',isGreaterThanOrEqualTo:Timestamp.fromDate(DateTime.now().subtract(const Duration(days:9))))
      .snapshots().listen((s){doses=s.docs.map((d)=>d.data()).toList();_queue();},onError:failed));
    if(FirebaseAuth.instance.currentUser?.uid==uid){subs.add(db.doc('users/$uid/settings/monitoring').snapshots().listen((s){settings=s.data()??{};_queue();},onError:(Object _){settings={};_queue();}));}
    else settings={};
    tick=Timer.periodic(const Duration(minutes:1),(_)=>_queue());
  }
  void _queue(){if(closed)return;debounce?.cancel();debounce=Timer(const Duration(milliseconds:150),_emit);}
  Object? _canonical(Object? v){
    if(v is num)return v.toDouble();
    if(v is Map){final keys=v.keys.map((k)=>k.toString()).toList()..sort();return {for(final k in keys)k:_canonical(v[k])};}
    if(v is List)return v.map(_canonical).toList();return v;
  }
  String _signature(Map<String,dynamic> data)=>jsonEncode(_canonical([data['timeZone'],HealthMonitoringService.days(data).map((d)=>[
    d['date'],d['components'],d['taken'],d['missed'],d['pending'],
    HealthMonitoringService.map(d['pressure'])['at'],HealthMonitoringService.map(d['pressure'])['systolic'],HealthMonitoringService.map(d['pressure'])['diastolic'],
    HealthMonitoringService.map(d['glucose'])['at'],HealthMonitoringService.map(d['glucose'])['value'],HealthMonitoringService.map(d['glucose'])['context'],
    HealthMonitoringService.map(d['a1c'])['value'],HealthMonitoringService.map(d['a1c'])['at']]).toList()]));
  void _emit(){
    if(closed)return;
    final validServer=server!=null&&HealthMonitoringService.days(server!).isNotEmpty;
    if(profile!=null&&vitals!=null&&doses!=null&&settings!=null){
      try{final local=LocalMonitoringEngine.build(uid:uid,profile:profile!,vitals:vitals!,doses:doses!,settings:{...settings!,if(settings!['timeZone']==null&&server?['timeZone']!=null)'timeZone':server!['timeZone']});
        latest=validServer&&_signature(server!)==_signature(local)?{...server!,'source':'server'}:local;
        output.add(latest!);return;
      }catch(error){localError=error;}
    }
    if(validServer){latest={...server!,'source':'server'};output.add(latest!);}
    else if(localError!=null){output.addError(localError!);}
  }
  Future<void> close()async{closed=true;debounce?.cancel();tick?.cancel();for(final sub in subs){await sub.cancel();}await output.close();}
}
