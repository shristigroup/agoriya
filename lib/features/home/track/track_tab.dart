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

class _TrackTabState extends State<TrackTab>
    with SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();
  bool _showMarkers = true;

  /// 0→1: how much of the route has been drawn. Plays each time the route is
  /// rendered (this widget created, or its points first arriving).
  late final AnimationController _anim;

  /// Index into widget.locations of the dot the user tapped.
  int? _selected;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 3000))
      ..forward();
  }

  @override
  void didUpdateWidget(covariant TrackTab old) {
    super.didUpdateWidget(old);
    if (old.locations.length < 2 && widget.locations.length >= 2) {
      _anim.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    _mapController.dispose();
    super.dispose();
  }

  /// The route drawn up to fraction [t] of its length.
  List<LatLng> _drawn(List<LatLng> pts, double t) {
    if (t >= 1 || pts.length < 2) return pts;
    final cum = <double>[0];
    for (var i = 1; i < pts.length; i++) {
      cum.add(cum.last + AppUtils.haversineMeters(pts[i - 1], pts[i]));
    }
    final target = cum.last * t;
    final out = <LatLng>[pts.first];
    for (var i = 1; i < pts.length; i++) {
      if (cum[i] <= target) {
        out.add(pts[i]);
      } else {
        final f = (target - cum[i - 1]) / (cum[i] - cum[i - 1]);
        out.add(LatLng(
          pts[i - 1].latitude + (pts[i].latitude - pts[i - 1].latitude) * f,
          pts[i - 1].longitude + (pts[i].longitude - pts[i - 1].longitude) * f,
        ));
        break;
      }
    }
    return out;
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

  /// The label shown inside the current-location marker. lastGpsUpdateTime
  /// is HomeBloc's single, always-correctly-resolved "last active" time —
  /// derived the same way lastKnownLocation's position is (currentBatch.last
  /// → the isolate's lastConfirmedPoint anchor → finalLocations.last — see
  /// LocationSyncService.resolveLastKnownLocationWithTimestamp) — not
  /// re-derived here from widget.locations.last, which goes stale during a
  /// stationary run after a sync trims currentBatch to empty (duration
  /// keeps climbing on the anchor, invisible to finalLocations/currentBatch
  /// until the next sync commits it).
  DateTime? get _markerTime => widget.lastGpsUpdateTime;

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
            // Show the whole route, so the drawing is visible end to end.
            initialCameraFit: points.length >= 2
                ? CameraFit.bounds(
                    bounds: LatLngBounds.fromPoints(points),
                    padding: const EdgeInsets.all(48),
                    maxZoom: 17,
                  )
                : null,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all,
            ),
            onTap: (_, __) => setState(() => _selected = null),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.agoriya.app',
            ),
            // Polyline — drawn directly from stored points (snapped where available)
            if (points.length >= 2)
              AnimatedBuilder(
                animation: _anim,
                builder: (_, __) => PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _drawn(points, _anim.value),
                      strokeWidth: 4.0,
                      color: AppTheme.primary,
                    ),
                  ],
                ),
              ),
            // Markers
            if (_showMarkers)
              AnimatedBuilder(
                animation: _anim,
                builder: (_, __) => MarkerLayer(
                markers: [
                  // Intermediate route dots (all stored points except the
                  // last), tappable; shown once the route has been drawn.
                  if (_anim.isCompleted)
                    for (var i = 0; i < widget.locations.length - 1; i++)
                      Marker(
                        point: widget.locations[i].position,
                        width: 28, // larger hit area around the 12 px dot
                        height: 28,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => setState(() => _selected = i),
                          child: Center(
                            child: Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withOpacity(0.7),
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: Colors.white, width: 1.5),
                              ),
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
              ),
          ],
        ),

        // Tapped dot: arrival time, plus how long they stayed if recorded
        if (_selected != null && _selected! < widget.locations.length)
          Positioned(
            left: 12,
            bottom: 20,
            child: _pointCard(widget.locations[_selected!]),
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
                    Icon(Icons.location_off_rounded,
                        color: AppTheme.textHint, size: 40),
                    const SizedBox(height: 10),
                    Text(
                      // No spinner here even while acquiring — the first
                      // location doesn't land in Firestore until the first
                      // batch sync (up to LOCATION_BATCH_MINUTES after
                      // punch-in), so a spinner would just sit there for
                      // minutes looking stuck rather than "in progress".
                      acquiring
                          ? 'Yet to capture location'
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

  Widget _pointCard(LocationPoint p) {
    final stayed = p.durationSeconds ?? 0;
    final time = AppUtils.formatTime(p.timestamp);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.15), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(stayed > 0 ? 'Arrived $time' : 'At $time',
              style: AppTheme.sora(12,
                  weight: FontWeight.w700, color: AppTheme.textPrimary)),
          if (stayed > 0)
            Text(
                'Stayed ${AppUtils.formatDuration(Duration(seconds: stayed))}',
                style: AppTheme.sora(12,
                    weight: FontWeight.w500, color: AppTheme.textSecondary)),
        ],
      ),
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
