import 'health_monitoring_service.dart';

/// Presentation of the canonical calendar-day report. No alternate score math.
class DailyScoreView {
  final Map<String,dynamic> day;
  DailyScoreView(Map<String,dynamic> report):day=HealthMonitoringService.days(report).isEmpty
      ? {}:HealthMonitoringService.days(report).last;
  num? get score=>day['score'] is num?day['score'] as num:null;
  String get text=>HealthMonitoringService.value(score);
  String get date=>day['date']?.toString()??'Loading';
  int get coverage=>day['coverage'] is num?(day['coverage'] as num).toInt():0;
  Map<String,dynamic> get components=>HealthMonitoringService.map(day['components']);
  String get band=>day['scoreBand']?.toString().replaceAll(' app score','')??'No score';
  String get basis=>'${date} · $coverage of 5 components · today’s eligible doses';
  String get adherenceDetail=>'${day['taken']??'—'}/${day['due']??'—'} eligible due doses confirmed';
}
