import 'dart:math' as math;
import 'package:flutter/material.dart';

enum HouseRoomKind {
  living,
  bedroom,
  kitchen,
  kids,
  bath,
  study,
  hall,
}

enum RadiatorWallSide {
  north,
  south,
  east,
  west,
}

class RadiatorNode {
  final String id;
  final RadiatorWallSide wallSide;
  final double offsetRatio; // 0.15..0.85 along the chosen wall

  const RadiatorNode({
    required this.id,
    required this.wallSide,
    this.offsetRatio = 0.5,
  });

  RadiatorNode copyWith({
    String? id,
    RadiatorWallSide? wallSide,
    double? offsetRatio,
  }) {
    return RadiatorNode(
      id: id ?? this.id,
      wallSide: wallSide ?? this.wallSide,
      offsetRatio: (offsetRatio ?? this.offsetRatio).clamp(0.15, 0.85),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'wallSide': wallSide.name,
        'offsetRatio': offsetRatio,
      };

  factory RadiatorNode.fromJson(Map<String, dynamic> map) {
    final rawWall = map['wallSide'] as String?;
    RadiatorWallSide side = RadiatorWallSide.north;
    for (final v in RadiatorWallSide.values) {
      if (v.name == rawWall) {
        side = v;
        break;
      }
    }
    return RadiatorNode(
      id: (map['id'] as String?) ?? 'rad_1',
      wallSide: side,
      offsetRatio: ((map['offsetRatio'] as num?)?.toDouble() ?? 0.5).clamp(0.15, 0.85),
    );
  }
}

class HouseRoom {
  final String id;
  final String name;
  final HouseRoomKind kind;
  final double gridX; // meters in 0..12
  final double gridY; // meters in 0..10
  final double width; // meters (1.5..9.0)
  final double depth; // meters (1.5..9.0)
  final String espNodeId;
  final bool isBoilerHub;
  final List<RadiatorNode> radiators;

  const HouseRoom({
    required this.id,
    required this.name,
    required this.kind,
    required this.gridX,
    required this.gridY,
    required this.width,
    required this.depth,
    this.espNodeId = '',
    this.isBoilerHub = false,
    this.radiators = const [],
  });

  double get centerX => gridX + width / 2.0;
  double get centerY => gridY + depth / 2.0;
  double get areaM2 => width * depth;

