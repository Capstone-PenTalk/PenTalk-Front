import Flutter
import PDFKit
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var drawingController: DrawingViewController?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let registrar = registrar(forPlugin: "drawing_platform_view") {
      let factory = DrawingPlatformViewFactory(messenger: registrar.messenger())
      registrar.register(factory, withId: "pentalk/drawing_view")
    }

    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: DrawingChannel.name,
        binaryMessenger: controller.binaryMessenger
      )
      let pdfChannel = FlutterMethodChannel(
        name: "pentalk/pdf",
        binaryMessenger: controller.binaryMessenger
      )
      DrawingChannel.channel = channel
      channel.setMethodCallHandler { call, result in
        switch call.method {
        case "open":
          let config = Self.parseBrushConfig(call.arguments)
          let drawingController = DrawingViewController(config: config)
          drawingController.onDismiss = { [weak self] in
            self?.drawingController = nil
          }
          self.drawingController = drawingController
          controller.present(drawingController, animated: true)
          result(nil)
        case "setBrush":
          let surfaceConfig = BrushConfigParser.parse(call.arguments)
          let controllerConfig = Self.parseBrushConfig(call.arguments)
          DrawingSurfaceManager.shared.applyBrushConfig(surfaceConfig)
          self.drawingController?.applyBrushConfig(controllerConfig)
          result(nil)
        case "setDrawingMetrics":
          if let args = call.arguments as? [String: Any] {
            let renderWidth = (args["renderWidth"] as? NSNumber)?.doubleValue ?? 0
            let renderHeight = (args["renderHeight"] as? NSNumber)?.doubleValue ?? 0
            let pdfWidth = (args["pdfWidth"] as? NSNumber)?.doubleValue ?? 0
            let pdfHeight = (args["pdfHeight"] as? NSNumber)?.doubleValue ?? 0
            DrawingMetricsStore.update(
              renderWidth: CGFloat(renderWidth),
              renderHeight: CGFloat(renderHeight),
              pdfWidth: CGFloat(pdfWidth),
              pdfHeight: CGFloat(pdfHeight)
            )
          }
          result(nil)
        case "setPageContext":
          if let args = call.arguments as? [String: Any],
             let materialId = args["materialId"] as? String,
             let pageNumber = (args["pageNumber"] as? NSNumber)?.intValue {
            DrawingSurfaceManager.shared.updatePageContext(
              materialId: materialId,
              pageNumber: pageNumber
            )
          }
          result(nil)
        case "exportDrawing":
          result(DrawingSurfaceManager.shared.exportDrawingSnapshot())
        case "undoLastStroke":
          DrawingSurfaceManager.shared.undoLastStroke()
          result(nil)
        case "clearDrawing":
          DrawingSurfaceManager.shared.clearDrawing()
          result(nil)
        case "replaceDrawing":
          let args = call.arguments as? [String: Any]
          let strokes = (args?["strokes"] as? [[String: Any]]) ?? []
          DrawingSurfaceManager.shared.replaceDrawingSnapshot(strokes)
          result(nil)
        case "sendDrawEvent":
          if let payload = call.arguments as? [String: Any] {
            NSLog("[draw][ios] sendDrawEvent received: %@", String(describing: payload))
            // TODO: forward payload to socket server.
            _ = payload
          }
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
      pdfChannel.setMethodCallHandler { call, result in
        switch call.method {
        case "inspectDocument":
          guard let args = call.arguments as? [String: Any],
                let materialId = args["materialId"] as? String,
                let pdfUrl = args["pdfUrl"] as? String,
                let localPdfPath = args["localPdfPath"] as? String else {
            result(
              FlutterError(
                code: "INVALID_ARGS",
                message: "inspectDocument arguments missing",
                details: nil
              )
            )
            return
          }
          DispatchQueue.global(qos: .userInitiated).async {
            do {
              let payload = try Self.inspectPdfDocument(
                materialId: materialId,
                pdfUrl: pdfUrl,
                localPdfPath: localPdfPath
              )
              DispatchQueue.main.async {
                result(payload)
              }
            } catch {
              DispatchQueue.main.async {
                result(
                  FlutterError(
                    code: "PDF_INSPECT_FAILED",
                    message: error.localizedDescription,
                    details: nil
                  )
                )
              }
            }
          }
        case "renderPage":
          guard let args = call.arguments as? [String: Any],
                let materialId = args["materialId"] as? String,
                let localPdfPath = args["localPdfPath"] as? String,
                let pageNumber = (args["pageNumber"] as? NSNumber)?.intValue,
                let targetWidth = (args["targetWidth"] as? NSNumber)?.doubleValue else {
            result(
              FlutterError(
                code: "INVALID_ARGS",
                message: "renderPage arguments missing",
                details: nil
              )
            )
            return
          }
          DispatchQueue.global(qos: .userInitiated).async {
            do {
              let payload = try Self.renderPdfPage(
                materialId: materialId,
                localPdfPath: localPdfPath,
                pageNumber: pageNumber,
                targetWidth: CGFloat(targetWidth)
              )
              DispatchQueue.main.async {
                result(payload)
              }
            } catch {
              DispatchQueue.main.async {
                result(
                  FlutterError(
                    code: "PDF_RENDER_FAILED",
                    message: error.localizedDescription,
                    details: nil
                  )
                )
              }
            }
          }
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
    let colorValue: UInt32 = (args?["color"] as? NSNumber)?.uint32Value ?? 0xFF000000
    let size = (args?["size"] as? NSNumber)?.doubleValue ?? 6.0
    let eraserSize = (args?["eraserSize"] as? NSNumber)?.doubleValue ?? 24.0
    let color = UIColor(argb: colorValue)
    return DrawingViewController.BrushConfig(
      tool: tool,
      color: color,
      size: CGFloat(size),
      eraserSize: CGFloat(eraserSize)
    )
  }

  private static func inspectPdfDocument(
    materialId: String,
    pdfUrl: String,
    localPdfPath: String
  ) throws -> [String: Any] {
    let fileUrl = URL(fileURLWithPath: localPdfPath)
    guard let document = PDFDocument(url: fileUrl) else {
      throw NSError(domain: "PentalkPdf", code: 1, userInfo: [
        NSLocalizedDescriptionKey: "PDF 문서를 열지 못했습니다."
      ])
    }

    var pages: [[String: Any]] = []
    for index in 0..<document.pageCount {
      let page = document.page(at: index)
      let bounds = page?.bounds(for: .mediaBox) ?? .zero
      pages.append([
        "pageNumber": index + 1,
        "width": bounds.width,
        "height": bounds.height,
      ])
    }

    return [
      "materialId": materialId,
      "pdfUrl": pdfUrl,
      "localPdfPath": localPdfPath,
      "pageCount": document.pageCount,
      "currentPage": 1,
      "pages": pages,
    ]
  }

  private static func renderPdfPage(
    materialId: String,
    localPdfPath: String,
    pageNumber: Int,
    targetWidth: CGFloat
  ) throws -> [String: Any] {
    let fileUrl = URL(fileURLWithPath: localPdfPath)
    guard let document = PDFDocument(url: fileUrl) else {
      throw NSError(domain: "PentalkPdf", code: 2, userInfo: [
        NSLocalizedDescriptionKey: "PDF 문서를 열지 못했습니다."
      ])
    }
    guard pageNumber > 0, pageNumber <= document.pageCount,
          let page = document.page(at: pageNumber - 1) else {
      throw NSError(domain: "PentalkPdf", code: 3, userInfo: [
        NSLocalizedDescriptionKey: "유효하지 않은 PDF 페이지입니다."
      ])
    }

    let bounds = page.bounds(for: .mediaBox)
    // PDF 페이지 회전(90/270도)이 있으면 mediaBox의 width/height가
    // 실제 화면에 그려지는 방향과 반대로 나온다. draw(with:to:)는 회전을
    // 자동 반영해서 그리므로, 캔버스 크기 쪽에서도 미리 가로/세로를 맞춰줘야
    // Android(회전 반영된 값 사용)와 렌더링 결과(종횡비)가 일치한다.
    let isSideways = page.rotation == 90 || page.rotation == 270
    let sourceWidth = isSideways ? bounds.height : bounds.width
    let sourceHeight = isSideways ? bounds.width : bounds.height
    let scale = targetWidth > 0 && sourceWidth > 0 ? targetWidth / sourceWidth : 1
    let renderSize = CGSize(
      width: max(1, sourceWidth * scale),
      height: max(1, sourceHeight * scale)
    )

    let renderer = UIGraphicsImageRenderer(size: renderSize)
    let image = renderer.image { context in
      UIColor.white.setFill()
      context.fill(CGRect(origin: .zero, size: renderSize))
      context.cgContext.saveGState()
      context.cgContext.translateBy(x: 0, y: renderSize.height)
      context.cgContext.scaleBy(x: scale, y: -scale)
      page.draw(with: .mediaBox, to: context.cgContext)
      context.cgContext.restoreGState()
    }

    guard let pngData = image.pngData() else {
      throw NSError(domain: "PentalkPdf", code: 4, userInfo: [
        NSLocalizedDescriptionKey: "PDF 페이지 이미지를 생성하지 못했습니다."
      ])
    }

    let pagesDirectory = try pdfRenderDirectory(materialId: materialId)
    let imageUrl = pagesDirectory.appendingPathComponent("page_\(pageNumber).png")
    try pngData.write(to: imageUrl, options: .atomic)

    return [
      "pageNumber": pageNumber,
      "imagePath": imageUrl.path,
      // 메타데이터는 실제 렌더링된 이미지 크기를 반환한다 (원본 PDF 크기가 아님)
      "width": renderSize.width,
      "height": renderSize.height,
    ]
  }

  private static func pdfRenderDirectory(materialId: String) throws -> URL {
    let baseDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let directory = baseDir
      .appendingPathComponent("pdf_cache", isDirectory: true)
      .appendingPathComponent(materialId, isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: nil
    )
    return directory
  }
}
