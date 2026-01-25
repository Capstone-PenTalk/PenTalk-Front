import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var drawingController: DrawingViewController?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: DrawingChannel.name,
        binaryMessenger: controller.binaryMessenger
      )
      DrawingChannel.channel = channel
      channel.setMethodCallHandler { [weak self] call, result in
        switch call.method {
        case "open":
          let config = Self.parseBrushConfig(call.arguments)
          let drawingController = DrawingViewController(config: config)
          drawingController.onDismiss = { [weak self] in
            self?.drawingController = nil
          }
          self?.drawingController = drawingController
          controller.present(drawingController, animated: true)
          result(nil)
        case "setBrush":
          let config = Self.parseBrushConfig(call.arguments)
          self?.drawingController?.applyBrushConfig(config)
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private static func parseBrushConfig(_ arguments: Any?) -> DrawingViewController.BrushConfig {
    let args = arguments as? [String: Any]
    let tool = args?["tool"] as? String ?? "pen"
    let colorValue = (args?["color"] as? NSNumber)?.int32Value ?? 0xFF000000
    let size = (args?["size"] as? NSNumber)?.doubleValue ?? 6.0
    let eraserSize = (args?["eraserSize"] as? NSNumber)?.doubleValue ?? 24.0
    let color = UIColor(argb: UInt32(bitPattern: colorValue))
    return DrawingViewController.BrushConfig(
      tool: tool,
      color: color,
      size: CGFloat(size),
      eraserSize: CGFloat(eraserSize)
    )
  }
}

private extension UIColor {
  convenience init(argb: UInt32) {
    let alpha = CGFloat((argb >> 24) & 0xFF) / 255.0
    let red = CGFloat((argb >> 16) & 0xFF) / 255.0
    let green = CGFloat((argb >> 8) & 0xFF) / 255.0
    let blue = CGFloat(argb & 0xFF) / 255.0
    self.init(red: red, green: green, blue: blue, alpha: alpha)
  }
}