  HouseRoom copyWith({
    String? id,
    String? name,
    HouseRoomKind? kind,
    double? gridX,
    double? gridY,
    double? width,
    double? depth,
    String? espNodeId,
    bool? isBoilerHub,
    List<RadiatorNode>? radiators,
  }) {
    return HouseRoom(
      id: id ?? this.id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      gridX: (gridX ?? this.gridX).clamp(0.0, 12.0),
      gridY: (gridY ?? this.gridY).clamp(0.0, 10.0),
      width: (width ?? this.width).clamp(1.5, 9.0),
      depth: (depth ?? this.depth).clamp(1.5, 9.0),
      espNodeId: espNodeId ?? this.espNodeId,
      isBoilerHub: isBoilerHub ?? this.isBoilerHub,
      radiators: radiators ?? this.radiators,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'gridX': gridX,
        'gridY': gridY,
        'width': width,
        'depth': depth,
        'espNodeId': espNodeId,
        'isBoilerHub': isBoilerHub,
        'radiators': radiators.map((r) => r.toJson()).toList(),
      };

  factory HouseRoom.fromJson(Map<String, dynamic> map) {
    final rawKind = map['kind'] as String?;
    HouseRoomKind parsedKind = HouseRoomKind.living;
    for (final v in HouseRoomKind.values) {
      if (v.name == rawKind) {
        parsedKind = v;
        break;
      }
    }
    final radRaw = map['radiators'];
    final rads = <RadiatorNode>[];
    if (radRaw is List) {
      for (final item in radRaw) {
        if (item is Map<String, dynamic>) {
          rads.add(RadiatorNode.fromJson(item));
        } else if (item is Map) {
          rads.add(RadiatorNode.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    return HouseRoom(
      id: (map['id'] as String?) ?? 'room_${DateTime.now().microsecondsSinceEpoch}',
      name: (map['name'] as String?) ?? 'Oda',
      kind: parsedKind,
      gridX: ((map['gridX'] as num?)?.toDouble() ?? 1.0).clamp(0.0, 11.0),
      gridY: ((map['gridY'] as num?)?.toDouble() ?? 1.0).clamp(0.0, 9.0),
      width: ((map['width'] as num?)?.toDouble() ?? 3.5).clamp(1.5, 9.0),
      depth: ((map['depth'] as num?)?.toDouble() ?? 3.0).clamp(1.5, 9.0),
      espNodeId: (map['espNodeId'] as String?) ?? '',
      isBoilerHub: (map['isBoilerHub'] as bool?) ?? false,
      radiators: rads,
    );
  }

  static String kindLabel(HouseRoomKind kind, {bool tr = true}) {
    switch (kind) {
      case HouseRoomKind.living:
        return tr ? 'Salon' : 'Living Room';
      case HouseRoomKind.bedroom:
        return tr ? 'Yatak Odası' : 'Bedroom';
      case HouseRoomKind.kitchen:
        return tr ? 'Mutfak' : 'Kitchen';
      case HouseRoomKind.kids:
        return tr ? 'Çocuk Odası' : 'Kids Room';
      case HouseRoomKind.bath:
        return tr ? 'Banyo' : 'Bathroom';
      case HouseRoomKind.study:
        return tr ? 'Çalışma' : 'Study';
      case HouseRoomKind.hall:
        return tr ? 'Koridor / Hol' : 'Hallway';
    }
  }

  static IconData kindIcon(HouseRoomKind kind) {
    switch (kind) {
      case HouseRoomKind.living:
        return Icons.weekend_outlined;
      case HouseRoomKind.bedroom:
        return Icons.bed_outlined;
      case HouseRoomKind.kitchen:
        return Icons.kitchen_outlined;
      case HouseRoomKind.kids:
        return Icons.child_care_outlined;
      case HouseRoomKind.bath:
        return Icons.bathtub_outlined;
      case HouseRoomKind.study:
        return Icons.desk_outlined;
      case HouseRoomKind.hall:
        return Icons.door_front_door_outlined;
    }
  }

  static String wallLabel(RadiatorWallSide side, {bool tr = true}) {
    switch (side) {
      case RadiatorWallSide.north:
        return tr ? 'Üst Duvar' : 'North Wall';
      case RadiatorWallSide.south:
        return tr ? 'Alt Duvar' : 'South Wall';
      case RadiatorWallSide.east:
        return tr ? 'Sağ Duvar' : 'East Wall';
      case RadiatorWallSide.west:
        return tr ? 'Sol Duvar' : 'West Wall';
    }
  }
}

class HouseTemplateOption {
  final String id;
  final String labelTr;
  final String labelEn;
  final String subtitleTr;
  final String subtitleEn;

  const HouseTemplateOption({
    required this.id,
    required this.labelTr,
    required this.labelEn,
    required this.subtitleTr,
    required this.subtitleEn,
  });
}

class HouseFloorPlan {
  final String templateId;
  final String name;
  final String referenceRoomId;
  final List<HouseRoom> rooms;

  const HouseFloorPlan({
    required this.templateId,
    required this.name,
    required this.referenceRoomId,
    required this.rooms,
  });

  static const double gridMaxWidth = 12.0;
  static const double gridMaxDepth = 10.0;

  static const List<HouseTemplateOption> readyTemplates = [
    HouseTemplateOption(
      id: '1+1',
      labelTr: '1+1 Daire',
      labelEn: '1+1 Apt',
      subtitleTr: '4 Alan · Salon, Mutfak, Yatak, Banyo',
      subtitleEn: '4 Zones · Living, Kitchen, Bedroom, Bath',
    ),
    HouseTemplateOption(
      id: '2+1',
      labelTr: '2+1 Daire',
      labelEn: '2+1 Apt',
      subtitleTr: '6 Alan · Salon, Mutfak, 2 Oda, Hol, Banyo',
      subtitleEn: '6 Zones · Living, Kitchen, 2 Beds, Hall, Bath',
    ),
    HouseTemplateOption(
      id: '3+1',
      labelTr: '3+1 Geniş',
      labelEn: '3+1 Family',
      subtitleTr: '7 Alan · Büyük Salon, 3 Oda, Mutfak, Banyo',
      subtitleEn: '7 Zones · Large Living, 3 Beds, Kitchen, Bath',
    ),
    HouseTemplateOption(
      id: 'duplex',
      labelTr: 'Dubleks Kat',
      labelEn: 'Duplex Floor',
      subtitleTr: '5 Alan · Açık Plan + Çalışma + Süit',
      subtitleEn: '5 Zones · Open Plan + Study + Suite',
    ),
  ];

  static double snapHalfMeter(double value) => (value * 2.0).round() / 2.0;

  static HouseFloorPlan fromTemplate(String templateId, {bool tr = true}) {
    switch (templateId) {
      case '1+1':
        return HouseFloorPlan.template1Plus1(tr: tr);
      case '3+1':
        return HouseFloorPlan.template3Plus1(tr: tr);
      case 'duplex':
        return HouseFloorPlan.templateDuplex(tr: tr);
      case '2+1':
      default:
        return HouseFloorPlan.template2Plus1(tr: tr);
    }
  }

  factory HouseFloorPlan.template1Plus1({bool tr = true}) => HouseFloorPlan(
        templateId: '1+1',
        name: tr ? '1+1 Daire Planı' : '1+1 Apartment Plan',
        referenceRoomId: 'salon',
        rooms: [
          HouseRoom(
            id: 'salon',
            name: tr ? 'Salon' : 'Living Room',
            kind: HouseRoomKind.living,
            gridX: 1.5,
            gridY: 1.5,
            width: 5.0,
            depth: 4.5,
            espNodeId: 'kombi',
            radiators: const [
              RadiatorNode(id: 'rad_s1', wallSide: RadiatorWallSide.north, offsetRatio: 0.5),
            ],
          ),
          HouseRoom(
            id: 'mutfak',
            name: tr ? 'Mutfak' : 'Kitchen',
            kind: HouseRoomKind.kitchen,
            gridX: 6.5,
            gridY: 1.5,
            width: 3.5,
            depth: 3.0,
            espNodeId: 'esp32_mutfak',
            isBoilerHub: true,
            radiators: const [
              RadiatorNode(id: 'rad_m1', wallSide: RadiatorWallSide.east, offsetRatio: 0.5),
            ],
          ),
          HouseRoom(
            id: 'yatak',
            name: tr ? 'Yatak Odası' : 'Bedroom',
            kind: HouseRoomKind.bedroom,
            gridX: 1.5,
            gridY: 6.0,
            width: 4.5,
            depth: 3.0,
            espNodeId: 'esp32_yatak',
            radiators: const [
              RadiatorNode(id: 'rad_y1', wallSide: RadiatorWallSide.south, offsetRatio: 0.5),
            ],
          ),
          HouseRoom(
            id: 'banyo',
            name: tr ? 'Banyo' : 'Bathroom',
            kind: HouseRoomKind.bath,
            gridX: 6.0,
            gridY: 4.5,
            width: 4.0,
            depth: 4.5,
            espNodeId: '',
            radiators: const [
              RadiatorNode(id: 'rad_b1', wallSide: RadiatorWallSide.east, offsetRatio: 0.6),
            ],
          ),
        ],
      );

  factory HouseFloorPlan.template2Plus1({bool tr = true}) => HouseFloorPlan(
        templateId: '2+1',
        name: tr ? '2+1 Standart Daire' : '2+1 Standard Flat',
        referenceRoomId: 'salon',
        rooms: [
          HouseRoom(
            id: 'salon',
            name: tr ? 'Salon' : 'Living Room',
            kind: HouseRoomKind.living,
            gridX: 1.0,
            gridY: 1.0,
            width: 5.0,
            depth: 4.5,
            espNodeId: 'kombi',
            radiators: const [
              RadiatorNode(id: 'rad_s1', wallSide: RadiatorWallSide.north, offsetRatio: 0.35),
              RadiatorNode(id: 'rad_s2', wallSide: RadiatorWallSide.west, offsetRatio: 0.5),
            ],
          ),
          HouseRoom(
            id: 'mutfak',
            name: tr ? 'Mutfak' : 'Kitchen',
            kind: HouseRoomKind.kitchen,
            gridX: 6.0,
            gridY: 1.0,
            width: 4.5,
            depth: 3.0,
            espNodeId: 'esp32_mutfak',
            isBoilerHub: true,
            radiators: const [
              RadiatorNode(id: 'rad_m1', wallSide: RadiatorWallSide.north, offsetRatio: 0.55),
            ],
          ),
          HouseRoom(
            id: 'hol',
            name: tr ? 'Koridor' : 'Hallway',
            kind: HouseRoomKind.hall,
            gridX: 4.5,
            gridY: 4.0,
            width: 2.5,
            depth: 4.5,
            espNodeId: '',
          ),
          HouseRoom(
            id: 'banyo',
            name: tr ? 'Banyo' : 'Bathroom',
            kind: HouseRoomKind.bath,
            gridX: 7.0,
            gridY: 4.0,
            width: 3.5,
            depth: 2.0,
            espNodeId: '',
            radiators: const [
              RadiatorNode(id: 'rad_b1', wallSide: RadiatorWallSide.east, offsetRatio: 0.5),
            ],
          ),
          HouseRoom(
            id: 'yatak',
            name: tr ? 'Yatak Odası' : 'Master Bedroom',
            kind: HouseRoomKind.bedroom,
            gridX: 1.0,
            gridY: 5.5,
            width: 3.5,
            depth: 3.5,
            espNodeId: 'esp32_yatak',
            radiators: const [
              RadiatorNode(id: 'rad_y1', wallSide: RadiatorWallSide.south, offsetRatio: 0.5),
            ],
          ),
          HouseRoom(
            id: 'cocuk',
            name: tr ? 'Çocuk Odası' : 'Kids Room',
            kind: HouseRoomKind.kids,
            gridX: 7.0,
            gridY: 6.0,
            width: 3.5,
            depth: 3.0,
            espNodeId: 'esp32_cocuk',
            radiators: const [
              RadiatorNode(id: 'rad_c1', wallSide: RadiatorWallSide.south, offsetRatio: 0.5),
            ],
          ),
        ],
      );

  factory HouseFloorPlan.template3Plus1({bool tr = true}) => HouseFloorPlan(
        templateId: '3+1',
        name: tr ? '3+1 Aile Dairesi' : '3+1 Family Residence',
        referenceRoomId: 'salon',
        rooms: [
          HouseRoom(
            id: 'salon',
            name: tr ? 'Büyük Salon' : 'Main Living',
            kind: HouseRoomKind.living,
            gridX: 0.5,
            gridY: 0.5,
            width: 5.5,
            depth: 4.5,
            espNodeId: 'kombi',
            radiators: const [
              RadiatorNode(id: 'rad_s1', wallSide: RadiatorWallSide.north, offsetRatio: 0.35),
              RadiatorNode(id: 'rad_s2', wallSide: RadiatorWallSide.north, offsetRatio: 0.72),
            ],
          ),
          HouseRoom(
            id: 'mutfak',
            name: tr ? 'Mutfak' : 'Kitchen',
            kind: HouseRoomKind.kitchen,
            gridX: 6.0,
            gridY: 0.5,
            width: 5.0,
            depth: 3.0,
            espNodeId: 'esp32_mutfak',
            isBoilerHub: true,
            radiators: const [
              RadiatorNode(id: 'rad_m1', wallSide: RadiatorWallSide.east, offsetRatio: 0.5),
            ],
          ),
          HouseRoom(
            id: 'hol',
            name: tr ? 'Antre / Hol' : 'Corridor',
            kind: HouseRoomKind.hall,
            gridX: 4.5,
            gridY: 3.5,
            width: 3.0,
            depth: 2.5,
          ),
          HouseRoom(
            id: 'banyo',
            name: tr ? 'Banyo' : 'Bathroom',
            kind: HouseRoomKind.bath,
            gridX: 7.5,
            gridY: 3.5,
            width: 3.5,
            depth: 2.5,
            radiators: const [
              RadiatorNode(id: 'rad_b1', wallSide: RadiatorWallSide.east, offsetRatio: 0.5),
            ],
          ),
          HouseRoom(
            id: 'yatak',
            name: tr ? 'Ebeveyn Odası' : 'Master Suite',
            kind: HouseRoomKind.bedroom,
            gridX: 0.5,
            gridY: 5.0,
            width: 4.0,
            depth: 4.0,
            espNodeId: 'esp32_yatak',
            radiators: const [
              RadiatorNode(id: 'rad_y1', wallSide: RadiatorWallSide.south, offsetRatio: 0.5),
            ],
          ),
          HouseRoom(
            id: 'cocuk1',
            name: tr ? 'Çocuk Odası 1' : 'Kids Room 1',
            kind: HouseRoomKind.kids,
            gridX: 4.5,
            gridY: 6.0,
            width: 3.2,
            depth: 3.0,
            espNodeId: 'esp32_cocuk1',
            radiators: const [
              RadiatorNode(id: 'rad_c1', wallSide: RadiatorWallSide.south, offsetRatio: 0.5),
            ],
          ),
          HouseRoom(
            id: 'cocuk2',
            name: tr ? 'Çalışma / Oda 3' : 'Study / Room 3',
            kind: HouseRoomKind.study,
            gridX: 7.7,
            gridY: 6.0,
            width: 3.3,
            depth: 3.0,
            espNodeId: 'esp32_calisma',
            radiators: const [
              RadiatorNode(id: 'rad_c2', wallSide: RadiatorWallSide.south, offsetRatio: 0.5),
            ],
          ),
        ],
      );

  factory HouseFloorPlan.templateDuplex({bool tr = true}) => HouseFloorPlan(
        templateId: 'duplex',
        name: tr ? 'Dubleks Yaşam Katı' : 'Duplex Living Floor',
        referenceRoomId: 'salon',
        rooms: [
          HouseRoom(
            id: 'salon',
            name: tr ? 'Galeri Salon' : 'Loft Living',
            kind: HouseRoomKind.living,
            gridX: 1.0,
            gridY: 1.0,
            width: 6.0,
            depth: 5.0,
            espNodeId: 'kombi',
            radiators: const [
              RadiatorNode(id: 'rad_s1', wallSide: RadiatorWallSide.north, offsetRatio: 0.3),
              RadiatorNode(id: 'rad_s2', wallSide: RadiatorWallSide.west, offsetRatio: 0.55),
            ],
          ),
          HouseRoom(
            id: 'mutfak',
            name: tr ? 'Ada Mutfak' : 'Island Kitchen',
            kind: HouseRoomKind.kitchen,
            gridX: 7.0,
            gridY: 1.0,
            width: 4.0,
            depth: 4.0,
            espNodeId: 'esp32_mutfak',
            isBoilerHub: true,
            radiators: const [
              RadiatorNode(id: 'rad_m1', wallSide: RadiatorWallSide.east, offsetRatio: 0.5),
            ],
          ),
          HouseRoom(
            id: 'calisma',
            name: tr ? 'Çalışma Odası' : 'Home Office',
            kind: HouseRoomKind.study,
            gridX: 1.0,
            gridY: 6.0,
            width: 3.5,
            depth: 3.0,
            espNodeId: 'esp32_ofis',
            radiators: const [
              RadiatorNode(id: 'rad_o1', wallSide: RadiatorWallSide.south, offsetRatio: 0.5),
            ],
          ),
          HouseRoom(
            id: 'suit',
            name: tr ? 'Üst Süit' : 'Master Suite',
            kind: HouseRoomKind.bedroom,
            gridX: 4.5,
            gridY: 6.0,
            width: 4.5,
            depth: 3.0,
            espNodeId: 'esp32_suit',
            radiators: const [
              RadiatorNode(id: 'rad_su1', wallSide: RadiatorWallSide.south, offsetRatio: 0.5),
            ],
          ),
          HouseRoom(
            id: 'banyo',
            name: tr ? 'Ebeveyn Banyo' : 'Ensuite Bath',
            kind: HouseRoomKind.bath,
            gridX: 9.0,
            gridY: 5.0,
            width: 2.0,
            depth: 4.0,
            radiators: const [
              RadiatorNode(id: 'rad_b1', wallSide: RadiatorWallSide.east, offsetRatio: 0.5),
            ],
          ),
        ],
      );

  factory HouseFloorPlan.defaults({bool tr = true}) =>
      HouseFloorPlan.template2Plus1(tr: tr);

  HouseRoom? findRoom(String id) {
    for (final r in rooms) {
      if (r.id == id) return r;
    }
    return rooms.isEmpty ? null : rooms.first;
  }

  Rect boundingRect() {
    if (rooms.isEmpty) return const Rect.fromLTWH(0, 0, 10, 8);
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;
    for (final r in rooms) {
      minX = math.min(minX, r.gridX);
      minY = math.min(minY, r.gridY);
      maxX = math.max(maxX, r.gridX + r.width);
      maxY = math.max(maxY, r.gridY + r.depth);
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  HouseFloorPlan copyWith({
    String? templateId,
    String? name,
    String? referenceRoomId,
    List<HouseRoom>? rooms,
  }) {
    return HouseFloorPlan(
      templateId: templateId ?? this.templateId,
      name: name ?? this.name,
      referenceRoomId: referenceRoomId ?? this.referenceRoomId,
      rooms: rooms ?? this.rooms,
    );
  }

  Map<String, dynamic> toJson() => {
        'templateId': templateId,
        'name': name,
        'referenceRoomId': referenceRoomId,
        'rooms': rooms.map((r) => r.toJson()).toList(),
      };

  factory HouseFloorPlan.fromJson(Map<String, dynamic> map) {
    final rawRooms = map['rooms'];
    final list = <HouseRoom>[];
    if (rawRooms is List) {
      for (final item in rawRooms) {
        if (item is Map<String, dynamic>) {
          list.add(HouseRoom.fromJson(item));
        } else if (item is Map) {
          list.add(HouseRoom.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    if (list.isEmpty) {
      return HouseFloorPlan.defaults();
    }
    final ref = (map['referenceRoomId'] as String?) ?? list.first.id;
    return HouseFloorPlan(
      templateId: (map['templateId'] as String?) ?? 'custom',
      name: (map['name'] as String?) ?? 'Ev Planı',
      referenceRoomId: list.any((r) => r.id == ref) ? ref : list.first.id,
      rooms: list,
    );
  }

  static RoomEspTelemetry resolveRoomTelemetry({
    required HouseRoom room,
    required Map<String, RoomEspTelemetry> roomTelemetries,
    required double? mainRoomTemp,
    required bool mainEspOnline,
    required String mainEspDeviceId,
    bool boilerHeating = false,
  }) {
    final node = room.espNodeId.trim();
    if (node.isEmpty) {
      return const RoomEspTelemetry.offline('');
    }
    final direct = roomTelemetries[node];
    if (direct != null) return direct;

    final isMainNode = node.toLowerCase() == 'kombi' ||
        node.toLowerCase() == mainEspDeviceId.trim().toLowerCase();
    if (isMainNode && mainEspOnline && mainRoomTemp != null) {
      return RoomEspTelemetry(
        espNodeId: node,
        online: true,
        roomTempC: mainRoomTemp,
        radiatorHeating: boilerHeating,
      );
    }
    return RoomEspTelemetry.offline(node);
  }
}

class RoomEspTelemetry {
  final String espNodeId;
  final bool online;
  final double? roomTempC;
  final double? humidityPercent;
  final double? radiatorTempC;
  final bool? radiatorHeating;
  final int? wifiRssiDbm;
  final String lastSeenLabel;

  const RoomEspTelemetry({
    required this.espNodeId,
    this.online = false,
    this.roomTempC,
    this.humidityPercent,
    this.radiatorTempC,
    this.radiatorHeating,
    this.wifiRssiDbm,
    this.lastSeenLabel = '',
  });

  const RoomEspTelemetry.offline(this.espNodeId)
      : online = false,
        roomTempC = null,
        humidityPercent = null,
        radiatorTempC = null,
        radiatorHeating = null,
        wifiRssiDbm = null,
        lastSeenLabel = '';

  int get wifiBars {
    final rssi = wifiRssiDbm;
    if (!online || rssi == null) return 0;
    if (rssi >= -55) return 4;
    if (rssi >= -67) return 3;
    if (rssi >= -78) return 2;
    return 1;
  }

  String wifiQualityLabel({bool tr = true}) {
    final rssi = wifiRssiDbm;
    if (!online || rssi == null) return '--';
    if (rssi >= -55) return tr ? '$rssi dBm · Mükemmel' : '$rssi dBm · Excellent';
    if (rssi >= -67) return tr ? '$rssi dBm · İyi' : '$rssi dBm · Good';
    if (rssi >= -78) return tr ? '$rssi dBm · Orta' : '$rssi dBm · Fair';
    return tr ? '$rssi dBm · Zayıf' : '$rssi dBm · Weak';
  }
}
