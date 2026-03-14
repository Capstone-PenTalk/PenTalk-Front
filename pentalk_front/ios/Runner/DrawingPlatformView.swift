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
    private let toolbarContainer = UIView(frame: .zero)
    private let toolControl = UISegmentedControl(items: ["Pen", "Eraser"])
    private let colorRow = UIStackView(frame: .zero)
    private let sizeSlider = UISlider(frame: .zero)
    private let sizeValueLabel = UILabel(frame: .zero)
    private let colorOptions: [UIColor] = [
        UIColor.black,
        UIColor.systemBlue,
        UIColor.systemRed,
        UIColor.systemGreen,
        UIColor.systemOrange,
        UIColor.systemPurple,
    ]
    private var colorButtons: [UIButton] = []
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

        setupToolbar()
        if currentConfig.tool.lowercased() == "pen",
           currentConfig.color.isEqual(UIColor.white) {
            currentConfig = BrushConfig(
                tool: currentConfig.tool,
                color: .black,
                size: currentConfig.size,
                eraserSize: currentConfig.eraserSize
            )
        }
        applyBrushConfig(currentConfig)
    }

    func view() -> UIView {
        containerView
    }

    func exportDrawingSnapshot() -> [[String: Any]] {
        if #available(iOS 14.0, *) {
            return canvasView.drawing.strokes.enumerated().compactMap { index, stroke in
                let path = stroke.path
                guard path.count > 0 else { return nil }

                let points: [[String: Double]] = (0..<path.count).map { pointIndex in
                    let point = path[pointIndex]
                    let normalized = DrawingMetricsStore.normalize(point: point.location)
                    return [
                        "x": Double(normalized.x),
                        "y": Double(normalized.y),
                        "p": Double(point.force),
                    ]
                }

                guard !points.isEmpty else { return nil }

                return [
                    "sId": Int(Date().timeIntervalSince1970 * 1000) + index,
                    "c": stroke.ink.color.hexRGB(),
                    "w": Double(stroke.ink.width),
                    "pts": points,
                ]
            }
        }
        return []
    }

    func applyBrushConfig(_ config: BrushConfig) {
        currentConfig = config
        switch config.tool.lowercased() {
        case "eraser":
            canvasView.tool = PKEraserTool(.vector)
        default:
            canvasView.tool = PKInkingTool(.pen, color: config.color, width: config.size)
        }
        syncToolbar()
    }

    private func setupToolbar() {
        toolbarContainer.translatesAutoresizingMaskIntoConstraints = false
        toolbarContainer.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        toolbarContainer.layer.cornerRadius = 16
        toolbarContainer.clipsToBounds = true
        containerView.addSubview(toolbarContainer)

        toolControl.translatesAutoresizingMaskIntoConstraints = false
        toolControl.selectedSegmentIndex = 0
        toolControl.addTarget(self, action: #selector(toolChanged), for: .valueChanged)

        colorRow.translatesAutoresizingMaskIntoConstraints = false
        colorRow.axis = .horizontal
        colorRow.alignment = .center
        colorRow.distribution = .fillEqually
        colorRow.spacing = 8

        colorButtons = colorOptions.enumerated().map { index, color in
            let button = UIButton(type: .system)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.backgroundColor = color
            button.layer.cornerRadius = 12
            button.layer.borderColor = UIColor.white.cgColor
            button.layer.borderWidth = 0
            button.tag = index
            button.addTarget(self, action: #selector(colorChanged(_:)), for: .touchUpInside)
            NSLayoutConstraint.activate([
                button.heightAnchor.constraint(equalToConstant: 24),
            ])
            return button
        }
        colorButtons.forEach { colorRow.addArrangedSubview($0) }

        sizeSlider.translatesAutoresizingMaskIntoConstraints = false
        sizeSlider.minimumValue = 1
        sizeSlider.maximumValue = 24
        sizeSlider.addTarget(self, action: #selector(sizeChanged), for: .valueChanged)

        sizeValueLabel.translatesAutoresizingMaskIntoConstraints = false
        sizeValueLabel.textColor = .white
        sizeValueLabel.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        sizeValueLabel.textAlignment = .right

        let sliderRow = UIStackView(arrangedSubviews: [sizeSlider, sizeValueLabel])
        sliderRow.translatesAutoresizingMaskIntoConstraints = false
        sliderRow.axis = .horizontal
        sliderRow.alignment = .center
        sliderRow.spacing = 8

        let toolbarStack = UIStackView(arrangedSubviews: [toolControl, colorRow, sliderRow])
        toolbarStack.translatesAutoresizingMaskIntoConstraints = false
        toolbarStack.axis = .vertical
        toolbarStack.spacing = 10
        toolbarContainer.addSubview(toolbarStack)

        NSLayoutConstraint.activate([
            toolbarContainer.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            toolbarContainer.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            toolbarContainer.bottomAnchor.constraint(equalTo: containerView.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            toolbarStack.leadingAnchor.constraint(equalTo: toolbarContainer.leadingAnchor, constant: 12),
            toolbarStack.trailingAnchor.constraint(equalTo: toolbarContainer.trailingAnchor, constant: -12),
            toolbarStack.topAnchor.constraint(equalTo: toolbarContainer.topAnchor, constant: 12),
            toolbarStack.bottomAnchor.constraint(equalTo: toolbarContainer.bottomAnchor, constant: -12),
            sizeValueLabel.widthAnchor.constraint(equalToConstant: 44),
        ])
    }

    private func syncToolbar() {
        let isEraser = currentConfig.tool.lowercased() == "eraser"
        toolControl.selectedSegmentIndex = isEraser ? 1 : 0
        sizeSlider.value = Float(isEraser ? currentConfig.eraserSize : currentConfig.size)
        sizeValueLabel.text = String(format: "%.1f", sizeSlider.value)
        updateColorSelection()
    }

    @objc private func toolChanged() {
        let isEraser = toolControl.selectedSegmentIndex == 1
        currentConfig = BrushConfig(
            tool: isEraser ? "eraser" : "pen",
            color: currentConfig.color,
            size: currentConfig.size,
            eraserSize: currentConfig.eraserSize
        )
        applyBrushConfig(currentConfig)
        DrawingChannel.notifyToolChanged(
            tool: currentConfig.tool,
            source: "ui",
            color: currentConfig.color.argbInt(),
            size: currentConfig.size,
            eraserSize: currentConfig.eraserSize
        )
    }

    @objc private func sizeChanged() {
        let value = CGFloat(sizeSlider.value)
        if currentConfig.tool.lowercased() == "eraser" {
            currentConfig = BrushConfig(
                tool: currentConfig.tool,
                color: currentConfig.color,
                size: currentConfig.size,
                eraserSize: value
            )
        } else {
            currentConfig = BrushConfig(
                tool: currentConfig.tool,
                color: currentConfig.color,
                size: value,
                eraserSize: currentConfig.eraserSize
            )
        }
        applyBrushConfig(currentConfig)
        DrawingChannel.notifyToolChanged(
            tool: currentConfig.tool,
            source: "ui",
            color: currentConfig.color.argbInt(),
            size: currentConfig.size,
            eraserSize: currentConfig.eraserSize
        )
    }

    @objc private func colorChanged(_ sender: UIButton) {
        let index = sender.tag
        guard index >= 0 && index < colorOptions.count else { return }
        currentConfig = BrushConfig(
            tool: currentConfig.tool,
            color: colorOptions[index],
            size: currentConfig.size,
            eraserSize: currentConfig.eraserSize
        )
        applyBrushConfig(currentConfig)
        DrawingChannel.notifyToolChanged(
            tool: currentConfig.tool,
            source: "ui",
            color: currentConfig.color.argbInt(),
            size: currentConfig.size,
            eraserSize: currentConfig.eraserSize
        )
    }

    private func updateColorSelection() {
        let currentArgb = currentConfig.color.argbInt()
        for (index, button) in colorButtons.enumerated() {
            let colorArgb = colorOptions[index].argbInt()
            button.layer.borderWidth = (colorArgb == currentArgb) ? 2 : 0
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
        if activePoints.isEmpty {
            activeStrokeId = nil
            lastPointCount = 0
            isDrawing = false
            return
        }
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
                let pressure = first.force
                let payload: [String: Any] = [
                    "e": "ds",
                    "sId": activeStrokeId as Any,
                    "x": normalized.x,
                    "y": normalized.y,
                    "p": pressure,
                    "c": currentConfig.color.hexRGB(),
                    "w": currentConfig.size,
                ]
                DrawingChannel.notifyDrawEvent(payload)
            }

            if count > lastPointCount {
                for index in lastPointCount..<count {
                    let point = path[index]
                    let normalized = DrawingMetricsStore.normalize(point: point.location)
                    activePoints.append([
                        "x": Double(normalized.x),
                        "y": Double(normalized.y),
                        "p": Double(point.force),
                    ])
                    if index == 0 { continue }
                    let payload: [String: Any] = [
                        "e": "dm",
                        "sId": activeStrokeId as Any,
                        "x": normalized.x,
                        "y": normalized.y,
                        "p": point.force,
                    ]
                    DrawingChannel.notifyDrawEvent(payload)
                }
                lastPointCount = count
            }
        }
    }
}
