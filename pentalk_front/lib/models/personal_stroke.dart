import 'package:flutter/material.dart';
import 'drawing_models.dart';

/// ===============================
/// 개인 필기용 Stroke 모델 (로컬 DB 저장)
/// ===============================
class PersonalStroke {
  final int? id; // SQLite auto-increment ID
  final String pageId; // materialTitle
  final int strokeId; // 고유 stroke ID
  final Color color;
  final double width;
  final List<DrawPoint> points;
  final List<DrawPoint>? refinedPoints;
  final DateTime timestamp; // 생성 시간

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

  /// Stroke → PersonalStroke 변환
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

  /// PersonalStroke → Stroke 변환
  Stroke toStroke() {
    return Stroke(
      strokeId: strokeId,
      color: color,
      width: width,
      points: points,
      refinedPoints: refinedPoints,
    );
  }

  /// JSON → PersonalStroke (SQLite 저장용)
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

  /// PersonalStroke → JSON (SQLite 저장용)
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

  /// SQLite Row → PersonalStroke
  factory PersonalStroke.fromMap(Map<String, dynamic> map) {
    // SQLite에서는 points를 JSON 문자열로 저장했다가 파싱
    final pointsData = map['points_json'] as String;
    final refinedPointsData = map['refined_points_json'] as String?;

    return PersonalStroke(
      id: map['id'] as int,
      pageId: map['page_id'] as String,
      strokeId: map['stroke_id'] as int,
      color: Color(map['color'] as int),
      width: (map['width'] as num).toDouble(),
      points: _parsePoints(pointsData),
      refinedPoints: refinedPointsData != null ? _parsePoints(refinedPointsData) : null,
      timestamp: DateTime.parse(map['timestamp'] as String),
    );
  }

  /// PersonalStroke → SQLite Row
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'page_id': pageId,
      'stroke_id': strokeId,
      'color': color.value,
      'width': width,
      'points_json': _pointsToJson(points),
      'refined_points_json': refinedPoints != null ? _pointsToJson(refinedPoints!) : null,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  /// DrawPoint 리스트 → JSON 문자열
  static String _pointsToJson(List<DrawPoint> points) {
    return '[${points.map((p) => '{"x":${p.x},"y":${p.y}${p.pressure != null ? ',"p":${p.pressure}' : ''}}').join(',')}]';
  }

  /// JSON 문자열 → DrawPoint 리스트
  static List<DrawPoint> _parsePoints(String json) {
    // 간단한 JSON 파싱 (dart:convert 사용하지 않고)
    final cleaned = json.replaceAll('[', '').replaceAll(']', '');
    if (cleaned.isEmpty) return [];

    final List<DrawPoint> points = [];
    final regex = RegExp(r'\{([^}]+)\}');
    final matches = regex.allMatches(cleaned);

    for (final match in matches) {
      final content = match.group(1)!;
      final parts = content.split(',');

      double? x, y, p;
      for (final part in parts) {
        final kv = part.split(':');
        final key = kv[0].replaceAll('"', '').trim();
        final value = double.tryParse(kv[1].trim());

        if (key == 'x') x = value;
        if (key == 'y') y = value;
        if (key == 'p') p = value;
      }

      if (x != null && y != null) {
        points.add(DrawPoint(x: x, y: y, pressure: p));
      }
    }

    return points;
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