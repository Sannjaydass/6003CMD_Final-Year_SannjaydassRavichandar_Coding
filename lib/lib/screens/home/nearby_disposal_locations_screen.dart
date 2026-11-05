import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:medictrack/design/medic_design.dart';

// ─── Design Tokens ────────────────────────────────────────────────────────────
class _C {
  static const navy    = MedicColors.c142F2B;
  static const teal    = MedicColors.c28715D;
  static const sky     = MedicColors.c477C91;
  static const amber   = MedicColors.cB77A27;
  static const rose    = MedicColors.cC05256;
  static const violet  = MedicColors.c78659B;
  static const surface = MedicColors.cF6F5F0;
  static const card    = MedicColors.cFFFFFF;
  static const border  = MedicColors.cE2E5DC;
  static const textPri = MedicColors.c142F2B;
  static const textSec = MedicColors.c63756D;
  static const textTer = MedicColors.c83938B;
}

/// One nearby facility that can accept unused/expired medicine for
/// take-back or safe disposal — pharmacies, hospitals and clinics.
class _Facility {
  final String name;
  final String kind; // pharmacy | hospital | clinic
  final String? address;
  final double lat, lon;
  final double distanceKm;
  const _Facility({
    required this.name,
    required this.kind,
    required this.address,
    required this.lat,
    required this.lon,
    required this.distanceKm,
  });
}

class NearbyDisposalLocationsScreen extends StatefulWidget {
  const NearbyDisposalLocationsScreen({Key? key}) : super(key: key);

  @override
  State<NearbyDisposalLocationsScreen> createState() =>
      _NearbyDisposalLocationsScreenState();
}

