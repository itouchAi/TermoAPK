import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/house_plan_model.dart';
import '../models/thermostat_state.dart';
import '../widgets/tactile_button.dart';

class Home3dScreen extends StatefulWidget {
  final LangCode lang;
  final ThemePaletteSpec palette;
  final Color accentColor;
  final HouseFloorPlan floorPlan;
  final Map<String, RoomEspTelemetry> roomTelemetries;
  final double? mainRoomTemp;
  final double targetTemp;
  final BoilerTelemetry boiler;
  final bool espOnline;
  final String mainEspDeviceId;
  final PerformanceMode performanceMode;
  final ValueChanged<HouseFloorPlan> onUpdateFloorPlan;

  const Home3dScreen({
    super.key,
    required this.lang,
    required this.palette,
    required this.accentColor,
    required this.floorPlan,
    this.roomTelemetries = const {},
    required this.mainRoomTemp,
    required this.targetTemp,
    required this.boiler,
    required this.espOnline,
    this.mainEspDeviceId = 'kombi',
    this.performanceMode = PerformanceMode.ultra60fps,
    required this.onUpdateFloorPlan,
  });

  @override
  State<Home3dScreen> createState() => _Home3dScreenState();
}

class _Home3dScreenState extends State<Home3dScreen> with SingleTickerProviderStateMixin {
  bool _editMode = false;
  late String _selectedRoomId;

  // 3D Orbit Camera State
  double _yawDeg = -36.0;
  double _pitchDeg = 44.0;
  double _zoom = 1.0;
  double _wallHeightRatio = 1.0; // 1.0 = full 3D walls, 0.28 = low cut, 0.0 = 2D flat
  Offset _focusWorld = Offset.zero; // meters relative to house center

  // Smooth room-to-room camera transition
  late final AnimationController _camCtrl;
  double _fromYaw = -36.0;
  double _toYaw = -36.0;
  double _fromPitch = 44.0;
  double _toPitch = 44.0;
  double _fromZoom = 1.0;
  double _toZoom = 1.0;
  Offset _fromFocus = Offset.zero;
  Offset _toFocus = Offset.zero;

  List<({String roomId, Path path, double depth})> _hitPolygons = const [];

  // Editor state
  final TextEditingController _roomNameCtrl = TextEditingController();
  final TextEditingController _espNodeCtrl = TextEditingController();
  String? _dragRoomId;
  bool _resizingRoom = false;
  Offset _dragStartGrid = Offset.zero;
  Size _resizeStartSize = Size.zero;

