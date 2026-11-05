import '../../services/daily_score_view.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../design/medic_design.dart';
import '../../services/health_monitoring_service.dart';
import 'vitals_upload_screen.dart';
import 'dose_history_screen.dart';

class HealthMonitoringScreen extends StatefulWidget {
  final String? ownerId;
  const HealthMonitoringScreen({super.key,this.ownerId});
  @override
  State<HealthMonitoringScreen> createState()=>_HealthMonitoringScreenState();
}
class _HealthMonitoringScreenState extends State<HealthMonitoringScreen> with SingleTickerProviderStateMixin {
  late final String? _uid;
  bool get _canEdit => _uid != null && _uid == FirebaseAuth.instance.currentUser?.uid;
  late final AnimationController _entrance;
  bool _refreshing=false;
  String? _error;
  @override
  void initState(){super.initState();_uid=widget.ownerId??FirebaseAuth.instance.currentUser?.uid;_entrance=AnimationController(vsync:this,duration:const Duration(milliseconds:700))..forward();_refresh();}
  @override
  void didChangeDependencies(){super.didChangeDependencies();if(MediaQuery.of(context).disableAnimations)_entrance.value=1;}
  @override
  void dispose(){_entrance.dispose();super.dispose();}
  Future<void> _refresh() async {
    if(_uid==null||_refreshing)return;
    setState((){_refreshing=true;_error=null;});
    try{await HealthMonitoringService.refresh(ownerId:_uid);}
    catch(error){debugPrint('Monitoring refresh failed: $error');if(mounted)setState(()=>_error=HealthMonitoringService.errorMessage(error));}
    finally{if(mounted)setState(()=>_refreshing=false);}
  }
  Color _color(String? severity)=>severity=='urgent'||severity=='high'?MedicColors.cC05256:severity=='watch'?MedicColors.cB77A27:MedicColors.green;
  Widget _card(Widget child)=>Container(width:double.infinity,margin:const EdgeInsets.only(bottom:16),padding:const EdgeInsets.all(22),
    decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(26),border:Border.all(color:MedicColors.line),
      boxShadow:[BoxShadow(color:MedicColors.forest.withOpacity(.025),blurRadius:20,offset:const Offset(0,7))]),child:child);
  String _v(Object? value)=>HealthMonitoringService.value(value);
  @override
  Widget build(BuildContext context)=>Scaffold(backgroundColor:MedicColors.canvas,body:Column(children:[
    MedicPageTitle(title:'Health monitoring',subtitle:'Your daily picture. Your seven-day story.',trailing:IconButton(
      tooltip:'Caregiver and alarm settings',onPressed:!_canEdit?null:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const MonitoringSettingsScreen())),
      icon:const Icon(Icons.tune_rounded,color:MedicColors.mint))),
    Expanded(child:_uid==null?const Center(child:Text('Sign in to see monitoring.')):StreamBuilder<Map<String,dynamic>>(
      stream:HealthMonitoringService.watch(_uid!),builder:(context,snap){
        final data=snap.data,days=HealthMonitoringService.days(data??{});
        final analysis=HealthMonitoringService.map(data?['analysis']),summary=HealthMonitoringService.map(data?['summary']);
        final current=days.isEmpty?<String,dynamic>{}:days.last;
        final dailyScore=DailyScoreView(data??{});
        return RefreshIndicator(onRefresh:_refresh,child:FadeTransition(opacity:_entrance,child:ListView(
          physics:const AlwaysScrollableScrollPhysics(),padding:const EdgeInsets.fromLTRB(22,20,22,32),children:[
            if(_refreshing)const Padding(padding:EdgeInsets.only(bottom:16),child:LinearProgressIndicator(color:MedicColors.green)),
            if(_error!=null||snap.hasError)_card(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text(_error??HealthMonitoringService.errorMessage(snap.error!),style:const TextStyle(color:MedicColors.cC05256,fontSize:12,height:1.5)),
              TextButton(onPressed:_refresh,child:const Text('Retry'))])),
            if(data==null)_card(const Text('Loading your saved readings and dose history…',
              style:TextStyle(color:MedicColors.muted,height:1.6)))
            else ...[
              if(data['source']=='saved_records')_card(const Text('Report calculated from your saved records. Push delivery is tracked separately when available.',style:TextStyle(fontSize:12,height:1.5,color:MedicColors.muted))),
              _card(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                MedicEyebrow('${current['date']??''} · ${data['timeZone']??''}'),const SizedBox(height:14),
                Row(children:[Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                  const Text('Today’s health score',style:TextStyle(fontFamily:'serif',fontSize:27,color:MedicColors.forest)),
                  const SizedBox(height:7),Text('${dailyScore.band} · ${dailyScore.coverage}/5 components',style:const TextStyle(fontSize:11,color:MedicColors.muted)),
                  const SizedBox(height:7),Text(analysis['delta']==null?'Yesterday comparison unavailable':'${_v(analysis['delta'])} points versus yesterday',style:const TextStyle(fontSize:11,color:MedicColors.muted)),
                ])),const SizedBox(width:14),SizedBox(width:78,height:78,child:Stack(alignment:Alignment.center,children:[
                  SizedBox(width:78,height:78,child:CircularProgressIndicator(value:current['score'] is num?(current['score'] as num)/100:0,
                    strokeWidth:6,color:_color(analysis['severity']?.toString()),backgroundColor:MedicColors.line)),
                  Text(dailyScore.text,style:const TextStyle(fontSize:20,fontWeight:FontWeight.w700,color:MedicColors.forest)),
                ]))]),const SizedBox(height:22),
                Text(analysis['title']?.toString()??'',style:TextStyle(color:_color(analysis['severity']?.toString()),fontWeight:FontWeight.w700)),
                const SizedBox(height:8),
                for(final flag in (analysis['flags'] is List?analysis['flags'] as List:const []))Padding(padding:const EdgeInsets.only(bottom:8),child:Text(
                  HealthMonitoringService.map(flag)['text']?.toString()??'',style:const TextStyle(fontSize:12,color:MedicColors.muted,height:1.5))),
                Text(analysis['action']?.toString()??'',style:const TextStyle(fontSize:12,height:1.6,color:MedicColors.forest)),
              ])),
              _card(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                const MedicEyebrow('Seven-day overview'),const SizedBox(height:10),
                const Text('The week in context',style:TextStyle(fontFamily:'serif',fontSize:25,color:MedicColors.forest)),const SizedBox(height:16),
                Text('Average score ${_v(summary['averageScore'])}/100 · ${summary['scoreDays']??0} observed days',style:const TextStyle(fontWeight:FontWeight.w700,color:MedicColors.forest)),
                const SizedBox(height:8),Text('Glucose mean ${_v(summary['glucoseAverage'])} mg/dL\nBP mean ${_v(summary['systolicAverage'])}/${_v(summary['diastolicAverage'])} mmHg\nDoses confirmed ${summary['taken']??0}/${summary['due']??0} eligible due · ${_v(summary['adherence'])}%',
                  style:const TextStyle(fontSize:12,color:MedicColors.muted,height:1.8)),const SizedBox(height:20),
                SizedBox(height:100,child:Row(crossAxisAlignment:CrossAxisAlignment.end,children:[for(final day in days)Expanded(child:Padding(
                  padding:const EdgeInsets.symmetric(horizontal:4),child:Column(mainAxisAlignment:MainAxisAlignment.end,children:[
                    Text(_v(day['score']),style:const TextStyle(fontSize:9,color:MedicColors.muted)),const SizedBox(height:5),
                    AnimatedContainer(duration:MediaQuery.of(context).disableAnimations?Duration.zero:const Duration(milliseconds:550),
                      height:day['score'] is num?(day['score'] as num).toDouble()*.6:3,width:18,
                      decoration:BoxDecoration(color:day['observed']==true?MedicColors.green:MedicColors.line,borderRadius:BorderRadius.circular(8))),
                    const SizedBox(height:6),Text('${day['date']}'.substring(5),style:const TextStyle(fontSize:8,color:MedicColors.muted)),
                  ])))])),
                TextButton.icon(onPressed:()=>_report(data),icon:const Icon(Icons.description_outlined,size:18),label:const Text('Open full seven-day report')),
              ])),
              const Padding(padding:EdgeInsets.only(bottom:14),child:Text('Daily progression',style:TextStyle(fontFamily:'serif',fontSize:25,color:MedicColors.forest))),
              for(final day in days.reversed)_dayCard(day),
              if(_canEdit && data['source']=='server') _deliveryCard(data['eventId']?.toString()),
              const SizedBox(height:8),Text(analysis['note']?.toString()??'',style:const TextStyle(fontSize:11,height:1.6,color:MedicColors.muted)),
            ],
            const SizedBox(height:16),Wrap(spacing:10,runSpacing:10,children:[
              if(_canEdit) FilledButton.icon(onPressed:()async{await Navigator.push(context,MaterialPageRoute(builder:(_)=>const VitalsUploadScreen()));if(mounted)_refresh();},
                icon:const Icon(Icons.add_rounded),label:const Text('Add reading')),
              if(_canEdit) OutlinedButton.icon(onPressed:()async{await Navigator.push(context,MaterialPageRoute(builder:(_)=>const DoseHistoryScreen()));if(mounted)_refresh();},
                icon:const Icon(Icons.medication_outlined,size:18),label:const Text('Record dose')),
            ]),
          ])));
      })),
  ]));
  Widget _dayCard(Map<String,dynamic> day){
    final p=HealthMonitoringService.map(day['pressure']),g=HealthMonitoringService.map(day['glucose']),a=HealthMonitoringService.map(day['a1c']);
    final daily=HealthMonitoringService.map(day['dailyAnalysis']),bpDelta=HealthMonitoringService.map(day['pressureDelta']);
    return _card(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(children:[Expanded(child:MedicEyebrow('${day['date']}')),Text('${DailyScoreView({'days':[day]}).text}/100',style:const TextStyle(fontWeight:FontWeight.w700,color:MedicColors.green))]),
      const SizedBox(height:12),Text(daily['title']?.toString()??'Not assessed',style:TextStyle(fontWeight:FontWeight.w700,fontSize:12,color:_color(daily['severity']?.toString()))),
      const SizedBox(height:8),Text('Glucose ${_v(g['value'])} mg/dL · ${g['context']??'not recorded'} · ${g['label']??'not recorded'}\nGlucose change from yesterday ${_v(day['glucoseDelta'])} mg/dL (same meal timing)\nPressure ${_v(p['systolic'])}/${_v(p['diastolic'])} mmHg · ${p['label']??'not recorded'}\nBP change from yesterday ${_v(bpDelta['systolic'])}/${_v(bpDelta['diastolic'])} mmHg\nDoses ${day['taken']}/${day['due']} eligible due · ${day['missed']} unconfirmed · ${day['pending']} pending\nBMI ${_v(day['bmi'])} · age ${_v(day['age'])}\nHbA1c lab ${_v(a['value'])}% · separate from daily glucose',
        style:const TextStyle(fontSize:11,color:MedicColors.muted,height:1.8)),
    ]));
  }
  Widget _deliveryCard(String? id)=>id==null?const SizedBox.shrink():StreamBuilder<DocumentSnapshot<Map<String,dynamic>>>(
    stream:FirebaseFirestore.instance.doc('users/$_uid/monitoring_deliveries/$id').snapshots(),builder:(context,snap){
      final data=snap.data?.data();
      return _card(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const MedicEyebrow('Alert delivery'),const SizedBox(height:10),
        Text(snap.hasError?'Delivery status could not load':data==null?'Delivery pending or not configured':'Push notification status: ${data['status']??'pending'}',
          style:const TextStyle(color:MedicColors.muted,fontSize:12)),
        if(data!=null) ...[const SizedBox(height:7),Text('Device/caregiver push: ${HealthMonitoringService.map(data['push']).values.map((v)=>HealthMonitoringService.map(v)['status']??'pending').join(' · ')}',style:const TextStyle(fontSize:11,color:MedicColors.muted))],
        const SizedBox(height:7),const Text('Accepted by FCM means handed to the push service, not confirmed receipt on the device. Emergency services are never automatically dispatched.',
          style:TextStyle(fontSize:11,height:1.5,color:MedicColors.muted))]));
    });
  // Shows the report as readable cards instead of one dense block of
  // technical text (which people were reporting as "looks like code") —
  // the full plain-text version from HealthMonitoringService.reportText is
  // still available via the copy button, for sharing with a clinician.
  void _report(Map<String,dynamic> data){Navigator.push(context,MaterialPageRoute(builder:(context)=>SevenDayReportScreen(data:data)));}
}