class _NearbyDisposalLocationsScreenState
    extends State<NearbyDisposalLocationsScreen> {
  bool _loading = true;
  String? _error;
  Position? _pos;
  List<_Facility> _facilities = [];
  String _filter = 'All'; // All | Pharmacy | Hospital | Clinic
  double _radiusKm = 5;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ── Distance (Haversine) ────────────────────────────────────────────────
  double _distanceKm(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(lat1)) *
            math.cos(_deg2rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  double _deg2rad(double deg) => deg * (math.pi / 180);

  // ── Load: location permission → position → Overpass query ──────────────
  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final pos = await _resolvePosition();
      if (pos == null) return; // _error already set
      _pos = pos;
      final facilities = await _fetchNearbyFacilities(pos.latitude, pos.longitude, _radiusKm);
      if (!mounted) return;
      setState(() { _facilities = facilities; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load nearby locations: $e';
      });
    }
  }

  Future<Position?> _resolvePosition() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _loading = false;
          _error = 'Location services are turned off on this device. Please enable location to find nearby drop-off points.';
        });
        return null;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        setState(() {
          _loading = false;
          _error = 'Location permission was denied. Allow location access to find nearby clinics and hospitals.';
        });
        return null;
      }
      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _loading = false;
          _error = 'Location permission is permanently denied. Enable it from your device settings to use this feature.';
        });
        return null;
      }

      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Could not get your current location: $e';
      });
      return null;
    }
  }

  /// Query OpenStreetMap's free, keyless Overpass API for pharmacies,
  /// hospitals and clinics within [radiusKm] of the given point — these are
  /// the facility types that commonly accept unused/expired medicine for
  /// safe take-back disposal or donation.
  Future<List<_Facility>> _fetchNearbyFacilities(
      double lat, double lon, double radiusKm) async {
    final radiusM = (radiusKm * 1000).round();
    final query = '''
      [out:json][timeout:25];
      (
        node["amenity"="pharmacy"](around:$radiusM,$lat,$lon);
        node["amenity"="hospital"](around:$radiusM,$lat,$lon);
        node["amenity"="clinic"](around:$radiusM,$lat,$lon);
        node["healthcare"="pharmacy"](around:$radiusM,$lat,$lon);
        node["healthcare"="hospital"](around:$radiusM,$lat,$lon);
        node["healthcare"="clinic"](around:$radiusM,$lat,$lon);
      );
      out center 60;
    ''';

    final endpoints = [
      'https://overpass-api.de/api/interpreter',
      'https://overpass.kumi.systems/api/interpreter',
    ];

    Object? lastError;
    for (final endpoint in endpoints) {
      try {
        final res = await http
            .post(Uri.parse(endpoint), body: {'data': query})
            .timeout(const Duration(seconds: 20));
        if (res.statusCode != 200) {
          lastError = 'HTTP ${res.statusCode}';
          continue;
        }
        final data = jsonDecode(res.body);
        final elements = (data['elements'] as List?) ?? [];

        final seen = <String>{};
        final results = <_Facility>[];
        for (final el in elements) {
          final tags = (el['tags'] as Map?) ?? {};
          final name = tags['name'] as String?;
          if (name == null || name.trim().isEmpty) continue;
          final elLat = (el['lat'] as num?)?.toDouble();
          final elLon = (el['lon'] as num?)?.toDouble();
          if (elLat == null || elLon == null) continue;

          final key = '$name-${elLat.toStringAsFixed(4)}-${elLon.toStringAsFixed(4)}';
          if (!seen.add(key)) continue;

          final amenity = (tags['amenity'] ?? tags['healthcare'] ?? '').toString();
          final kind = amenity.contains('pharmacy')
              ? 'Pharmacy'
              : amenity.contains('hospital')
                  ? 'Hospital'
                  : 'Clinic';

          final addrParts = [
            tags['addr:housenumber'],
            tags['addr:street'],
            tags['addr:city'] ?? tags['addr:suburb'],
          ].where((p) => p != null && p.toString().trim().isNotEmpty).join(' ');

          results.add(_Facility(
            name: name.trim(),
            kind: kind,
            address: addrParts.isEmpty ? null : addrParts,
            lat: elLat,
            lon: elLon,
            distanceKm: _distanceKm(lat, lon, elLat, elLon),
          ));
        }

        results.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
        return results;
      } catch (e) {
        lastError = e;
        continue; // try next mirror
      }
    }
    throw lastError ?? Exception('All Overpass mirrors failed');
  }

  List<_Facility> get _filtered => _filter == 'All'
      ? _facilities
      : _facilities.where((f) => f.kind == _filter).toList();

  Future<void> _openDirections(_Facility f) async {
    HapticFeedback.lightImpact();
    final uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=${f.lat},${f.lon}');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Could not open maps app'),
      ));
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _C.surface,
    body: Column(children: [
      MedicPageTitle(
        title: 'Nearby Drop-Off Points',
        subtitle: 'Pharmacies, hospitals and clinics near you that take '
            'back unused or expired medicine for safe disposal or donation.',
      ),
      Expanded(child: _buildBody()),
    ]),
  );

  Widget _buildBody() {
    if (_loading) return _buildLoading();
    if (_error != null) return _buildError();
    return Column(children: [
      _buildControls(),
      Expanded(
        child: _filtered.isEmpty ? _buildEmpty() : _buildList(),
      ),
    ]);
  }

  Widget _buildLoading() => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(width: 36, height: 36,
          child: CircularProgressIndicator(strokeWidth: 2.5, color: _C.teal,
              backgroundColor: _C.teal.withOpacity(0.15))),
      const SizedBox(height: 14),
      const Text('Finding nearby drop-off points...',
          style: TextStyle(color: _C.textSec, fontSize: 13, fontWeight: FontWeight.w500)),
    ]),
  );

  Widget _buildError() => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 64, height: 64,
            decoration: BoxDecoration(
                color: _C.rose.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20)),
            child: const Icon(Icons.location_off_rounded, color: _C.rose, size: 30)),
        const SizedBox(height: 16),
        Text(_error!, textAlign: TextAlign.center,
            style: const TextStyle(color: _C.textSec, fontSize: 13, height: 1.5)),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Try Again'),
          style: ElevatedButton.styleFrom(
            backgroundColor: _C.teal, foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ]),
    ),
  );

  Widget _buildEmpty() => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 64, height: 64,
            decoration: BoxDecoration(
                color: _C.teal.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20)),
            child: const Icon(Icons.search_off_rounded, color: _C.teal, size: 30)),
        const SizedBox(height: 16),
        const Text('No locations found nearby',
            style: TextStyle(color: _C.textPri, fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        const Text('Try widening the search radius below.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _C.textSec, fontSize: 12.5)),
      ]),
    ),
  );

  Widget _buildControls() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
    child: Column(children: [
      Row(children: [
        Expanded(child: Row(
          children: ['All', 'Pharmacy', 'Hospital', 'Clinic'].map((f) {
            final on = _filter == f;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() => _filter = f),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                  decoration: BoxDecoration(
                    color: on ? _C.teal : _C.card,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: on ? _C.teal : _C.border),
                  ),
                  child: Text(f, style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700,
                      color: on ? Colors.white : _C.textSec)),
                ),
              ),
            );
          }).toList(),
        )),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Icon(Icons.social_distance_rounded, size: 15, color: _C.textTer),
        const SizedBox(width: 6),
        Text('Radius: ${_radiusKm.toStringAsFixed(0)} km',
            style: const TextStyle(fontSize: 12, color: _C.textSec, fontWeight: FontWeight.w600)),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: _C.teal,
              inactiveTrackColor: _C.teal.withOpacity(0.15),
              thumbColor: _C.teal,
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: _radiusKm, min: 1, max: 20, divisions: 19,
              onChanged: (v) => setState(() => _radiusKm = v),
              onChangeEnd: (_) => _load(),
            ),
          ),
        ),
      ]),
    ]),
  );

  Widget _buildList() => RefreshIndicator(
    color: _C.teal,
    onRefresh: _load,
    child: ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      itemCount: _filtered.length,
      itemBuilder: (_, i) => _FacilityCard(
        facility: _filtered[i],
        onDirections: () => _openDirections(_filtered[i]),
      ),
    ),
  );
}

