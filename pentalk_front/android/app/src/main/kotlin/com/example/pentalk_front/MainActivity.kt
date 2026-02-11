package com.example.pentalk_front

import android.content.Intent
import com.example.pentalk_front.drawing.DrawingChannel
import com.example.pentalk_front.drawing.InkDrawingActivity
import com.example.pentalk_front.drawing.InkDrawingView
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DrawingChannel.CHANNEL_NAME)
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
                        // TODO: forward payload to socket server.
                    }
                    result.success(null)
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
}
