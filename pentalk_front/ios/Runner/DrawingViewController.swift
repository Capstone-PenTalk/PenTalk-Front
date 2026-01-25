import UIKit
import PencilKit

final class DrawingViewController: UIViewController, PKToolPickerObserver {
    struct BrushConfig {
        let tool: String
        let color: UIColor
        let size: CGFloat
        let eraserSize: CGFloat
    }

    private let canvasView = PKCanvasView(frame: .zero)
    private var toolPicker: PKToolPicker?
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
        canvasView.drawingPolicy = .anyInput
        view.addSubview(canvasView)

        NSLayoutConstraint.activate([
            canvasView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            canvasView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            canvasView.topAnchor.constraint(equalTo: view.topAnchor),
            canvasView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
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

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        setUpToolPicker()
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

    private func setUpToolPicker() {
        guard let window = view.window else { return }
        let picker = PKToolPicker.shared(for: window)
        toolPicker = picker
        picker?.addObserver(canvasView)
        picker?.addObserver(self)
        picker?.setVisible(true, forFirstResponder: canvasView)
        canvasView.becomeFirstResponder()
    }

    @objc private func closeTapped() {
        dismiss(animated: true) { [onDismiss] in
            onDismiss?()
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
                color: argbInt(from: inkingTool.color),
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
            color: argbInt(from: currentConfig.color),
            size: currentConfig.size,
            eraserSize: currentConfig.eraserSize
        )
    }

    private func argbInt(from color: UIColor) -> Int {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color.getRed(&red, &green, &blue, &alpha)
        let a = Int(alpha * 255.0) & 0xFF
        let r = Int(red * 255.0) & 0xFF
        let g = Int(green * 255.0) & 0xFF
        let b = Int(blue * 255.0) & 0xFF
        return (a << 24) | (r << 16) | (g << 8) | b
    }
}
