import UIKit
import PencilKit

final class DrawingViewController: UIViewController {
    struct BrushConfig {
        let tool: String
        let color: UIColor
        let size: CGFloat
        let eraserSize: CGFloat
    }

    private let canvasView = PKCanvasView(frame: .zero)
    private let infoContainer = UIView(frame: .zero)
    private let toolLabel = UILabel(frame: .zero)
    private let sizeLabel = UILabel(frame: .zero)
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
    var onDismiss: (() -> Void)?

    init(config: BrushConfig) {
        self.currentConfig = config
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .white
        canvasView.translatesAutoresizingMaskIntoConstraints = false
        canvasView.backgroundColor = .white
        if #available(iOS 14.0, *) {
            canvasView.drawingPolicy = .anyInput
        } else {
            // Fallback on earlier versions
        }
        view.addSubview(canvasView)

        NSLayoutConstraint.activate([
            canvasView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            canvasView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            canvasView.topAnchor.constraint(equalTo: view.topAnchor),
            canvasView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        toolbarContainer.translatesAutoresizingMaskIntoConstraints = false
        toolbarContainer.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        toolbarContainer.layer.cornerRadius = 16
        toolbarContainer.clipsToBounds = true
        view.addSubview(toolbarContainer)

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
            toolbarContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            toolbarContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            toolbarContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            toolbarStack.leadingAnchor.constraint(equalTo: toolbarContainer.leadingAnchor, constant: 12),
            toolbarStack.trailingAnchor.constraint(equalTo: toolbarContainer.trailingAnchor, constant: -12),
            toolbarStack.topAnchor.constraint(equalTo: toolbarContainer.topAnchor, constant: 12),
            toolbarStack.bottomAnchor.constraint(equalTo: toolbarContainer.bottomAnchor, constant: -12),
            sizeValueLabel.widthAnchor.constraint(equalToConstant: 44),
        ])

        infoContainer.translatesAutoresizingMaskIntoConstraints = false
        infoContainer.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        infoContainer.layer.cornerRadius = 12
        infoContainer.clipsToBounds = true
        view.addSubview(infoContainer)

        toolLabel.translatesAutoresizingMaskIntoConstraints = false
        toolLabel.textColor = .white
        toolLabel.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        sizeLabel.translatesAutoresizingMaskIntoConstraints = false
        sizeLabel.textColor = .white
        sizeLabel.font = UIFont.systemFont(ofSize: 13, weight: .regular)

        let infoStack = UIStackView(arrangedSubviews: [toolLabel, sizeLabel])
        infoStack.translatesAutoresizingMaskIntoConstraints = false
        infoStack.axis = .vertical
        infoStack.spacing = 4
        infoContainer.addSubview(infoStack)

        NSLayoutConstraint.activate([
            infoContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            infoContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            infoStack.leadingAnchor.constraint(equalTo: infoContainer.leadingAnchor, constant: 12),
            infoStack.trailingAnchor.constraint(equalTo: infoContainer.trailingAnchor, constant: -12),
            infoStack.topAnchor.constraint(equalTo: infoContainer.topAnchor, constant: 10),
            infoStack.bottomAnchor.constraint(equalTo: infoContainer.bottomAnchor, constant: -10),
        ])

        let closeButton = UIButton(type: .system)
        closeButton.setTitle("Done", for: .normal)
        closeButton.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeButton)

        NSLayoutConstraint.activate([
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
        ])

        applyBrushConfig(currentConfig)
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
        updateInfoLabels()
    }

    @objc private func closeTapped() {
        dismiss(animated: true) { [onDismiss] in
            onDismiss?()
        }
    }

    private func updateInfoLabels() {
        let toolText = "Tool: \(currentConfig.tool)"
        let brushText = String(format: "Brush %.1f | Eraser %.1f",
                               currentConfig.size,
                               currentConfig.eraserSize)
        toolLabel.text = toolText
        sizeLabel.text = brushText
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
}
