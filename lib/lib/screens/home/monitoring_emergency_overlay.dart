import 'package:flutter/material.dart';
import '../../design/medic_design.dart';
import '../../services/monitoring_alarm_service.dart';
import 'health_monitoring_screen.dart';

final monitoringNavigatorKey=GlobalKey<NavigatorState>();
class MonitoringEmergencyOverlay extends StatelessWidget {
  final Widget child;
  const MonitoringEmergencyOverlay({super.key,required this.child});
  @override
  Widget build(BuildContext context)=>AnimatedBuilder(animation:MonitoringAlarmService.instance,child:child,builder:(context,child){
    final service=MonitoringAlarmService.instance;
    return Stack(children:[child!,if(service.active)Positioned.fill(child:Material(color:MedicColors.forest.withOpacity(.97),child:SafeArea(
      child:Center(child:SingleChildScrollView(padding:const EdgeInsets.all(30),child:Column(mainAxisSize:MainAxisSize.min,children:[
        const Icon(Icons.health_and_safety_outlined,size:64,color:MedicColors.mint),const SizedBox(height:22),
        const Text('A reading needs\nurgent review',textAlign:TextAlign.center,style:TextStyle(fontFamily:'serif',fontSize:34,color:Colors.white)),
        const SizedBox(height:20),Text(service.message,textAlign:TextAlign.center,style:const TextStyle(fontSize:14,height:1.7,color:Colors.white)),
        const SizedBox(height:16),Text(service.audioStatus,textAlign:TextAlign.center,style:const TextStyle(fontSize:11,color:Colors.white70)),
        const SizedBox(height:26),FilledButton.icon(onPressed:()=>service.stop(dismiss:true),icon:const Icon(Icons.volume_off_outlined),label:const Text('Stop alarm')),
        const SizedBox(height:10),OutlinedButton(onPressed:()async{await service.stop(dismiss:true);monitoringNavigatorKey.currentState?.push(MaterialPageRoute(builder:(_)=>const HealthMonitoringScreen()));},
          style:OutlinedButton.styleFrom(foregroundColor:MedicColors.mint,side:const BorderSide(color:MedicColors.mint)),child:const Text('Review readings and alerts')),
        const SizedBox(height:18),const Text('If you have serious symptoms, seek emergency help now. Do not wait for this app or a caregiver response.',
          textAlign:TextAlign.center,style:TextStyle(fontSize:12,height:1.6,color:Colors.white70)),
      ]))))))]);
  });
}
