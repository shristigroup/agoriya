import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/app_utils.dart';
import '../../../data/data_manager.dart';
import '../../../data/models/tracking_model.dart';
import '../../../data/models/location_model.dart';
import '../../../data/models/visit_model.dart';
import '../../home/track/track_tab.dart';
import '../../home/visits/visit_detail_screen.dart';

class HistoryDayScreen extends StatefulWidget {
  final String userId;
  final String? userName;
  final TrackingModel tracking;

  const HistoryDayScreen({
    super.key,
    required this.userId,
    this.userName,
    required this.tracking,
  });

  @override
  State<HistoryDayScreen> createState() => _HistoryDayScreenState();
}

class _HistoryDayScreenState extends State<HistoryDayScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Visits
  List<VisitModel> _visits = [];
  bool _visitsLoading = true;

  // Locations (fetched on demand)
  List<LocationPoint> _locations = [];
  _RouteState _routeState = _RouteState.idle;

  // Punch-in image (fetched on demand)
  _ImageState _imageState = _ImageState.idle;
  String? _punchInImageUrl;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchVisits();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchVisits() async {
    try {
      final visits = await DataManager.getVisitsForDay(
          widget.userId, widget.tracking.date);
      if (mounted) setState(() { _visits = visits; _visitsLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _visitsLoading = false);
    }
  }

  Future<void> _fetchRoute() async {
    setState(() => _routeState = _RouteState.loading);
    try {
      final points = await DataManager.getLocationsForTracking(
          widget.userId, widget.tracking.id);
      if (mounted) {
        setState(() {
          _locations = points;
          _routeState = _RouteState.loaded;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _routeState = _RouteState.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tracking;
    final date = DateTime.parse(t.date);
    final title = AppUtils.formatDateDisplay(date);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        title: Text(title,
            style: AppTheme.sora(18, weight: FontWeight.w700, color: Colors.white)),
      ),
      body: Column(
        children: [
          // ── Tracking header ───────────────────────────────────────────────
          _buildHeader(t),

          // ── Tabs ─────────────────────────────────────────────────────────
          Container(
            color: AppTheme.primary,
            child: TabBar(
              controller: _tabController,
              indicatorColor: AppTheme.accent,
              indicatorWeight: 3,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              labelStyle: AppTheme.sora(14, weight: FontWeight.w600),
              unselectedLabelStyle: AppTheme.sora(14),
              tabs: const [Tab(text: 'Track'), Tab(text: 'Visits')],
            ),
          ),

          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildTrackTab(),
                _buildVisitsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(TrackingModel t) {
    final punchIn = t.startTime;
    final punchOut = t.stopTime;
    final duration = t.attendanceDuration;

    return Container(
      color: AppTheme.primary,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        children: [
          _headerStat(
            Icons.login_rounded,
            'In',
            AppUtils.formatTime(punchIn),
          ),
          _headerDivider(),
          _headerStat(
            Icons.logout_rounded,
            'Out',
            punchOut != null ? AppUtils.formatTime(punchOut) : 'Active',
          ),
          _headerDivider(),
          _headerStat(
            Icons.access_time_rounded,
            'Duration',
            AppUtils.formatDuration(duration),
          ),
          _headerDivider(),
          _headerStat(
            Icons.route_rounded,
            'Distance',
            AppUtils.formatDistance(t.distance),
          ),
        ],
      ),
    );
  }

  Widget _headerStat(IconData icon, String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: Colors.white60),
              const SizedBox(width: 4),
              Text(label, style: AppTheme.sora(10, color: Colors.white60)),
            ],
          ),
          const SizedBox(height: 3),
          Text(value,
              style: AppTheme.sora(13,
                  weight: FontWeight.w700, color: Colors.white)),
        ],
      ),
    );
  }

  Widget _headerDivider() {
    return Container(
        width: 1, height: 36, color: Colors.white.withOpacity(0.2));
  }

  Future<void> _fetchPunchInImage() async {
    final path = widget.tracking.punchInImage;
    if (path == null) return;
    setState(() => _imageState = _ImageState.loading);
    try {
      final url = await FirebaseStorage.instance.ref(path).getDownloadURL();
      if (mounted) setState(() { _punchInImageUrl = url; _imageState = _ImageState.loaded; });
    } catch (_) {
      if (mounted) setState(() => _imageState = _ImageState.error);
    }
  }

  // ── Track tab ─────────────────────────────────────────────────────────────

  Widget _buildTrackTab() {
    final hasPunchInImage = widget.tracking.punchInImage != null;
    Widget mapSection;
    if (_routeState == _RouteState.loaded) {
      mapSection = TrackTab(
        attendance: widget.tracking,
        locations: _locations,
        isReadOnly: true,
        isSnapping: false,
      );
    } else {
      mapSection = _buildRouteLoadSection();
    }
    if (!hasPunchInImage) return mapSection;
    return Column(
      children: [
        _buildPunchInImageSection(),
        Expanded(child: mapSection),
      ],
    );
  }

  Widget _buildPunchInImageSection() {
    return Container(
      width: double.infinity,
      color: AppTheme.surface,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _imageState == _ImageState.idle ? _fetchPunchInImage : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: _buildPunchInImageContent(),
          ),
        ),
      ),
    );
  }

  Widget _buildPunchInImageContent() {
    switch (_imageState) {
      case _ImageState.idle:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.image_outlined, size: 20, color: AppTheme.primary),
            const SizedBox(width: 8),
            Text('Load punch in image',
                style: AppTheme.sora(13, color: AppTheme.primary,
                    weight: FontWeight.w600)),
          ],
        );
      case _ImageState.loading:
        return const SizedBox(
          height: 20,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary)),
              SizedBox(width: 12),
              Text('Loading...'),
            ],
          ),
        );
      case _ImageState.error:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 20, color: Colors.red),
            const SizedBox(width: 8),
            Text('Could not load image',
                style: AppTheme.sora(13, color: Colors.red)),
          ],
        );
      case _ImageState.loaded:
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.network(
            _punchInImageUrl!,
            width: double.infinity,
            height: 200,
            fit: BoxFit.cover,
          ),
        );
    }
  }

  Widget _buildRouteLoadSection() {

    return Stack(
      children: [
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
          child: FlutterMap(
            options: const MapOptions(
              initialCenter: LatLng(20.5937, 78.9629),
              initialZoom: 5,
              interactionOptions:
                  InteractionOptions(flags: InteractiveFlag.none),
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.agoriya.app',
              ),
            ],
          ),
        ),

        Container(color: Colors.black.withOpacity(0.35)),

        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_routeState == _RouteState.loading) ...[
                const CircularProgressIndicator(color: Colors.white),
                const SizedBox(height: 16),
                Text('Loading route...',
                    style: AppTheme.sora(14, color: Colors.white)),
              ] else if (_routeState == _RouteState.error) ...[
                const Icon(Icons.error_outline,
                    color: Colors.white70, size: 40),
                const SizedBox(height: 12),
                Text('Could not load route',
                    style: AppTheme.sora(14, color: Colors.white70)),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _fetchRoute,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ] else ...[
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      onTap: _fetchRoute,
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 16),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.route_rounded,
                                color: AppTheme.primary, size: 24),
                            const SizedBox(width: 12),
                            Text('Show Route',
                                style: AppTheme.sora(15,
                                    weight: FontWeight.w600,
                                    color: AppTheme.primary)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Tap to load the GPS route for this session',
                  style: AppTheme.sora(12, color: Colors.white70),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ── Visits tab ────────────────────────────────────────────────────────────

  Widget _buildVisitsTab() {
    if (_visitsLoading) {
      return const Center(
          child: CircularProgressIndicator(color: AppTheme.primary));
    }

    if (_visits.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.storefront_outlined,
                size: 56, color: AppTheme.textHint),
            const SizedBox(height: 16),
            Text('No visits on this day',
                style: AppTheme.sora(15, color: AppTheme.textSecondary)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      itemCount: _visits.length,
      itemBuilder: (_, i) => _HistoryVisitCard(
        visit: _visits[i],
        targetUserId: widget.userId,
        isReadOnly: !DataManager.isOwner(widget.userId),
      ),
    );
  }
}

