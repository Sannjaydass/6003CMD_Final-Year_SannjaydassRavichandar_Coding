import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class NearbyFacilitiesScreen extends StatefulWidget {
  const NearbyFacilitiesScreen({super.key});
  @override
  State<NearbyFacilitiesScreen> createState() => _NearbyFacilitiesScreenState();
}
class _NearbyFacilitiesScreenState extends State<NearbyFacilitiesScreen> {
  final _area = TextEditingController();
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _places = [];
  DateTime? _lastSearch;
  @override
  void dispose() { _area.dispose(); super.dispose(); }
  Future<void> _open(Uri uri) async {
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) throw StateError('No app could open this link.');
    } catch (_) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open the link. Try another maps/browser app.'))); }
  }
  Future<void> _nearby() async {
    if (_lastSearch != null && DateTime.now().difference(_lastSearch!).inSeconds < 30) return;
    setState(() { _loading = true; _error = null; });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) throw StateError('Turn on location services, or search by town below.');
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        throw StateError('Location access is unavailable. Search by town below.');
      }
      final p = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 20));
      _lastSearch = DateTime.now();
      final query = '[out:json][timeout:20];nwr["amenity"~"^(hospital|clinic|pharmacy)\$"](around:10000,${p.latitude},${p.longitude});out center tags;';
      final res = await http.post(Uri.parse('https://overpass-api.de/api/interpreter'),
        body: {'data': query}, headers: {'Accept': 'application/json'}).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) throw StateError('Nearby search is busy. Try the maps search below.');
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final places = <Map<String, dynamic>>[];
      for (final element in json['elements'] as List? ?? []) {
        final e = Map<String, dynamic>.from(element as Map);
        final tags = Map<String, dynamic>.from(e['tags'] as Map? ?? {});
        final lat = (e['lat'] ?? e['center']?['lat']) as num?;
        final lon = (e['lon'] ?? e['center']?['lon']) as num?;
        if (lat == null || lon == null) continue;
        places.add({'name': tags['name'] ?? 'Unnamed ${tags['amenity']}', 'type': tags['amenity'],
          'lat': lat.toDouble(), 'lon': lon.toDouble(),
          'distance': Geolocator.distanceBetween(p.latitude, p.longitude, lat.toDouble(), lon.toDouble()),
          'phone': tags['contact:phone'] ?? tags['phone'],
          'address': [tags['addr:housenumber'], tags['addr:street'], tags['addr:city']].whereType<String>().join(', ')});
      }
      places.sort((a, b) => (a['distance'] as double).compareTo(b['distance'] as double));
      if (mounted) setState(() { _places = places.take(40).toList(); if (_places.isEmpty) _error = 'No mapped facilities found within 10 km. Try a town search.'; });
    } catch (e) { if (mounted) setState(() => _error = '$e'); }
    finally { if (mounted) setState(() => _loading = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Find a medicine return point')),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      Card(color: const Color(0xFFE4EEDC), child: Padding(padding: const EdgeInsets.all(18), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Return safely. Ask before donating.', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text('These are nearby clinics, hospitals and pharmacies, not verified donation centres. Call a pharmacist to confirm medicine return, disposal or donation eligibility before travelling. Do not give your prescription medicines directly to another person.'),
      ]))),
      const SizedBox(height: 12),
      const Text('Nearby search shares your coordinates with OpenStreetMap’s Overpass service only when you tap below. Locations are not saved to your account.'),
      FilledButton.icon(onPressed: _loading ? null : _nearby, icon: const Icon(Icons.my_location), label: const Text('Find facilities within 10 km')),
      TextField(controller: _area, decoration: const InputDecoration(labelText: 'Or enter a town / postcode')),
      OutlinedButton.icon(onPressed: () {
        final area = _area.text.trim();
        if (area.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a town or postcode first.'))); return; }
        _open(Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': 'hospitals clinics pharmacies in $area'}));
      }, icon: const Icon(Icons.map_outlined), label: const Text('Search this area in Maps')),
      ExpansionTile(title: const Text('What to ask the pharmacist'), children: const [Padding(padding: EdgeInsets.all(16),
        child: Text('“Do you accept unused medicines for safe disposal? Do you run an authorised donation programme? My medicine is [name], [opened/unopened], expires [date], and has been stored [conditions]. What can I bring, and when?”\n\nKeep medicines in their original packaging and bring the label. Ask separately about needles, inhalers, liquids and refrigerated medicines.'))]),
      if (_loading) const LinearProgressIndicator(),
      if (_error != null) Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
      ..._places.map((p) => Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${p['name']}', style: Theme.of(context).textTheme.titleMedium),
        Text('${p['type']} · ${((p['distance'] as double) / 1000).toStringAsFixed(1)} km away'),
        if ((p['address'] as String).isNotEmpty) Text(p['address'] as String),
        const Text('Acceptance unverified — call ahead'),
        Wrap(spacing: 8, children: [
          TextButton.icon(onPressed: () => _open(Uri.https('www.google.com', '/maps/dir/',
            {'api': '1', 'destination': '${p['lat']},${p['lon']}'})), icon: const Icon(Icons.directions), label: const Text('Directions')),
          if (p['phone'] != null) TextButton.icon(onPressed: () => _open(Uri(scheme: 'tel', path: '${p['phone']}'.split(';').first.replaceAll(RegExp(r'[^+0-9]'), ''))),
            icon: const Icon(Icons.call_outlined), label: const Text('Call')),
        ]),
      ])))),
      TextButton(onPressed: () => _open(Uri.parse('https://www.openstreetmap.org/copyright')), child: const Text('Map data © OpenStreetMap contributors')),
      TextButton(onPressed: () => _open(Uri.parse('https://pharmacy.moh.gov.my/en/documents/guideline-management-medicine-donations.html')),
        child: const Text('Malaysia MOH medicine donation guidance')),
    ]));
}