class SevenDayReportScreen extends StatelessWidget {
  final Map<String,dynamic> data;
  const SevenDayReportScreen({super.key,required this.data});
  Color _color(String? severity)=>severity=='urgent'||severity=='high'?MedicColors.cC05256:severity=='watch'?MedicColors.cB77A27:MedicColors.green;
  Widget _card(Widget child)=>Container(width:double.infinity,margin:const EdgeInsets.only(bottom:14),padding:const EdgeInsets.all(20),
    decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(22),border:Border.all(color:MedicColors.line)),child:child);
  @override
  Widget build(BuildContext context){
    final days=HealthMonitoringService.days(data),analysis=HealthMonitoringService.map(data['analysis']),summary=HealthMonitoringService.map(data['summary']);
    String v(Object? x)=>HealthMonitoringService.value(x);
    return Scaffold(backgroundColor:MedicColors.canvas,appBar:AppBar(title:const Text('Seven-day report'),backgroundColor:MedicColors.canvas,
      foregroundColor:MedicColors.forest,elevation:0,actions:[IconButton(tooltip:'Copy as text',icon:const Icon(Icons.copy_rounded),onPressed:()async{
        await Clipboard.setData(ClipboardData(text:HealthMonitoringService.reportText(data)));
        if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Report copied as text — ready to share with your clinician.')));
      })]),
      body:ListView(padding:const EdgeInsets.fromLTRB(20,8,20,32),children:[
        _card(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          const MedicEyebrow('Summary'),const SizedBox(height:10),
          Text(analysis['title']?.toString()??'Unavailable',style:TextStyle(fontFamily:'serif',fontSize:22,color:_color(analysis['severity']?.toString()))),
          const SizedBox(height:8),Text('Timezone ${data['timeZone']??'Unknown'}'
            '${days.isNotEmpty?' · ${days.first['date']} to ${days.last['date']}':''}',style:const TextStyle(fontSize:12,color:MedicColors.muted)),
          const SizedBox(height:14),Text(analysis['action']?.toString()??'',style:const TextStyle(fontSize:13,height:1.6,color:MedicColors.forest)),
        ])),
        _card(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          const MedicEyebrow('This week at a glance'),const SizedBox(height:10),
          _row('Average daily score','${v(summary['averageScore'])}/100 (${summary['scoreDays']??0} days observed)'),
          _row('Doses confirmed','${summary['taken']??0} of ${summary['due']??0} due (${v(summary['adherence'])}%)'),
          _row('Mean blood sugar','${v(summary['glucoseAverage'])} mg/dL'),
          _row('Mean blood pressure','${v(summary['systolicAverage'])}/${v(summary['diastolicAverage'])} mmHg'),
          _row('Days above reference','sugar ${summary['aboveReferenceGlucoseDays']??0} · BP ${summary['aboveReferencePressureDays']??0}'),
          if((summary['urgentDays'] as List? ?? []).isNotEmpty)
            _row('Urgent-reading days',(summary['urgentDays'] as List).join(', ')),
        ])),
        if((analysis['flags'] is List?analysis['flags'] as List:const []).isNotEmpty)
          _card(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            const MedicEyebrow('Observed patterns'),const SizedBox(height:10),
            for(final flag in (analysis['flags'] as List))Padding(padding:const EdgeInsets.only(bottom:8),
              child:Text('•  ${HealthMonitoringService.map(flag)['text']??''}',style:const TextStyle(fontSize:13,height:1.6,color:MedicColors.forest))),
          ])),
        const Padding(padding:EdgeInsets.only(bottom:10,top:4),child:Text('Day by day',style:TextStyle(fontFamily:'serif',fontSize:20,color:MedicColors.forest))),
        for(final day in days.reversed)_dayCard(day,v,_color),
        _card(Text(analysis['note']?.toString()??'',style:const TextStyle(fontSize:11.5,height:1.6,color:MedicColors.muted))),
        _card(const Text('Cross-check with your healthcare team. Do not change or catch up medication doses based on this report. '
          'Serious symptoms need immediate emergency help.',style:TextStyle(fontSize:11.5,height:1.6,color:MedicColors.muted))),
      ]));
  }
  Widget _row(String label,String value)=>Padding(padding:const EdgeInsets.only(bottom:10),child:Row(
    crossAxisAlignment:CrossAxisAlignment.start,children:[
      Expanded(flex:2,child:Text(label,style:const TextStyle(fontSize:12.5,color:MedicColors.muted))),
      Expanded(flex:3,child:Text(value,style:const TextStyle(fontSize:12.5,fontWeight:FontWeight.w600,color:MedicColors.forest))),
    ]));
  Widget _dayCard(Map<String,dynamic> day,String Function(Object?) v,Color Function(String?) color){
    final p=HealthMonitoringService.map(day['pressure']),g=HealthMonitoringService.map(day['glucose']),a=HealthMonitoringService.map(day['a1c']);
    final daily=HealthMonitoringService.map(day['dailyAnalysis']);
    return _card(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(children:[Expanded(child:MedicEyebrow('${day['date']}')),
        Text('${v(day['score'])}/100',style:TextStyle(fontWeight:FontWeight.w700,color:color(daily['severity']?.toString())))]),
      const SizedBox(height:8),Text(daily['title']?.toString()??'Not assessed',
        style:TextStyle(fontWeight:FontWeight.w700,fontSize:12.5,color:color(daily['severity']?.toString()))),
      const SizedBox(height:10),
      _row('Glucose','${v(g['value'])} mg/dL · ${g['context']??'not recorded'} · ${g['label']??'unavailable'}'),
      _row('Blood pressure','${v(p['systolic'])}/${v(p['diastolic'])} mmHg · ${p['label']??'unavailable'}'),
      _row('Doses','${day['taken']??0} taken · ${day['missed']??0} unconfirmed · ${day['pending']??0} pending'),
      if(a['value']!=null)_row('HbA1c lab','${v(a['value'])}% (separate from daily glucose)'),
    ]));
  }
}

