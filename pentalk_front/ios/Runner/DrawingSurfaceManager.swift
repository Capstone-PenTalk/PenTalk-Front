final class DrawingSurfaceManager {
    static let shared = DrawingSurfaceManager()
    weak var surface: DrawingPlatformView?

    func applyBrushConfig(_ config: DrawingPlatformView.BrushConfig) {
        surface?.applyBrushConfig(config)
    }
}
