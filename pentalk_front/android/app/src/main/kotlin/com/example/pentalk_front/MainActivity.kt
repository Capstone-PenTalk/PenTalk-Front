package com.example.pentalk_front

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.content.Intent
import android.os.ParcelFileDescriptor
import android.util.Log
import com.example.pentalk_front.drawing.DrawingChannel
import com.example.pentalk_front.drawing.DrawingMetricsStore
import com.example.pentalk_front.drawing.InkDrawingActivity
import com.example.pentalk_front.drawing.InkDrawingView
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DrawingChannel.CHANNEL_NAME)
        val pdfChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pentalk/pdf")
        DrawingChannel.channel = channel

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "open" -> {
                    val config = parseBrushConfig(call.arguments)
                    val intent = Intent(this, InkDrawingActivity::class.java).apply {
                        putExtras(
                            InkDrawingActivity.newIntentExtras(
                                config.tool.name.lowercase(),
                                config.color,
                                config.size,
                                config.eraserSize,
                            )
                        )
                    }
                    startActivity(intent)
                    result.success(null)
                }
                "setBrush" -> {
                    val config = parseBrushConfig(call.arguments)
                    InkDrawingActivity.updateBrush(config)
                    result.success(null)
                }
                "setDrawingMetrics" -> {
                    @Suppress("UNCHECKED_CAST")
                    val payload = call.arguments as? Map<String, Any>
                    if (payload != null) {
                        DrawingMetricsStore.update(payload)
                    }
                    result.success(null)
                }
                "sendDrawEvent" -> {
                    @Suppress("UNCHECKED_CAST")
                    val payload = call.arguments as? Map<String, Any>
                    if (payload != null) {
                        Log.d("PentalkDrawing", "[draw][android] sendDrawEvent received: $payload")
                        // TODO: forward payload to socket server.
                    }
                    result.success(null)
                }
                "undoLastStroke" -> {
                    result.success(null)
                }
                "clearDrawing" -> {
                    result.success(null)
                }
                "replaceDrawing" -> {
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        pdfChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "inspectDocument" -> {
                    @Suppress("UNCHECKED_CAST")
                    val args = call.arguments as? Map<String, Any?>
                    val materialId = args?.get("materialId")?.toString()
                    val pdfUrl = args?.get("pdfUrl")?.toString()
                    val localPdfPath = args?.get("localPdfPath")?.toString()
                    if (materialId.isNullOrBlank() || pdfUrl.isNullOrBlank() || localPdfPath.isNullOrBlank()) {
                        result.error("INVALID_ARGS", "inspectDocument arguments missing", null)
                        return@setMethodCallHandler
                    }
                    Thread {
                        try {
                            val payload = inspectPdfDocument(materialId, pdfUrl, localPdfPath)
                            runOnUiThread { result.success(payload) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("PDF_INSPECT_FAILED", e.message, null) }
                        }
                    }.start()
                }
                "renderPage" -> {
                    @Suppress("UNCHECKED_CAST")
                    val args = call.arguments as? Map<String, Any?>
                    val materialId = args?.get("materialId")?.toString()
                    val localPdfPath = args?.get("localPdfPath")?.toString()
                    val pageNumber = (args?.get("pageNumber") as? Number)?.toInt()
                    val targetWidth = (args?.get("targetWidth") as? Number)?.toInt() ?: 1440
                    if (materialId.isNullOrBlank() || localPdfPath.isNullOrBlank() || pageNumber == null) {
                        result.error("INVALID_ARGS", "renderPage arguments missing", null)
                        return@setMethodCallHandler
                    }
                    Thread {
                        try {
                            val payload = renderPdfPage(materialId, localPdfPath, pageNumber, targetWidth)
                            runOnUiThread { result.success(payload) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("PDF_RENDER_FAILED", e.message, null) }
                        }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun parseBrushConfig(arguments: Any?): InkDrawingView.BrushConfig {
        val args = arguments as? Map<*, *> ?: emptyMap<String, Any>()
        val tool = (args["tool"] as? String).orEmpty()
        val color = (args["color"] as? Number)?.toInt() ?: 0xFF000000.toInt()
        val size = (args["size"] as? Number)?.toFloat() ?: 6f
        val eraserSize = (args["eraserSize"] as? Number)?.toFloat() ?: 24f
        return InkDrawingView.BrushConfig(
            toolFromString(tool),
            color,
            size,
            eraserSize,
        )
    }

    private fun toolFromString(value: String): InkDrawingView.ToolKind {
        return when (value.lowercase()) {
            "eraser" -> InkDrawingView.ToolKind.ERASER
            "finger" -> InkDrawingView.ToolKind.FINGER
            else -> InkDrawingView.ToolKind.PEN
        }
    }

    private fun inspectPdfDocument(
        materialId: String,
        pdfUrl: String,
        localPdfPath: String,
    ): Map<String, Any> {
        val file = File(localPdfPath)
        ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY).use { descriptor ->
            PdfRenderer(descriptor).use { renderer ->
                val pages = (0 until renderer.pageCount).map { index ->
                    renderer.openPage(index).use { page ->
                        mapOf(
                            "pageNumber" to (index + 1),
                            "width" to page.width.toDouble(),
                            "height" to page.height.toDouble(),
                        )
                    }
                }
                return mapOf(
                    "materialId" to materialId,
                    "pdfUrl" to pdfUrl,
                    "localPdfPath" to localPdfPath,
                    "pageCount" to renderer.pageCount,
                    "currentPage" to 1,
                    "pages" to pages,
                )
            }
        }
    }

    private fun renderPdfPage(
        materialId: String,
        localPdfPath: String,
        pageNumber: Int,
        targetWidth: Int,
    ): Map<String, Any> {
        val file = File(localPdfPath)
        ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY).use { descriptor ->
            PdfRenderer(descriptor).use { renderer ->
                require(pageNumber in 1..renderer.pageCount) { "유효하지 않은 PDF 페이지입니다." }
                renderer.openPage(pageNumber - 1).use { page ->
                    val width = if (targetWidth > 0) targetWidth else page.width
                    val height = ((page.height.toFloat() / page.width.toFloat()) * width).toInt().coerceAtLeast(1)
                    val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                    val canvas = Canvas(bitmap)
                    canvas.drawColor(Color.WHITE)
                    page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)

                    val directory = File(filesDir, "pdf_cache/$materialId").apply { mkdirs() }
                    val imageFile = File(directory, "page_$pageNumber.png")
                    FileOutputStream(imageFile).use { output ->
                        bitmap.compress(Bitmap.CompressFormat.PNG, 100, output)
                    }
                    bitmap.recycle()

                    return mapOf(
                        "pageNumber" to pageNumber,
                        "imagePath" to imageFile.absolutePath,
                        "width" to page.width.toDouble(),
                        "height" to page.height.toDouble(),
                    )
                }
            }
        }
    }
}