class MonitoringSettingsScreen extends StatefulWidget {
  const MonitoringSettingsScreen({super.key});
  @override
  State<MonitoringSettingsScreen> createState()=>_MonitoringSettingsScreenState();
}
class _MonitoringSettingsScreenState extends State<MonitoringSettingsScreen> {
  final _zone=TextEditingController(text:'Asia/Kuala_Lumpur');
  final _uid=FirebaseAuth.instance.currentUser?.uid;
  bool _alarm=true,_caregivers=true,_push=true,_receiveCaregiver=true,_loading=true,_saving=false;
  String? _error;
  bool _checking=false;
  Map<String,String>? _diagnosis;
  Future<void> _checkPush()async{
    setState((){_checking=true;_error=null;});
    try{final result=await HealthMonitoringService.registerAndCheckPush();if(mounted)setState(()=>_diagnosis=result);}
    catch(error){if(mounted)setState(()=>_error='Device registration could not finish: ${error is FirebaseException?error.code:error.runtimeType}. Check notification permission and account access.');}
    finally{if(mounted)setState(()=>_checking=false);}
  }
  @override
  void initState(){super.initState();_load();}
  Future<void> _load()async{try{if(_uid!=null){final d=(await FirebaseFirestore.instance.doc('users/$_uid/settings/monitoring').get()).data()??{};
    if(mounted)setState((){_alarm=d['alarmEnabled']!=false;_caregivers=d['notifyCaregivers']!=false;_push=d['pushEnabled']!=false;_receiveCaregiver=d['receiveCaregiverPush']!=false;
_zone.text=d['timeZone']?.toString()??'Asia/Kuala_Lumpur';});}}
    catch(_){if(mounted)_error='Settings could not be loaded.';}finally{if(mounted)setState(()=>_loading=false);}}
  @override
  void dispose(){_zone.dispose();super.dispose();}
  Future<void> _save()async{
    if(_uid==null)return;
    setState((){_saving=true;_error=null;});
    try{await FirebaseFirestore.instance.doc('users/$_uid/settings/monitoring').set({'alarmEnabled':_alarm,'notifyCaregivers':_caregivers,'pushEnabled':_push,'receiveCaregiverPush':_receiveCaregiver,
      'smsEnabled':FieldValue.delete(),'caregiverConsent':FieldValue.delete(),'caregiverPhone':FieldValue.delete(),'timeZone':_zone.text.trim(),'updatedAt':FieldValue.serverTimestamp()},SetOptions(merge:true));
      if(mounted)Navigator.pop(context);}
    catch(_){if(mounted)setState(()=>_error='Settings could not be saved. Retry.');}finally{if(mounted)setState(()=>_saving=false);}
  }
  @override
  Widget build(BuildContext context)=>Scaffold(backgroundColor:MedicColors.canvas,body:Column(children:[
    const MedicPageTitle(title:'Monitoring settings',subtitle:'Choose how you and your caregivers are alerted.'),
    Expanded(child:_loading?const Center(child:CircularProgressIndicator()):ListView(padding:const EdgeInsets.all(22),children:[
      if(_error!=null)Text(_error!,style:const TextStyle(color:MedicColors.cC05256)),
      SwitchListTile(title:const Text('Urgent foreground alarm'),subtitle:const Text('Loop audio for a recent urgent reading while the app is open.'),value:_alarm,onChanged:_saving?null:(v)=>setState(()=>_alarm=v)),
      SwitchListTile(title:const Text('Approved caregiver alerts'),subtitle:const Text('Send high-priority alerts to people you approved in Guardian.'),value:_caregivers,onChanged:_saving?null:(v)=>setState(()=>_caregivers=v)),
      SwitchListTile(title:const Text('My health push notifications'),subtitle:const Text('Send daily and urgent health alerts to my registered devices.'),value:_push,onChanged:_saving?null:(v)=>setState(()=>_push=v)),
      SwitchListTile(title:const Text('Receive caregiver push alerts'),subtitle:const Text('Receive alerts for patients who approved your tracking request.'),value:_receiveCaregiver,onChanged:_saving?null:(v)=>setState(()=>_receiveCaregiver=v)),
      const SizedBox(height:12),TextField(controller:_zone,enabled:!_saving,decoration:const InputDecoration(labelText:'IANA timezone · Asia/Kuala_Lumpur')),
      const SizedBox(height:20),const Text('Push alerts are sent through Firebase Cloud Messaging to registered devices. '
        'This system cannot guarantee delivery or override device sound settings; use local emergency services when needed.',style:TextStyle(fontSize:12,height:1.6,color:MedicColors.muted)),
      const SizedBox(height:16),OutlinedButton.icon(onPressed:_checking?null:_checkPush,icon:const Icon(Icons.notifications_active_outlined),label:Text(_checking?'Checking…':'Enable & check notifications')),
      if(_diagnosis!=null) ...[for(final entry in _diagnosis!.entries)Padding(padding:const EdgeInsets.only(top:8),child:Text('${entry.key}: ${entry.value}',style:const TextStyle(fontSize:12,color:MedicColors.muted)))],
      const SizedBox(height:20),FilledButton(onPressed:_saving?null:_save,child:Text(_saving?'Saving…':'Save settings')),
    ])),
  ]));
}