// ─── Facility Card ──────────────────────────────────────────────────────────
class _FacilityCard extends StatelessWidget {
  final _Facility facility;
  final VoidCallback onDirections;
  const _FacilityCard({required this.facility, required this.onDirections});

  Color get _kindColor {
    switch (facility.kind) {
      case 'Pharmacy': return _C.teal;
      case 'Hospital': return _C.rose;
      default: return _C.sky;
    }
  }

  IconData get _kindIcon {
    switch (facility.kind) {
      case 'Pharmacy': return Icons.local_pharmacy_rounded;
      case 'Hospital': return Icons.local_hospital_rounded;
      default: return Icons.medical_services_rounded;
    }
  }

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: _C.card,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _C.border),
      boxShadow: [BoxShadow(color: MedicColors.forest.withOpacity(0.025),
          blurRadius: 10, offset: const Offset(0, 3))],
    ),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
            color: _kindColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12)),
        child: Icon(_kindIcon, color: _kindColor, size: 22),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(facility.name,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _C.textPri),
            maxLines: 2, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 5),
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
                color: _kindColor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(7)),
            child: Text(facility.kind, style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700, color: _kindColor)),
          ),
          const SizedBox(width: 8),
          Icon(Icons.place_rounded, size: 11, color: _C.textTer),
          const SizedBox(width: 2),
          Text('${facility.distanceKm.toStringAsFixed(1)} km away',
              style: const TextStyle(fontSize: 11, color: _C.textSec, fontWeight: FontWeight.w500)),
        ]),
        if (facility.address != null) ...[
          const SizedBox(height: 4),
          Text(facility.address!,
              style: const TextStyle(fontSize: 11.5, color: _C.textTer, height: 1.35),
              maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      ])),
      const SizedBox(width: 6),
      GestureDetector(
        onTap: onDirections,
        child: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
              color: _C.teal.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _C.teal.withOpacity(0.25))),
          child: const Icon(Icons.directions_rounded, color: _C.teal, size: 18),
        ),
      ),
    ]),
  );
}
