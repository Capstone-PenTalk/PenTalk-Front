import CoreGraphics

enum DrawingMetricsStore {
    struct Metrics {
        let renderWidth: CGFloat
        let renderHeight: CGFloat
        let pdfWidth: CGFloat
        let pdfHeight: CGFloat
    }

    static var metrics: Metrics?

    static func update(renderWidth: CGFloat, renderHeight: CGFloat, pdfWidth: CGFloat, pdfHeight: CGFloat) {
        metrics = Metrics(
            renderWidth: renderWidth,
            renderHeight: renderHeight,
            pdfWidth: pdfWidth,
            pdfHeight: pdfHeight
        )
    }

    static func normalize(point: CGPoint) -> CGPoint {
        guard let metrics, metrics.renderWidth > 0, metrics.renderHeight > 0 else {
            return point
        }
        let nx = max(0, min(1, point.x / metrics.renderWidth))
        let ny = max(0, min(1, point.y / metrics.renderHeight))
        return CGPoint(x: nx, y: ny)
    }
}