  @override
  void initState() {
    super.initState();
    _selectedRoomId = widget.floorPlan.rooms.isNotEmpty
        ? widget.floorPlan.rooms.first.id
        : '';
    _syncEditorFields();

    _camCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    )..addListener(() {
        final t = Curves.easeOutCubic.transform(_camCtrl.value);
        setState(() {
          _yawDeg = _fromYaw + (_toYaw - _fromYaw) * t;
          _pitchDeg = _fromPitch + (_toPitch - _fromPitch) * t;
          _zoom = _fromZoom + (_toZoom - _fromZoom) * t;
          _focusWorld = Offset.lerp(_fromFocus, _toFocus, t) ?? _toFocus;
        });
      });
  }

  @override
  void didUpdateWidget(covariant Home3dScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.floorPlan.rooms.isNotEmpty &&
        !widget.floorPlan.rooms.any((r) => r.id == _selectedRoomId)) {
      _selectedRoomId = widget.floorPlan.rooms.first.id;
      _syncEditorFields();
    }
  }

  @override
  void dispose() {
    _camCtrl.dispose();
    _roomNameCtrl.dispose();
    _espNodeCtrl.dispose();
    super.dispose();
  }

  void _syncEditorFields() {
    final room = widget.floorPlan.findRoom(_selectedRoomId);
    if (room != null) {
      if (_roomNameCtrl.text != room.name) _roomNameCtrl.text = room.name;
      if (_espNodeCtrl.text != room.espNodeId) _espNodeCtrl.text = room.espNodeId;
    }
  }

  void _animateCameraTo({
    double? yawDeg,
    double? pitchDeg,
    double? zoom,
    Offset? focusWorld,
  }) {
    _fromYaw = _yawDeg;
    _toYaw = yawDeg ?? _yawDeg;
    _fromPitch = _pitchDeg;
    _toPitch = (pitchDeg ?? _pitchDeg).clamp(18.0, 86.0);
    _fromZoom = _zoom;
    _toZoom = (zoom ?? _zoom).clamp(0.65, 1.90);
    _fromFocus = _focusWorld;
    _toFocus = focusWorld ?? _focusWorld;
    _camCtrl.forward(from: 0.0);
  }

  void _focusOnRoom(HouseRoom room, {bool zoomIn = true}) {
    HapticFeedback.selectionClick();
    setState(() => _selectedRoomId = room.id);
    _syncEditorFields();
    final bounds = widget.floorPlan.boundingRect();
    final houseCenter = bounds.center;
    final targetOffset = Offset(
      room.centerX - houseCenter.dx,
      room.centerY - houseCenter.dy,
    );
    _animateCameraTo(
      focusWorld: targetOffset,
      zoom: zoomIn ? math.max(_zoom, 1.32) : 1.0,
      pitchDeg: _pitchDeg < 30 ? 40.0 : _pitchDeg,
    );
  }

  void _resetCamera() {
    HapticFeedback.selectionClick();
    _animateCameraTo(
      yawDeg: -36.0,
      pitchDeg: 44.0,
      zoom: 1.0,
      focusWorld: Offset.zero,
    );
  }

  RoomEspTelemetry _resolveTelemetry(HouseRoom room) {
    final node = room.espNodeId.trim();
    if (node.isEmpty) {
      return const RoomEspTelemetry.offline('');
    }
    final direct = widget.roomTelemetries[node];
    if (direct != null) return direct;

    // Link main thermostat ESP node ('kombi' or configured espDeviceId) if online
    final isMainNode = node.toLowerCase() == 'kombi' ||
        node.toLowerCase() == widget.mainEspDeviceId.trim().toLowerCase();
    if (isMainNode && widget.espOnline && widget.mainRoomTemp != null) {
      return RoomEspTelemetry(
        espNodeId: node,
        online: true,
        roomTempC: widget.mainRoomTemp,
        radiatorHeating: widget.boiler.isHeating,
      );
    }
    return RoomEspTelemetry.offline(node);
  }

  void _selectTemplate(String templateId) {
    HapticFeedback.selectionClick();
    final tr = widget.lang == LangCode.tr;
    final next = HouseFloorPlan.fromTemplate(templateId, tr: tr);
    widget.onUpdateFloorPlan(next);
    setState(() {
      _selectedRoomId = next.rooms.isNotEmpty ? next.rooms.first.id : '';
      _focusWorld = Offset.zero;
    });
    _syncEditorFields();
  }

  void _updateSelectedRoom(HouseRoom Function(HouseRoom) transform) {
    final nextRooms = [
      for (final r in widget.floorPlan.rooms)
        if (r.id == _selectedRoomId) transform(r) else r,
    ];
    widget.onUpdateFloorPlan(
      widget.floorPlan.copyWith(templateId: 'custom', rooms: nextRooms),
    );
  }

  void _addNewRoom() {
    HapticFeedback.selectionClick();
    final tr = widget.lang == LangCode.tr;
    final id = 'oda_${DateTime.now().millisecondsSinceEpoch % 100000}';
    final count = widget.floorPlan.rooms.length + 1;
    final newRoom = HouseRoom(
      id: id,
      name: tr ? 'Yeni Oda $count' : 'Room $count',
      kind: HouseRoomKind.study,
      gridX: 2.0,
      gridY: 2.0,
      width: 3.0,
      depth: 3.0,
      espNodeId: 'esp32_oda$count',
      radiators: [
        RadiatorNode(id: 'rad_$id', wallSide: RadiatorWallSide.north, offsetRatio: 0.5),
      ],
    );
    widget.onUpdateFloorPlan(
      widget.floorPlan.copyWith(
        templateId: 'custom',
        rooms: [...widget.floorPlan.rooms, newRoom],
      ),
    );
    setState(() => _selectedRoomId = id);
    _syncEditorFields();
  }

  void _deleteSelectedRoom() {
    if (widget.floorPlan.rooms.length <= 1) return;
    HapticFeedback.selectionClick();
    final nextRooms = widget.floorPlan.rooms.where((r) => r.id != _selectedRoomId).toList();
    final nextRef = nextRooms.any((r) => r.id == widget.floorPlan.referenceRoomId)
        ? widget.floorPlan.referenceRoomId
        : nextRooms.first.id;
    widget.onUpdateFloorPlan(
      widget.floorPlan.copyWith(
        templateId: 'custom',
        referenceRoomId: nextRef,
        rooms: nextRooms,
      ),
    );
    setState(() => _selectedRoomId = nextRooms.first.id);
    _syncEditorFields();
  }

  @override
  Widget build(BuildContext context) {
    final tr = widget.lang == LangCode.tr;
    final palette = widget.palette;
    final rooms = widget.floorPlan.rooms;
    final selectedRoom = widget.floorPlan.findRoom(_selectedRoomId);

    int onlineCount = 0;
    for (final r in rooms) {
      if (_resolveTelemetry(r).online) onlineCount++;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isLandscape = constraints.maxWidth > constraints.maxHeight;
        final compact = constraints.maxHeight < 460;

        final bottomNavClearance = isLandscape ? (compact ? 26.0 : 38.0) : 34.0;

        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isLandscape ? 1040 : 520),
            child: Padding(
              padding: EdgeInsets.fromLTRB(14, 6, 14, bottomNavClearance),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Top Header: Mode Switch + Online Status + Quick View Buttons
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: palette.isLight
                                ? Colors.black.withValues(alpha: 0.06)
                                : Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: palette.cardBorder),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: _ModeSegmentButton(
                                  label: tr ? '3D Ev Haritası' : '3D House Map',
                                  icon: Icons.view_in_ar_rounded,
                                  selected: !_editMode,
                                  accent: widget.accentColor,
                                  palette: palette,
                                  onTap: () => setState(() => _editMode = false),
                                ),
                              ),
                              Expanded(
                                child: _ModeSegmentButton(
                                  label: tr ? 'Planı Çiz / Düzenle' : 'Draw / Edit Plan',
                                  icon: Icons.edit_location_alt_outlined,
                                  selected: _editMode,
                                  accent: widget.accentColor,
                                  palette: palette,
                                  onTap: () {
                                    _syncEditorFields();
                                    setState(() => _editMode = true);
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: (onlineCount > 0 ? const Color(0xFF10B981) : const Color(0xFFF59E0B))
                              .withValues(alpha: palette.isLight ? 0.14 : 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: (onlineCount > 0 ? const Color(0xFF10B981) : const Color(0xFFF59E0B))
                                .withValues(alpha: 0.42),
                          ),
                        ),
                        child: Text(
                          '$onlineCount/${rooms.length} ESP',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: onlineCount > 0
                                ? (palette.isLight ? const Color(0xFF065F46) : const Color(0xFF6EE7B7))
                                : (palette.isLight ? const Color(0xFF92400E) : const Color(0xFFFCD34D)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Body: Either Interactive 3D Map or Visual Floorplan Editor
                  Expanded(
                    child: _editMode
                        ? _buildFloorplanEditor(tr, palette, rooms, selectedRoom, isLandscape)
                        : _build3dHouseView(tr, palette, rooms, selectedRoom, isLandscape, compact),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _build3dHouseView(
    bool tr,
    ThemePaletteSpec palette,
    List<HouseRoom> rooms,
    HouseRoom? selectedRoom,
    bool isLandscape,
    bool compact,
  ) {
    final telMap = <String, RoomEspTelemetry>{
      for (final r in rooms) r.id: _resolveTelemetry(r),
    };
    final selectedTel = selectedRoom != null ? telMap[selectedRoom.id]! : const RoomEspTelemetry.offline('');
    final refRoom = widget.floorPlan.findRoom(widget.floorPlan.referenceRoomId);
    final refTel = refRoom != null ? telMap[refRoom.id] : null;

    final viewport3d = Container(
      decoration: BoxDecoration(
        color: palette.isLight
            ? Colors.white.withValues(alpha: 0.65)
            : const Color(0xFF090C14).withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: palette.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: palette.isLight ? 0.08 : 0.45),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(21),
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) => _camCtrl.stop(),
                onPanUpdate: (details) {
                  setState(() {
                    _yawDeg = (_yawDeg + details.delta.dx * 0.55) % 360.0;
                    _pitchDeg = (_pitchDeg + details.delta.dy * 0.38).clamp(18.0, 86.0);
                  });
                },
                onTapUp: (details) {
                  final pos = details.localPosition;
                  // _hitPolygons are ordered nearest-first or front-last; iterate reverse (front-most first)
                  for (int i = _hitPolygons.length - 1; i >= 0; i--) {
                    if (_hitPolygons[i].path.contains(pos)) {
                      final tapped = widget.floorPlan.findRoom(_hitPolygons[i].roomId);
                      if (tapped != null) {
                        _focusOnRoom(tapped);
                      }
                      break;
                    }
                  }
                },
                child: CustomPaint(
                  painter: _House3DPainter(
                    plan: widget.floorPlan,
                    telemetries: telMap,
                    selectedRoomId: _selectedRoomId,
                    yawDeg: _yawDeg,
                    pitchDeg: _pitchDeg,
                    zoom: _zoom,
                    wallHeightRatio: _wallHeightRatio,
                    focusWorld: _focusWorld,
                    accentColor: widget.accentColor,
                    palette: palette,
                    boiler: widget.boiler,
                    performanceMode: widget.performanceMode,
                    tr: tr,
                    onPolygonsProjected: (polys) => _hitPolygons = polys,
                  ),
                ),
              ),
            ),

            // Top-left hint badge
            Positioned(
              left: 10,
              top: 10,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: palette.isLight
                        ? Colors.white.withValues(alpha: 0.85)
                        : const Color(0xFF0D101B).withValues(alpha: 0.84),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: palette.cardBorder),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.threesixty_rounded, size: 13, color: widget.accentColor),
                      const SizedBox(width: 5),
                      Text(
                        widget.performanceMode == PerformanceMode.ecoBattery
                            ? (tr ? 'Döndür · Odaya dokun · Eko' : 'Drag to orbit · Tap room · ECO')
                            : (tr ? 'Döndür · Odaya dokun · 60 FPS' : 'Drag to orbit · Tap room · 60 FPS'),
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: palette.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Top-right quick camera & depth controls
            Positioned(
              right: 10,
              top: 10,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _MiniCamChip(
                    label: '3D',
                    active: _pitchDeg < 72 && _wallHeightRatio > 0.6,
                    palette: palette,
                    accent: widget.accentColor,
                    onTap: () {
                      setState(() => _wallHeightRatio = 1.0);
                      _animateCameraTo(yawDeg: -36.0, pitchDeg: 44.0, zoom: 1.0, focusWorld: Offset.zero);
                    },
                  ),
                  const SizedBox(width: 4),
                  _MiniCamChip(
                    label: tr ? 'Kesit' : 'Cut',
                    active: _wallHeightRatio < 0.6 && _wallHeightRatio > 0.1,
                    palette: palette,
                    accent: widget.accentColor,
                    onTap: () {
                      setState(() => _wallHeightRatio = 0.35);
                      _animateCameraTo(pitchDeg: 52.0);
                    },
                  ),
                  const SizedBox(width: 4),
                  _MiniCamChip(
                    label: '2D',
                    active: _pitchDeg >= 72,
                    palette: palette,
                    accent: widget.accentColor,
                    onTap: () {
                      setState(() => _wallHeightRatio = 0.12);
                      _animateCameraTo(yawDeg: 0.0, pitchDeg: 85.0, zoom: 1.05, focusWorld: Offset.zero);
                    },
                  ),
                  const SizedBox(width: 4),
                  _MiniCamChip(
                    icon: Icons.center_focus_strong_rounded,
                    active: false,
                    palette: palette,
                    accent: widget.accentColor,
                    onTap: _resetCamera,
                  ),
                ],
              ),
            ),

            // Bottom quick zoom / depth controls
            Positioned(
              left: 10,
              right: 10,
              bottom: 8,
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 30,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: rooms.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 6),
                        itemBuilder: (ctx, i) {
                          final r = rooms[i];
                          final sel = r.id == _selectedRoomId;
                          final tel = telMap[r.id]!;
                          final tempStr = tel.roomTempC != null ? '${tel.roomTempC!.toStringAsFixed(1)}°' : '--';
                          return GestureDetector(
                            onTap: () => _focusOnRoom(r),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: sel
                                    ? widget.accentColor.withValues(alpha: 0.24)
                                    : (palette.isLight
                                        ? Colors.white.withValues(alpha: 0.85)
                                        : const Color(0xFF101422).withValues(alpha: 0.88)),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: sel ? widget.accentColor : palette.cardBorder,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    HouseRoom.kindIcon(r.kind),
                                    size: 12,
                                    color: sel ? widget.accentColor : palette.textSecondary,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    '${r.name} · $tempStr',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                                      color: palette.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _MiniCamChip(
                    icon: Icons.remove_rounded,
                    active: false,
                    palette: palette,
                    accent: widget.accentColor,
                    onTap: () => _animateCameraTo(zoom: _zoom - 0.18),
                  ),
                  const SizedBox(width: 4),
                  _MiniCamChip(
                    icon: Icons.add_rounded,
                    active: false,
                    palette: palette,
                    accent: widget.accentColor,
                    onTap: () => _animateCameraTo(zoom: _zoom + 0.18),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    final inspectorCard = selectedRoom == null
        ? const SizedBox.shrink()
        : _buildSelectedRoomTelemetryCard(tr, palette, selectedRoom, selectedTel, refRoom, refTel);

    if (isLandscape) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 6, child: viewport3d),
          const SizedBox(width: 10),
          Expanded(
            flex: 4,
            child: Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: palette.isLight
                    ? Colors.white.withValues(alpha: 0.72)
                    : const Color(0xFF0A0D16).withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: palette.cardBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  inspectorCard,
                  const SizedBox(height: 10),
                  Text(
                    tr ? 'TÜM ODALAR · ANLIK DURUM' : 'ALL ROOMS · LIVE STATUS',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: palette.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: ListView.separated(
                      itemCount: rooms.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (ctx, idx) {
                        final r = rooms[idx];
                        final sel = r.id == _selectedRoomId;
                        final t = telMap[r.id]!;
                        final tStr = t.roomTempC != null ? '${t.roomTempC!.toStringAsFixed(1)}°C' : '--';
                        final radStr = t.radiatorTempC != null ? '${t.radiatorTempC!.toStringAsFixed(1)}°C' : '--';
                        return GestureDetector(
                          onTap: () => _focusOnRoom(r),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: sel
                                  ? widget.accentColor.withValues(alpha: 0.14)
                                  : palette.cardBg,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: sel ? widget.accentColor : palette.cardBorder,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  HouseRoom.kindIcon(r.kind),
                                  size: 15,
                                  color: sel ? widget.accentColor : palette.textSecondary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        r.name,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: palette.textPrimary,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        '${r.areaM2.toStringAsFixed(1)} m² · ${tr ? 'Petek' : 'Rad'}: $radStr',
                                        style: TextStyle(fontSize: 10, color: palette.textSecondary),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  tStr,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800,
                                    color: t.roomTempC != null ? widget.accentColor : palette.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: viewport3d),
        SizedBox(height: compact ? 6 : 8),
        inspectorCard,
      ],
    );
  }

  Widget _buildSelectedRoomTelemetryCard(
    bool tr,
    ThemePaletteSpec palette,
    HouseRoom room,
    RoomEspTelemetry tel,
    HouseRoom? refRoom,
    RoomEspTelemetry? refTel,
  ) {
    final isRef = widget.floorPlan.referenceRoomId == room.id;
    String diffText;
    if (!tel.online || tel.roomTempC == null) {
      diffText = room.espNodeId.trim().isEmpty
          ? (tr ? 'Bu odaya henüz ESP sensörü atanmadı.' : 'No ESP node assigned to this room yet.')
          : (tr
              ? 'ESP (${room.espNodeId}) bağlantısı yok — canlı oda, petek ve Wi-Fi verisi bekleniyor (--).'
              : 'ESP (${room.espNodeId}) offline — awaiting live room, radiator & Wi-Fi data (--).');
    } else if (refRoom != null && refRoom.id != room.id && refTel != null && refTel.roomTempC != null) {
      final delta = tel.roomTempC! - refTel.roomTempC!;
      final sign = delta >= 0 ? '+' : '';
      diffText = tr
          ? '${refRoom.name} ile fark: $sign${delta.toStringAsFixed(1)}°C'
          : 'Delta vs ${refRoom.name}: $sign${delta.toStringAsFixed(1)}°C';
    } else {
      final deltaTarget = tel.roomTempC! - widget.targetTemp;
      final sign = deltaTarget >= 0 ? '+' : '';
      diffText = tr
          ? 'Hedefe göre: $sign${deltaTarget.toStringAsFixed(1)}°C'
          : 'Vs target: $sign${deltaTarget.toStringAsFixed(1)}°C';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(HouseRoom.kindIcon(room.kind), size: 17, color: widget.accentColor),
              const SizedBox(width: 7),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      room.name,
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: palette.textPrimary),
                    ),
                    Text(
                      '${room.areaM2.toStringAsFixed(1)} m² · ${room.radiators.length} ${tr ? 'petek' : 'rad.'} · '
                      '${room.espNodeId.trim().isEmpty ? (tr ? 'ESP atanmadı' : 'No ESP') : room.espNodeId}',
                      style: TextStyle(fontSize: 10.5, color: palette.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              TactilePress(
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    widget.onUpdateFloorPlan(widget.floorPlan.copyWith(referenceRoomId: room.id));
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    decoration: BoxDecoration(
                      color: isRef
                          ? widget.accentColor.withValues(alpha: 0.20)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isRef ? widget.accentColor : palette.cardBorder,
                      ),
                    ),
                    child: Text(
                      isRef
                          ? (tr ? '★ Referans' : '★ Reference')
                          : (tr ? 'Referans Yap' : 'Set Ref'),
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: isRef ? widget.accentColor : palette.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _RoomStatBox(
                  label: tr ? 'Oda Sıcaklığı' : 'Room Temp',
                  value: tel.roomTempC != null ? '${tel.roomTempC!.toStringAsFixed(1)}°C' : '--',
                  icon: Icons.thermostat_outlined,
                  color: widget.accentColor,
                  palette: palette,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _RoomStatBox(
                  label: tr ? 'Petek' : 'Radiator',
                  value: tel.radiatorTempC != null ? '${tel.radiatorTempC!.toStringAsFixed(1)}°C' : '--',
                  icon: Icons.view_week_outlined,
                  color: const Color(0xFFF59E0B),
                  palette: palette,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _RoomStatBox(
                  label: tr ? 'Wi-Fi Gücü' : 'Wi-Fi Signal',
                  value: tel.wifiQualityLabel(tr: tr),
                  icon: Icons.wifi_rounded,
                  color: tel.wifiBars >= 3
                      ? const Color(0xFF10B981)
                      : (tel.wifiBars >= 1 ? const Color(0xFFF59E0B) : palette.textSecondary),
                  palette: palette,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            diffText,
            style: TextStyle(
              fontSize: 10.5,
              color: tel.online ? palette.textPrimary : palette.textSecondary,
              fontWeight: tel.online ? FontWeight.w600 : FontWeight.w400,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildFloorplanEditor(
    bool tr,
    ThemePaletteSpec palette,
    List<HouseRoom> rooms,
    HouseRoom? selectedRoom,
    bool isLandscape,
  ) {
    final gridWidget = Container(
      decoration: BoxDecoration(
        color: palette.isLight
            ? Colors.white.withValues(alpha: 0.72)
            : const Color(0xFF0A0D16).withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.cardBorder),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(19),
        child: LayoutBuilder(
          builder: (context, box) {
            final cellW = box.maxWidth / HouseFloorPlan.gridMaxWidth;
            final cellH = box.maxHeight / HouseFloorPlan.gridMaxDepth;
            final unitPx = math.min(cellW, cellH);
            final offsetX = (box.maxWidth - HouseFloorPlan.gridMaxWidth * unitPx) / 2.0;
            final offsetY = (box.maxHeight - HouseFloorPlan.gridMaxDepth * unitPx) / 2.0;

            Offset pxToGrid(Offset p) => Offset(
                  (p.dx - offsetX) / math.max(1.0, unitPx),
                  (p.dy - offsetY) / math.max(1.0, unitPx),
                );

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) {
                final gp = pxToGrid(d.localPosition);
                for (int i = rooms.length - 1; i >= 0; i--) {
                  final r = rooms[i];
                  if (gp.dx >= r.gridX &&
                      gp.dx <= r.gridX + r.width &&
                      gp.dy >= r.gridY &&
                      gp.dy <= r.gridY + r.depth) {
                    setState(() => _selectedRoomId = r.id);
                    _syncEditorFields();
                    break;
                  }
                }
              },
              onPanStart: (d) {
                final gp = pxToGrid(d.localPosition);
                for (int i = rooms.length - 1; i >= 0; i--) {
                  final r = rooms[i];
                  if (gp.dx >= r.gridX &&
                      gp.dx <= r.gridX + r.width &&
                      gp.dy >= r.gridY &&
                      gp.dy <= r.gridY + r.depth) {
                    final nearResize = (gp.dx >= r.gridX + r.width - 0.65) &&
                        (gp.dy >= r.gridY + r.depth - 0.65);
                    setState(() {
                      _selectedRoomId = r.id;
                      _dragRoomId = r.id;
                      _resizingRoom = nearResize;
                      _dragStartGrid = gp;
                      _resizeStartSize = Size(r.width, r.depth);
                    });
                    _syncEditorFields();
                    break;
                  }
                }
              },
              onPanUpdate: (d) {
                final id = _dragRoomId;
                if (id == null) return;
                final currentRoom = widget.floorPlan.findRoom(id);
                if (currentRoom == null) return;
                final gp = pxToGrid(d.localPosition);
                final delta = gp - _dragStartGrid;
                if (_resizingRoom) {
                  final nw = HouseFloorPlan.snapHalfMeter(
                    (_resizeStartSize.width + delta.dx).clamp(1.5, HouseFloorPlan.gridMaxWidth - currentRoom.gridX),
                  );
                  final nd = HouseFloorPlan.snapHalfMeter(
                    (_resizeStartSize.height + delta.dy).clamp(1.5, HouseFloorPlan.gridMaxDepth - currentRoom.gridY),
                  );
                  _updateSelectedRoom((r) => r.copyWith(width: nw, depth: nd));
                } else {
                  final nx = HouseFloorPlan.snapHalfMeter(
                    (currentRoom.gridX + delta.dx).clamp(0.0, HouseFloorPlan.gridMaxWidth - currentRoom.width),
                  );
                  final ny = HouseFloorPlan.snapHalfMeter(
                    (currentRoom.gridY + delta.dy).clamp(0.0, HouseFloorPlan.gridMaxDepth - currentRoom.depth),
                  );
                  if ((nx - currentRoom.gridX).abs() >= 0.45 ||
                      (ny - currentRoom.gridY).abs() >= 0.45) {
                    _dragStartGrid = gp;
                    _updateSelectedRoom((r) => r.copyWith(gridX: nx, gridY: ny));
                  }
                }
              },
              onPanEnd: (_) {
                _dragRoomId = null;
                _resizingRoom = false;
              },
              child: CustomPaint(
                painter: _FloorplanEditorPainter(
                  plan: widget.floorPlan,
                  selectedRoomId: _selectedRoomId,
                  unitPx: unitPx,
                  offset: Offset(offsetX, offsetY),
                  accentColor: widget.accentColor,
                  palette: palette,
                  tr: tr,
                ),
              ),
            );
          },
        ),
      ),
    );

    final templatesHeader = Row(
      children: [
        Expanded(
          child: Text(
            tr ? 'HAZIR EV ŞABLONLARI' : 'READY TEMPLATES',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: palette.textSecondary,
            ),
          ),
        ),
        OutlinedButton.icon(
          onPressed: _addNewRoom,
          style: OutlinedButton.styleFrom(
            foregroundColor: widget.accentColor,
            side: BorderSide(color: widget.accentColor.withValues(alpha: 0.5)),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            minimumSize: const Size(0, 30),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          icon: const Icon(Icons.add_box_outlined, size: 14),
          label: Text(
            tr ? '+ Oda Ekle' : '+ Add Room',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );

    final templatesWrap = Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final tpl in HouseFloorPlan.readyTemplates)
          ChoiceChip(
            label: Text(
              tr ? tpl.labelTr : tpl.labelEn,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: widget.floorPlan.templateId == tpl.id ? Colors.white : palette.textPrimary,
              ),
            ),
            selected: widget.floorPlan.templateId == tpl.id,
            selectedColor: widget.accentColor,
            backgroundColor: palette.cardBg,
            side: BorderSide(
              color: widget.floorPlan.templateId == tpl.id ? widget.accentColor : palette.cardBorder,
            ),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onSelected: (_) => _selectTemplate(tpl.id),
          ),
      ],
    );

    final roomEditorDetails = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (selectedRoom != null)
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: palette.cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: palette.cardBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _roomNameCtrl,
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: palette.textPrimary),
                        decoration: InputDecoration(
                          isDense: true,
                          labelText: tr ? 'Oda Adı' : 'Room Name',
                          labelStyle: TextStyle(fontSize: 11, color: palette.textSecondary),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        ),
                        onChanged: (v) {
                          final trimmed = v.trim();
                          if (trimmed.isNotEmpty) {
                            _updateSelectedRoom((r) => r.copyWith(name: trimmed));
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _espNodeCtrl,
                        style: TextStyle(fontSize: 12, color: palette.textPrimary),
                        decoration: InputDecoration(
                          isDense: true,
                          labelText: tr ? 'ESP ID (ör. esp32_salon)' : 'ESP ID',
                          labelStyle: TextStyle(fontSize: 11, color: palette.textSecondary),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        ),
                        onChanged: (v) => _updateSelectedRoom((r) => r.copyWith(espNodeId: v.trim())),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final kind in HouseRoomKind.values)
                      ChoiceChip(
                        label: Text(
                          HouseRoom.kindLabel(kind, tr: tr),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: selectedRoom.kind == kind ? Colors.white : palette.textPrimary,
                          ),
                        ),
                        selected: selectedRoom.kind == kind,
                        selectedColor: widget.accentColor,
                        backgroundColor: Colors.transparent,
                        side: BorderSide(color: selectedRoom.kind == kind ? widget.accentColor : palette.cardBorder),
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) => _updateSelectedRoom((r) => r.copyWith(kind: kind)),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _DimStepper(
                      label: tr ? 'En' : 'W',
                      value: selectedRoom.width,
                      palette: palette,
                      onDelta: (d) => _updateSelectedRoom((r) => r.copyWith(width: r.width + d)),
                    ),
                    const SizedBox(width: 6),
                    _DimStepper(
                      label: tr ? 'Boy' : 'D',
                      value: selectedRoom.depth,
                      palette: palette,
                      onDelta: (d) => _updateSelectedRoom((r) => r.copyWith(depth: r.depth + d)),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () {
                        final idx = selectedRoom.radiators.length % RadiatorWallSide.values.length;
                        final side = RadiatorWallSide.values[idx];
                        final newRad = RadiatorNode(
                          id: 'rad_${DateTime.now().microsecondsSinceEpoch}',
                          wallSide: side,
                          offsetRatio: 0.5,
                        );
                        _updateSelectedRoom((r) => r.copyWith(radiators: [...r.radiators, newRad]));
                      },
                      icon: const Icon(Icons.add_rounded, size: 15),
                      label: Text(tr ? '+ Petek' : '+ Rad', style: const TextStyle(fontSize: 11)),
                    ),
                    if (selectedRoom.radiators.isNotEmpty)
                      IconButton(
                        tooltip: tr ? 'Son peteği kaldır' : 'Remove radiator',
                        onPressed: () {
                          final copy = List<RadiatorNode>.from(selectedRoom.radiators)..removeLast();
                          _updateSelectedRoom((r) => r.copyWith(radiators: copy));
                        },
                        icon: const Icon(Icons.layers_clear_outlined, size: 16),
                        color: palette.textSecondary,
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                Row(
                  children: [
                    FilterChip(
                      label: Text(
                        tr ? 'Kombi Merkezi' : 'Boiler Hub',
                        style: TextStyle(fontSize: 10.5, color: palette.textPrimary),
                      ),
                      selected: selectedRoom.isBoilerHub,
                      selectedColor: const Color(0xFFF59E0B).withValues(alpha: 0.25),
                      onSelected: (v) {
                        final nextRooms = [
                          for (final r in widget.floorPlan.rooms)
                            r.id == selectedRoom.id
                                ? r.copyWith(isBoilerHub: v)
                                : (v ? r.copyWith(isBoilerHub: false) : r),
                        ];
                        widget.onUpdateFloorPlan(
                          widget.floorPlan.copyWith(templateId: 'custom', rooms: nextRooms),
                        );
                      },
                    ),
                    const SizedBox(width: 6),
                    TextButton(
                      onPressed: () {
                        _espNodeCtrl.text = widget.mainEspDeviceId;
                        _updateSelectedRoom((r) => r.copyWith(espNodeId: widget.mainEspDeviceId));
                      },
                      child: Text(
                        tr ? 'Ana Kombi ESP Bağla' : 'Bind Main ESP',
                        style: const TextStyle(fontSize: 10.5),
                      ),
                    ),
                    const Spacer(),
                    if (rooms.length > 1)
                      IconButton(
                        onPressed: _deleteSelectedRoom,
                        icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFFEF4444)),
                        tooltip: tr ? 'Odayı Sil' : 'Delete Room',
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ],
            ),
          ),
        const SizedBox(height: 10),
        Text(
          tr ? 'PLANDAKİ ODALAR (${rooms.length})' : 'ROOMS IN PLAN (${rooms.length})',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: palette.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final r in rooms)
              GestureDetector(
                onTap: () {
                  setState(() => _selectedRoomId = r.id);
                  _syncEditorFields();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: r.id == _selectedRoomId
                        ? widget.accentColor.withValues(alpha: 0.20)
                        : palette.cardBg,
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(
                      color: r.id == _selectedRoomId ? widget.accentColor : palette.cardBorder,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        HouseRoom.kindIcon(r.kind),
                        size: 13,
                        color: r.id == _selectedRoomId ? widget.accentColor : palette.textSecondary,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '${r.name} · ${r.width.toStringAsFixed(1)}×${r.depth.toStringAsFixed(1)}m',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: r.id == _selectedRoomId ? FontWeight.w700 : FontWeight.w500,
                          color: palette.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );

    if (isLandscape) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 6, child: gridWidget),
          const SizedBox(width: 10),
          Expanded(
            flex: 4,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: palette.isLight
                    ? Colors.white.withValues(alpha: 0.72)
                    : const Color(0xFF0A0D16).withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: palette.cardBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  templatesHeader,
                  const SizedBox(height: 6),
                  templatesWrap,
                  const SizedBox(height: 10),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: roomEditorDetails,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 5, child: gridWidget),
        const SizedBox(height: 8),
        Expanded(
          flex: 5,
          child: ListView(
            padding: const EdgeInsets.only(bottom: 6),
            children: [
              templatesHeader,
              const SizedBox(height: 6),
              templatesWrap,
              const SizedBox(height: 8),
              roomEditorDetails,
            ],
          ),
        ),
      ],
    );
  }
}

class _ModeSegmentButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final Color accent;
  final ThemePaletteSpec palette;
  final VoidCallback onTap;

  const _ModeSegmentButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.accent,
    required this.palette,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 170),
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? accent : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: selected ? Colors.white : palette.textSecondary),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : palette.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniCamChip extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final bool active;
  final ThemePaletteSpec palette;
  final Color accent;
  final VoidCallback onTap;

  const _MiniCamChip({
    this.label,
    this.icon,
    required this.active,
    required this.palette,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: active
              ? accent.withValues(alpha: 0.28)
              : (palette.isLight
                  ? Colors.white.withValues(alpha: 0.88)
                  : const Color(0xFF0E1320).withValues(alpha: 0.86)),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: active ? accent : palette.cardBorder),
        ),
        child: icon != null
            ? Icon(icon, size: 14, color: palette.textPrimary)
            : Text(
                label ?? '',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: active ? accent : palette.textPrimary,
                ),
              ),
      ),
    );
  }
}

