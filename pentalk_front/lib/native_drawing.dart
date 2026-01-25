import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class BrushConfig {
  const BrushConfig({
    required this.tool,
    required this.color,
    required this.size,
    required this.eraserSize,
  });

  final String tool;
  final int color;
  final double size;
  final double eraserSize;

  BrushConfig copyWith({
    String? tool,
    int? color,
    double? size,
    double? eraserSize,
  }) {
    return BrushConfig(
      tool: tool ?? this.tool,
      color: color ?? this.color,
      size: size ?? this.size,
      eraserSize: eraserSize ?? this.eraserSize,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'tool': tool,
      'color': color,
      'size': size,
      'eraserSize': eraserSize,
    };
  }
}

class NativeDrawingBridge {
  static const MethodChannel _channel = MethodChannel('pentalk/native_drawing');
  static bool _initialized = false;

  static final ValueNotifier<BrushConfig> currentBrush = ValueNotifier(
    const BrushConfig(
      tool: 'pen',
      color: 0xFF111111,
      size: 6,
      eraserSize: 24,
    ),
  );

  static void init() {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  static Future<void> open(BrushConfig config) async {
    await _channel.invokeMethod('open', config.toMap());
  }

  static Future<void> setBrush(BrushConfig config) async {
    await _channel.invokeMethod('setBrush', config.toMap());
  }

  static Future<void> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'toolChanged':
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final tool = args['tool'] as String?;
        final color = args['color'] as int?;
        final size = (args['size'] as num?)?.toDouble();
        final eraserSize = (args['eraserSize'] as num?)?.toDouble();
        if (tool != null && tool.isNotEmpty) {
          currentBrush.value = currentBrush.value.copyWith(
            tool: tool,
            color: color,
            size: size,
            eraserSize: eraserSize,
          );
        }
        break;
    }
  }
}
