import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../design/medic_design.dart';
import '../../services/daily_score_view.dart';
import '../../services/health_monitoring_service.dart';
import 'health_score_breakdown_screen.dart';

class DailyHealthScoreCard extends StatelessWidget {
  final bool dark;
  final VoidCallback? onTap;
  const DailyHealthScoreCard({super.key,this.dark=false,this.onTap});
  static const labels={'bloodPressure':'Blood pressure','bloodSugar':'Blood sugar','adherence':'Adherence','bmi':'BMI','age':'Age'};
  static Color scoreColor(num? value)=>value==null?MedicColors.muted:value>=75?MedicColors.green:value>=40?MedicColors.cB77A27:MedicColors.cC05256;
  @override
  Widget build(BuildContext context){final uid=FirebaseAuth.instance.currentUser?.uid;
    return StreamBuilder<Map<String,dynamic>>(stream:uid==null?null:HealthMonitoringService.watch(uid),builder:(context,snap){
      final view=DailyScoreView(snap.data??{}),color=scoreColor(view.score),ink=dark?Colors.white:MedicColors.forest,muted=dark?Colors.white70:MedicColors.muted;
      return Material(color:dark?MedicColors.forest:Colors.white,borderRadius:BorderRadius.circular(26),child:InkWell(
        onTap:onTap??()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const HealthScoreBreakdownScreen())),borderRadius:BorderRadius.circular(26),
        child:Container(padding:const EdgeInsets.all(22),decoration:BoxDecoration(borderRadius:BorderRadius.circular(26),border:Border.all(color:dark?Colors.white12:MedicColors.line)),
          child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Row(children:[Expanded(child:Text('TODAY’S HEALTH SCORE',style:TextStyle(fontSize:10,letterSpacing:1.5,fontWeight:FontWeight.w700,color:muted))),
              Icon(Icons.arrow_forward_rounded,color:dark?MedicColors.mint:MedicColors.green,size:18)]),const SizedBox(height:20),
            Row(children:[SizedBox(width:106,height:106,child:TweenAnimationBuilder<double>(key:ValueKey(view.text),
              tween:Tween(begin:0,end:(view.score??0).toDouble()),duration:MediaQuery.of(context).disableAnimations?Duration.zero:const Duration(milliseconds:750),
              builder:(context,value,child)=>Stack(alignment:Alignment.center,children:[
                SizedBox(width:106,height:106,child:CircularProgressIndicator(value:value/100,strokeWidth:8,strokeCap:StrokeCap.round,
                  color:dark&&view.score!=null&&view.score!>=75?MedicColors.mint:color,backgroundColor:dark?Colors.white12:MedicColors.line)),
                Column(mainAxisSize:MainAxisSize.min,children:[Text(view.text,style:TextStyle(fontSize:31,fontWeight:FontWeight.w700,color:ink)),
                  Text('out of 100',style:TextStyle(fontSize:10,color:muted))]),
              ]))),const SizedBox(width:20),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                Text(view.band,style:TextStyle(fontFamily:'serif',fontSize:25,color:ink)),const SizedBox(height:8),
                Text(view.basis,style:TextStyle(fontSize:11,color:muted,height:1.6)),const SizedBox(height:7),
                Text('App estimate; missing components are excluded.',style:TextStyle(fontSize:11,color:muted,height:1.5)),
              ]))]),const SizedBox(height:20),
            for(final entry in labels.entries)Padding(padding:const EdgeInsets.only(bottom:9),child:Row(children:[
              SizedBox(width:100,child:Text(entry.value,style:TextStyle(fontSize:11,color:muted))),
              Expanded(child:ClipRRect(borderRadius:BorderRadius.circular(5),child:LinearProgressIndicator(
                value:view.components[entry.key] is num?(view.components[entry.key] as num)/100:0,minHeight:4,
                color:dark?MedicColors.mint:MedicColors.green,backgroundColor:dark?Colors.white12:MedicColors.line))),const SizedBox(width:10),
              SizedBox(width:30,child:Text(HealthMonitoringService.value(view.components[entry.key]),textAlign:TextAlign.end,style:TextStyle(fontSize:10,color:ink))),
            ])),
            Text(view.adherenceDetail,style:TextStyle(fontSize:10,color:muted)),
            if(snap.hasError)Padding(padding:const EdgeInsets.only(top:8),child:Text('Score unavailable. Check record access and refresh.',style:TextStyle(fontSize:11,color:muted))),
          ]))));
    });
  }
}