class _RoomStatBox extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final ThemePaletteSpec palette;

  const _RoomStatBox({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: palette.isLight
            ? Colors.black.withValues(alpha: 0.035)
            : Colors.white.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: palette.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 9.5, color: palette.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: palette.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _DimStepper extends StatelessWidget {
  final String label;
  final double value;
  final ThemePaletteSpec palette;
  final ValueChanged<double> onDelta;

  const _DimStepper({
    required this.label,
    required this.value,
    required this.palette,
    required this.onDelta,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: palette.isLight ? 0.5 : 0.05),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: palette.cardBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label ', style: TextStyle(fontSize: 10, color: palette.textSecondary)),
          GestureDetector(
            onTap: () => onDelta(-0.5),
            child: Icon(Icons.remove_rounded, size: 15, color: palette.textPrimary),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '${value.toStringAsFixed(1)}m',
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: palette.textPrimary),
            ),
          ),
          GestureDetector(
            onTap: () => onDelta(0.5),
            child: Icon(Icons.add_rounded, size: 15, color: palette.textPrimary),
          ),
        ],
      ),
    );
  }
}

class _Vec3 {
  final double x;
  final double y;
  final double z;
  const _Vec3(this.x, this.y, this.z);
}

class _ProjectedQuad {
  final List<Offset> pts;
  final double depth;
  final Color fill;
  final Color? stroke;
  final double strokeWidth;

