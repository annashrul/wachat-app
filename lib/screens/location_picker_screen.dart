import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../theme.dart';

/// Hasil pemilihan lokasi dari [LocationPickerScreen].
class LocationPickResult {
  final double lat;
  final double lng;
  final bool live;
  final Duration? duration;
  final String? placeName;

  const LocationPickResult({
    required this.lat,
    required this.lng,
    this.live = false,
    this.duration,
    this.placeName,
  });
}

/// Satu tempat di sekitar (hasil Overpass API).
class _NearbyPlace {
  final String name;
  final String category;
  final double lat;
  final double lng;
  final double distanceMeters;
  const _NearbyPlace(
      this.name, this.category, this.lat, this.lng, this.distanceMeters);
}

/// Layar pemilih lokasi ala WhatsApp: peta interaktif OSM, kirim lokasi
/// terkini, bagikan lokasi langsung, dan daftar tempat di sekitar.
class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({super.key});

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  final _map = MapController();
  final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 18),
    headers: const {'User-Agent': 'WAChat/1.0 (location picker)'},
  ));

  LatLng _center = const LatLng(-6.2088, 106.8456); // default Jakarta
  bool _ready = false;
  bool _permError = false;

  String? _address;
  bool _loadingAddress = false;

  List<_NearbyPlace> _places = [];
  bool _loadingPlaces = false;

  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _map.dispose();
    super.dispose();
  }

  Future<void> _initLocation() async {
    try {
      if (await Geolocator.isLocationServiceEnabled()) {
        var perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) {
          perm = await Geolocator.requestPermission();
        }
        if (perm != LocationPermission.denied &&
            perm != LocationPermission.deniedForever) {
          final pos = await Geolocator.getCurrentPosition();
          _center = LatLng(pos.latitude, pos.longitude);
        } else {
          _permError = true;
        }
      } else {
        _permError = true;
      }
    } catch (_) {
      _permError = true;
    }
    if (!mounted) return;
    setState(() => _ready = true);
    _map.move(_center, 16);
    _refreshForCenter();
  }

  /// Pusat peta berubah → muat ulang alamat & tempat sekitar (debounce).
  void _onCenterChanged(LatLng c) {
    _center = c;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _refreshForCenter);
  }

  void _refreshForCenter() {
    _reverseGeocode(_center);
    _fetchNearby(_center);
  }

  Future<void> _reverseGeocode(LatLng c) async {
    setState(() => _loadingAddress = true);
    try {
      final res = await _dio.get(
        'https://nominatim.openstreetmap.org/reverse',
        queryParameters: {
          'format': 'jsonv2',
          'lat': c.latitude,
          'lon': c.longitude,
          'zoom': 18,
          'addressdetails': 0,
        },
      );
      final data = res.data;
      final name = data is Map ? data['display_name'] as String? : null;
      if (mounted) setState(() => _address = name);
    } catch (_) {
      if (mounted) setState(() => _address = null);
    } finally {
      if (mounted) setState(() => _loadingAddress = false);
    }
  }

  Future<void> _fetchNearby(LatLng c) async {
    setState(() => _loadingPlaces = true);
    try {
      final lat = c.latitude;
      final lng = c.longitude;
      final query = '[out:json][timeout:15];'
          '(node(around:300,$lat,$lng)[name][amenity];'
          'node(around:300,$lat,$lng)[name][shop];'
          'node(around:300,$lat,$lng)[name][tourism];);'
          'out 30;';
      final res = await _dio.post(
        'https://overpass-api.de/api/interpreter',
        data: 'data=${Uri.encodeComponent(query)}',
        options: Options(
          contentType: 'application/x-www-form-urlencoded',
        ),
      );
      final elements = (res.data is Map ? res.data['elements'] : null) as List?;
      final out = <_NearbyPlace>[];
      for (final e in elements ?? []) {
        final m = e as Map;
        final tags = m['tags'] as Map?;
        final name = tags?['name'] as String?;
        final plat = (m['lat'] as num?)?.toDouble();
        final plng = (m['lon'] as num?)?.toDouble();
        if (name == null || plat == null || plng == null) continue;
        final cat = (tags?['amenity'] ??
                tags?['shop'] ??
                tags?['tourism'] ??
                'tempat')
            .toString();
        final dist = Geolocator.distanceBetween(lat, lng, plat, plng);
        out.add(_NearbyPlace(name, cat, plat, plng, dist));
      }
      out.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
      if (mounted) setState(() => _places = out.take(25).toList());
    } catch (_) {
      if (mounted) setState(() => _places = []);
    } finally {
      if (mounted) setState(() => _loadingPlaces = false);
    }
  }

  Future<void> _recenterToGps() async {
    try {
      final pos = await Geolocator.getCurrentPosition();
      final c = LatLng(pos.latitude, pos.longitude);
      _center = c;
      _map.move(c, 16);
      _refreshForCenter();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal mengambil lokasi saat ini')),
        );
      }
    }
  }

  void _sendCenter() {
    Navigator.pop(
      context,
      LocationPickResult(
        lat: _center.latitude,
        lng: _center.longitude,
        placeName: _address,
      ),
    );
  }

  void _sendPlace(_NearbyPlace p) {
    Navigator.pop(
      context,
      LocationPickResult(lat: p.lat, lng: p.lng, placeName: p.name),
    );
  }

  Future<void> _shareLive() async {
    final dur = await showModalBottomSheet<Duration>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Bagikan lokasi langsung',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            for (final o in const [
              (label: '15 menit', mins: 15),
              (label: '1 jam', mins: 60),
              (label: '8 jam', mins: 480),
            ])
              ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: Text(o.label),
                onTap: () => Navigator.pop(context, Duration(minutes: o.mins)),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (dur == null || !mounted) return;
    Navigator.pop(
      context,
      LocationPickResult(
        lat: _center.latitude,
        lng: _center.longitude,
        live: true,
        duration: dur,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Kirim lokasi')),
      body: !_ready
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // ---- Peta interaktif dengan pin tengah ----
                Expanded(
                  flex: 5,
                  child: Stack(
                    children: [
                      FlutterMap(
                        mapController: _map,
                        options: MapOptions(
                          initialCenter: _center,
                          initialZoom: 16,
                          onPositionChanged: (camera, hasGesture) {
                            if (hasGesture) _onCenterChanged(camera.center);
                          },
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.wachat.wachat',
                            maxZoom: 19,
                          ),
                        ],
                      ),
                      // Pin tetap di tengah (lokasi yang dipilih).
                      IgnorePointer(
                        child: Center(
                          child: Transform.translate(
                            offset: const Offset(0, -18),
                            child: Icon(Icons.location_on_rounded,
                                size: 44, color: scheme.error),
                          ),
                        ),
                      ),
                      // Tombol recenter ke GPS.
                      Positioned(
                        right: 12,
                        bottom: 12,
                        child: FloatingActionButton.small(
                          heroTag: 'gps',
                          onPressed: _recenterToGps,
                          child: const Icon(Icons.my_location_rounded),
                        ),
                      ),
                      if (_permError)
                        Positioned(
                          left: 12,
                          right: 64,
                          bottom: 12,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: scheme.errorContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Izin lokasi tidak aktif — geser peta untuk memilih.',
                              style: TextStyle(
                                  color: scheme.onErrorContainer, fontSize: 12),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                // ---- Panel aksi + daftar tempat ----
                Expanded(
                  flex: 5,
                  child: Container(
                    color: palette.chatBackground,
                    child: ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        // Kirim lokasi yang ditunjuk pin.
                        ListTile(
                          leading: CircleAvatar(
                            backgroundColor: scheme.error,
                            child: const Icon(Icons.location_on_rounded,
                                color: Colors.white),
                          ),
                          title: const Text('Kirim lokasi ini',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            _loadingAddress
                                ? 'Memuat alamat…'
                                : (_address ?? 'Lokasi terpilih di peta'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: _sendCenter,
                        ),
                        // Bagikan lokasi langsung.
                        ListTile(
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFF16A34A),
                            child: const Icon(Icons.my_location_rounded,
                                color: Colors.white),
                          ),
                          title: const Text('Bagikan lokasi langsung',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: const Text(
                              'Anggota melihat posisi Anda secara real-time'),
                          onTap: _shareLive,
                        ),
                        const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                          child: Row(
                            children: [
                              Text('Tempat di sekitar',
                                  style: TextStyle(
                                      color: palette.muted,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(width: 8),
                              if (_loadingPlaces)
                                const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2)),
                            ],
                          ),
                        ),
                        if (!_loadingPlaces && _places.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text('Tidak ada tempat terdeteksi di sekitar',
                                style: TextStyle(color: palette.muted)),
                          ),
                        for (final p in _places)
                          ListTile(
                            dense: true,
                            leading: Icon(_iconFor(p.category),
                                color: scheme.primary),
                            title: Text(p.name,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                                '${_prettyCat(p.category)} • ${_dist(p.distanceMeters)}'),
                            onTap: () => _sendPlace(p),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  String _dist(double m) =>
      m < 1000 ? '${m.round()} m' : '${(m / 1000).toStringAsFixed(1)} km';

  String _prettyCat(String c) =>
      c.isEmpty ? 'Tempat' : c[0].toUpperCase() + c.substring(1).replaceAll('_', ' ');

  IconData _iconFor(String c) {
    switch (c) {
      case 'restaurant':
      case 'fast_food':
      case 'food_court':
        return Icons.restaurant_rounded;
      case 'cafe':
        return Icons.local_cafe_rounded;
      case 'hospital':
      case 'clinic':
      case 'pharmacy':
        return Icons.local_hospital_rounded;
      case 'school':
      case 'university':
      case 'college':
        return Icons.school_rounded;
      case 'bank':
      case 'atm':
        return Icons.account_balance_rounded;
      case 'fuel':
        return Icons.local_gas_station_rounded;
      case 'place_of_worship':
        return Icons.mosque_rounded;
      case 'supermarket':
      case 'convenience':
      case 'mall':
        return Icons.shopping_cart_rounded;
      case 'hotel':
        return Icons.hotel_rounded;
      default:
        return Icons.place_rounded;
    }
  }
}
