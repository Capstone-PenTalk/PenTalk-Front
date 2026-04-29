final class DrawingSurfaceManager {
    static let shared = DrawingSurfaceManager()
    weak var surface: DrawingPlatformView?

    func applyBrushConfig(_ config: DrawingPlatformView.BrushConfig) {
        surface?.applyBrushConfig(config)
    }

    func exportDrawingSnapshot() -> [[String: Any]] {
        surface?.exportDrawingSnapshot() ?? []
    }

    func undoLastStroke() {
        surface?.undoLastStroke()
    }

    func clearDrawing() {
        surface?.clearDrawing()
    }

    func replaceDrawingSnapshot(_ snapshot: [[String: Any]]) {
        surface?.replaceDrawingSnapshot(snapshot)
    }
}