  const _ProjectedQuad({
    required this.pts,
    required this.depth,
    required this.fill,
    this.stroke,
    this.strokeWidth = 1.0,
  });
}

class _House3DPainter extends CustomPainter {
  final HouseFloorPlan plan;
  final Map<String, RoomEspTelemetry> telemetries;
  final String selectedRoomId;
  final double yawDeg;
  final double pitchDeg;
  final double zoom;
  final double wallHeightRatio;
  final Offset focusWorld;
  final Color accentColor;
  final ThemePaletteSpec palette;
  final BoilerTelemetry boiler;
  final PerformanceMode performanceMode;
  final bool tr;
  final ValueChanged<List<({String roomId, Path path, double depth})>> onPolygonsProjected;

  const _House3DPainter({
    required this.plan,
    required this.telemetries,
    required this.selectedRoomId,
    required this.yawDeg,
    required this.pitchDeg,
    required this.zoom,
    required this.wallHeightRatio,
    required this.focusWorld,
    required this.accentColor,
    required this.palette,
    required this.boiler,
    required this.performanceMode,
    required this.tr,
    required this.onPolygonsProjected,
  });

  Color _roomFloorBaseColor(HouseRoomKind kind) {
    final light = palette.isLight;
    switch (kind) {
      case HouseRoomKind.living:
        return light ? const Color(0xFFE7AD78) : const Color(0xFF5A402D);
      case HouseRoomKind.bedroom:
        return light ? const Color(0xFFDFB98E) : const Color(0xFF513E30);
      case HouseRoomKind.kids:
        return light ? const Color(0xFFEBD2A9) : const Color(0xFF4C4335);
      case HouseRoomKind.study:
        return light ? const Color(0xFFCBB296) : const Color(0xFF3E3630);
      case HouseRoomKind.kitchen:
        return light ? const Color(0xFFE2E8F0) : const Color(0xFF283244);
      case HouseRoomKind.bath:
        return light ? const Color(0xFFCBE4EC) : const Color(0xFF1F3646);
      case HouseRoomKind.hall:
        return light ? const Color(0xFFD6CFC4) : const Color(0xFF313542);
    }
  }

  Color? _thermalOverlayTint(RoomEspTelemetry tel) {
    if (!tel.online || tel.roomTempC == null) return null;
    final t = tel.roomTempC!;
    if (t < 18.5) return const Color(0xFF38BDF8).withValues(alpha: 0.34);
    if (t < 21.5) return const Color(0xFF10B981).withValues(alpha: 0.32);
    if (t < 24.0) return const Color(0xFFF59E0B).withValues(alpha: 0.36);
    return const Color(0xFFEF4444).withValues(alpha: 0.40);
  }

  Color _wallInnerColor(HouseRoomKind kind) {
    if (palette.isLight) {
      switch (kind) {
        case HouseRoomKind.living:
          return const Color(0xFF2DC5AC);
        case HouseRoomKind.kitchen:
          return const Color(0xFFDBEAFE);
        case HouseRoomKind.bedroom:
          return const Color(0xFF9FB8AD);
        case HouseRoomKind.kids:
          return const Color(0xFFA7D8DE);
        case HouseRoomKind.bath:
          return const Color(0xFF7EC8D9);
        case HouseRoomKind.study:
          return const Color(0xFF93A8BE);
        case HouseRoomKind.hall:
          return const Color(0xFFC7CEDB);
      }
    } else {
      switch (kind) {
        case HouseRoomKind.living:
          return const Color(0xFF1E6E68);
        case HouseRoomKind.kitchen:
          return const Color(0xFF27425D);
        case HouseRoomKind.bedroom:
          return const Color(0xFF2A4A4D);
        case HouseRoomKind.kids:
          return const Color(0xFF2B526E);
        case HouseRoomKind.bath:
          return const Color(0xFF1A4B5C);
        case HouseRoomKind.study:
          return const Color(0xFF2B3A52);
        case HouseRoomKind.hall:
          return const Color(0xFF2E3748);
      }
    }
  }

  double _cutawayFactor(double frontness) => ((frontness + 0.05) / 0.28).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    final isEco = performanceMode == PerformanceMode.ecoBattery;
    final bounds = plan.boundingRect();
    final centerWorld = bounds.center;
    final yaw = yawDeg * math.pi / 180.0;
    final pitch = pitchDeg * math.pi / 180.0;
    final cosY = math.cos(yaw);
    final sinY = math.sin(yaw);
    final sinP = math.sin(pitch);
    final cosP = math.cos(pitch);

    final span = math.max(bounds.width, bounds.height).clamp(4.0, 14.0);
    final baseScale = (math.min(size.width, size.height) * 0.68 / span) * zoom;
    final screenCenter = Offset(size.width * 0.5, size.height * 0.50);

    ({Offset pt, double depth}) project(_Vec3 v) {
      final wx = v.x - centerWorld.dx - focusWorld.dx;
      final wz = v.z - centerWorld.dy - focusWorld.dy;
      final wy = v.y;

      final rx = wx * cosY - wz * sinY;
      final rz = wx * sinY + wz * cosY;

      final sx = rx;
      final sy = -wy * cosP + rz * sinP;
      final depth = wy * sinP + rz * cosP;

      final persp = 1.0 / (1.0 - (depth * 0.022).clamp(-0.35, 0.35));
      return (
        pt: Offset(
          screenCenter.dx + sx * baseScale * persp,
          screenCenter.dy + sy * baseScale * persp,
        ),
        depth: depth,
      );
    }

