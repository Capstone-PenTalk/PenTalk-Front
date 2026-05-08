import 'dart:convert';
import 'package:flutter/material.dart';
import 'drawing_models.dart';

/// ===============================
/// 개인 필기용 Stroke 모델 (로컬 DB 저장)
/// ===============================
class PersonalStroke {
  final int? id;
  final String pageId; // materialTitle
  final int strokeId;
  final Color color;
  final double width;
  final List<DrawPoint> points;
  final List<DrawPoint>? refinedPoints;
  final DateTime timestamp;

  PersonalStroke({
    this.id,
    required this.pageId,
    required this.strokeId,
    required this.color,
    required this.width,
    required this.points,
    this.refinedPoints,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory PersonalStroke.fromStroke(
      Stroke stroke,
      String pageId, {
        DateTime? timestamp,
      }) {
    return PersonalStroke(
      pageId: pageId,
      strokeId: stroke.strokeId,
      color: stroke.color,
      width: stroke.width,
      points: stroke.points,
      refinedPoints: stroke.refinedPoints,
      timestamp: timestamp,
    );
  }

  Stroke toStroke() {
    final safeRefinedPoints =
        refinedPoints != null && refinedPoints!.isNotEmpty
            ? refinedPoints
            : null;
    return Stroke(
      strokeId: strokeId,
      color: color,
      width: width,
      points: points,
      refinedPoints: safeRefinedPoints,
    );
  }

  /// ===============================
  /// 서버 export용 JSON 변환
  /// POST /export/pdf 요청 형식
  /// ===============================
  Map<String, dynamic> toServerJson(int pageNumber) {
    // refinedPoints 우선 사용. DrawPoint는 이미 0~1 정규화 좌표다.
    final exportPoints =
        refinedPoints != null && refinedPoints!.isNotEmpty
            ? refinedPoints!
            : points;

    return {
      'pageNumber': pageNumber,
      'c': _toArgbHex(color),
      'w': width,
      'points': exportPoints
          .map((p) => {
        'x': p.x,
        'y': p.y,
        if (p.pressure != null) 'p': p.pressure,
      })
          .toList(),
    };
  }

  static String _toArgbHex(Color color) {
    final argb = color.toARGB32().toRadixString(16).padLeft(8, '0');
    return '#${argb.toUpperCase()}';
  }

  factory PersonalStroke.fromJson(Map<String, dynamic> json) {
    return PersonalStroke(
      id: json['id'] as int?,
      pageId: json['pageId'] as String,
      strokeId: json['strokeId'] as int,
      color: Color(json['color'] as int),
      width: (json['width'] as num).toDouble(),
      points: (json['points'] as List<dynamic>)
          .map((p) => DrawPoint.fromJson(p as Map<String, dynamic>))
          .toList(),
      refinedPoints: json['refinedPoints'] != null
          ? (json['refinedPoints'] as List<dynamic>)
          .map((p) => DrawPoint.fromJson(p as Map<String, dynamic>))
          .toList()
          : null,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'pageId': pageId,
      'strokeId': strokeId,
      'color': color.value,
      'width': width,
      'points': points.map((p) => p.toJson()).toList(),
      if (refinedPoints != null)
        'refinedPoints': refinedPoints!.map((p) => p.toJson()).toList(),
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory PersonalStroke.fromMap(Map<String, dynamic> map) {
    final pointsData = map['points_json'] as String;
    final refinedPointsData = map['refined_points_json'] as String?;

    return PersonalStroke(
      id: map['id'] as int,
      pageId: map['page_id'] as String,
      strokeId: map['stroke_id'] as int,
      color: Color(map['color'] as int),
      width: (map['width'] as num).toDouble(),
      points: _parsePoints(pointsData),
      refinedPoints:
      refinedPointsData != null ? _parsePoints(refinedPointsData) : null,
      timestamp: DateTime.parse(map['timestamp'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'page_id': pageId,
      'stroke_id': strokeId,
      'color': color.value,
      'width': width,
      'points_json': _pointsToJson(points),
      'refined_points_json':
      refinedPoints != null ? _pointsToJson(refinedPoints!) : null,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  static String _pointsToJson(List<DrawPoint> points) {
    return jsonEncode(points
        .map((p) => {
      'x': p.x,
      'y': p.y,
      if (p.pressure != null) 'p': p.pressure,
    })
        .toList());
  }

  static List<DrawPoint> _parsePoints(String json) {
    final list = jsonDecode(json) as List<dynamic>;
    return list
        .map((p) => DrawPoint(
      x: (p['x'] as num).toDouble(),
      y: (p['y'] as num).toDouble(),
      pressure:
      p['p'] != null ? (p['p'] as num).toDouble() : null,
    ))
        .toList();
  }

  PersonalStroke copyWith({
    int? id,
    String? pageId,
    int? strokeId,
    Color? color,
    double? width,
    List<DrawPoint>? points,
    List<DrawPoint>? refinedPoints,
    DateTime? timestamp,
  }) {
    return PersonalStroke(
      id: id ?? this.id,
      pageId: pageId ?? this.pageId,
      strokeId: strokeId ?? this.strokeId,
      color: color ?? this.color,
      width: width ?? this.width,
      points: points ?? this.points,
      refinedPoints: refinedPoints ?? this.refinedPoints,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}
