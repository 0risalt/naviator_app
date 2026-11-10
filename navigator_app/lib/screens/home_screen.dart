import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:yandex_maps_mapkit/image.dart' as image_provider;
import 'package:yandex_maps_mapkit/mapkit.dart' as ymk;
import 'package:yandex_maps_mapkit/mapkit_factory.dart';
import 'package:yandex_maps_mapkit/yandex_map.dart';

import '../assets/map_style.dart';
import '../config.dart';
import '../services/supabase_service.dart';
import '../services/yandex_api.dart';
import '../theme/app_colors.dart';
import '../utils/format.dart';

enum _EditTarget { start, destination, waypoint }

class _Waypoint {
  ymk.Point? point;
  String address = '';
  ymk.PlacemarkMapObject? marker;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  static const double _sheetHeight = 320;

  final SupabaseService _supabase = SupabaseService();
  final YandexApi _api = YandexApi();

  late final TabController _tabs = TabController(length: 4, vsync: this);
  late final AppLifecycleListener _lifecycle;
  late final image_provider.ImageProvider _pinkMarkerIcon;

  // Карта
  ymk.Map? _map;
  ymk.TrafficLayer? _trafficLayer;
  // Слушатель нужно держать сильной ссылкой — MapKit хранит его слабо.
  _MapInputListener? _inputListener;
  bool _mapReady = false;
  bool _isTrafficOn = false;

  // Точки маршрута
  ymk.Point? _currentPosition;
  ymk.Point? _startPoint;
  ymk.Point? _destination;
  String? _startAddress;
  String? _destinationAddress;
  final List<_Waypoint> _waypoints = [];

  ymk.PlacemarkMapObject? _currentLocationMarker;
  ymk.PlacemarkMapObject? _startMarker;
  ymk.PlacemarkMapObject? _destinationMarker;
  ymk.PolylineMapObject? _routePolyline;

  double? _routeDistance;
  double? _routeDuration;
  bool _isRouting = false;

  // Режим редактирования точки
  _EditTarget? _editTarget;
  int? _editWaypointIndex;

  // Поиск
  final TextEditingController _searchController = TextEditingController();
  List<Suggestion> _suggestions = [];
  bool _isLoadingSuggestions = false;
  bool _searchOrganizations = false;
  Timer? _debounce;

  // Закладки, история, дом/работа
  List<Map<String, dynamic>> _bookmarks = [];
  List<Map<String, dynamic>> _history = [];
  Map<String, dynamic>? _homePointData;
  Map<String, dynamic>? _workPointData;

  @override
  void initState() {
    super.initState();
    _pinkMarkerIcon = image_provider.ImageProvider.fromImageProvider(
      const AssetImage('assets/images/pink_marker.png'),
    );

    mapkit.onStart();
    _lifecycle = AppLifecycleListener(
      onResume: () => mapkit.onStart(),
      onPause: () => mapkit.onStop(),
    );

    _determinePosition();
    _loadDataFromSupabase();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _tabs.dispose();
    _lifecycle.dispose();
    mapkit.onStop();
    super.dispose();
  }

  // ---------------------------------------------------------------- данные

  Future<void> _loadDataFromSupabase() async {
    try {
      final bookmarks = await _supabase.getBookmarks();
      final history = await _supabase.getHistory();
      final home = await _supabase.getPlace('home');
      final work = await _supabase.getPlace('work');
      if (!mounted) return;
      setState(() {
        _bookmarks = bookmarks;
        _history = history;
        _homePointData = home;
        _workPointData = work;
      });
    } catch (e) {
      debugPrint('Ошибка загрузки из Supabase: $e');
    }
  }

  // ---------------------------------------------------------- геопозиция

