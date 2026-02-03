import 'dart:async';
import 'dart:math' as math;

class DrawPoint {
  const DrawPoint({
    required this.x,
    required this.y,
    this.pressure,
    this.tick,
  });

  final double x;
  final double y;
  final double? pressure;
  final int? tick;

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'x': x,
      'y': y,
    };
    if (pressure != null) map['p'] = pressure;
    if (tick != null) map['t'] = tick;
    return map;
  }
}

class DrawStreamScheduler {
  DrawStreamScheduler({
    required this.sender,
    this.sampleInterval = const Duration(milliseconds: 16),
    this.sendInterval = const Duration(milliseconds: 32),
    this.distanceThreshold = 0.5,
  });

  final Future<void> Function(Map<String, dynamic> payload) sender;
  final Duration sampleInterval;
  final Duration sendInterval;
  final double distanceThreshold;

  Timer? _sampleTimer;
  Timer? _sendTimer;
  int? _strokeId;
  String? _colorHex;
  double? _width;

  DrawPoint? _latestPoint;
  bool _hasNewPoint = false;
  DrawPoint? _lastSampled;
  final List<DrawPoint> _pending = [];
  final List<DrawPoint> _allPoints = [];

  void startStroke({
    required int strokeId,
    required double x,
    required double y,
    required String colorHex,
    required double width,
  }) {
    _strokeId = strokeId;
    _colorHex = colorHex;
    _width = width;
    _latestPoint = DrawPoint(x: x, y: y);
    _hasNewPoint = true;
    _lastSampled = null;
    _pending.clear();
    _allPoints.clear();
    _allPoints.add(_latestPoint!);

    _startTimers();
    sender({
      'e': 'ds',
      'sId': strokeId,
      'x': x,
      'y': y,
      'c': colorHex,
      'w': width,
    });
  }

  void addPoint({
    required double x,
    required double y,
    double? pressure,
    int? tick,
  }) {
    if (_strokeId == null) return;
    final point = DrawPoint(x: x, y: y, pressure: pressure, tick: tick);
    _latestPoint = point;
    _hasNewPoint = true;
    _allPoints.add(point);
  }

  void endStroke({List<DrawPoint>? controlPoints}) {
    final strokeId = _strokeId;
    if (strokeId == null) return;
    _flushPending(force: true);
    _stopTimers();

    final points = (controlPoints != null && controlPoints.isNotEmpty)
        ? controlPoints
        : _allPoints;
    sender({
      'e': 'de',
      'sId': strokeId,
      'pts': points.map((p) => p.toMap()).toList(),
    });

    _strokeId = null;
    _colorHex = null;
    _width = null;
    _latestPoint = null;
    _hasNewPoint = false;
    _lastSampled = null;
    _pending.clear();
    _allPoints.clear();
  }

  void dispose() {
    _stopTimers();
  }

  void _startTimers() {
    _sampleTimer ??= Timer.periodic(sampleInterval, (_) => _samplePoint());
    _sendTimer ??= Timer.periodic(sendInterval, (_) => _flushPending());
  }

  void _stopTimers() {
    _sampleTimer?.cancel();
    _sampleTimer = null;
    _sendTimer?.cancel();
    _sendTimer = null;
  }

  void _samplePoint() {
    if (!_hasNewPoint || _latestPoint == null) return;
    final point = _latestPoint!;
    if (_lastSampled == null ||
        _distance(_lastSampled!, point) >= distanceThreshold) {
      _pending.add(point);
      _lastSampled = point;
    }
    _hasNewPoint = false;
  }

  void _flushPending({bool force = false}) {
    if (_strokeId == null) return;
    if (_pending.isEmpty && !force) return;
    if (_pending.isEmpty) return;
    final strokeId = _strokeId!;
    final payload = <String, dynamic>{
      'e': 'dm',
      'sId': strokeId,
      'pts': _pending.map((p) => p.toMap()).toList(),
    };
    _pending.clear();
    sender(payload);
  }

  double _distance(DrawPoint a, DrawPoint b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
  }
}

class ColorHex {
  static String fromArgbInt(int argb) {
    final r = (argb >> 16) & 0xFF;
    final g = (argb >> 8) & 0xFF;
    final b = argb & 0xFF;
    return '#'
        '${r.toRadixString(16).padLeft(2, '0').toUpperCase()}'
        '${g.toRadixString(16).padLeft(2, '0').toUpperCase()}'
        '${b.toRadixString(16).padLeft(2, '0').toUpperCase()}';
  }
}
