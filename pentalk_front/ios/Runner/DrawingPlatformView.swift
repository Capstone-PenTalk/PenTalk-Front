import Flutter
import PencilKit
import UIKit

final class DrawingPlatformView: NSObject, FlutterPlatformView, PKToolPickerObserver {
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
    private var toolPicker: PKToolPicker?
    private var currentConfig: BrushConfig

    init(frame: CGRect, viewId: Int64, arguments: Any?) {
        self.currentConfig = BrushConfigParser.parse(arguments)
        super.init()
        DrawingSurfaceManager.shared.surface = self

        containerView.backgroundColor = .white
        containerView.clipsToBounds = false
        canvasView.translatesAutoresizingMaskIntoConstraints = false
        canvasView.backgroundColor = .white
        if #available(iOS 14.0, *) {
            canvasView.drawingPolicy = .anyInput
        }
        containerView.addSubview(canvasView)

        NSLayoutConstraint.activate([
            canvasView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            canvasView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            canvasView.topAnchor.constraint(equalTo: containerView.topAnchor),
            canvasView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])

        containerView.onDidMoveToWindow = { [weak self] in
            self?.ensureToolPickerVisible()
        }
        containerView.onLayout = { [weak self] in
            self?.ensureToolPickerVisible()
        }

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

    private func ensureToolPickerVisible() {
        guard let window = containerView.window else { return }
        if toolPicker == nil {
            let picker = PKToolPicker.shared(for: window)
            toolPicker = picker
            picker?.addObserver(canvasView)
            picker?.addObserver(self)
        }
        toolPicker?.setVisible(true, forFirstResponder: canvasView)
        canvasView.becomeFirstResponder()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }
            self.toolPicker?.setVisible(true, forFirstResponder: self.canvasView)
            self.canvasView.becomeFirstResponder()
        }
    }

    func toolPickerSelectedToolDidChange(_ toolPicker: PKToolPicker) {
        if let inkingTool = toolPicker.selectedTool as? PKInkingTool {
            currentConfig = BrushConfig(
                tool: "pen",
                color: inkingTool.color,
                size: inkingTool.width,
                eraserSize: currentConfig.eraserSize
            )
            DrawingChannel.notifyToolChanged(
                tool: "pen",
                source: "ui",
                color: inkingTool.color.argbInt(),
                size: inkingTool.width,
                eraserSize: currentConfig.eraserSize
            )
            return
        }

        currentConfig = BrushConfig(
            tool: "eraser",
            color: currentConfig.color,
            size: currentConfig.size,
            eraserSize: currentConfig.eraserSize
        )
        DrawingChannel.notifyToolChanged(
            tool: "eraser",
            source: "ui",
            color: currentConfig.color.argbInt(),
            size: currentConfig.size,
            eraserSize: currentConfig.eraserSize
        )
    }
}