    // -------------------------------------------------------------------------
    // PASS 0: Ground radial shadow & subtle 1m architect grid
    // -------------------------------------------------------------------------
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(screenCenter.dx, screenCenter.dy + baseScale * 0.25),
        width: size.width * 0.78,
        height: size.height * 0.44,
      ),
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.black.withValues(alpha: palette.isLight ? 0.14 : 0.46),
            Colors.transparent,
          ],
        ).createShader(Offset.zero & size),
    );

    final gridPaint = Paint()
      ..color = palette.isLight
          ? const Color(0xFF0F172A).withValues(alpha: 0.06)
          : Colors.white.withValues(alpha: 0.045)
      ..strokeWidth = 1.0;
    for (double gx = 0; gx <= HouseFloorPlan.gridMaxWidth; gx += 1.0) {
      canvas.drawLine(
        project(_Vec3(gx, 0.0, 0.0)).pt,
        project(_Vec3(gx, 0.0, HouseFloorPlan.gridMaxDepth)).pt,
        gridPaint,
      );
    }
    for (double gz = 0; gz <= HouseFloorPlan.gridMaxDepth; gz += 1.0) {
      canvas.drawLine(
        project(_Vec3(0.0, 0.0, gz)).pt,
        project(_Vec3(HouseFloorPlan.gridMaxWidth, 0.0, gz)).pt,
        gridPaint,
      );
    }

    // Backface visibility booleans for axis-aligned 3D boxes
    final showNorth = -cosY > -0.06;
    final showSouth = cosY > -0.06;
    final showWest = -sinY > -0.06;
    final showEast = sinY > -0.06;

    // Wall outward frontness (>0 means wall faces toward viewer -> lower cutaway curb)
    final frontN = -cosY;
    final frontS = cosY;
    final frontW = -sinY;
    final frontE = sinY;

    final hScaleN = 1.0 - 0.85 * _cutawayFactor(frontN);
    final hScaleS = 1.0 - 0.85 * _cutawayFactor(frontS);
    final hScaleW = 1.0 - 0.85 * _cutawayFactor(frontW);
    final hScaleE = 1.0 - 0.85 * _cutawayFactor(frontE);

    // -------------------------------------------------------------------------
    // PASS 1: Floors, Parquet/Tiles, Live Thermal Tint & Flat Rugs (Zero Z-fight)
    // -------------------------------------------------------------------------
    final roomProjections = <({
      HouseRoom room,
      RoomEspTelemetry tel,
      bool isSel,
      Path floorPath,
      double avgFloorDepth,
    })>[];

    for (final r in plan.rooms) {
      final isSel = r.id == selectedRoomId;
      final tel = telemetries[r.id] ?? const RoomEspTelemetry.offline('');
      final x0 = r.gridX;
      final x1 = r.gridX + r.width;
      final z0 = r.gridY;
      final z1 = r.gridY + r.depth;

      final p00 = project(_Vec3(x0, 0.0, z0));
      final p10 = project(_Vec3(x1, 0.0, z0));
      final p11 = project(_Vec3(x1, 0.0, z1));
      final p01 = project(_Vec3(x0, 0.0, z1));
      final avgFloorDepth = (p00.depth + p10.depth + p11.depth + p01.depth) * 0.25;
      final floorPath = Path()..addPolygon([p00.pt, p10.pt, p11.pt, p01.pt], true);

      roomProjections.add((
        room: r,
        tel: tel,
        isSel: isSel,
        floorPath: floorPath,
        avgFloorDepth: avgFloorDepth,
      ));
    }

    roomProjections.sort((a, b) => a.avgFloorDepth.compareTo(b.avgFloorDepth));
    onPolygonsProjected([
      for (final rp in roomProjections)
        (roomId: rp.room.id, path: rp.floorPath, depth: rp.avgFloorDepth),
    ]);

    void drawFlatFloorQuad(
      double fx0,
      double fz0,
      double fx1,
      double fz1,
      Color fill, {
      Color? stroke,
      double strokeWidth = 0.8,
    }) {
      final a = project(_Vec3(fx0, 0.01, fz0)).pt;
      final b = project(_Vec3(fx1, 0.01, fz0)).pt;
      final c = project(_Vec3(fx1, 0.01, fz1)).pt;
      final d = project(_Vec3(fx0, 0.01, fz1)).pt;
      final p = Path()..addPolygon([a, b, c, d], true);
      canvas.drawPath(p, Paint()..color = fill);
      if (stroke != null) {
        canvas.drawPath(
          p,
          Paint()
            ..color = stroke
            ..style = PaintingStyle.stroke
            ..strokeWidth = strokeWidth,
        );
      }
    }

    for (final rp in roomProjections) {
      final r = rp.room;
      final x0 = r.gridX;
      final x1 = r.gridX + r.width;
      final z0 = r.gridY;
      final z1 = r.gridY + r.depth;

      // Room natural floor material
      final floorBase = _roomFloorBaseColor(r.kind);
      canvas.drawPath(rp.floorPath, Paint()..color = floorBase);

      // Floor surface texture in 60 FPS Ultra mode only
      if (!isEco) {
        canvas.save();
        canvas.clipPath(rp.floorPath);
        final isTiled = r.kind == HouseRoomKind.kitchen ||
            r.kind == HouseRoomKind.bath ||
            r.kind == HouseRoomKind.hall;
        final grainPaint = Paint()
          ..color = (palette.isLight ? Colors.black : Colors.white)
              .withValues(alpha: isTiled ? 0.09 : 0.08)
          ..strokeWidth = 0.85;
        if (isTiled) {
          const step = 0.55;
          for (double gx = x0 + step; gx < x1; gx += step) {
            canvas.drawLine(
              project(_Vec3(gx, 0.0, z0)).pt,
              project(_Vec3(gx, 0.0, z1)).pt,
              grainPaint,
            );
          }
          for (double gz = z0 + step; gz < z1; gz += step) {
            canvas.drawLine(
              project(_Vec3(x0, 0.0, gz)).pt,
              project(_Vec3(x1, 0.0, gz)).pt,
              grainPaint,
            );
          }
        } else {
          const plankW = 0.42;
          for (double gz = z0 + plankW; gz < z1; gz += plankW) {
            canvas.drawLine(
              project(_Vec3(x0, 0.0, gz)).pt,
              project(_Vec3(x1, 0.0, gz)).pt,
              grainPaint,
            );
          }
        }
        canvas.restore();
      }

      // Live ESP thermal floor tint ONLY when online
      final heatTint = _thermalOverlayTint(rp.tel);
      if (heatTint != null) {
        canvas.drawPath(rp.floorPath, Paint()..color = heatTint);
      }

      // Room floor rugs drawn in Pass 1 so 3D furniture cleanly sits above
      final cx = x0 + r.width * 0.5;
      final cz = z0 + r.depth * 0.5;
      final rugW = math.min(r.width * 0.52, 2.2);
      final rugD = math.min(r.depth * 0.48, 1.8);
      if (r.kind == HouseRoomKind.living) {
        drawFlatFloorQuad(
          cx - rugW * 0.5,
          cz - rugD * 0.42,
          cx + rugW * 0.5,
          cz + rugD * 0.52,
          palette.isLight ? const Color(0xFFE14D72) : const Color(0xFF9F2A4D),
          stroke: Colors.white.withValues(alpha: 0.25),
        );
      } else if (r.kind == HouseRoomKind.bedroom) {
        drawFlatFloorQuad(
          cx - rugW * 0.55,
          cz - rugD * 0.35,
          cx + rugW * 0.55,
          cz + rugD * 0.55,
          palette.isLight ? const Color(0xFFD1D5DB) : const Color(0xFF334155),
          stroke: Colors.white.withValues(alpha: 0.16),
        );
      } else if (r.kind == HouseRoomKind.kids) {
        drawFlatFloorQuad(
          cx - rugW * 0.46,
          cz - rugD * 0.36,
          cx + rugW * 0.46,
          cz + rugD * 0.44,
          palette.isLight ? const Color(0xFF38BDF8) : const Color(0xFF0369A1),
          stroke: const Color(0xFFFDE047).withValues(alpha: 0.45),
        );
      } else if (r.kind == HouseRoomKind.study) {
        drawFlatFloorQuad(
          cx - rugW * 0.48,
          cz - rugD * 0.38,
          cx + rugW * 0.48,
          cz + rugD * 0.44,
          palette.isLight ? const Color(0xFF64748B) : const Color(0xFF1E293B),
          stroke: Colors.white.withValues(alpha: 0.15),
        );
      } else if (r.kind == HouseRoomKind.bath) {
        drawFlatFloorQuad(
          cx - rugW * 0.34,
          cz,
          cx + rugW * 0.34,
          cz + rugD * 0.45,
          palette.isLight ? const Color(0xFFF8FAFC) : const Color(0xFF475569),
        );
      } else if (r.kind == HouseRoomKind.hall) {
        final rw = math.min(r.width * 0.58, 1.3);
        final rd = math.min(r.depth * 0.68, 2.4);
        drawFlatFloorQuad(
          cx - rw * 0.5,
          cz - rd * 0.5,
          cx + rw * 0.5,
          cz + rd * 0.5,
          palette.isLight ? const Color(0xFFB45309) : const Color(0xFF78350F),
          stroke: const Color(0xFFFDE68A).withValues(alpha: 0.32),
        );
      }

      // Floor selection rim
      canvas.drawPath(
        rp.floorPath,
        Paint()
          ..color = rp.isSel ? accentColor : palette.cardBorder.withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = rp.isSel ? 2.2 : 0.9,
      );
    }

    // -------------------------------------------------------------------------
    // PASS 2: 3D Extruded Cutaway Walls, Windows, Boiler Hub, Radiators & Diorama Furniture
    // -------------------------------------------------------------------------
    final quads = <_ProjectedQuad>[];
    final wallH = 1.26 * wallHeightRatio;

    void addQuadRaw(
      List<({Offset pt, double depth})> pts,
      Color fill, {
      Color? stroke,
      double strokeWidth = 0.6,
      double depthBias = 0.0,
    }) {
      double d = 0.0;
      for (final p in pts) {
        d += p.depth;
      }
      quads.add(
        _ProjectedQuad(
          pts: [for (final p in pts) p.pt],
          depth: (d / pts.length) + depthBias,
          fill: fill,
          stroke: stroke,
          strokeWidth: strokeWidth,
        ),
      );
    }

    // Backface-culled 3D box builder with isometric directional shading
    void addBox3D({
      required double x0,
      required double y0,
      required double z0,
      required double x1,
      required double y1,
      required double z1,
      required Color color,
      Color? topColor,
      Color? stroke,
      double strokeWidth = 0.55,
      double depthBias = 0.0,
      bool drawTop = true,
    }) {
      if (x1 <= x0 + 0.002 || y1 <= y0 + 0.002 || z1 <= z0 + 0.002) return;

      final b00 = project(_Vec3(x0, y0, z0));
      final b10 = project(_Vec3(x1, y0, z0));
      final b11 = project(_Vec3(x1, y0, z1));
      final b01 = project(_Vec3(x0, y0, z1));

      final t00 = project(_Vec3(x0, y1, z0));
      final t10 = project(_Vec3(x1, y1, z0));
      final t11 = project(_Vec3(x1, y1, z1));
      final t01 = project(_Vec3(x0, y1, z1));

      final shadedTop = topColor ?? Color.lerp(color, Colors.white, 0.22)!;
      final shadedLit = Color.lerp(color, Colors.white, 0.06)!;
      final shadedMid = color;
      final shadedDark = Color.lerp(color, Colors.black, 0.24)!;

      if (drawTop) {
        addQuadRaw(
          [t00, t10, t11, t01],
          shadedTop,
          stroke: stroke,
          strokeWidth: strokeWidth,
          depthBias: depthBias + 0.002,
        );
      }
      if (showSouth) {
        addQuadRaw([b01, b11, t11, t01], shadedLit, stroke: stroke, strokeWidth: strokeWidth, depthBias: depthBias);
      }
      if (showWest) {
        addQuadRaw([b00, b01, t01, t00], shadedMid, stroke: stroke, strokeWidth: strokeWidth, depthBias: depthBias);
      }
      if (showEast) {
        addQuadRaw([b10, b11, t11, t10], shadedDark, stroke: stroke, strokeWidth: strokeWidth, depthBias: depthBias);
      }
      if (showNorth) {
        addQuadRaw([b00, b10, t10, t00], shadedDark, stroke: stroke, strokeWidth: strokeWidth, depthBias: depthBias);
      }
    }

    // Wall-mounted flat panel (for windows, framed art, mirrors, wall clocks, TV screen)
    void addNorthWallDecor({
      required double cx,
      required double cy,
      required double zPlane,
      required double w,
      required double h,
      required Color fill,
      Color? stroke,
      double depthBias = 0.02,
    }) {
      final a = project(_Vec3(cx - w * 0.5, cy - h * 0.5, zPlane));
      final b = project(_Vec3(cx + w * 0.5, cy - h * 0.5, zPlane));
      final c = project(_Vec3(cx + w * 0.5, cy + h * 0.5, zPlane));
      final d = project(_Vec3(cx - w * 0.5, cy + h * 0.5, zPlane));
      addQuadRaw([a, b, c, d], fill, stroke: stroke, strokeWidth: 0.7, depthBias: depthBias);
    }

    void addEastWallDecor({
      required double xPlane,
      required double cy,
      required double cz,
      required double d,
      required double h,
      required Color fill,
      Color? stroke,
      double depthBias = 0.02,
    }) {
      final a = project(_Vec3(xPlane, cy - h * 0.5, cz - d * 0.5));
      final b = project(_Vec3(xPlane, cy - h * 0.5, cz + d * 0.5));
      final c = project(_Vec3(xPlane, cy + h * 0.5, cz + d * 0.5));
      final e = project(_Vec3(xPlane, cy + h * 0.5, cz - d * 0.5));
      addQuadRaw([a, b, c, e], fill, stroke: stroke, strokeWidth: 0.7, depthBias: depthBias);
    }

    void addSouthWallDecor({
      required double cx,
      required double cy,
      required double zPlane,
      required double w,
      required double h,
      required Color fill,
      Color? stroke,
      double depthBias = 0.02,
    }) {
      final a = project(_Vec3(cx - w * 0.5, cy - h * 0.5, zPlane));
      final b = project(_Vec3(cx + w * 0.5, cy - h * 0.5, zPlane));
      final c = project(_Vec3(cx + w * 0.5, cy + h * 0.5, zPlane));
      final d = project(_Vec3(cx - w * 0.5, cy + h * 0.5, zPlane));
      addQuadRaw([a, b, c, d], fill, stroke: stroke, strokeWidth: 0.7, depthBias: depthBias);
    }

    void addWestWallDecor({
      required double xPlane,
      required double cy,
      required double cz,
      required double d,
      required double h,
      required Color fill,
      Color? stroke,
      double depthBias = 0.02,
    }) {
      final a = project(_Vec3(xPlane, cy - h * 0.5, cz - d * 0.5));
      final b = project(_Vec3(xPlane, cy - h * 0.5, cz + d * 0.5));
      final c = project(_Vec3(xPlane, cy + h * 0.5, cz + d * 0.5));
      final e = project(_Vec3(xPlane, cy + h * 0.5, cz - d * 0.5));
      addQuadRaw([a, b, c, e], fill, stroke: stroke, strokeWidth: 0.7, depthBias: depthBias);
    }

    void addPottedPlant({
      required double px,
      required double pz,
      double radius = 0.16,
      double height = 0.68,
    }) {
      addBox3D(
        x0: px - radius * 0.72,
        y0: 0.0,
        z0: pz - radius * 0.72,
        x1: px + radius * 0.72,
        y1: height * 0.24,
        z1: pz + radius * 0.72,
        color: const Color(0xFFB4654A),
      );
      addBox3D(
        x0: px - radius,
        y0: height * 0.24,
        z0: pz - radius,
        x1: px + radius,
        y1: height * 0.62,
        z1: pz + radius,
        color: const Color(0xFF65B741),
        depthBias: 0.015,
      );
      addBox3D(
        x0: px - radius * 0.65,
        y0: height * 0.62,
        z0: pz - radius * 0.65,
        x1: px + radius * 0.65,
        y1: height,
        z1: pz + radius * 0.65,
        color: const Color(0xFF84CC16),
        depthBias: 0.025,
      );
    }

    for (final rp in roomProjections) {
      final r = rp.room;
      final tel = rp.tel;
      final isSel = rp.isSel;
      final x0 = r.gridX;
      final x1 = r.gridX + r.width;
      final z0 = r.gridY;
      final z1 = r.gridY + r.depth;

      final innerWallCol = _wallInnerColor(r.kind);
      final capWallCol = palette.isLight
          ? Color.lerp(innerWallCol, Colors.white, 0.58)!
          : Color.lerp(innerWallCol, const Color(0xFF94A3B8), 0.35)!;
      final wallBorderCol = isSel
          ? accentColor.withValues(alpha: 0.75)
          : Colors.white.withValues(alpha: palette.isLight ? 0.30 : 0.12);

      // 2A. Cutaway Walls
      if (wallH > 0.05) {
        final wN = wallH * hScaleN;
        final wS = wallH * hScaleS;
        final wW = wallH * hScaleW;
        final wE = wallH * hScaleE;

        if (isEco) {
          // Low-poly ECO mode: single translucent wall planes without thickness caps
          void addSimpleWall(double ax, double az, double bx, double bz, double h, double shade, double bias) {
            final p0 = project(_Vec3(ax, 0.0, az));
            final p1 = project(_Vec3(bx, 0.0, bz));
            final t1 = project(_Vec3(bx, h, bz));
            final t0 = project(_Vec3(ax, h, az));
            final col = Color.lerp(innerWallCol, Colors.black, shade)!.withValues(alpha: isSel ? 0.62 : 0.45);
            addQuadRaw([p0, p1, t1, t0], col, stroke: wallBorderCol, strokeWidth: isSel ? 1.3 : 0.8, depthBias: bias);
          }

          addSimpleWall(x0, z0, x1, z0, wN, 0.10, frontN > 0 ? 0.02 : -0.04);
          addSimpleWall(x1, z0, x1, z1, wE, 0.22, frontE > 0 ? 0.02 : -0.04);
          addSimpleWall(x1, z1, x0, z1, wS, 0.14, frontS > 0 ? 0.02 : -0.04);
          addSimpleWall(x0, z1, x0, z0, wW, 0.26, frontW > 0 ? 0.02 : -0.04);
        } else {
          // 60 FPS Ultra mode: thick extruded cutaway architectural walls with top caps
          const wt = 0.095;
          addBox3D(
            x0: x0,
            y0: 0.0,
            z0: z0,
            x1: x1,
            y1: wN,
            z1: z0 + wt,
            color: innerWallCol,
            topColor: capWallCol,
            stroke: wallBorderCol,
            strokeWidth: 0.7,
            depthBias: frontN > 0 ? 0.025 : -0.045,
          );
          addBox3D(
            x0: x0,
            y0: 0.0,
            z0: z1 - wt,
            x1: x1,
            y1: wS,
            z1: z1,
            color: innerWallCol,
            topColor: capWallCol,
            stroke: wallBorderCol,
            strokeWidth: 0.7,
            depthBias: frontS > 0 ? 0.025 : -0.045,
          );
          addBox3D(
            x0: x0,
            y0: 0.0,
            z0: z0 + wt,
            x1: x0 + wt,
            y1: wW,
            z1: z1 - wt,
            color: innerWallCol,
            topColor: capWallCol,
            stroke: wallBorderCol,
            strokeWidth: 0.7,
            depthBias: frontW > 0 ? 0.025 : -0.045,
          );
          addBox3D(
            x0: x1 - wt,
            y0: 0.0,
            z0: z0 + wt,
            x1: x1,
            y1: wE,
            z1: z1 - wt,
            color: innerWallCol,
            topColor: capWallCol,
            stroke: wallBorderCol,
            strokeWidth: 0.7,
            depthBias: frontE > 0 ? 0.025 : -0.045,
          );

          // 2B. Back-wall Windows, Clock & Wall Art on tall rear walls (Ultra 60 FPS)
          final skyCol = palette.isLight ? const Color(0xFF93C5FD) : const Color(0xFF2B4170);
          final frameCol = palette.isLight ? const Color(0xFFFEF3C7) : const Color(0xFF475569);

          if (r.kind != HouseRoomKind.hall && r.kind != HouseRoomKind.bath) {
            if (hScaleN > 0.65 && wallH > 0.75 && r.width >= 2.2) {
              final wx = x0 + r.width * 0.5;
              final winW = math.min(r.width * 0.42, 1.25);
              addNorthWallDecor(
                cx: wx,
                cy: wN * 0.58,
                zPlane: z0 + wt + 0.01,
                w: winW + 0.08,
                h: wN * 0.44 + 0.08,
                fill: frameCol,
                depthBias: -0.03,
              );
              addNorthWallDecor(
                cx: wx,
                cy: wN * 0.58,
                zPlane: z0 + wt + 0.018,
                w: winW,
                h: wN * 0.44,
                fill: skyCol,
                depthBias: -0.022,
              );
              // Mini sill planter boxes on window ledge
              if (r.kind == HouseRoomKind.living || r.kind == HouseRoomKind.kitchen) {
                addBox3D(
                  x0: wx - 0.16,
                  y0: wN * 0.34,
                  z0: z0 + wt,
                  x1: wx - 0.04,
                  y1: wN * 0.44,
                  z1: z0 + wt + 0.09,
                  color: const Color(0xFF65B741),
                  depthBias: -0.015,
                );
                addBox3D(
                  x0: wx + 0.06,
                  y0: wN * 0.34,
                  z0: z0 + wt,
                  x1: wx + 0.18,
                  y1: wN * 0.43,
                  z1: z0 + wt + 0.09,
                  color: const Color(0xFF84CC16),
                  depthBias: -0.015,
                );
              }
            } else if (hScaleS > 0.65 && wallH > 0.75 && r.width >= 2.2) {
              final wx = x0 + r.width * 0.5;
              final winW = math.min(r.width * 0.42, 1.25);
              addSouthWallDecor(
                cx: wx,
                cy: wS * 0.58,
                zPlane: z1 - wt - 0.01,
                w: winW + 0.08,
                h: wS * 0.44 + 0.08,
                fill: frameCol,
                depthBias: -0.03,
              );
              addSouthWallDecor(
                cx: wx,
                cy: wS * 0.58,
                zPlane: z1 - wt - 0.018,
                w: winW,
                h: wS * 0.44,
                fill: skyCol,
                depthBias: -0.022,
              );
            }
          }

          // Wall art & round clock on tall East or West back wall
          if (r.kind == HouseRoomKind.living || r.kind == HouseRoomKind.study || r.kind == HouseRoomKind.bedroom) {
            if (hScaleE > 0.65 && wallH > 0.75 && r.depth >= 2.2) {
              addEastWallDecor(
                xPlane: x1 - wt - 0.01,
                cy: wE * 0.65,
                cz: z0 + r.depth * 0.34,
                d: 0.34,
                h: 0.38,
                fill: const Color(0xFF3B82F6),
                stroke: Colors.white,
                depthBias: -0.025,
              );
              addEastWallDecor(
                xPlane: x1 - wt - 0.015,
                cy: wE * 0.65,
                cz: z0 + r.depth * 0.34,
                d: 0.22,
                h: 0.26,
                fill: const Color(0xFFFDF2F8),
                depthBias: -0.018,
              );
              if (r.kind == HouseRoomKind.living || r.kind == HouseRoomKind.study) {
                addEastWallDecor(
                  xPlane: x1 - wt - 0.012,
                  cy: wE * 0.66,
                  cz: z0 + r.depth * 0.66,
                  d: 0.22,
                  h: 0.22,
                  fill: Colors.white,
                  stroke: const Color(0xFF334155),
                  depthBias: -0.02,
                );
              }
            } else if (hScaleW > 0.65 && wallH > 0.75 && r.depth >= 2.2) {
              addWestWallDecor(
                xPlane: x0 + wt + 0.01,
                cy: wW * 0.65,
                cz: z0 + r.depth * 0.34,
                d: 0.34,
                h: 0.38,
                fill: const Color(0xFF3B82F6),
                stroke: Colors.white,
                depthBias: -0.025,
              );
              addWestWallDecor(
                xPlane: x0 + wt + 0.015,
                cy: wW * 0.65,
                cz: z0 + r.depth * 0.34,
                d: 0.22,
                h: 0.26,
                fill: const Color(0xFFFDF2F8),
                depthBias: -0.018,
              );
            }
          }

          // Kitchen upper wall cabinets on tall North/East wall
          if (r.kind == HouseRoomKind.kitchen && wallH > 0.75) {
            if (hScaleN > 0.55) {
              addBox3D(
                x0: x0 + 0.14,
                y0: wN * 0.56,
                z0: z0 + wt,
                x1: x0 + math.min(r.width * 0.52, 2.0),
                y1: wN * 0.90,
                z1: z0 + wt + 0.24,
                color: palette.isLight ? const Color(0xFFF8FAFC) : const Color(0xFF475569),
                depthBias: -0.01,
              );
            }
          }

          // Bathroom vanity mirror on tall North/East wall
          if (r.kind == HouseRoomKind.bath && wallH > 0.75) {
            if (hScaleE > 0.55) {
              addEastWallDecor(
                xPlane: x1 - wt - 0.012,
                cy: wE * 0.64,
                cz: z0 + r.depth * 0.35,
                d: 0.44,
                h: 0.40,
                fill: const Color(0xFFBAE6FD),
                stroke: Colors.white,
                depthBias: -0.02,
              );
            } else if (hScaleN > 0.55) {
              addNorthWallDecor(
                cx: x0 + r.width * 0.35,
                cy: wN * 0.64,
                zPlane: z0 + wt + 0.012,
                w: 0.44,
                h: 0.40,
                fill: const Color(0xFFBAE6FD),
                stroke: Colors.white,
                depthBias: -0.02,
              );
            }
          }
        }
      }

      // 2C. 3D Combi Boiler Hub Cabinet inside boiler hub room
      if (r.isBoilerHub) {
        final bx = x0 + 0.20;
        final bz = z0 + 0.20;
        final boilerTop = 0.28 + 0.58 * math.max(0.28, wallHeightRatio);
        addBox3D(
          x0: bx,
          y0: 0.28,
          z0: bz,
          x1: bx + 0.36,
          y1: boilerTop,
          z1: bz + 0.24,
          color: palette.isLight ? const Color(0xFFF8FAFC) : const Color(0xFFE2E8F0),
          stroke: const Color(0xFFF59E0B),
          strokeWidth: 1.0,
          depthBias: 0.03,
        );
        if (!isEco) {
          addBox3D(
            x0: bx + 0.08,
            y0: 0.36,
            z0: bz + 0.22,
            x1: bx + 0.28,
            y1: 0.36 + (boilerTop - 0.36) * 0.45,
            z1: bz + 0.26,
            color: boiler.isHeating ? const Color(0xFFF97316) : const Color(0xFF0F172A),
            depthBias: 0.045,
          );
        }
      }

      // 2D. 3D Radiators along walls
      for (final rad in r.radiators) {
        final isHot = tel.online && tel.radiatorTempC != null && tel.radiatorTempC! >= 35.0;
        final radColor = isHot
            ? const Color(0xFFF59E0B)
            : (palette.isLight ? const Color(0xFFE2E8F0) : const Color(0xFF94A3B8));
        late double rx0, rx1, rz0, rz1;
        switch (rad.wallSide) {
          case RadiatorWallSide.north:
            {
              final cx = x0 + r.width * rad.offsetRatio;
              rx0 = cx - 0.36;
              rx1 = cx + 0.36;
              rz0 = z0 + 0.11;
              rz1 = z0 + 0.23;
            }
            break;
          case RadiatorWallSide.south:
            {
              final cx = x0 + r.width * rad.offsetRatio;
              rx0 = cx - 0.36;
              rx1 = cx + 0.36;
              rz0 = z1 - 0.23;
              rz1 = z1 - 0.11;
            }
            break;
          case RadiatorWallSide.west:
            {
              final cz = z0 + r.depth * rad.offsetRatio;
              rx0 = x0 + 0.11;
              rx1 = x0 + 0.23;
              rz0 = cz - 0.36;
              rz1 = cz + 0.36;
            }
            break;
          case RadiatorWallSide.east:
            {
              final cz = z0 + r.depth * rad.offsetRatio;
              rx0 = x1 - 0.23;
              rx1 = x1 - 0.11;
              rz0 = cz - 0.36;
              rz1 = cz + 0.36;
            }
            break;
        }
        final topY = 0.07 + 0.38 * math.max(0.25, wallHeightRatio);
        addBox3D(
          x0: rx0.clamp(x0 + 0.10, x1 - 0.22),
          y0: 0.07,
          z0: rz0.clamp(z0 + 0.10, z1 - 0.22),
          x1: rx1.clamp(x0 + 0.22, x1 - 0.10),
          y1: topY,
          z1: rz1.clamp(z0 + 0.22, z1 - 0.10),
          color: radColor,
          stroke: isHot ? const Color(0xFFFDE68A) : Colors.white.withValues(alpha: 0.45),
          strokeWidth: 0.85,
          depthBias: 0.04,
        );
      }

      // 2E. Room-Kind Isometric Diorama Furniture (Full 60 FPS detail vs ECO low-poly)
      const margin = 0.24;
      final fx0 = x0 + margin;
      final fx1 = x1 - margin;
      final fz0 = z0 + margin;
      final fz1 = z1 - margin;
      final fw = math.max(0.6, fx1 - fx0);
      final fd = math.max(0.6, fz1 - fz0);
      final fcx = (fx0 + fx1) * 0.5;
      final fcz = (fz0 + fz1) * 0.5;

      switch (r.kind) {
        case HouseRoomKind.living:
          {
            // Sofa near right-back quadrant
            final sofaW = math.min(fw * 0.44, 1.45);
            final sofaD = math.min(fd * 0.30, 0.72);
            final sx1 = fx1 - 0.06;
            final sx0 = sx1 - sofaW;
            final sz0 = fz0 + 0.12;
            final sz1 = sz0 + sofaD;
            final sofaCol = palette.isLight ? const Color(0xFFFDF5E6) : const Color(0xFFCBD5E1);

            if (isEco) {
              addBox3D(x0: sx0, y0: 0.04, z0: sz0, x1: sx1, y1: 0.42, z1: sz1, color: sofaCol);
            } else {
              // Base seat + armrests + tall backrest + teal throw pillow
              addBox3D(x0: sx0, y0: 0.08, z0: sz0, x1: sx1, y1: 0.28, z1: sz1, color: sofaCol);
              addBox3D(
                x0: sx0,
                y0: 0.28,
                z0: sz0,
                x1: sx1,
                y1: 0.58,
                z1: sz0 + sofaD * 0.26,
                color: Color.lerp(sofaCol, Colors.white, 0.25)!,
                depthBias: 0.012,
              );
              addBox3D(
                x0: sx0,
                y0: 0.24,
                z0: sz0 + sofaD * 0.26,
                x1: sx0 + 0.14,
                y1: 0.40,
                z1: sz1,
                color: sofaCol,
                depthBias: 0.015,
              );
              addBox3D(
                x0: sx1 - 0.14,
                y0: 0.24,
                z0: sz0 + sofaD * 0.26,
                x1: sx1,
                y1: 0.40,
                z1: sz1,
                color: sofaCol,
                depthBias: 0.015,
              );
              // Teal throw pillow
              addBox3D(
                x0: sx0 + 0.18,
                y0: 0.28,
                z0: sz0 + sofaD * 0.28,
                x1: sx0 + 0.44,
                y1: 0.39,
                z1: sz0 + sofaD * 0.62,
                color: const Color(0xFF14B8A6),
                depthBias: 0.03,
              );
            }

            // Coffee table in center
            final tblW = math.min(fw * 0.30, 0.85);
            final tblD = math.min(fd * 0.24, 0.62);
            final tx0 = fcx - tblW * 0.5;
            final tx1 = fcx + tblW * 0.5;
            final tz0 = fcz - tblD * 0.45;
            final tz1 = fcz + tblD * 0.55;
            final oakCol = const Color(0xFFE0A976);
            if (isEco) {
              addBox3D(x0: tx0, y0: 0.04, z0: tz0, x1: tx1, y1: 0.26, z1: tz1, color: oakCol);
            } else {
              addBox3D(x0: tx0 + 0.04, y0: 0.0, z0: tz0 + 0.04, x1: tx0 + 0.10, y1: 0.22, z1: tz0 + 0.10, color: const Color(0xFF334155));
              addBox3D(x0: tx1 - 0.10, y0: 0.0, z0: tz0 + 0.04, x1: tx1 - 0.04, y1: 0.22, z1: tz0 + 0.10, color: const Color(0xFF334155));
              addBox3D(x0: tx0 + 0.04, y0: 0.0, z0: tz1 - 0.10, x1: tx0 + 0.10, y1: 0.22, z1: tz1 - 0.04, color: const Color(0xFF334155));
              addBox3D(x0: tx1 - 0.10, y0: 0.0, z0: tz1 - 0.10, x1: tx1 - 0.04, y1: 0.22, z1: tz1 - 0.04, color: const Color(0xFF334155));
              addBox3D(x0: tx0, y0: 0.22, z0: tz0, x1: tx1, y1: 0.27, z1: tz1, color: oakCol, depthBias: 0.015);
              // Hardcover book & white coffee mug on table
              addBox3D(
                x0: tx0 + tblW * 0.45,
                y0: 0.27,
                z0: tz0 + tblD * 0.35,
                x1: tx0 + tblW * 0.78,
                y1: 0.33,
                z1: tz0 + tblD * 0.70,
                color: const Color(0xFF2563EB),
                depthBias: 0.032,
              );
              addBox3D(
                x0: tx0 + tblW * 0.16,
                y0: 0.27,
                z0: tz0 + tblD * 0.22,
                x1: tx0 + tblW * 0.29,
                y1: 0.36,
                z1: tz0 + tblD * 0.35,
                color: Colors.white,
                depthBias: 0.035,
              );
            }

            // TV Stand + Flatscreen TV opposite sofa
            final tvW = math.min(fw * 0.38, 1.10);
            final tvD = math.min(fd * 0.18, 0.38);
            final mx0 = fx0 + 0.08;
            final mx1 = mx0 + tvW;
            final mz1 = fz1 - 0.08;
            final mz0 = mz1 - tvD;
            addBox3D(x0: mx0, y0: 0.04, z0: mz0, x1: mx1, y1: 0.28, z1: mz1, color: sofaCol);
            if (!isEco) {
              addBox3D(
                x0: mx0 + tvW * 0.10,
                y0: 0.31,
                z0: mz0 + tvD * 0.38,
                x1: mx1 - tvW * 0.10,
                y1: 0.74,
                z1: mz0 + tvD * 0.56,
                color: const Color(0xFF1E293B),
                stroke: const Color(0xFF475569),
                depthBias: 0.025,
              );
              addPottedPlant(px: fx0 + 0.28, pz: fz0 + 0.28, radius: math.min(0.15, fw * 0.09), height: 0.72);
            }
          }
          break;

        case HouseRoomKind.kitchen:
          {
            final cntD = math.min(fd * 0.34, 0.68);
            final cntW = math.min(fw * 0.72, 2.30);
            final cntCol = palette.isLight ? const Color(0xFFF1F5F9) : const Color(0xFF334155);
            final stoneCol = palette.isLight ? const Color(0xFFCBD5E1) : const Color(0xFF64748B);
            addBox3D(
              x0: fx0 + 0.05,
              y0: 0.0,
              z0: fz0 + 0.05,
              x1: fx0 + 0.05 + cntW,
              y1: 0.56,
              z1: fz0 + 0.05 + cntD,
              color: cntCol,
              topColor: stoneCol,
            );
            // Fridge in right-back corner
            final frW = math.min(fw * 0.24, 0.64);
            addBox3D(
              x0: fx1 - frW - 0.04,
              y0: 0.0,
              z0: fz0 + 0.05,
              x1: fx1 - 0.04,
              y1: 1.05,
              z1: fz0 + 0.05 + math.min(fd * 0.32, 0.64),
              color: palette.isLight ? const Color(0xFFCBD5E1) : const Color(0xFF94A3B8),
            );
            // Dining table
            final dtW = math.min(fw * 0.44, 1.10);
            final dtD = math.min(fd * 0.30, 0.74);
            addBox3D(
              x0: fcx - dtW * 0.45,
              y0: isEco ? 0.0 : 0.32,
              z0: fz1 - dtD - 0.14,
              x1: fcx + dtW * 0.45,
              y1: 0.40,
              z1: fz1 - 0.14,
              color: const Color(0xFFD99B66),
            );
            if (!isEco) {
              // Cooktop plate + sink basin + 2 dining chairs
              addBox3D(
                x0: fx0 + 0.22,
                y0: 0.56,
                z0: fz0 + 0.14,
                x1: fx0 + 0.22 + math.min(0.48, cntW * 0.32),
                y1: 0.59,
                z1: fz0 + 0.14 + cntD * 0.62,
                color: const Color(0xFF0F172A),
                depthBias: 0.02,
              );
              addBox3D(
                x0: fx0 + 0.22 + cntW * 0.42,
                y0: 0.56,
                z0: fz0 + 0.16,
                x1: fx0 + 0.22 + cntW * 0.68,
                y1: 0.585,
                z1: fz0 + 0.16 + cntD * 0.56,
                color: const Color(0xFF38BDF8),
                depthBias: 0.02,
              );
              // Two chairs
              addBox3D(
                x0: fcx - dtW * 0.62,
                y0: 0.0,
                z0: fz1 - dtD * 0.72 - 0.14,
                x1: fcx - dtW * 0.48,
                y1: 0.30,
                z1: fz1 - dtD * 0.32 - 0.14,
                color: const Color(0xFF475569),
              );
              addBox3D(
                x0: fcx + dtW * 0.48,
                y0: 0.0,
                z0: fz1 - dtD * 0.72 - 0.14,
                x1: fcx + dtW * 0.62,
                y1: 0.30,
                z1: fz1 - dtD * 0.32 - 0.14,
                color: const Color(0xFF475569),
              );
            }
          }
          break;

        case HouseRoomKind.bedroom:
          {
            final bedW = math.min(fw * 0.56, 1.55);
            final bedD = math.min(fd * 0.58, 1.75);
            final bx0 = fcx - bedW * 0.5;
            final bx1 = fcx + bedW * 0.5;
            final bz0 = fz0 + 0.12;
            final bz1 = bz0 + bedD;

            if (isEco) {
              addBox3D(
                x0: bx0,
                y0: 0.04,
                z0: bz0,
                x1: bx1,
                y1: 0.34,
                z1: bz1,
                color: const Color(0xFF2D6A74),
                topColor: const Color(0xFFF8FAFC),
              );
            } else {
              // Wood frame + headboard + crisp mattress + folded duvet + 2 pillows
              addBox3D(x0: bx0, y0: 0.04, z0: bz0, x1: bx1, y1: 0.24, z1: bz1, color: const Color(0xFF8B5E3C));
              addBox3D(x0: bx0, y0: 0.24, z0: bz0, x1: bx1, y1: 0.66, z1: bz0 + 0.10, color: const Color(0xFF6B4423), depthBias: 0.01);
              addBox3D(x0: bx0 + 0.04, y0: 0.24, z0: bz0 + 0.10, x1: bx1 - 0.04, y1: 0.34, z1: bz1 - 0.04, color: const Color(0xFFF8FAFC), depthBias: 0.015);
              addBox3D(
                x0: bx0 + 0.03,
                y0: 0.30,
                z0: bz0 + bedD * 0.36,
                x1: bx1 - 0.03,
                y1: 0.38,
                z1: bz1 - 0.03,
                color: const Color(0xFF2D6A74),
                depthBias: 0.025,
              );
              // Pillows
              addBox3D(
                x0: bx0 + 0.10,
                y0: 0.34,
                z0: bz0 + 0.14,
                x1: fcx - 0.05,
                y1: 0.42,
                z1: bz0 + 0.36,
                color: Colors.white,
                depthBias: 0.035,
              );
              addBox3D(
                x0: fcx + 0.05,
                y0: 0.34,
                z0: bz0 + 0.14,
                x1: bx1 - 0.10,
                y1: 0.42,
                z1: bz0 + 0.36,
                color: Colors.white,
                depthBias: 0.035,
              );
              // Nightstands + glowing bedside lamps if width allows
              if (fw > 2.0) {
                addBox3D(x0: bx0 - 0.36, y0: 0.0, z0: bz0 + 0.06, x1: bx0 - 0.08, y1: 0.32, z1: bz0 + 0.34, color: const Color(0xFF8B5E3C));
                addBox3D(x0: bx0 - 0.28, y0: 0.32, z0: bz0 + 0.14, x1: bx0 - 0.16, y1: 0.48, z1: bz0 + 0.26, color: const Color(0xFFFDE68A), depthBias: 0.025);
                addBox3D(x0: bx1 + 0.08, y0: 0.0, z0: bz0 + 0.06, x1: bx1 + 0.36, y1: 0.32, z1: bz0 + 0.34, color: const Color(0xFF8B5E3C));
                addBox3D(x0: bx1 + 0.16, y0: 0.32, z0: bz0 + 0.14, x1: bx1 + 0.28, y1: 0.48, z1: bz0 + 0.26, color: const Color(0xFFFDE68A), depthBias: 0.025);
              }
            }
            // Wardrobe
            addBox3D(
              x0: fx0 + 0.05,
              y0: 0.0,
              z0: fz1 - math.min(fd * 0.36, 0.85),
              x1: fx0 + math.min(fw * 0.22, 0.52),
              y1: 0.96,
              z1: fz1 - 0.05,
              color: palette.isLight ? const Color(0xFFE2E8F0) : const Color(0xFF475569),
            );
          }
          break;

        case HouseRoomKind.kids:
          {
            final kBedW = math.min(fw * 0.42, 0.92);
            final kBedD = math.min(fd * 0.56, 1.48);
            addBox3D(
              x0: fx0 + 0.08,
              y0: 0.04,
              z0: fz0 + 0.12,
              x1: fx0 + 0.08 + kBedW,
              y1: 0.32,
              z1: fz0 + 0.12 + kBedD,
              color: const Color(0xFFF59E0B),
              topColor: const Color(0xFFFEF3C7),
            );
            // Kids study desk
            final dW = math.min(fw * 0.40, 0.96);
            final dD = math.min(fd * 0.24, 0.48);
            addBox3D(
              x0: fx1 - dW - 0.06,
              y0: isEco ? 0.0 : 0.34,
              z0: fz0 + 0.12,
              x1: fx1 - 0.06,
              y1: 0.42,
              z1: fz0 + 0.12 + dD,
              color: const Color(0xFFE0A976),
            );
            if (!isEco) {
              // Pillow + colorful toy cubes
              addBox3D(
                x0: fx0 + 0.16,
                y0: 0.32,
                z0: fz0 + 0.18,
                x1: fx0 + kBedW - 0.04,
                y1: 0.40,
                z1: fz0 + 0.42,
                color: Colors.white,
                depthBias: 0.03,
              );
              addBox3D(
                x0: fx1 - 0.42,
                y0: 0.0,
                z0: fz1 - 0.40,
                x1: fx1 - 0.20,
                y1: 0.22,
                z1: fz1 - 0.18,
                color: const Color(0xFFEC4899),
              );
              addBox3D(
                x0: fx1 - 0.64,
                y0: 0.0,
                z0: fz1 - 0.36,
                x1: fx1 - 0.44,
                y1: 0.18,
                z1: fz1 - 0.18,
                color: const Color(0xFF38BDF8),
              );
            }
          }
          break;

        case HouseRoomKind.bath:
          {
            // Corner shower tray
            final shW = math.min(fw * 0.44, 0.92);
            final shD = math.min(fd * 0.44, 0.92);
            addBox3D(
              x0: fx0 + 0.04,
              y0: 0.0,
              z0: fz0 + 0.04,
              x1: fx0 + 0.04 + shW,
              y1: 0.09,
              z1: fz0 + 0.04 + shD,
              color: const Color(0xFFF8FAFC),
            );
            if (!isEco) {
              // Translucent glass shower enclosure
              addBox3D(
                x0: fx0 + 0.04 + shW - 0.03,
                y0: 0.09,
                z0: fz0 + 0.04,
                x1: fx0 + 0.04 + shW,
                y1: 0.96,
                z1: fz0 + 0.04 + shD,
                color: const Color(0xFF67E8F9).withValues(alpha: 0.28),
                stroke: Colors.white.withValues(alpha: 0.55),
                depthBias: 0.02,
              );
            }
            // Vanity + sink
            final vW = math.min(fw * 0.36, 0.72);
            addBox3D(
              x0: fx1 - vW - 0.06,
              y0: 0.06,
              z0: fz0 + 0.08,
              x1: fx1 - 0.06,
              y1: 0.48,
              z1: fz0 + 0.08 + math.min(fd * 0.26, 0.44),
              color: palette.isLight ? const Color(0xFF0F766E) : const Color(0xFF1E293B),
              topColor: Colors.white,
            );
            // Ceramic toilet
            addBox3D(
              x0: fx1 - 0.42,
              y0: 0.0,
              z0: fz1 - 0.46,
              x1: fx1 - 0.10,
              y1: 0.28,
              z1: fz1 - 0.14,
              color: const Color(0xFFF8FAFC),
            );
            if (!isEco) {
              addBox3D(
                x0: fx1 - 0.42,
                y0: 0.28,
                z0: fz1 - 0.24,
                x1: fx1 - 0.10,
                y1: 0.52,
                z1: fz1 - 0.10,
                color: Colors.white,
                depthBias: 0.02,
              );
            }
          }
          break;

        case HouseRoomKind.study:
          {
            // Desk + monitor + chair + bookcase
            final dW = math.min(fw * 0.56, 1.35);
            final dD = math.min(fd * 0.30, 0.62);
            final dx0 = fcx - dW * 0.5;
            final dx1 = fcx + dW * 0.5;
            final dz0 = fz0 + 0.14;
            final dz1 = dz0 + dD;
            addBox3D(
              x0: dx0,
              y0: isEco ? 0.0 : 0.38,
              z0: dz0,
              x1: dx1,
              y1: 0.46,
              z1: dz1,
              color: const Color(0xFF92400E),
            );
            // Ergonomic chair
            addBox3D(
              x0: fcx - 0.20,
              y0: 0.14,
              z0: dz1 + 0.08,
              x1: fcx + 0.20,
              y1: 0.36,
              z1: dz1 + 0.44,
              color: const Color(0xFF1E293B),
            );
            // Bookcase
            addBox3D(
              x0: fx1 - math.min(fw * 0.24, 0.42),
              y0: 0.0,
              z0: fz0 + 0.14,
              x1: fx1 - 0.04,
              y1: 0.98,
              z1: fz0 + 0.14 + math.min(fd * 0.46, 1.05),
              color: const Color(0xFF78350F),
            );
            if (!isEco) {
              // Monitor screen + keyboard + desk mug + potted plant
              addBox3D(
                x0: fcx - 0.28,
                y0: 0.48,
                z0: dz0 + 0.10,
                x1: fcx + 0.28,
                y1: 0.80,
                z1: dz0 + 0.18,
                color: const Color(0xFF0F172A),
                stroke: const Color(0xFF38BDF8),
                depthBias: 0.03,
              );
              addBox3D(
                x0: dx1 - 0.22,
                y0: 0.46,
                z0: dz0 + 0.22,
                x1: dx1 - 0.10,
                y1: 0.54,
                z1: dz0 + 0.34,
                color: Colors.white,
                depthBias: 0.035,
              );
              addPottedPlant(px: fx0 + 0.22, pz: fz1 - 0.22, radius: math.min(0.14, fw * 0.08), height: 0.64);
            }
          }
          break;

        case HouseRoomKind.hall:
          {
            // Entryway coat/shoe console + bench
            final cW = math.min(fw * 0.42, 0.95);
            addBox3D(
              x0: fx0 + 0.06,
              y0: 0.0,
              z0: fz0 + 0.08,
              x1: fx0 + 0.06 + cW,
              y1: 0.88,
              z1: fz0 + 0.08 + math.min(fd * 0.22, 0.38),
              color: palette.isLight ? const Color(0xFF94A3B8) : const Color(0xFF475569),
            );
            addBox3D(
              x0: fx1 - math.min(fw * 0.36, 0.78) - 0.06,
              y0: 0.0,
              z0: fz1 - math.min(fd * 0.24, 0.40) - 0.06,
              x1: fx1 - 0.06,
              y1: 0.28,
              z1: fz1 - 0.06,
              color: const Color(0xFFD97706),
            );
          }
          break;
      }
    }

    // Painter's algorithm sort (far to near)
    quads.sort((a, b) => a.depth.compareTo(b.depth));

    for (final q in quads) {
      final path = Path()..addPolygon(q.pts, true);
      canvas.drawPath(path, Paint()..color = q.fill);
      if (q.stroke != null) {
        canvas.drawPath(
          path,
          Paint()
            ..color = q.stroke!
            ..style = PaintingStyle.stroke
            ..strokeWidth = q.strokeWidth
            ..strokeJoin = StrokeJoin.round,
        );
      }
    }

    // -------------------------------------------------------------------------
    // PASS 3: Top-Level Boiler Hub Badge, ESP32 Beacon & Room Telemetry Labels
    // -------------------------------------------------------------------------
    for (final r in plan.rooms) {
      final tel = telemetries[r.id] ?? const RoomEspTelemetry.offline('');
      final isSel = r.id == selectedRoomId;
      final center = project(_Vec3(r.centerX, 0.22, r.centerY)).pt;

      if (r.isBoilerHub) {
        final bp = project(_Vec3(r.gridX + 0.38, 0.92, r.gridY + 0.34)).pt;
        canvas.drawCircle(
          bp,
          6.5,
          Paint()..color = boiler.isHeating ? const Color(0xFFF97316) : const Color(0xFFF59E0B),
        );
        canvas.drawCircle(
          bp,
          6.5,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4,
        );
      }

      if (r.espNodeId.trim().isNotEmpty) {
        final ep = project(_Vec3(r.gridX + r.width - 0.34, 0.34, r.gridY + 0.34)).pt;
        final beaconCol = tel.online ? const Color(0xFF10B981) : const Color(0xFF94A3B8);
        canvas.drawCircle(ep, 4.5, Paint()..color = beaconCol);
        if (tel.online) {
          canvas.drawCircle(
            ep,
            9.0,
            Paint()
              ..color = beaconCol.withValues(alpha: 0.35)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.3,
          );
        }
      }

      final tempBadge = tel.roomTempC != null ? '${tel.roomTempC!.toStringAsFixed(1)}°' : '--';
      final tp = TextPainter(
        text: TextSpan(
          children: [
            TextSpan(
              text: '${r.name}\n',
              style: TextStyle(
                fontSize: isSel ? 11.0 : 9.8,
                fontWeight: FontWeight.w700,
                color: palette.textPrimary,
              ),
            ),
            TextSpan(
              text: tempBadge,
              style: TextStyle(
                fontSize: isSel ? 12.0 : 10.5,
                fontWeight: FontWeight.w800,
                color: tel.roomTempC != null ? accentColor : palette.textSecondary,
              ),
            ),
          ],
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 96);

      final pillRect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: center,
          width: tp.width + 12,
          height: tp.height + 6,
        ),
        const Radius.circular(8),
      );
      canvas.drawRRect(
        pillRect,
        Paint()
          ..color = (palette.isLight ? Colors.white : const Color(0xFF0A0D16))
              .withValues(alpha: isSel ? 0.90 : 0.72),
      );
      if (isSel) {
        canvas.drawRRect(
          pillRect,
          Paint()
            ..color = accentColor.withValues(alpha: 0.75)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );
      }
      tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _House3DPainter oldDelegate) => true;
}