class MonitoringLaunchCard extends StatelessWidget {
  const MonitoringLaunchCard({super.key});
  @override
  Widget build(BuildContext context) {
    final uid=FirebaseAuth.instance.currentUser?.uid;
    return StreamBuilder<Map<String,dynamic>>(stream:uid==null?null:HealthMonitoringService.watch(uid),builder:(context,snap){
      final data=snap.data??{},days=HealthMonitoringService.days(data),a=HealthMonitoringService.map(data['analysis']);
      final day=days.isEmpty?<String,dynamic>{}:days.last;
      final view=DailyScoreView(data);
      final caption=days.isEmpty?'Trends, dose patterns and caregiver alerts':'${day['date']} · ${view.text}/100 · ${a['title']??'Daily summary'}';
      return Material(color:MedicColors.mint.withOpacity(.4),borderRadius:BorderRadius.circular(22),child:InkWell(
        borderRadius:BorderRadius.circular(22),onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const HealthMonitoringScreen())),
        child:Padding(padding:const EdgeInsets.all(18),child:Row(children:[const Icon(Icons.monitor_heart_outlined,color:MedicColors.green),
          const SizedBox(width:12),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            const Text('Daily monitoring & seven-day report',style:TextStyle(fontWeight:FontWeight.w700,fontSize:12,color:MedicColors.forest)),
            const SizedBox(height:4),Text(caption,style:const TextStyle(fontSize:11,height:1.5,color:MedicColors.muted)),
          ])),const Icon(Icons.arrow_forward_rounded,color:MedicColors.green,size:18)]))));
    });
  }
}
