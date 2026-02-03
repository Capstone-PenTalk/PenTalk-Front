package com.example.pentalk_front.drawing

import io.flutter.plugin.common.MethodChannel

object DrawingChannel {
    const val CHANNEL_NAME = "pentalk/native_drawing"

    @Volatile
    var channel: MethodChannel? = null

    fun notifyToolChanged(
        tool: String,
        source: String,
        color: Int? = null,
        size: Float? = null,
        eraserSize: Float? = null,
    ) {
        val payload = mutableMapOf<String, Any>(
            "tool" to tool,
            "source" to source,
        )
        if (color != null) payload["color"] = color
        if (size != null) payload["size"] = size
        if (eraserSize != null) payload["eraserSize"] = eraserSize
        channel?.invokeMethod("toolChanged", payload)
    }
}