class _FloorplanEditorPainter extends CustomPainter {
  final HouseFloorPlan plan;
  final String selectedRoomId;
  final double unitPx;
  final Offset offset;
  final Color accentColor;
  final ThemePaletteSpec palette;
  final bool tr;

  const _FloorplanEditorPainter({
    required this.plan,
    required this.selectedRoomId,
    required this.unitPx,
    required this.offset,
    required this.accentColor,
    required this.palette,
    required this.tr,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = palette.isLight
          ? const Color(0xFF0F172A).withValues(alpha: 0.08)
          : Colors.white.withValues(alpha: 0.06)
      ..strokeWidth = 1.0;

    for (double x = 0; x <= HouseFloorPlan.gridMaxWidth; x += 1.0) {
      final px = offset.dx + x * unitPx;
      canvas.drawLine(
        Offset(px, offset.dy),
        Offset(px, offset.dy + HouseFloorPlan.gridMaxDepth * unitPx),
        gridPaint,
      );
    }
    for (double y = 0; y <= HouseFloorPlan.gridMaxDepth; y += 1.0) {
      final py = offset.dy + y * unitPx;
      canvas.drawLine(
        Offset(offset.dx, py),
        Offset(offset.dx + HouseFloorPlan.gridMaxWidth * unitPx, py),
        gridPaint,
      );
    }

    for (final r in plan.rooms) {
      final isSel = r.id == selectedRoomId;
      final rect = Rect.fromLTWH(
        offset.dx + r.gridX * unitPx,
        offset.dy + r.gridY * unitPx,
        r.width * unitPx,
        r.depth * unitPx,
      );
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(8));
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = isSel
              ? accentColor.withValues(alpha: 0.22)
              : (palette.isLight
                  ? const Color(0xFFCBD5E1).withValues(alpha: 0.45)
                  : Colors.white.withValues(alpha: 0.07)),
      );
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = isSel ? accentColor : palette.cardBorder
          ..style = PaintingStyle.stroke
          ..strokeWidth = isSel ? 2.2 : 1.2,
      );

