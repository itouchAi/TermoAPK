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

        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isLandscape ? 980 : 520),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
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
                        tr ? 'Döndür · Odaya dokun' : 'Drag to orbit · Tap room',
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
            child: SingleChildScrollView(child: inspectorCard),
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

    final inspector = ListView(
      padding: const EdgeInsets.only(bottom: 6),
      children: [
        // Ready Templates Row
        Text(
          tr ? 'HAZIR EV ŞABLONLARI' : 'READY TEMPLATES',
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: palette.textSecondary),
        ),
        const SizedBox(height: 5),
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: HouseFloorPlan.readyTemplates.length + 1,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (ctx, idx) {
              if (idx == HouseFloorPlan.readyTemplates.length) {
                return OutlinedButton.icon(
                  onPressed: _addNewRoom,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: widget.accentColor,
                    side: BorderSide(color: widget.accentColor.withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.add_box_outlined, size: 15),
                  label: Text(tr ? '+ Oda Ekle' : '+ Add Room', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                );
              }
              final tpl = HouseFloorPlan.readyTemplates[idx];
              final active = widget.floorPlan.templateId == tpl.id;
              return ChoiceChip(
                label: Text(
                  tr ? tpl.labelTr : tpl.labelEn,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: active ? Colors.white : palette.textPrimary,
                  ),
                ),
                selected: active,
                selectedColor: widget.accentColor,
                backgroundColor: palette.cardBg,
                side: BorderSide(color: active ? widget.accentColor : palette.cardBorder),
                onSelected: (_) => _selectTemplate(tpl.id),
              );
            },
          ),
        ),
        if (selectedRoom != null) ...[
          const SizedBox(height: 8),
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
        ],
      ],
    );

    if (isLandscape) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 6, child: gridWidget),
          const SizedBox(width: 10),
          Expanded(flex: 4, child: inspector),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 5, child: gridWidget),
        const SizedBox(height: 8),
        Expanded(flex: 5, child: inspector),
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
    required this.tr,
    required this.onPolygonsProjected,
  });

  Color _thermalFloorColor(RoomEspTelemetry tel, bool isSelected) {
    if (!tel.online || tel.roomTempC == null) {
      return palette.isLight
          ? (isSelected ? const Color(0xFFCBD5E1) : const Color(0xFFE2E8F0))
          : (isSelected ? const Color(0xFF1E293B) : const Color(0xFF141926));
    }
    final t = tel.roomTempC!;
    if (t < 18.5) return const Color(0xFF38BDF8).withValues(alpha: 0.72);
    if (t < 21.5) return const Color(0xFF10B981).withValues(alpha: 0.72);
    if (t < 24.0) return const Color(0xFFF59E0B).withValues(alpha: 0.76);
    return const Color(0xFFEF4444).withValues(alpha: 0.80);
  }

  @override
  void paint(Canvas canvas, Size size) {
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
      // Shift relative to house center & camera focus
      final wx = v.x - centerWorld.dx - focusWorld.dx;
      final wz = v.z - centerWorld.dy - focusWorld.dy;
      final wy = v.y;

      // Rotate around Y (yaw)
      final rx = wx * cosY - wz * sinY;
      final rz = wx * sinY + wz * cosY;

      // Rotate around X (pitch): looking down from pitch angle
      final sx = rx;
      final sy = -wy * cosP + rz * sinP;
      final depth = wy * sinP + rz * cosP;

      // Subtle perspective foreshortening
      final persp = 1.0 / (1.0 - (depth * 0.022).clamp(-0.35, 0.35));
      return (
        pt: Offset(
          screenCenter.dx + sx * baseScale * persp,
          screenCenter.dy + sy * baseScale * persp,
        ),
        depth: depth,
      );
    }

    // 1. Soft radial shadow & subtle ground grid
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(screenCenter.dx, screenCenter.dy + baseScale * 0.25),
        width: size.width * 0.76,
        height: size.height * 0.42,
      ),
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.black.withValues(alpha: palette.isLight ? 0.14 : 0.45),
            Colors.transparent,
          ],
        ).createShader(Offset.zero & size),
    );

    final gridPaint = Paint()
      ..color = palette.isLight
          ? const Color(0xFF0F172A).withValues(alpha: 0.07)
          : Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1.0;
    for (double gx = 0; gx <= HouseFloorPlan.gridMaxWidth; gx += 1.0) {
      final a = project(_Vec3(gx, 0, 0)).pt;
      final b = project(_Vec3(gx, 0, HouseFloorPlan.gridMaxDepth)).pt;
      canvas.drawLine(a, b, gridPaint);
    }
    for (double gz = 0; gz <= HouseFloorPlan.gridMaxDepth; gz += 1.0) {
      final a = project(_Vec3(0, 0, gz)).pt;
      final b = project(_Vec3(HouseFloorPlan.gridMaxWidth, 0, gz)).pt;
      canvas.drawLine(a, b, gridPaint);
    }

    // 2. Collect projected room floors & walls
    final quads = <_ProjectedQuad>[];
    final hitFloors = <({String roomId, Path path, double depth})>[];
    final wallH = 1.15 * wallHeightRatio;

    for (final r in plan.rooms) {
      final isSel = r.id == selectedRoomId;
      final tel = telemetries[r.id] ?? const RoomEspTelemetry.offline('');
      final x0 = r.gridX;
      final x1 = r.gridX + r.width;
      final z0 = r.gridY;
      final z1 = r.gridY + r.depth;

      final p00 = project(_Vec3(x0, 0, z0));
      final p10 = project(_Vec3(x1, 0, z0));
      final p11 = project(_Vec3(x1, 0, z1));
      final p01 = project(_Vec3(x0, 0, z1));
      final avgFloorDepth = (p00.depth + p10.depth + p11.depth + p01.depth) * 0.25;

      final floorPts = [p00.pt, p10.pt, p11.pt, p01.pt];
      final floorPath = Path()..addPolygon(floorPts, true);
      hitFloors.add((roomId: r.id, path: floorPath, depth: avgFloorDepth));

      quads.add(
        _ProjectedQuad(
          pts: floorPts,
          depth: avgFloorDepth - 0.15,
          fill: _thermalFloorColor(tel, isSel),
          stroke: isSel ? accentColor : palette.cardBorder,
          strokeWidth: isSel ? 2.2 : 1.0,
        ),
      );

      if (wallH > 0.05) {
        final t00 = project(_Vec3(x0, wallH, z0));
        final t10 = project(_Vec3(x1, wallH, z0));
        final t11 = project(_Vec3(x1, wallH, z1));
        final t01 = project(_Vec3(x0, wallH, z1));

        void addWall(
          ({Offset pt, double depth}) b0,
          ({Offset pt, double depth}) b1,
          ({Offset pt, double depth}) t1,
          ({Offset pt, double depth}) t0,
          double shade,
        ) {
          final baseCol = palette.isLight
              ? Color.lerp(const Color(0xFFF8FAFC), const Color(0xFFCBD5E1), shade)!
              : Color.lerp(const Color(0xFF1F2937), const Color(0xFF0F172A), shade)!;
          quads.add(
            _ProjectedQuad(
              pts: [b0.pt, b1.pt, t1.pt, t0.pt],
              depth: (b0.depth + b1.depth + t1.depth + t0.depth) * 0.25,
              fill: baseCol.withValues(alpha: isSel ? 0.56 : 0.42),
              stroke: isSel
                  ? accentColor.withValues(alpha: 0.75)
                  : Colors.white.withValues(alpha: palette.isLight ? 0.35 : 0.14),
              strokeWidth: isSel ? 1.4 : 0.9,
            ),
          );
        }

        addWall(p00, p10, t10, t00, 0.25);
        addWall(p10, p11, t11, t10, 0.55);
        addWall(p11, p01, t01, t11, 0.35);
        addWall(p01, p00, t00, t01, 0.65);
      }

      // 3. Draw 3D radiators mounted along walls
      for (final rad in r.radiators) {
        final radColor = (tel.online && tel.radiatorTempC != null && tel.radiatorTempC! >= 35.0)
            ? const Color(0xFFF59E0B)
            : (palette.isLight ? const Color(0xFF64748B) : const Color(0xFF94A3B8));
        late double rx0, rx1, rz0, rz1;
        late bool isHorizontalWall;
        switch (rad.wallSide) {
          case RadiatorWallSide.north:
            {
              final cx = x0 + r.width * rad.offsetRatio;
              rx0 = cx - 0.38; rx1 = cx + 0.38; rz0 = z0 + 0.06; rz1 = z0 + 0.22;
              isHorizontalWall = true;
            }
            break;
          case RadiatorWallSide.south:
            {
              final cx = x0 + r.width * rad.offsetRatio;
              rx0 = cx - 0.38; rx1 = cx + 0.38; rz0 = z1 - 0.22; rz1 = z1 - 0.06;
              isHorizontalWall = true;
            }
            break;
          case RadiatorWallSide.west:
            {
              final cz = z0 + r.depth * rad.offsetRatio;
              rx0 = x0 + 0.06; rx1 = x0 + 0.22; rz0 = cz - 0.38; rz1 = cz + 0.38;
              isHorizontalWall = false;
            }
            break;
          case RadiatorWallSide.east:
            {
              final cz = z0 + r.depth * rad.offsetRatio;
              rx0 = x1 - 0.22; rx1 = x1 - 0.06; rz0 = cz - 0.38; rz1 = cz + 0.38;
              isHorizontalWall = false;
            }
            break;
        }
        final topY = 0.08 + 0.36 * math.max(0.25, wallHeightRatio);
        // Vertical panel face along the wall
        final vf0 = isHorizontalWall
            ? project(_Vec3(rx0, 0.06, (rz0 + rz1) * 0.5))
            : project(_Vec3((rx0 + rx1) * 0.5, 0.06, rz0));
        final vf1 = isHorizontalWall
            ? project(_Vec3(rx1, 0.06, (rz0 + rz1) * 0.5))
            : project(_Vec3((rx0 + rx1) * 0.5, 0.06, rz1));
        final vt1 = isHorizontalWall
            ? project(_Vec3(rx1, topY, (rz0 + rz1) * 0.5))
            : project(_Vec3((rx0 + rx1) * 0.5, topY, rz1));
        final vt0 = isHorizontalWall
            ? project(_Vec3(rx0, topY, (rz0 + rz1) * 0.5))
            : project(_Vec3((rx0 + rx1) * 0.5, topY, rz0));
        quads.add(
          _ProjectedQuad(
            pts: [vf0.pt, vf1.pt, vt1.pt, vt0.pt],
            depth: (vf0.depth + vf1.depth + vt1.depth + vt0.depth) * 0.25 + 0.06,
            fill: radColor.withValues(alpha: 0.90),
            stroke: Colors.white.withValues(alpha: 0.45),
            strokeWidth: 0.9,
          ),
        );
        // Top rim so 2D / top-down views also show the radiator clearly
        final rt00 = project(_Vec3(rx0, topY, rz0));
        final rt10 = project(_Vec3(rx1, topY, rz0));
        final rt11 = project(_Vec3(rx1, topY, rz1));
        final rt01 = project(_Vec3(rx0, topY, rz1));
        quads.add(
          _ProjectedQuad(
            pts: [rt00.pt, rt10.pt, rt11.pt, rt01.pt],
            depth: (rt00.depth + rt10.depth + rt11.depth + rt01.depth) * 0.25 + 0.09,
            fill: Color.lerp(radColor, Colors.white, 0.18)!.withValues(alpha: 0.95),
            stroke: Colors.white.withValues(alpha: 0.55),
            strokeWidth: 0.9,
          ),
        );
      }
    }

    // Painter's algorithm sort (far to near)
    quads.sort((a, b) => a.depth.compareTo(b.depth));
    hitFloors.sort((a, b) => a.depth.compareTo(b.depth));
    onPolygonsProjected(hitFloors);

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

    // 4. Draw Boiler Hub badge, ESP32 Beacon & Room Temperature Labels on top
    for (final r in plan.rooms) {
      final tel = telemetries[r.id] ?? const RoomEspTelemetry.offline('');
      final isSel = r.id == selectedRoomId;
      final center = project(_Vec3(r.centerX, 0.22, r.centerY)).pt;

      // Boiler Hub marker
      if (r.isBoilerHub) {
        final bp = project(_Vec3(r.gridX + 0.45, 0.35, r.gridY + 0.45)).pt;
        canvas.drawCircle(bp, 7.5, Paint()..color = const Color(0xFFF59E0B));
        canvas.drawCircle(
          bp,
          7.5,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4,
        );
      }

      // ESP32 beacon dot
      if (r.espNodeId.trim().isNotEmpty) {
        final ep = project(_Vec3(r.gridX + r.width - 0.38, 0.28, r.gridY + 0.38)).pt;
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
