package com.example.pentalk_front.drawing

import kotlin.math.max
import kotlin.math.min

object DrawingMetricsStore {
    @Volatile
    private var renderWidth: Float = 0f
    @Volatile
    private var renderHeight: Float = 0f
    @Volatile
    private var pdfWidth: Float = 0f
    @Volatile
    private var pdfHeight: Float = 0f

    fun update(payload: Map<String, Any>) {
        renderWidth = (payload["renderWidth"] as? Number)?.toFloat() ?: 0f
        renderHeight = (payload["renderHeight"] as? Number)?.toFloat() ?: 0f
        pdfWidth = (payload["pdfWidth"] as? Number)?.toFloat() ?: 0f
        pdfHeight = (payload["pdfHeight"] as? Number)?.toFloat() ?: 0f
    }

    fun normalize(x: Float, y: Float): Pair<Float, Float> {
        if (renderWidth <= 0f || renderHeight <= 0f) {
            return Pair(x, y)
        }
        val nx = min(1f, max(0f, x / renderWidth))
        val ny = min(1f, max(0f, y / renderHeight))
        return Pair(nx, ny)
    }

    fun getPdfSize(): Pair<Float, Float> {
        return Pair(pdfWidth, pdfHeight)
    }
}