      // Draw radiator bars on walls
      for (final rad in r.radiators) {
        late Rect radRect;
        switch (rad.wallSide) {
          case RadiatorWallSide.north:
            {
              final cx = rect.left + rect.width * rad.offsetRatio;
              radRect = Rect.fromCenter(center: Offset(cx, rect.top + 4.0), width: math.min(26.0, rect.width * 0.45), height: 5.0);
            }
            break;
          case RadiatorWallSide.south:
            {
              final cx = rect.left + rect.width * rad.offsetRatio;
              radRect = Rect.fromCenter(center: Offset(cx, rect.bottom - 4.0), width: math.min(26.0, rect.width * 0.45), height: 5.0);
            }
            break;
          case RadiatorWallSide.west:
            {
              final cy = rect.top + rect.height * rad.offsetRatio;
              radRect = Rect.fromCenter(center: Offset(rect.left + 4.0, cy), width: 5.0, height: math.min(26.0, rect.height * 0.45));
            }
            break;
          case RadiatorWallSide.east:
            {
              final cy = rect.top + rect.height * rad.offsetRatio;
              radRect = Rect.fromCenter(center: Offset(rect.right - 4.0, cy), width: 5.0, height: math.min(26.0, rect.height * 0.45));
            }
            break;
        }
        canvas.drawRRect(
          RRect.fromRectAndRadius(radRect, const Radius.circular(2)),
          Paint()..color = const Color(0xFFF59E0B),
        );
      }

      // Boiler hub orange badge
      if (r.isBoilerHub) {
        canvas.drawCircle(Offset(rect.left + 10, rect.top + 10), 4.5, Paint()..color = const Color(0xFFF59E0B));
      }

      // Resize handle bottom-right on selected room
      if (isSel) {
        canvas.drawCircle(
          Offset(rect.right - 4, rect.bottom - 4),
          6.0,
          Paint()..color = accentColor,
        );
      }

      final tp = TextPainter(
        text: TextSpan(
          text: '${r.name}\n${r.width.toStringAsFixed(1)}×${r.depth.toStringAsFixed(1)}m',
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
            color: palette.textPrimary,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: math.max(30.0, rect.width - 6));
      tp.paint(
        canvas,
        Offset(rect.center.dx - tp.width / 2, rect.center.dy - tp.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FloorplanEditorPainter oldDelegate) => true;
}
