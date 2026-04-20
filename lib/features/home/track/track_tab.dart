import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_utils.dart';
import '../../../../data/models/tracking_model.dart';
import '../../../../data/models/location_model.dart';

class TrackTab extends StatefulWidget {
  final TrackingModel? attendance;
  final List<LocationPoint> locations;
  final LatLng? lastKnownLocation;

  /// Wall-clock time of the last GPS ping from the background service.
  /// Updated even when stationary (no new point stored).
  /// null in read-only / history mode — falls back to locations.last.timestamp.
  final DateTime? lastGpsUpdateTime;

  final bool isReadOnly;
  final bool isSnapping; // OSRM snap in progress — shows indicator

  const TrackTab({
    super.key,
    this.attendance,
    this.locations = const [],
    this.lastKnownLocation,
    this.lastGpsUpdateTime,
    this.isReadOnly = false,
    this.isSnapping = false,
  });

  @override
  State<TrackTab> createState() => _TrackTabState();
}

class _TrackTabState extends State<TrackTab> {
  final MapController _mapController = MapController();
  bool _showMarkers = true;

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  LatLng get _mapCenter {
    // Prefer lastKnownLocation — updated on every GPS event including
    // stationary pings, so it's always the freshest position.
    if (widget.lastKnownLocation != null) return widget.lastKnownLocation!;
    if (widget.locations.isNotEmpty) return widget.locations.last.position;
    return const LatLng(20.5937, 78.9629); // India centre
  }

  /// The position to show for the current-location marker.
  LatLng? get _currentPosition =>
      widget.lastKnownLocation ??
      (widget.locations.isNotEmpty ? widget.locations.last.position : null);

  /// The label shown inside the current-location marker.
  /// Uses lastPoint.timestamp + durationSeconds so owner and manager both see
  /// the same effective "last active" time. Falls back to lastGpsUpdateTime
  /// when no stored points exist yet (e.g. acquiring first GPS fix).
  DateTime? get _markerTime {
    if (widget.locations.isEmpty) return widget.lastGpsUpdateTime;
    final last = widget.locations.last;
    return last.timestamp.add(Duration(seconds: last.durationSeconds ?? 0));
  }

  @override
  Widget build(BuildContext context) {
    final hasData = widget.locations.isNotEmpty;
    final points = widget.locations.map((p) => p.position).toList();

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
              userAgentPackageName: 'com.trackfolks.app',
            ),
            // Polyline — drawn directly from stored points (snapped where available)
            if (points.length >= 2)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: points,
                    strokeWidth: 4.0,
                    color: AppTheme.primary,
                  ),
                ],
              ),
            // Markers
            if (_showMarkers)
              MarkerLayer(
                markers: [
                  // Intermediate route dots (all stored points except the last)
                  if (hasData && widget.locations.length > 1)
                    ...widget.locations
                        .take(widget.locations.length - 1)
                        .map(
                          (p) => Marker(
                            point: p.position,
                            width: 12,
                            height: 12,
                            child: Container(
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withOpacity(0.7),
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: Colors.white, width: 1.5),
                              ),
                            ),
                          ),
                        ),
                  // Current position — shown as soon as we have a GPS fix,
                  // even before any points are stored (stationary case).
                  if (_currentPosition != null && _markerTime != null)
                    Marker(
                      point: _currentPosition!,
                      width: 90,
                      height: 62,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.12),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                            child: Text(
                              AppUtils.formatTime(_markerTime!),
                              style: AppTheme.sora(10,
                                  weight: FontWeight.w600,
                                  color: AppTheme.textSecondary),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: AppTheme.accent,
                              shape: BoxShape.circle,
                              border:
                                  Border.all(color: Colors.white, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.accent.withValues(alpha: 0.4),
                                  blurRadius: 8,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: const Icon(Icons.person_pin,
                                color: Colors.white, size: 22),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
          ],
        ),

        // No data watermark
        if (!hasData)
          Builder(builder: (context) {
            final isPunchedIn = widget.attendance?.isPunchedIn == true;
            final isPunchedOut = widget.attendance?.isPunchedOut == true;
            final acquiring = isPunchedIn && !isPunchedOut;
            return Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (acquiring)
                      const SizedBox(
                        width: 36,
                        height: 36,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: AppTheme.primary,
                        ),
                      )
                    else
                      Icon(Icons.location_off_rounded,
                          color: AppTheme.textHint, size: 40),
                    const SizedBox(height: 10),
                    Text(
                      acquiring
                          ? 'Acquiring GPS location...'
                          : 'No location data yet',
                      style: AppTheme.sora(14,
                          weight: FontWeight.w500,
                          color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
            );
          }),

        // Map controls
        Positioned(
          right: 12,
          bottom: 20,
          child: Column(
            children: [
              _mapButton(
                icon: _showMarkers
                    ? Icons.location_on
                    : Icons.location_off,
                color: _showMarkers
                    ? AppTheme.primary
                    : AppTheme.textSecondary,
                onTap: () =>
                    setState(() => _showMarkers = !_showMarkers),
                tooltip: _showMarkers ? 'Hide markers' : 'Show markers',
              ),
              const SizedBox(height: 8),
              _mapButton(
                icon: Icons.add,
                onTap: () => _mapController.move(
                  _mapController.camera.center,
                  _mapController.camera.zoom + 1,
                ),
              ),
              const SizedBox(height: 8),
              _mapButton(
                icon: Icons.remove,
                onTap: () => _mapController.move(
                  _mapController.camera.center,
                  _mapController.camera.zoom - 1,
                ),
              ),
              const SizedBox(height: 8),
              if (_currentPosition != null)
                _mapButton(
                  icon: Icons.my_location,
                  onTap: () => _mapController.move(_currentPosition!, 15.0),
                ),
            ],
          ),
        ),

        // OSRM snapping indicator
        if (widget.isSnapping)
          Positioned(
            top: 12,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('Snapping to roads...',
                        style: AppTheme.sora(12, color: Colors.white)),
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
