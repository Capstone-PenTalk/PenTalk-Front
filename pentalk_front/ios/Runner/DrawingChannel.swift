import Flutter

enum DrawingChannel {
    static let name = "pentalk/drawing"
    static var channel: FlutterMethodChannel?

    static func notifyToolChanged(
        tool: String,
        source: String,
        color: Int? = nil,
        size: CGFloat? = nil,
        eraserSize: CGFloat? = nil
    ) {
        var payload: [String: Any] = [
            "tool": tool,
            "source": source,
        ]
        if let color = color { payload["color"] = color }
        if let size = size { payload["size"] = size }
        if let eraserSize = eraserSize { payload["eraserSize"] = eraserSize }
        channel?.invokeMethod("toolChanged", arguments: payload)
    }

    static func notifyDrawEvent(_ payload: [String: Any]) {
        channel?.invokeMethod("onDrawEvent", arguments: payload)
    }
}
