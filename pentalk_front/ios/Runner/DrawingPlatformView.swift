import Flutter
import PencilKit
import UIKit

final class DrawingPlatformView: NSObject, FlutterPlatformView, PKCanvasViewDelegate {
    struct BrushConfig {
        let tool: String
        let color: UIColor
        let size: CGFloat
        let eraserSize: CGFloat
    }

    private final class ContainerView: UIView {
        var onDidMoveToWindow: (() -> Void)?
        var onLayout: (() -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            onDidMoveToWindow?()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            onLayout?()
        }
    }

    private let containerView = ContainerView()
    private let canvasView = PKCanvasView(frame: .zero)
    private var currentConfig: BrushConfig
    private var activeStrokeId: Int?
    private var activePoints: [[String: Double]] = []
    private var lastPointCount: Int = 0
    private var isDrawing: Bool = false

    init(frame: CGRect, viewId: Int64, arguments: Any?) {
        self.currentConfig = BrushConfigParser.parse(arguments)
        super.init()
        DrawingSurfaceManager.shared.surface = self

        containerView.backgroundColor = .clear
        containerView.isOpaque = false
        containerView.clipsToBounds = false
        canvasView.translatesAutoresizingMaskIntoConstraints = false
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        if #available(iOS 14.0, *) {
            if UIDevice.current.userInterfaceIdiom == .pad {
                canvasView.drawingPolicy = .pencilOnly
            } else {
                canvasView.drawingPolicy = .anyInput
            }
        }
        canvasView.delegate = self
        containerView.addSubview(canvasView)

        NSLayoutConstraint.activate([
            canvasView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            canvasView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            canvasView.topAnchor.constraint(equalTo: containerView.topAnchor),
            canvasView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])

        applyBrushConfig(currentConfig)
    }

    func view() -> UIView {
        containerView
    }

    func applyBrushConfig(_ config: BrushConfig) {
        currentConfig = config
        switch config.tool.lowercased() {
        case "eraser":
            canvasView.tool = PKEraserTool(.vector)
        default:
            canvasView.tool = PKInkingTool(.pen, color: config.color, width: config.size)
        }
    }

    func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
        isDrawing = true
        activeStrokeId = Int(Date().timeIntervalSince1970 * 1000)
        activePoints.removeAll()
        lastPointCount = 0
    }

    func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
        appendNewPoints(from: canvasView)
        guard let strokeId = activeStrokeId else { return }
        let payload: [String: Any] = [
            "e": "de",
            "sId": strokeId,
            "pts": activePoints,
        ]
        DrawingChannel.notifyDrawEvent(payload)
        activeStrokeId = nil
        activePoints.removeAll()
        lastPointCount = 0
        isDrawing = false
    }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        appendNewPoints(from: canvasView)
    }

    private func appendNewPoints(from canvasView: PKCanvasView) {
        if #available(iOS 14.0, *) {
            guard isDrawing, let stroke = canvasView.drawing.strokes.last else { return }
            let path = stroke.path
            let count = path.count
            if count == 0 { return }

            if activeStrokeId == nil {
                activeStrokeId = Int(Date().timeIntervalSince1970 * 1000)
            }
            if lastPointCount == 0 {
                let first = path[0]
                let normalized = DrawingMetricsStore.normalize(point: first.location)
                let payload: [String: Any] = [
                    "e": "ds",
                    "sId": activeStrokeId as Any,
                    "x": normalized.x,
                    "y": normalized.y,
                    "c": currentConfig.color.hexRGB(),
                    "w": currentConfig.size,
                ]
                DrawingChannel.notifyDrawEvent(payload)
            }

            if count > lastPointCount {
                for index in lastPointCount..<count {
                    let point = path[index].location
                    let normalized = DrawingMetricsStore.normalize(point: point)
                    activePoints.append([
                        "x": Double(normalized.x),
                        "y": Double(normalized.y),
                    ])
                    if index == 0 { continue }
                    let payload: [String: Any] = [
                        "e": "dm",
                        "sId": activeStrokeId as Any,
                        "x": normalized.x,
                        "y": normalized.y,
                    ]
                    DrawingChannel.notifyDrawEvent(payload)
                }
                lastPointCount = count
            }
        }
    }
}