enum _RouteState { idle, loading, loaded, error }
enum _ImageState { idle, loading, loaded, error }

// ─── Read-only visit card for history ────────────────────────────────────────

class _HistoryVisitCard extends StatelessWidget {
  final VisitModel visit;
  final String targetUserId;
  final bool isReadOnly;

  const _HistoryVisitCard({
    required this.visit,
    required this.targetUserId,
    required this.isReadOnly,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => VisitDetailScreen(
              visit: visit,
              targetUserId: targetUserId,
              isReadOnly: isReadOnly,
            ),
          )),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.check_circle_rounded,
                      color: AppTheme.primary, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(visit.clientName,
                          style: AppTheme.sora(14, weight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(visit.location,
                          style: AppTheme.sora(12,
                              color: AppTheme.textSecondary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.login_rounded,
                              size: 12, color: AppTheme.textHint),
                          const SizedBox(width: 4),
                          Text(AppUtils.formatTime(visit.checkinTimestamp),
                              style: AppTheme.sora(11,
                                  color: AppTheme.textHint)),
                          if (visit.checkoutTimestamp != null) ...[
                            Text(' → ',
                                style: AppTheme.sora(11,
                                    color: AppTheme.textHint)),
                            Text(
                                AppUtils.formatTime(
                                    visit.checkoutTimestamp!),
                                style: AppTheme.sora(11,
                                    color: AppTheme.textHint)),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (visit.expenseAmount != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                        '₹${visit.expenseAmount!.toStringAsFixed(0)}',
                        style: AppTheme.sora(12,
                            weight: FontWeight.w700,
                            color: AppTheme.primary)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
