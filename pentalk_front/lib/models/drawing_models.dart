import 'package:flutter/material.dart';

/// ===============================
/// 판서 이벤트 타입
/// ===============================
enum DrawEventType {
  drawStart('ds'),
  drawMove('dm'),
  drawEnd('de'),
  undo('un'),
  eraser('er');

  final String code;
  const DrawEventType(this.code);

  static DrawEventType fromCode(String code) {
    return DrawEventType.values.firstWhere(
          (type) => type.code == code,
      orElse: () => DrawEventType.drawMove,
    );
  }
}

/// ===============================
/// 좌표 포인트 (정규화된 값 0.0 ~ 1.0)
/// ===============================
class DrawPoint {
  final double x; // 0.0 ~ 1.0
  final double y; // 0.0 ~ 1.0
  final double? pressure; // 필압 (선택)

  DrawPoint({
    required this.x,
    required this.y,
    this.pressure,
  });

  /// JSON → DrawPoint (정규화 강제 + 안전 처리)
  factory DrawPoint.fromJson(Map<String, dynamic> json) {
    double clamp(double v) => v.clamp(0.0, 1.0);

    return DrawPoint(
      x: clamp((json['x'] as num).toDouble()),
      y: clamp((json['y'] as num).toDouble()),
      pressure: json['p'] != null ? (json['p'] as num).toDouble() : null,
    );
  }

  /// DrawPoint → JSON (null 값은 아예 안 보냄)
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> map = {
      'x': x,
      'y': y,
    };

    if (pressure != null) {
      map['p'] = pressure;
    }

    return map;
  }

  /// 정규화 → 픽셀 좌표
  Offset toPixelOffset(Size canvasSize) {
    return Offset(
      x * canvasSize.width,
      y * canvasSize.height,
    );
  }

  /// 픽셀 좌표 → 정규화
  static DrawPoint fromPixelOffset(Offset offset, Size canvasSize) {
    return DrawPoint(
      x: (offset.dx / canvasSize.width).clamp(0.0, 1.0),
      y: (offset.dy / canvasSize.height).clamp(0.0, 1.0),
    );
  }
}

/// ===============================
/// Stroke 데이터
/// ===============================
class Stroke {
  final int strokeId; // clientId << 32 | localCounter
  final Color color;
  final double width;
  final List<DrawPoint> points;
  final List<DrawPoint>? refinedPoints; // draw_end 보정 좌표

  Stroke({
    required this.strokeId,
    required this.color,
    required this.width,
    required this.points,
    this.refinedPoints,
  });

  Stroke copyWith({
    int? strokeId,
    Color? color,
    double? width,
    List<DrawPoint>? points,
    List<DrawPoint>? refinedPoints,
  }) {
    return Stroke(
      strokeId: strokeId ?? this.strokeId,
      color: color ?? this.color,
      width: width ?? this.width,
      points: points ?? this.points,
      refinedPoints: refinedPoints ?? this.refinedPoints,
    );
  }

  /// 보정 좌표 적용
  Stroke withRefinedPoints(List<DrawPoint> refined) {
    return copyWith(refinedPoints: refined);
  }

  /// 실제 렌더링용 좌표
  List<DrawPoint> get displayPoints => refinedPoints ?? points;
}

/// ===============================
/// 판서 이벤트
/// ===============================
class DrawEvent {
  final DrawEventType eventType;
  final int strokeId;
  final DrawPoint? point;
  final Color? color;
  final double? width;
  final List<DrawPoint>? points; // draw_end
  final int? tick;

  DrawEvent({
    required this.eventType,
    required this.strokeId,
    this.point,
    this.color,
    this.width,
    this.points,
    this.tick,
  });

  /// JSON → DrawEvent
  factory DrawEvent.fromJson(Map<String, dynamic> json) {
    final eventType = DrawEventType.fromCode(json['e'] as String);
    final strokeId = json['sId'] as int;

    // draw_start
    if (eventType == DrawEventType.drawStart) {
      return DrawEvent(
        eventType: eventType,
        strokeId: strokeId,
        point: DrawPoint.fromJson(json),
        color: _parseColor(json['c'] as String?),
        width: json['w'] != null ? (json['w'] as num).toDouble() : 2.5,
      );
    }

    // draw_move
    if (eventType == DrawEventType.drawMove) {
      return DrawEvent(
        eventType: eventType,
        strokeId: strokeId,
        point: DrawPoint.fromJson(json),
        tick: json['t'] as int?,
      );
    }

    // draw_end
    if (eventType == DrawEventType.drawEnd) {
      final ptsList = json['pts'] as List<dynamic>?;

      return DrawEvent(
        eventType: eventType,
        strokeId: strokeId,
        points: ptsList
            ?.map((pt) => DrawPoint.fromJson(pt as Map<String, dynamic>))
            .toList(),
      );
    }

    // undo / eraser
    return DrawEvent(
      eventType: eventType,
      strokeId: strokeId,
    );
  }

  /// DrawEvent → JSON (nullable 값 완전 안전)
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> json = {
      'e': eventType.code,
      'sId': strokeId,
    };

    if (point != null) {
      json['x'] = point!.x;
      json['y'] = point!.y;
      if (point!.pressure != null) {
        json['p'] = point!.pressure;
      }
    }

    if (color != null) {
      json['c'] = _colorToHex(color!);
    }

    if (width != null) {
      json['w'] = width;
    }

    if (points != null) {
      json['pts'] = points!.map((p) => p.toJson()).toList();
    }

    if (tick != null) {
      json['t'] = tick;
    }

    return json;
  }

  /// ===============================
  /// Color Utils
  /// ===============================
  static Color _parseColor(String? hexColor) {
    if (hexColor == null) return Colors.black;

    final hex = hexColor.replaceAll('#', '');
    if (hex.length == 6) {
      return Color(int.parse('FF$hex', radix: 16));
    }
    return Colors.black;
  }

  static String _colorToHex(Color color) {
    return '#${color.value.toRadixString(16).substring(2).toUpperCase()}';
  }
}