  Future<void> _determinePosition({bool userInitiated = false}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (userInitiated) _snack('Включите геолокацию на устройстве');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (userInitiated) _snack('Нет доступа к геопозиции');
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (!mounted) return;
      final point = ymk.Point(
        latitude: position.latitude,
        longitude: position.longitude,
      );
      setState(() => _currentPosition = point);
      _showCurrentLocation(moveCamera: true);
    } catch (e) {
      debugPrint('Location error: $e');
      if (userInitiated) _snack('Не удалось определить местоположение');
    }
  }

  void _showCurrentLocation({required bool moveCamera}) {
    final p = _currentPosition;
    if (p == null || _map == null) return;
    _removeMarker(_currentLocationMarker);
    _currentLocationMarker = _addMarker(p);
    if (moveCamera) _moveCamera(p, zoom: 15);
  }

  // ----------------------------------------------------------------- карта

  void _onMapCreated(ymk.MapWindow mapWindow) {
    final map = mapWindow.map;
    _map = map;

    if (!map.setMapStyle(pinkMapStyle)) {
      debugPrint('Не удалось применить розовый стиль карты');
    }

    try {
      _trafficLayer = mapkit.createTrafficLayer(mapWindow)
        ..setTrafficVisible(false);
    } catch (e) {
      debugPrint('Failed to create traffic layer: $e');
    }

    _inputListener = _MapInputListener(_handleMapTap);
    map.addInputListener(_inputListener!);

    final start = _currentPosition ??
        ymk.Point(
          latitude: AppConfig.defaultLat,
          longitude: AppConfig.defaultLon,
        );
    _moveCamera(start, zoom: _currentPosition != null ? 15 : 12);
    _showCurrentLocation(moveCamera: false);

    setState(() => _mapReady = true);
  }

  void _moveCamera(ymk.Point point, {double zoom = 16}) {
    _map?.move(
      ymk.CameraPosition(point, zoom: zoom, azimuth: 0.0, tilt: 0.0),
    );
  }

  ymk.PlacemarkMapObject? _addMarker(ymk.Point point) {
    final marker = _map?.mapObjects.addPlacemark();
    if (marker == null) return null;
    marker
      ..geometry = point
      ..setIcon(_pinkMarkerIcon)
      ..setIconStyle(ymk.IconStyle(scale: 0.5));
    return marker;
  }

  void _removeMarker(ymk.PlacemarkMapObject? marker) {
    if (marker != null) _map?.mapObjects.remove(marker);
  }

  void _toggleTraffic() {
    setState(() => _isTrafficOn = !_isTrafficOn);
    try {
      _trafficLayer?.setTrafficVisible(_isTrafficOn);
    } catch (e) {
      debugPrint('Failed to toggle traffic: $e');
    }
  }

  // ------------------------------------------------------ выбор/правка точек

  /// Ставит точку (начало / конец / промежуточная) и обновляет маркер.
  void _applyPoint(
    _EditTarget target,
    ymk.Point point,
    String address, {
    _Waypoint? waypoint,
    bool moveCamera = false,
  }) {
    switch (target) {
      case _EditTarget.start:
        _removeMarker(_startMarker);
        _startMarker = _addMarker(point);
        _startPoint = point;
        _startAddress = address;
      case _EditTarget.destination:
        _removeMarker(_destinationMarker);
        _destinationMarker = _addMarker(point);
        _destination = point;
        _destinationAddress = address;
      case _EditTarget.waypoint:
        if (waypoint != null) {
          _removeMarker(waypoint.marker);
          waypoint.marker = _addMarker(point);
          waypoint.point = point;
          waypoint.address = address;
        }
    }
    setState(() {
      _editTarget = null;
      _editWaypointIndex = null;
    });
    if (moveCamera) _moveCamera(point);
  }

  void _updateAddress(_EditTarget target, _Waypoint? wp, String address) {
    if (!mounted) return;
    setState(() {
      switch (target) {
        case _EditTarget.start:
          _startAddress = address;
        case _EditTarget.destination:
          _destinationAddress = address;
        case _EditTarget.waypoint:
          wp?.address = address;
      }
    });
  }

  _Waypoint? get _editingWaypoint {
    final i = _editWaypointIndex;
    if (_editTarget != _EditTarget.waypoint ||
        i == null ||
        i >= _waypoints.length) {
      return null;
    }
    return _waypoints[i];
  }

  Future<void> _handleMapTap(ymk.Point point) async {
    // Без режима редактирования клик по карте задаёт конец маршрута.
    final target = _editTarget ?? _EditTarget.destination;
    final wp = _editingWaypoint;
    if (target == _EditTarget.waypoint && wp == null) return;

    _applyPoint(target, point, 'Определение...', waypoint: wp);

    final address = await _api.reverseGeocode(
          LatLon(point.latitude, point.longitude),
        ) ??
        'Адрес не найден';
    _updateAddress(target, wp, address);
  }

  void _startEditing(_EditTarget target, {int? waypointIndex}) {
    FocusScope.of(context).unfocus();
    _searchController.clear();
    setState(() {
      _editTarget = target;
      _editWaypointIndex = waypointIndex;
      _suggestions = [];
    });
  }

  void _addWaypoint() {
    setState(() => _waypoints.add(_Waypoint()));
    _tabs.animateTo(0);
    _startEditing(_EditTarget.waypoint, waypointIndex: _waypoints.length - 1);
  }

  void _removeWaypoint(int index) {
    setState(() {
      _removeMarker(_waypoints[index].marker);
      _waypoints.removeAt(index);
      _editTarget = null;
      _editWaypointIndex = null;
    });
  }

  // ----------------------------------------------------------------- поиск

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    if (query.trim().length < 3) {
      setState(() {
        _suggestions = [];
        _isLoadingSuggestions = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      setState(() => _isLoadingSuggestions = true);
      final cur = _currentPosition;
      final result = await _api.suggest(
        query.trim(),
        organizations: _searchOrganizations,
        near: cur != null ? LatLon(cur.latitude, cur.longitude) : null,
      );
      if (!mounted) return;
      setState(() {
        _suggestions = result;
        _isLoadingSuggestions = false;
      });
    });
  }

  Future<void> _onSuggestionSelected(Suggestion item) async {
    FocusScope.of(context).unfocus();
    _searchController.text = item.title;
    setState(() => _suggestions = []);

    final target = _editTarget ?? _EditTarget.destination;
    final wp = _editingWaypoint;
    if (target == _EditTarget.waypoint && wp == null) return;

    final result = await _api.geocode(item.geocodeText);
    if (result == null) {
      _snack('Не удалось найти место');
      return;
    }
    if (!mounted) return;
    _applyPoint(
      target,
      ymk.Point(latitude: result.point.lat, longitude: result.point.lon),
      item.title,
      waypoint: wp,
      moveCamera: true,
    );
  }

  // --------------------------------------------------------------- маршрут

  Future<void> _buildRoute() async {
    final start = _startPoint ?? _currentPosition;
    final end = _destination;
    if (start == null || end == null) {
      _snack('Нужна начальная и конечная точка');
      return;
    }

    setState(() {
      _isRouting = true;
      _routeDistance = null;
      _routeDuration = null;
    });

    final points = <LatLon>[
      LatLon(start.latitude, start.longitude),
      for (final wp in _waypoints)
        if (wp.point != null) LatLon(wp.point!.latitude, wp.point!.longitude),
      LatLon(end.latitude, end.longitude),
    ];

    final route = await _api.buildRoute(points);
    if (!mounted) return;

    if (route == null) {
      setState(() => _isRouting = false);
      _snack('Не удалось построить маршрут');
      return;
    }

    if (_routePolyline != null) _map?.mapObjects.remove(_routePolyline!);
    final polyline = _map?.mapObjects.addPolyline();
    if (polyline != null) {
      polyline.geometry = ymk.Polyline(
        route.points
            .map((p) => ymk.Point(latitude: p.lat, longitude: p.lon))
            .toList(),
      );
      polyline.setStrokeColor(AppColors.primary);
      polyline.strokeWidth = 6.0;
      _routePolyline = polyline;
    }

    setState(() {
      _routeDistance = route.distance;
      _routeDuration = route.duration;
      _isRouting = false;
    });

    // Сохраняем в историю
    if (_destinationAddress != null) {
      try {
        await _supabase.savePlace(
          address: _destinationAddress!,
          lat: end.latitude,
          lon: end.longitude,
          type: 'history',
        );
        _loadDataFromSupabase();
      } catch (e) {
        debugPrint('Не удалось сохранить историю: $e');
      }
    }
  }

  /// Выбор сохранённого места (закладка/история/дом/работа) как конца маршрута.
  void _selectSavedPlace(Map<String, dynamic> data, {bool build = false}) {
    final point = ymk.Point(
      latitude: (data['latitude'] as num).toDouble(),
      longitude: (data['longitude'] as num).toDouble(),
    );
    _applyPoint(
      _EditTarget.destination,
      point,
      (data['address'] as String?) ?? '',
      moveCamera: true,
    );
    _tabs.animateTo(0);
    if (build) _buildRoute();
  }

  // ------------------------------------------------- сохранение мест в БД

  Future<void> _saveCurrentDestination(String type, String okMessage) async {
    final dest = _destination;
    final address = _destinationAddress;
    if (dest == null || address == null) {
      _snack('Сначала выберите конец маршрута');
      return;
    }
    try {
      await _supabase.savePlace(
        address: address,
        lat: dest.latitude,
        lon: dest.longitude,
        type: type,
      );
      await _loadDataFromSupabase();
      _snack(okMessage);
    } catch (e) {
      debugPrint('Ошибка сохранения ($type): $e');
      _snack('Не удалось сохранить');
    }
  }

  Future<void> _deleteItem(Map<String, dynamic> item) async {
    try {
      await _supabase.deleteItem(item['id'] as int);
      await _loadDataFromSupabase();
    } catch (e) {
      debugPrint('Ошибка удаления: $e');
      _snack('Не удалось удалить');
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  // -------------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final sheetHeight = _sheetHeight + media.padding.bottom;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          YandexMap(onMapCreated: _onMapCreated),
          Positioned(
            top: media.padding.top + 10,
            left: 16,
            right: 16,
            child: _buildTopPanel(),
          ),
          Positioned(
            right: 16,
            bottom: sheetHeight,
            child: _buildFabColumn(),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: _buildBottomSheet(sheetHeight, media.padding.bottom),
          ),
          if (!_mapReady)
            const Positioned.fill(
              child: ColoredBox(
                color: AppColors.background,
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTopPanel() {
    final editLabel = switch (_editTarget) {
      _EditTarget.start => 'Изменение начала',
      _EditTarget.destination => 'Изменение конца',
      _EditTarget.waypoint => 'Изменение промежуточной',
      null => '',
    };

    return Column(
      children: [
        if (_editTarget != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                const Icon(Icons.edit, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text(editLabel, style: const TextStyle(color: Colors.white)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 18),
                  onPressed: () => setState(() {
                    _editTarget = null;
                    _editWaypointIndex = null;
                  }),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: Colors.pink.withValues(alpha: 0.2),
                blurRadius: 10,
              ),
            ],
          ),
          child: TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              hintText: _editTarget == null
                  ? 'Поиск адреса или клик по карте'
                  : 'Введите адрес для изменения...',
              prefixIcon: const Icon(Icons.search, color: AppColors.primary),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 15),
              suffixIcon: _isLoadingSuggestions
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : IconButton(
                      icon: Icon(
                        _searchOrganizations
                            ? Icons.business
                            : Icons.location_on,
                        color: AppColors.primary,
                      ),
                      onPressed: () => setState(
                          () => _searchOrganizations = !_searchOrganizations),
                    ),
            ),
          ),
        ),
        if (_suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 8),
            constraints: const BoxConstraints(maxHeight: 250),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(color: Colors.black12, blurRadius: 10),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: _suggestions.length,
                itemBuilder: (context, index) {
                  final item = _suggestions[index];
                  return ListTile(
                    leading: const Icon(Icons.location_on,
                        color: AppColors.primary),
                    title: Text(item.title),
                    subtitle: (item.subtitle ?? '').isEmpty
                        ? null
                        : Text(item.subtitle!,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => _onSuggestionSelected(item),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildFabColumn() {
    final hasDestination =
        _destination != null && _destinationAddress != null;
    return Column(
      children: [
        FloatingActionButton(
          heroTag: 'traffic',
          mini: true,
          backgroundColor: _isTrafficOn ? AppColors.primary : Colors.white,
          foregroundColor: _isTrafficOn ? Colors.white : AppColors.primary,
          onPressed: _toggleTraffic,
          child: const Icon(Icons.traffic),
        ),
        const SizedBox(height: 8),
        FloatingActionButton(
          heroTag: 'myLocation',
          mini: true,
          backgroundColor: Colors.white,
          foregroundColor: AppColors.primary,
          onPressed: () => _determinePosition(userInitiated: true),
          child: const Icon(Icons.my_location),
        ),
        if (hasDestination) ...[
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: 'bookmark',
            mini: true,
            backgroundColor: Colors.white,
            foregroundColor: AppColors.primary,
            onPressed: () =>
                _saveCurrentDestination('bookmark', 'Добавлено в закладки'),
            child: const Icon(Icons.star),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: 'waypoint',
            mini: true,
            backgroundColor: Colors.white,
            foregroundColor: AppColors.primary,
            onPressed: _addWaypoint,
            child: const Icon(Icons.add_location_alt),
          ),
        ],
      ],
    );
  }

  Widget _buildBottomSheet(double height, double bottomInset) {
    return Container(
      height: height,
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(30),
          topRight: Radius.circular(30),
        ),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 20)],
      ),
      child: Column(
        children: [
          TabBar(
            controller: _tabs,
            labelColor: AppColors.primary,
            unselectedLabelColor: Colors.grey,
            indicatorColor: AppColors.primary,
            isScrollable: true,
            tabs: const [
              Tab(icon: Icon(Icons.route), text: 'Маршрут'),
              Tab(icon: Icon(Icons.star), text: 'Избранное'),
              Tab(icon: Icon(Icons.history), text: 'История'),
              Tab(icon: Icon(Icons.home), text: 'Дом/Работа'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _buildRouteTab(),
                _buildBookmarksTab(),
                _buildHistoryTab(),
                _buildHomeWorkTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- вкладка «Маршрут»

  Widget _buildRouteTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildPointRow(
            icon: Icons.my_location,
            label: 'Начало',
            address: _startPoint != null
                ? (_startAddress ?? '')
                : 'Мое местоположение',
            onEdit: () => _startEditing(_EditTarget.start),
          ),
          for (var i = 0; i < _waypoints.length; i++)
            _buildPointRow(
              icon: Icons.add_location_alt,
              label: 'Промежуточная ${i + 1}',
              address: _waypoints[i].point == null
                  ? 'Нажмите для выбора'
                  : _waypoints[i].address,
              onEdit: () => _startEditing(_EditTarget.waypoint,
                  waypointIndex: i),
              onDelete: () => _removeWaypoint(i),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: TextButton.icon(
              onPressed: _addWaypoint,
              icon: const Icon(Icons.add, size: 18),
              label:
                  const Text('Добавить точку', style: TextStyle(fontSize: 12)),
            ),
          ),
          _buildPointRow(
            icon: Icons.location_on,
            label: 'Конец',
            address: _destinationAddress ?? 'Выберите на карте или в поиске',
            onEdit: () => _startEditing(_EditTarget.destination),
          ),
          if (_routeDistance != null && _routeDuration != null)
            _buildRouteSummary(),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed:
                  (_destination != null && !_isRouting) ? _buildRoute : null,
              icon: _isRouting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.navigation),
              label: const Text('Построить маршрут'),
              style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRouteSummary() {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.pink.shade100),
      ),
      child: Row(
        children: [
          const Icon(Icons.timer, color: AppColors.primary, size: 20),
          const SizedBox(width: 6),
          Text(formatDuration(_routeDuration!),
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 16),
          const Icon(Icons.straighten, color: AppColors.primary, size: 20),
          const SizedBox(width: 6),
          Text(formatDistance(_routeDistance!),
              style: const TextStyle(color: Colors.grey)),
          const Spacer(),
          TextButton(
            onPressed: () => context.push('/navigate/1', extra: {
              'distance': _routeDistance,
              'duration': _routeDuration,
            }),
            child: const Text('Поехали',
                style: TextStyle(
                    color: AppColors.primary, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildPointRow({
    required IconData icon,
    required String label,
    required String address,
    required VoidCallback onEdit,
    VoidCallback? onDelete,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.pink.shade100),
      ),
      child: ListTile(
        leading: Icon(icon, color: AppColors.primary),
        title: Text(label,
            style: const TextStyle(fontSize: 12, color: Colors.grey)),
        subtitle: Text(address,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onDelete != null)
              IconButton(
                icon: const Icon(Icons.delete,
                    color: Colors.redAccent, size: 20),
                onPressed: onDelete,
              ),
            IconButton(
              icon: const Icon(Icons.edit, color: AppColors.primary, size: 20),
              onPressed: onEdit,
            ),
          ],
        ),
      ),
    );
  }

  // --- вкладки «Избранное» и «История»

  Widget _buildBookmarksTab() {
    if (_bookmarks.isEmpty) {
      return const Center(child: Text('Нет избранных мест'));
    }
    return ListView.builder(
      itemCount: _bookmarks.length,
      itemBuilder: (context, index) {
        final b = _bookmarks[index];
        return ListTile(
          leading: const Icon(Icons.star, color: AppColors.primary),
          title: Text(b['address'] ?? '',
              maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () => _selectSavedPlace(b),
          trailing: IconButton(
            icon: const Icon(Icons.delete, color: Colors.grey),
            onPressed: () => _deleteItem(b),
          ),
        );
      },
    );
  }

  Widget _buildHistoryTab() {
    if (_history.isEmpty) {
      return const Center(child: Text('История пуста'));
    }
    return ListView.builder(
      itemCount: _history.length,
      itemBuilder: (context, index) {
        final h = _history[index];
        return ListTile(
          leading: const Icon(Icons.history, color: Colors.grey),
          title: Text(h['address'] ?? '',
              maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle:
              const Text('Последний маршрут', style: TextStyle(fontSize: 10)),
          onTap: () => _selectSavedPlace(h),
          trailing: IconButton(
            icon: const Icon(Icons.delete, color: Colors.grey),
            onPressed: () => _deleteItem(h),
          ),
        );
      },
    );
  }

  // --- вкладка «Дом/Работа»

  Widget _buildHomeWorkTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton.icon(
                onPressed: () => _saveCurrentDestination('home', 'Дом сохранен'),
                icon: const Icon(Icons.home),
                label: const Text('Сохранить Дом'),
              ),
              ElevatedButton.icon(
                onPressed: () =>
                    _saveCurrentDestination('work', 'Работа сохранена'),
                icon: const Icon(Icons.work),
                label: const Text('Сохранить Работу'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_homePointData != null)
            ListTile(
              leading: const Icon(Icons.home, color: AppColors.primary),
              title: const Text('Домой'),
              subtitle: Text(_homePointData!['address'] ?? '',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => _selectSavedPlace(_homePointData!, build: true),
            ),
          if (_workPointData != null)
            ListTile(
              leading: const Icon(Icons.work, color: AppColors.primary),
              title: const Text('На работу'),
              subtitle: Text(_workPointData!['address'] ?? '',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => _selectSavedPlace(_workPointData!, build: true),
            ),
        ],
      ),
    );
  }
}

/// Реагирует на тап по карте (не по объекту на карте).
class _MapInputListener implements ymk.MapInputListener {
  _MapInputListener(this.onTap);
  final void Function(ymk.Point point) onTap;

  @override
  void onMapTap(ymk.Map map, ymk.Point point) => onTap(point);

  @override
  void onMapLongTap(ymk.Map map, ymk.Point point) {}
}
