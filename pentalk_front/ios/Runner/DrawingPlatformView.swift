import Flutter
import Foundation
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

    private final class TouchAwareCanvasView: PKCanvasView {
        var onTouchesBegan: ((Set<UITouch>) -> Void)?
        var onTouchesMoved: ((Set<UITouch>) -> Void)?
        var onTouchesEnded: (() -> Void)?
        var onTouchesCancelled: (() -> Void)?

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesBegan(touches, with: event)
            onTouchesBegan?(touches)
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesMoved(touches, with: event)
            onTouchesMoved?(touches)
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesEnded(touches, with: event)
            onTouchesEnded?()
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesCancelled(touches, with: event)
            onTouchesCancelled?()
        }
    }

    private let containerView = ContainerView()
    private let canvasView = TouchAwareCanvasView(frame: .zero)
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
    private var isDrawing: Bool = false
    private var finalizeWorkItem: DispatchWorkItem?
    private var strokeIdBySignature: [String: Int] = [:]
    private var previousStrokeSignatures: Set<String> = []
    private var syntheticStrokeIdSeed: Int = Int(Date().timeIntervalSince1970 * 1000)
    private var hasSentLiveDrawStart: Bool = false
    private var lastLiveMoveSentAt: TimeInterval = 0

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
            // Allow finger input on iPad as well; pencil-only mode makes the
            // canvas look unresponsive on devices without Apple Pencil.
            canvasView.drawingPolicy = .anyInput
        }
        canvasView.delegate = self
        canvasView.onTouchesBegan = { [weak self] touches in
            guard let self else { return }
            self.finalizeWorkItem?.cancel()
            self.emitLiveDrawStartIfNeeded(from: touches)
        }
        canvasView.onTouchesMoved = { [weak self] touches in
            self?.emitLiveDrawMove(from: touches)
            self?.scheduleStrokeFinalization()
        }
        canvasView.onTouchesEnded = { [weak self] in
            self?.completeStrokeFromTouchEnd()
        }
        canvasView.onTouchesCancelled = { [weak self] in
            self?.completeStrokeFromTouchEnd()
        }
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
            return canvasView.drawing.strokes.compactMap { stroke -> [String: Any]? in
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
                let firstPoint = path[0]
                let signature = strokeSignature(stroke)
                let strokeId = strokeIdBySignature[signature] ?? {
                    syntheticStrokeIdSeed += 1
                    strokeIdBySignature[signature] = syntheticStrokeIdSeed
                    return syntheticStrokeIdSeed
                }()

                return [
                    "sId": strokeId,
                    "c": stroke.ink.color.hexRGB(),
                    "w": Double(firstPoint.size.width),
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

    func undoLastStroke() {
        guard #available(iOS 14.0, *) else { return }
        let currentStrokes = canvasView.drawing.strokes
        guard !currentStrokes.isEmpty else { return }
        let removedStroke = currentStrokes.last
        canvasView.drawing = PKDrawing(strokes: Array(currentStrokes.dropLast()))
        if let removedStroke {
            let signature = strokeSignature(removedStroke)
            strokeIdBySignature.removeValue(forKey: signature)
            previousStrokeSignatures.remove(signature)
        }
    }

    func clearDrawing() {
        canvasView.drawing = PKDrawing()
        strokeIdBySignature.removeAll()
        previousStrokeSignatures.removeAll()
        activeStrokeId = nil
        activePoints.removeAll()
        isDrawing = false
        hasSentLiveDrawStart = false
        lastLiveMoveSentAt = 0
    }

    func replaceDrawingSnapshot(_ snapshot: [[String: Any]]) {
        guard #available(iOS 14.0, *) else {
            clearDrawing()
            return
        }

        let strokes = snapshot.compactMap { makeStroke(from: $0) }
        canvasView.drawing = PKDrawing(strokes: strokes.map(\.stroke))
        strokeIdBySignature = Dictionary(
            uniqueKeysWithValues: strokes.map { ($0.signature, $0.strokeId) }
        )
        previousStrokeSignatures = Set(strokes.map(\.signature))
        activeStrokeId = nil
        activePoints.removeAll()
        isDrawing = false
        hasSentLiveDrawStart = false
        lastLiveMoveSentAt = 0
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
        if currentConfig.tool.lowercased() == "eraser" {
            if #available(iOS 14.0, *) {
                previousStrokeSignatures = Set(canvasView.drawing.strokes.map { strokeSignature($0) })
            } else {
                previousStrokeSignatures.removeAll()
            }
            isDrawing = false
            activeStrokeId = nil
            activePoints.removeAll()
            return
        }
    }

    func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
        if currentConfig.tool.lowercased() == "eraser" {
            handleEraserDiff(from: canvasView)
            return
        }
        // Pen stroke lifecycle is touch-driven; keep delegate as fallback only.
        if activeStrokeId != nil {
            finalizeActiveStroke()
        }
    }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        if currentConfig.tool.lowercased() == "eraser" {
            handleEraserDiff(from: canvasView)
        }
    }

    private func scheduleStrokeFinalization() {
        finalizeWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.finalizeActiveStroke()
        }
        finalizeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03, execute: workItem)
    }

    private func completeStrokeFromTouchEnd() {
        finalizeActiveStroke()
    }

    private func finalizeActiveStroke() {
        finalizeWorkItem?.cancel()
        finalizeWorkItem = nil
        guard let strokeId = activeStrokeId else { return }
        if activePoints.isEmpty {
            activeStrokeId = nil
            isDrawing = false
            hasSentLiveDrawStart = false
            lastLiveMoveSentAt = 0
            return
        }
        let payload: [String: Any] = [
            "e": "de",
            "sId": strokeId,
            "pts": activePoints,
        ]
        DrawingChannel.notifyDrawEvent(payload)
        if #available(iOS 14.0, *) {
            if let stroke = canvasView.drawing.strokes.last {
                strokeIdBySignature[strokeSignature(stroke)] = strokeId
            }
        }
        activeStrokeId = nil
        activePoints.removeAll()
        isDrawing = false
        hasSentLiveDrawStart = false
        lastLiveMoveSentAt = 0
    }

    private func handleEraserDiff(from canvasView: PKCanvasView) {
        if #available(iOS 14.0, *) {
            let current = Set(canvasView.drawing.strokes.map { strokeSignature($0) })
            let removed = previousStrokeSignatures.subtracting(current)
            if !removed.isEmpty {
                var mappedCount = 0
                for signature in removed {
                    if let strokeId = strokeIdBySignature[signature] {
                        mappedCount += 1
                        DrawingChannel.notifyDrawEvent([
                            "e": "er",
                            "sId": strokeId,
                        ])
                    } else {
                        NSLog("[draw][ios][warn] eraser removed stroke without mapped sId signature=%@", signature)
                    }
                    strokeIdBySignature.removeValue(forKey: signature)
                }
                NSLog(
                    "[draw][ios] eraser diff removed=%d mapped=%d unmapped=%d",
                    removed.count,
                    mappedCount,
                    removed.count - mappedCount
                )
            }
            previousStrokeSignatures = current
        }
    }

    @available(iOS 14.0, *)
    private func strokeSignature(_ stroke: PKStroke) -> String {
        let path = stroke.path
        let count = path.count
        guard count > 0 else { return "empty" }
        let width = path[0].size.width
        let bounds = stroke.renderBounds
        let sampleCount = min(8, count)
        let step = max(1, (count - 1) / max(1, sampleCount - 1))

        var parts: [String] = [
            "n:\(count)",
            String(format: "w:%.3f", width),
            String(
                format: "b:%.2f,%.2f,%.2f,%.2f",
                bounds.minX, bounds.minY, bounds.width, bounds.height
            ),
            "c:\(stroke.ink.color.hexRGB())",
        ]

        var index = 0
        while index < count {
            let p = path[index].location
            parts.append(String(format: "%.3f,%.3f", p.x, p.y))
            index += step
        }
        if index - step != count - 1 {
            let last = path[count - 1].location
            parts.append(String(format: "%.3f,%.3f", last.x, last.y))
        }

        return parts.joined(separator: "|")
    }

    private func emitLiveDrawStartIfNeeded(from touches: Set<UITouch>) {
        guard currentConfig.tool.lowercased() != "eraser" else { return }
        guard !touches.isEmpty else { return }
        // Hard-split: every new touch begins a new independent stroke.
        if activeStrokeId != nil || hasSentLiveDrawStart || !activePoints.isEmpty {
            finalizeActiveStroke()
        }
        activeStrokeId = nextStrokeId()
        activePoints.removeAll()
        isDrawing = true
        hasSentLiveDrawStart = false
        lastLiveMoveSentAt = 0
        guard let strokeId = activeStrokeId, !hasSentLiveDrawStart else { return }
        guard let touch = touches.first else { return }
        let location = touch.location(in: canvasView)
        let normalized = DrawingMetricsStore.normalize(point: location)
        let pressure = touch.force
        let pointPayload: [String: Double] = [
            "x": Double(normalized.x),
            "y": Double(normalized.y),
            "p": Double(pressure),
        ]
        activePoints.append(pointPayload)
        DrawingChannel.notifyDrawEvent([
            "e": "ds",
            "sId": strokeId,
            "x": normalized.x,
            "y": normalized.y,
            "p": pressure,
            "c": currentConfig.color.hexRGB(),
            "w": currentConfig.size,
        ])
        hasSentLiveDrawStart = true
    }

    private func nextStrokeId() -> Int {
        syntheticStrokeIdSeed += 1
        return syntheticStrokeIdSeed
    }

    private func emitLiveDrawMove(from touches: Set<UITouch>) {
        guard currentConfig.tool.lowercased() != "eraser" else { return }
        guard hasSentLiveDrawStart, let strokeId = activeStrokeId else { return }
        guard let touch = touches.first else { return }

        let now = ProcessInfo.processInfo.systemUptime
        if now - lastLiveMoveSentAt < (1.0 / 60.0) {
            return
        }
        lastLiveMoveSentAt = now

        let location = touch.location(in: canvasView)
        let normalized = DrawingMetricsStore.normalize(point: location)
        let pressure = touch.force
        activePoints.append([
            "x": Double(normalized.x),
            "y": Double(normalized.y),
            "p": Double(pressure),
        ])
        DrawingChannel.notifyDrawEvent([
            "e": "dm",
            "sId": strokeId,
            "x": normalized.x,
            "y": normalized.y,
            "p": pressure,
        ])
    }

    @available(iOS 14.0, *)
    private func makeStroke(from payload: [String: Any]) -> (stroke: PKStroke, strokeId: Int, signature: String)? {
        let strokeId = (payload["sId"] as? NSNumber)?.intValue ?? 0
        let width = (payload["w"] as? NSNumber)?.doubleValue ?? Double(currentConfig.size)
        let color = colorFromHex(payload["c"] as? String) ?? currentConfig.color
        let rawPoints = payload["pts"] as? [[String: Any]] ?? []
        guard !rawPoints.isEmpty else { return nil }
        let renderWidth = DrawingMetricsStore.metrics?.renderWidth ?? max(canvasView.bounds.width, 1)
        let renderHeight = DrawingMetricsStore.metrics?.renderHeight ?? max(canvasView.bounds.height, 1)

        let controlPoints: [PKStrokePoint] = rawPoints.enumerated().map { index, rawPoint in
            let x = (rawPoint["x"] as? NSNumber)?.doubleValue ?? 0
            let y = (rawPoint["y"] as? NSNumber)?.doubleValue ?? 0
            let force = (rawPoint["p"] as? NSNumber)?.doubleValue ?? 1.0
            return PKStrokePoint(
                location: CGPoint(x: x * renderWidth, y: y * renderHeight),
                timeOffset: TimeInterval(index) / 120.0,
                size: CGSize(width: width, height: width),
                opacity: 1.0,
                force: force,
                azimuth: 0,
                altitude: .pi / 2
            )
        }

        let path = PKStrokePath(controlPoints: controlPoints, creationDate: Date())
        let stroke = PKStroke(ink: PKInk(.pen, color: color), path: path)
        let signature = strokeSignature(stroke)
        return (stroke, strokeId, signature)
    }

    private func colorFromHex(_ hexColor: String?) -> UIColor? {
        guard let hexColor else { return nil }
        let hex = hexColor.replacingOccurrences(of: "#", with: "")
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        return UIColor(argb: 0xFF000000 | value)
    }
}
