import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'health_score_service.dart';
import 'vital_summary_service.dart';

/// Local report fallback. It never sends push messages or writes server summaries.
class LocalMonitoringEngine {
  static bool _ready=false;
  static Map<String,dynamic> _m(Object? v)=>scoreMap(v);
  static double? _n(Object? v)=>scoreNumber(v);
  static String _day(DateTime at,tz.Location zone){final d=tz.TZDateTime.from(at,zone);return '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';}
  static double? _avg(Iterable<Object?> values){final v=values.whereType<num>().toList();return v.isEmpty?null:(v.reduce((a,b)=>a+b)/v.length*10).round()/10;}
  static bool _high(Map<String,dynamic> d,String key)=>['high','urgent'].contains(_m(d[key])['level']);
  static int _run(List<Map<String,dynamic>> days,String key){var n=0;for(final d in days.reversed){if(!_high(d,key))break;n++;}return n;}
  static bool _trend(List<Map<String,dynamic>> days,String key,String field,{bool reverse=false}){
    if(days.length<3)return false;final d=days.sublist(days.length-3);
    if(d.any((v)=>_n(_m(v[key])[field])==null))return false;
    if(key=='glucose' && d.any((v)=>_m(v[key])['context']=='unknown'||_m(v[key])['context']!=_m(d.first[key])['context']))return false;
    final a=_n(_m(d[1][key])[field])!-_n(_m(d[0][key])[field])!,b=_n(_m(d[2][key])[field])!-_n(_m(d[1][key])[field])!;
    return reverse?a*b<0:a>0&&b>0;
  }
  static Map<String,dynamic> _analyze(List<Map<String,dynamic>> days){
    final today=days.last,flags=<Map<String,dynamic>>[];var severity='info';
    void add(String code,String level,String text){flags.add({'code':code,'level':level,'text':text});if(['info','watch','high','urgent'].indexOf(level)>['info','watch','high','urgent'].indexOf(severity))severity=level;}
    for(final key in ['glucose','pressure']){
      final metric=_m(today[key]),name=key=='glucose'?'Glucose':'Blood pressure',run=_run(days,key);
      if(metric['level']=='urgent')add('urgent_$key','urgent','$name needs urgent reading review. Confirm the reading and follow the urgent guidance.');
      if(run>=4)add('${key}_persistent4','high','$name is above its reference on $run consecutive calendar days. Arrange prompt clinician review.');
      else if(run>=3)add('${key}_persistent3','high','$name is above its reference on 3 consecutive calendar days. Share the log with your care team.');
      else if(_high(today,key))add('${key}_high','watch','$name is above its reference today.');
      if(metric['level']=='low')add('${key}_low','high','$name is below its reference. Follow your care plan and seek help if unwell.');
    }
    if(_trend(days,'glucose','value')||_trend(days,'pressure','systolic')||_trend(days,'pressure','diastolic'))add('rising3','watch','Readings increased across three consecutive calendar days. This numerical trend does not prove deterioration.');
    if(_trend(days,'glucose','value',reverse:true)||_trend(days,'pressure','systolic',reverse:true)||_trend(days,'pressure','diastolic',reverse:true))add('fluctuation','watch','Readings changed direction across three days; context and measurement conditions matter.');
    if((_n(_m(today['a1c'])['value'])??0)>=7)add('lab_review','watch','The HbA1c lab value is above the general adult diabetes target. Review it with your clinician; it is separate from daily glucose.');
    if((today['missed'] as int)>0)add('missed','watch',"${today['missed']} due dose(s) are unconfirmed after the grace period. Do not take extra or catch-up doses based on this app.");
    if((today['missed'] as int)>0&&(_high(today,'glucose')||_high(today,'pressure')))add('cooccurrence','watch','High readings and unconfirmed doses occurred on the same day. These records do not establish cause.');
    double? delta;
    if(days.length>1){final old=days[days.length-2],parts=_m(today['components']),before=_m(old['components']);
      if(parts.values.any((v)=>v!=null)&&parts.keys.every((k)=>(parts[k]!=null)==(before[k]!=null)))delta=((today['score'] as num)-(old['score'] as num))*1.0;
    }
    return {'severity':severity,'title':severity=='urgent'?'Urgent reading review':severity=='high'?'Persistent or low reading alert':severity=='watch'?'Your readings need attention':today['observed']==true?'Your daily summary':'More measurements needed',
      'flags':flags,'delta':delta==null?null:(delta*10).round()/10,'glucoseHighDays':_run(days,'glucose'),'pressureHighDays':_run(days,'pressure'),
      'action':severity=='urgent'?'Check the urgent-reading guidance now. Serious symptoms need immediate emergency help; do not wait for a caregiver reply.':severity=='high'?'Arrange clinician review and share your records. Continue medicines only as prescribed.':'Keep recording comparable readings and follow your prescribed schedule.',
      'note':'Awareness estimates, not a diagnosis. Missing days break consecutive-day patterns. HbA1c is separate from daily glucose. No causal conclusion is made.'};
  }
  static Map<String,dynamic> build({required String uid,required Map<String,dynamic> profile,required List<Map<String,dynamic>> vitals,
      required List<Map<String,dynamic>> doses,Map<String,dynamic> settings=const {},DateTime? asOf}){
    if(!_ready){tzdata.initializeTimeZones();_ready=true;}
    var zoneName=settings['timeZone']?.toString()??'Asia/Kuala_Lumpur';tz.Location zone;
    try{zone=tz.getLocation(zoneName);}catch(_){zoneName='Asia/Kuala_Lumpur';zone=tz.getLocation(zoneName);}
    final now=asOf??DateTime.now(),localNow=tz.TZDateTime.from(now,zone);
    final days=List.generate(7,(i)=> <String,dynamic>{'date':_day(tz.TZDateTime(zone,localNow.year,localNow.month,localNow.day+i-6,12),zone),
      'pressure':null,'glucose':null,'a1c':null,'taken':0,'missed':0,'pending':0,'scheduled':0,'due':0,'adherence':null,
      'bmi':null,'age':null,'bmiScore':null,'ageScore':null,'components':<String,dynamic>{},'score':null,'coverage':0,'observed':false,'latestReadingAt':null});
    final byDate={for(final d in days)d['date']:d};
    DateTime? at(Map<String,dynamic> r)=>scoreDate(r['measuredAt'])??scoreDate(r['recordedAt'])??scoreDate(r['clientRecordedAt']);
    final records=vitals.where((r)=>at(r)!=null&&!at(r)!.isAfter(now)).toList()..sort((a,b){final c=at(a)!.compareTo(at(b)!);return c==0?'${a['id']}'.compareTo('${b['id']}'):c;});
    for(final r in records){final date=at(r)!,day=byDate[_day(date,zone)];if(day==null)continue;
      final p=_m(r['bloodPressure']),g=_m(r['bloodSugar']),lab=_m(r['hba1c']),sys=_n(p['systolic']),dia=_n(p['diastolic']);
      if(sys!=null&&sys>0&&dia!=null&&dia>0){final s=VitalSummaryService.bloodPressure(sys.round(),dia.round());day['pressure']={'systolic':sys,'diastolic':dia,'score':s.awarenessScore,'level':s.level,'label':s.label,'at':date.toUtc().toIso8601String(),'sourceId':r['id']};}
      final unit='${g['unit']??''}'.toLowerCase(),raw=_n(g['value']);
      final mg=unit.contains('mmol')?(raw??_n(g['valueMmol']))==null?null:(raw??_n(g['valueMmol']))!*18:unit.contains('mg')?raw:null;
      if(mg!=null&&mg>0){final context=g['readingContext']?.toString()??'unknown',s=VitalSummaryService.glucose(mg,context:context);day['glucose']={'value':mg,'unit':'mg/dL','context':context,'score':s.awarenessScore,'level':s.level,'label':s.label,'at':date.toUtc().toIso8601String(),'sourceId':r['id']};}
      final a1c=_n(lab['value']);if(a1c!=null&&a1c>0&&a1c<=25)day['a1c']={'value':a1c,'unit':'%','at':date.toUtc().toIso8601String()};
      final snap=HealthScoreSnapshot.fromUpload(r);if(_n(snap.signals['bmiValue'])!=null){day['bmi']=snap.signals['bmiValue'];day['bmiScore']=snap.components['bmi'];}
      if(_n(snap.signals['ageYears'])!=null){day['age']=snap.signals['ageYears'];day['ageScore']=snap.components['age'];}
      day['observed']=true;day['latestReadingAt']=date.toUtc().toIso8601String();
    }
    for(final e in doses){final date=scoreDate(e['dueAt']);if(date==null||e['status']=='cancelled')continue;final day=byDate[_day(date,zone)];if(day==null)continue;day['scheduled']=(day['scheduled'] as int)+1;
      if(date.isAfter(now)){day['pending']=(day['pending'] as int)+1;continue;}
      final key=e['status']=='taken'?'taken':e['status']=='missed'||now.difference(date)>const Duration(minutes:20)?'missed':'pending';
      day[key]=(day[key] as int)+1;if(key!='pending')day['due']=(day['due'] as int)+1;
    }
    final stat=HealthScoreSnapshot.fromProfile(profile,at:localNow);
    for(var i=0;i<days.length;i++){final day=days[i];if(i==6){day['bmi']??=stat.signals['bmiValue'];day['bmiScore']??=stat.components['bmi'];day['age']??=stat.signals['ageYears'];day['ageScore']??=stat.components['age'];}
      day['adherence']=(day['due'] as int)>0?((day['taken'] as int)/(day['due'] as int)*1000).round()/10:null;
      day['components']={'bloodPressure':_m(day['pressure'])['score'],'bloodSugar':_m(day['glucose'])['score'],'adherence':day['adherence'],'bmi':day['bmiScore'],'age':day['ageScore']};
      day['coverage']=_m(day['components']).values.whereType<num>().length;final score=_avg(_m(day['components']).values);day['score']=score;
      day['scoreBand']=score==null?'No score':score>=90?'Excellent app score':score>=75?'Good app score':score>=60?'Moderate app score':score>=40?'Low app score':'Very low app score';
      if(i>0){final old=days[i-1],p=_m(day['pressure']),b=_m(old['pressure']),g=_m(day['glucose']),prev=_m(old['glucose']);
        day['pressureDelta']=p.isNotEmpty&&b.isNotEmpty?{'systolic':(p['systolic'] as num)-(b['systolic'] as num),'diastolic':(p['diastolic'] as num)-(b['diastolic'] as num)}:null;
        day['glucoseDelta']=g.isNotEmpty&&prev.isNotEmpty&&g['context']!='unknown'&&g['context']==prev['context']?((g['value'] as num)-(prev['value'] as num)):null;
      }
      day['dailyAnalysis']=_analyze(days.sublist(0,i+1));
    }
    final today=days.last,analysis=_analyze(days),due=days.fold<int>(0,(a,d)=>a+(d['due'] as int)),taken=days.fold<int>(0,(a,d)=>a+(d['taken'] as int));
    final observed=days.where((d)=>d['observed']==true||(d['due'] as int)>0).toList();
    final urgent=[_m(today['pressure']),_m(today['glucose'])].where((m)=>m['level']=='urgent').toList()..sort((a,b)=>DateTime.parse(b['at']).compareTo(DateTime.parse(a['at'])));
    final u=urgent.isEmpty?<String,dynamic>{}:urgent.first,when=scoreDate(u['at']);Map<String,dynamic>? original;
    for(final r in records){if(r['id']==u['sourceId'])original=r;}
    final received=scoreDate(original?['recordedAt']),live=when!=null&&received!=null&&!when.isAfter(now)&&!received.isAfter(now)&&now.difference(when)<const Duration(minutes:15)&&now.difference(received)<const Duration(minutes:15);
    final labs=days.map((d)=>_m(d['a1c'])).where((l)=>l.isNotEmpty).toList();
    return {'version':1,'source':'saved_records','timeZone':zoneName,'days':days,'analysis':analysis,'eventId':'local:$uid:${u['sourceId']??today['date']}',
      'liveUrgent':live,'urgentReadingAt':u['at'],'updatedAt':now,'summary':{'averageScore':_avg(observed.map((d)=>d['score'])),'scoreDays':observed.where((d)=>d['score']!=null).length,
        'taken':taken,'due':due,'adherence':due>0?(taken/due*1000).round()/10:null,'glucoseAverage':_avg(days.map((d)=>_m(d['glucose'])['value'])),
        'systolicAverage':_avg(days.map((d)=>_m(d['pressure'])['systolic'])),'diastolicAverage':_avg(days.map((d)=>_m(d['pressure'])['diastolic'])),
        'measuredDays':days.where((d)=>d['observed']==true).length,'aboveReferenceGlucoseDays':days.where((d)=>_high(d,'glucose')).length,'aboveReferencePressureDays':days.where((d)=>_high(d,'pressure')).length,
        'urgentDays':days.where((d)=>_m(d['pressure'])['level']=='urgent'||_m(d['glucose'])['level']=='urgent').map((d)=>d['date']).toList(),
        'cooccurrenceDays':days.where((d)=>(d['missed'] as int)>0&&(_high(d,'glucose')||_high(d,'pressure'))).map((d)=>d['date']).toList(),'latestA1c':labs.isEmpty?null:labs.last}};
  }
}
