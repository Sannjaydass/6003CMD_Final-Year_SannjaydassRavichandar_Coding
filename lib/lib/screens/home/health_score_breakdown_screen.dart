import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../design/medic_design.dart';
import '../../services/health_monitoring_service.dart';
import '../../services/daily_score_view.dart';
import 'daily_health_score_card.dart';
import 'health_monitoring_screen.dart';
import 'vitals_upload_screen.dart';
import 'dose_history_screen.dart';
import 'edit_profile_screen.dart';

class HealthScoreBreakdownScreen extends StatefulWidget {
  const HealthScoreBreakdownScreen({super.key});
  @override
  State<HealthScoreBreakdownScreen> createState()=>_HealthScoreBreakdownScreenState();
}
class _HealthScoreBreakdownScreenState extends State<HealthScoreBreakdownScreen> with SingleTickerProviderStateMixin {
  final _uid=FirebaseAuth.instance.currentUser?.uid;
  late final AnimationController _entrance;
  String? _notice;
  @override
  void initState(){super.initState();_entrance=AnimationController(vsync:this,duration:const Duration(milliseconds:650))..forward();}
  @override
  void didChangeDependencies(){super.didChangeDependencies();if(MediaQuery.of(context).disableAnimations)_entrance.value=1;}
  @override
  void dispose(){_entrance.dispose();super.dispose();}
  Future<void> _refresh()async{
    try{await HealthMonitoringService.refresh();if(mounted)setState(()=>_notice=null);}
    catch(error){if(mounted)setState(()=>_notice=HealthMonitoringService.errorMessage(error));}
  }
  Future<void> _open(Widget page)async{await Navigator.push(context,MaterialPageRoute(builder:(_)=>page));if(mounted)_refresh();}
  String _value(Object? v)=>HealthMonitoringService.value(v);
  Widget _card(Widget child)=>Container(width:double.infinity,padding:const EdgeInsets.all(22),margin:const EdgeInsets.only(bottom:16),
    decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(26),border:Border.all(color:MedicColors.line)),child:child);
  @override
  Widget build(BuildContext context)=>Scaffold(backgroundColor:MedicColors.canvas,body:Column(children:[
    const MedicPageTitle(title:'Health score breakdown',subtitle:'One daily score. The same calculation everywhere.'),
    Expanded(child:_uid==null?const Center(child:Text('Sign in to view your score.')):StreamBuilder<Map<String,dynamic>>(
      stream:HealthMonitoringService.watch(_uid!),builder:(context,snap){
        final report=snap.data??{},days=HealthMonitoringService.days(report),view=DailyScoreView(report);
        final current=days.isEmpty?<String,dynamic>{}:days.last,previous=days.length<2?<String,dynamic>{}:days[days.length-2];
        final analysis=HealthMonitoringService.map(report['analysis']),delta=analysis['delta'];
        final oldParts=HealthMonitoringService.map(previous['components']);
        return RefreshIndicator(onRefresh:_refresh,child:FadeTransition(opacity:_entrance,child:ListView(
          physics:const AlwaysScrollableScrollPhysics(),padding:const EdgeInsets.fromLTRB(22,20,22,30),children:[
            if(_notice!=null)_card(Text(_notice!,style:const TextStyle(fontSize:12,height:1.6,color:MedicColors.muted))),
            if(snap.hasError)_card(const Text('Your score could not load. Check record access and retry.')),
            DailyHealthScoreCard(onTap:()=>_open(const HealthMonitoringScreen())),const SizedBox(height:16),
            _card(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              const MedicEyebrow('Yesterday → today'),const SizedBox(height:14),
              Row(children:[Expanded(child:_total(previous)),const Icon(Icons.arrow_forward_rounded,color:MedicColors.muted),Expanded(child:_total(current))]),
              const SizedBox(height:16),Text(delta is num?'${delta>0?'+':''}${_value(delta)} points versus yesterday.':
                'A total change is shown only when both dates have the same available components.',style:const TextStyle(fontSize:12,height:1.6,color:MedicColors.muted)),
            ])),
            _card(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              const MedicEyebrow('Component changes'),const SizedBox(height:14),
              for(final entry in DailyHealthScoreCard.labels.entries)Padding(padding:const EdgeInsets.only(bottom:18),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                Text(entry.value,style:const TextStyle(fontSize:12,fontWeight:FontWeight.w700,color:MedicColors.forest)),const SizedBox(height:7),
                Row(children:[Text('${_value(oldParts[entry.key])} → ${_value(view.components[entry.key])}',style:const TextStyle(fontSize:12,color:MedicColors.muted)),
                  const Spacer(),Text(_change(oldParts[entry.key],view.components[entry.key]),style:const TextStyle(fontSize:11,color:MedicColors.green))]),
                const SizedBox(height:8),ClipRRect(borderRadius:BorderRadius.circular(6),child:LinearProgressIndicator(
                  value:view.components[entry.key] is num?(view.components[entry.key] as num)/100:0,color:MedicColors.green,backgroundColor:MedicColors.line,minHeight:5)),
              ])),
              Text(view.adherenceDetail,style:const TextStyle(fontSize:12,color:MedicColors.muted)),const SizedBox(height:8),
              Text('BMI ${_value(current['bmi'])} · age ${_value(current['age'])}',style:const TextStyle(fontSize:12,color:MedicColors.muted)),
            ])),
            _card(const Text('Daily score = the average of available blood-pressure, glucose, medication adherence, BMI and age component scores. '
              'Adherence uses today’s confirmed/expired due doses; future and grace-period doses are excluded. Missing components are excluded, and zero adherence is included when eligible doses exist. '
              'The score is an app estimate, not a diagnosis.',style:TextStyle(fontSize:12,color:MedicColors.muted,height:1.7))),
            Wrap(spacing:8,runSpacing:8,children:[
              FilledButton.icon(onPressed:()=>_open(const VitalsUploadScreen()),icon:const Icon(Icons.add_rounded),label:const Text('Add reading')),
              OutlinedButton.icon(onPressed:()=>_open(const DoseHistoryScreen()),icon:const Icon(Icons.medication_outlined),label:const Text('Record dose')),
              TextButton.icon(onPressed:()=>_open(const EditProfileScreen()),icon:const Icon(Icons.person_outline_rounded),label:const Text('Update profile')),
            ]),
          ])));
      })),
  ]));
  String _change(Object? old,Object? current)=>old is num&&current is num?
    '${current-old>0?'+':''}${_value(current-old)} points':'Not comparable';
  Widget _total(Map<String,dynamic> day)=>Column(children:[
    Text(_value(day['score']),style:const TextStyle(fontSize:32,fontWeight:FontWeight.w700,color:MedicColors.forest)),
    const SizedBox(height:5),Text(day['date']?.toString()??'No record',style:const TextStyle(fontSize:10,color:MedicColors.muted)),
    const SizedBox(height:4),Text('${day['coverage']??0}/5 components',style:const TextStyle(fontSize:10,color:MedicColors.muted)),
  ]);
}
