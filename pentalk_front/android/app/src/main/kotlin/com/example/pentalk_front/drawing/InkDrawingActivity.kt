package com.example.pentalk_front.drawing

import android.app.Activity
import android.graphics.Color
import android.os.Bundle
import android.util.TypedValue
import android.view.Gravity
import android.widget.FrameLayout
import android.widget.ImageButton
import java.lang.ref.WeakReference
import java.util.Locale

class InkDrawingActivity : Activity() {

    private lateinit var drawingView: InkDrawingView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        activeActivity = WeakReference(this)

        drawingView = InkDrawingView(this)
        drawingView.setOnToolChangedListener { tool ->
            val config = drawingView.getBrushConfig()
            DrawingChannel.notifyToolChanged(
                tool.name.lowercase(Locale.US),
                "hardware",
                config.color,
                config.size,
                config.eraserSize,
            )
        }

        applyBrushConfig(readBrushConfig())

        val root = FrameLayout(this)
        root.addView(
            drawingView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )

        val closeButton = ImageButton(this).apply {
            setImageResource(android.R.drawable.ic_menu_close_clear_cancel)
            setBackgroundColor(Color.TRANSPARENT)
            setOnClickListener { finish() }
            contentDescription = "Close"
        }
        val closeSize = TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            40f,
            resources.displayMetrics,
        ).toInt()
        val closeMargin = TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            12f,
            resources.displayMetrics,
        ).toInt()
        root.addView(
            closeButton,
            FrameLayout.LayoutParams(closeSize, closeSize).apply {
                gravity = Gravity.TOP or Gravity.END
                setMargins(closeMargin, closeMargin, closeMargin, closeMargin)
            },
        )

        setContentView(root)
    }

    override fun onDestroy() {
        if (activeActivity?.get() === this) {
            activeActivity = null
        }
        super.onDestroy()
    }

    private fun applyBrushConfig(config: InkDrawingView.BrushConfig) {
        drawingView.setBrushConfig(config)
    }

    private fun readBrushConfig(): InkDrawingView.BrushConfig {
        val toolName = intent.getStringExtra(EXTRA_TOOL) ?: "pen"
        val tool = toolFromString(toolName)
        val color = intent.getIntExtra(EXTRA_COLOR, Color.BLACK)
        val size = intent.getFloatExtra(EXTRA_SIZE, DEFAULT_SIZE)
        val eraserSize = intent.getFloatExtra(EXTRA_ERASER_SIZE, DEFAULT_ERASER_SIZE)
        return InkDrawingView.BrushConfig(tool, color, size, eraserSize)
    }

    private fun toolFromString(value: String): InkDrawingView.ToolKind {
        return when (value.lowercase(Locale.US)) {
            "eraser" -> InkDrawingView.ToolKind.ERASER
            "finger" -> InkDrawingView.ToolKind.FINGER
            else -> InkDrawingView.ToolKind.PEN
        }
    }

    companion object {
        private const val EXTRA_TOOL = "tool"
        private const val EXTRA_COLOR = "color"
        private const val EXTRA_SIZE = "size"
        private const val EXTRA_ERASER_SIZE = "eraserSize"

        private const val DEFAULT_SIZE = 6f
        private const val DEFAULT_ERASER_SIZE = 24f

        private var activeActivity: WeakReference<InkDrawingActivity>? = null

        fun updateBrush(config: InkDrawingView.BrushConfig) {
            activeActivity?.get()?.applyBrushConfig(config)
        }

        fun newIntentExtras(
            tool: String,
            color: Int,
            size: Float,
            eraserSize: Float,
        ): Bundle {
            return Bundle().apply {
                putString(EXTRA_TOOL, tool)
                putInt(EXTRA_COLOR, color)
                putFloat(EXTRA_SIZE, size)
                putFloat(EXTRA_ERASER_SIZE, eraserSize)
            }
        }
    }
}
