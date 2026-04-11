import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_utils.dart';
import '../../../../data/models/attendance_model.dart';
import '../../../../data/models/location_model.dart';
import '../../../../services/osrm_service.dart';

class TrackTab extends StatefulWidget {
  final AttendanceModel? attendance;
  final List<LocationPoint> locations;
  final LatLng? lastKnownLocation;
  final bool isReadOnly;

  const TrackTab({
    super.key,
    this.attendance,
    this.locations = const [],
    this.lastKnownLocation,
    this.isReadOnly = false,
  });

  @override
  State<TrackTab> createState() => _TrackTabState();
}

class _TrackTabState extends State<TrackTab> {
  final MapController _mapController = MapController();
  bool _showMarkers = true;
  List<LatLng> _snappedPoints = [];
  bool _snapping = false;

  @override
  void initState() {
    super.initState();
    _snapPoints();
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(TrackTab old) {
    super.didUpdateWidget(old);
    if (old.locations.length != widget.locations.length) {
      _snapPoints();
    }
  }

  Future<void> _snapPoints() async {
    if (widget.locations.length < 2) {
      if (mounted) {
        setState(() => _snappedPoints =
            widget.locations.map((p) => p.position).toList());
      }
      return;
    }
    if (mounted) setState(() => _snapping = true);
    try {
      final snapped = await OsrmService.snapToRoads(
        widget.locations.map((p) => p.position).toList(),
      );
      if (mounted) setState(() => _snappedPoints = snapped);
    } catch (_) {
      if (mounted) {
        setState(() => _snappedPoints =
            widget.locations.map((p) => p.position).toList());
      }
    }
    if (mounted) setState(() => _snapping = false);
  }

  LatLng get _mapCenter {
    if (widget.locations.isNotEmpty) return widget.locations.last.position;
    if (widget.lastKnownLocation != null) return widget.lastKnownLocation!;
    return const LatLng(20.5937, 78.9629); // India center
  }

  @override
  Widget build(BuildContext context) {
    final hasData = widget.locations.isNotEmpty;

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _mapCenter,
            initialZoom: hasData ? 14.0 : 10.0,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.agoriya.app',
            ),
            // Polyline
            if (_snappedPoints.length >= 2)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _snappedPoints,
                    strokeWidth: 4.0,
                    color: AppTheme.primary,
                  ),
                ],
              ),
            // Markers
            if (_showMarkers && hasData)
              MarkerLayer(
                markers: [
                  // Start marker
                  Marker(
                    point: widget.locations.first.position,
                    width: 32,
                    height: 32,
                    child: Container(
                      decoration: const BoxDecoration(
                        color: AppTheme.punchIn,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.play_arrow, color: Colors.white, size: 18),
                    ),
                  ),
                  // Intermediate points
                  ...widget.locations
                      .skip(1)
                      .take(widget.locations.length - 2)
                      .map(
                        (p) => Marker(
                          point: p.position,
                          width: 12,
                          height: 12,
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withOpacity(0.7),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 1.5),
                            ),
                          ),
                        ),
                      ),
                  // Current / last marker
                  if (widget.locations.length > 1)
                    Marker(
                      point: widget.locations.last.position,
                      width: 40,
                      height: 40,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppTheme.accent,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.accent.withOpacity(0.4),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Icon(Icons.person_pin, color: Colors.white, size: 22),
                      ),
                    ),
                ],
              ),
          ],
        ),

        // No data watermark
        if (!hasData)
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.9),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.location_off_rounded,
                      color: AppTheme.textHint, size: 40),
                  const SizedBox(height: 8),
                  Text(
                    widget.attendance?.isPunchedIn == true
                        ? 'No location data yet'
                        : 'No user location data yet',
                    style: const TextStyle(
                      fontFamily: 'Sora',
                      fontSize: 14,
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Controls overlay
        Positioned(
          right: 12,
          bottom: 20,
          child: Column(
            children: [
              // Toggle markers
              _mapButton(
                icon: _showMarkers ? Icons.location_on : Icons.location_off,
                color: _showMarkers ? AppTheme.primary : AppTheme.textSecondary,
                onTap: () => setState(() => _showMarkers = !_showMarkers),
                tooltip: _showMarkers ? 'Hide markers' : 'Show markers',
              ),
              const SizedBox(height: 8),
              // Zoom in
              _mapButton(
                icon: Icons.add,
                onTap: () => _mapController.move(
                  _mapController.camera.center,
                  _mapController.camera.zoom + 1,
                ),
              ),
              const SizedBox(height: 8),
              // Zoom out
              _mapButton(
                icon: Icons.remove,
                onTap: () => _mapController.move(
                  _mapController.camera.center,
                  _mapController.camera.zoom - 1,
                ),
              ),
              const SizedBox(height: 8),
              // Center on current
              if (hasData)
                _mapButton(
                  icon: Icons.my_location,
                  onTap: () => _mapController.move(
                    widget.locations.last.position,
                    15.0,
                  ),
                ),
            ],
          ),
        ),

        // Last location time
        if (hasData)
          Positioned(
            bottom: 20,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 6,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.access_time, size: 14, color: AppTheme.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    'Last: ${AppUtils.formatTime(widget.locations.last.timestamp)}',
                    style: const TextStyle(
                      fontFamily: 'Sora',
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Snapping indicator
        if (_snapping)
          Positioned(
            top: 12,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Snapping to roads...',
                      style: TextStyle(
                        fontFamily: 'Sora',
                        fontSize: 12,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _mapButton({
    required IconData icon,
    required VoidCallback onTap,
    Color color = AppTheme.textPrimary,
    String? tooltip,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: tooltip ?? '',
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 6,
              ),
            ],
          ),
          child: Icon(icon, color: color, size: 20),
        ),
      ),
    );
  }
}
