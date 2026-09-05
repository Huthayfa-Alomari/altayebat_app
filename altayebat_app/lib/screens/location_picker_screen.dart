import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../models/picked_location.dart';

class LocationPickerScreen extends StatefulWidget {
  final double? initialLatitude;
  final double? initialLongitude;

  const LocationPickerScreen({
    super.key,
    this.initialLatitude,
    this.initialLongitude,
  });

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  final MapController _mapController = MapController();

  late LatLng _selected;
  double? _accuracy;
  String _source = 'map';
  bool _locating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selected = LatLng(
      widget.initialLatitude ?? 32.0608,
      widget.initialLongitude ?? 36.0942,
    );

    if (widget.initialLatitude == null || widget.initialLongitude == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _useMyLocation());
    }
  }

  Future<void> _useMyLocation() async {
    if (_locating) return;

    setState(() {
      _locating = true;
      _error = null;
    });

    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        throw StateError('فعّل خدمة الموقع (GPS) ثم حاول مرة ثانية');
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        throw StateError('نحتاج إذن الموقع حتى نحدد عنوانك تلقائيًا');
      }

      if (permission == LocationPermission.deniedForever) {
        throw StateError(
          'إذن الموقع مرفوض نهائيًا. فعّله من إعدادات التطبيق أو حدد الموقع يدويًا على الخريطة',
        );
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      final point = LatLng(position.latitude, position.longitude);
      if (!mounted) return;

      setState(() {
        _selected = point;
        _accuracy = position.accuracy;
        _source = 'gps';
      });
      _mapController.move(point, 17);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _confirm() {
    Navigator.of(context).pop(
      PickedLocation(
        latitude: _selected.latitude,
        longitude: _selected.longitude,
        accuracyMeters: _accuracy,
        source: _source,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('حدد موقع التوصيل')),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _selected,
              initialZoom: 15,
              minZoom: 7,
              maxZoom: 19,
              onTap: (_, point) {
                setState(() {
                  _selected = point;
                  _accuracy = null;
                  _source = 'map';
                  _error = null;
                });
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.altayebat.app',
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: _selected,
                    width: 56,
                    height: 56,
                    child: const Icon(
                      Icons.location_pin,
                      size: 52,
                      color: Color(0xFFE31E24),
                    ),
                  ),
                ],
              ),
              const RichAttributionWidget(
                attributions: [
                  TextSourceAttribution('OpenStreetMap contributors'),
                ],
              ),
            ],
          ),
          PositionedDirectional(
            top: 14,
            start: 14,
            end: 14,
            child: Material(
              elevation: 2,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.touch_app_outlined, size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'حرّك الخريطة واضغط على موقع البيت، أو استخدم موقعك الحالي.',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                    IconButton(
                      tooltip: 'موقعي الحالي',
                      onPressed: _locating ? null : _useMyLocation,
                      icon: _locating
                          ? const SizedBox(
                              width: 21,
                              height: 21,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.my_location),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_error != null)
            PositionedDirectional(
              start: 14,
              end: 14,
              bottom: 92,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF1F2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      color: Color(0xFF9F1239),
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          child: FilledButton.icon(
            onPressed: _confirm,
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('اعتماد هذا الموقع'),
          ),
        ),
      ),
    );
  }
}
