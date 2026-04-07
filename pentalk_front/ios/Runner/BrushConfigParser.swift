import UIKit

enum BrushConfigParser {
    static func parse(_ arguments: Any?) -> DrawingPlatformView.BrushConfig {
        let args = arguments as? [String: Any]
        let tool = args?["tool"] as? String ?? "pen"
        let colorValue: UInt32 = (args?["color"] as? NSNumber)?.uint32Value ?? 0xFF000000
        let size = (args?["size"] as? NSNumber)?.doubleValue ?? 6.0
        let eraserSize = (args?["eraserSize"] as? NSNumber)?.doubleValue ?? 24.0
        let color = UIColor(argb: colorValue)
        return DrawingPlatformView.BrushConfig(
            tool: tool,
            color: color,
            size: CGFloat(size),
            eraserSize: CGFloat(eraserSize)
        )
    }
}
