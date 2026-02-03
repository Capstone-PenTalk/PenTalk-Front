package com.example.pentalk_front.drawing

import android.content.Context
import android.graphics.Color
import android.util.AttributeSet
import android.view.MotionEvent
import android.widget.FrameLayout
import androidx.ink.authoring.InProgressStrokesFinishedListener
import androidx.ink.authoring.InProgressStrokesView
import androidx.ink.brush.Brush
import androidx.ink.brush.StockBrushes
import androidx.ink.geometry.AffineTransform
import androidx.ink.geometry.ImmutableSegment
import androidx.ink.geometry.ImmutableVec
import androidx.ink.geometry.Intersection.intersects
import androidx.ink.strokes.InProgressStrokeId
import androidx.ink.strokes.Stroke
import kotlin.math.max
import kotlin.math.min

class InkDrawingView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
) : FrameLayout(context, attrs) {

    enum class ToolKind {
        PEN,
        ERASER,
        FINGER,
    }

    data class BrushConfig(
        val tool: ToolKind,
        val color: Int,
        val size: Float,
        val eraserSize: Float,
    )

    private val inkView = InProgressStrokesView(context)
    private val finishedStrokes = LinkedHashMap<InProgressStrokeId, Stroke>()
    private val eraserPaths = mutableMapOf<Int, MutableList<ImmutableVec>>()

    private var lastTool: ToolKind? = null
    private var onToolChanged: ((ToolKind) -> Unit)? = null

    private var brushConfig = BrushConfig(ToolKind.PEN, Color.BLACK, 6f, 24f)
    private var penBrush = buildPenBrush(brushConfig)
    private var fingerBrush = buildFingerBrush(brushConfig)

    init {
        isClickable = true
        isFocusable = true

        inkView.addFinishedStrokesListener(
            InProgressStrokesFinishedListener { strokes ->
                finishedStrokes.putAll(strokes)
            }
        )

        addView(
            inkView,
            LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT),
        )
    }

    fun setBrushConfig(config: BrushConfig) {
        brushConfig = config
        penBrush = buildPenBrush(config)
        fingerBrush = buildFingerBrush(config)
    }

    fun getBrushConfig(): BrushConfig = brushConfig

    fun setOnToolChangedListener(listener: ((ToolKind) -> Unit)?) {
        onToolChanged = listener
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN,
            MotionEvent.ACTION_POINTER_DOWN -> handlePointerDown(event, event.actionIndex)
            MotionEvent.ACTION_MOVE -> handleMove(event)
            MotionEvent.ACTION_UP,
            MotionEvent.ACTION_POINTER_UP -> handlePointerUp(event, event.actionIndex)
            MotionEvent.ACTION_CANCEL -> handleCancel(event)
        }
        return true
    }

    private fun handlePointerDown(event: MotionEvent, pointerIndex: Int) {
        val pointerId = event.getPointerId(pointerIndex)
        val tool = toolKindFor(event, pointerIndex)
        reportTool(tool)

        if (tool == ToolKind.ERASER) {
            eraserPaths[pointerId] =
                mutableListOf(ImmutableVec(event.getX(pointerIndex), event.getY(pointerIndex)))
            return
        }

        requestUnbufferedDispatch(event)
        inkView.startStroke(event, pointerId, brushFor(tool))
    }

    private fun handleMove(event: MotionEvent) {
        for (i in 0 until event.pointerCount) {
            val pointerId = event.getPointerId(i)
            val tool = toolKindFor(event, i)
            if (tool == ToolKind.ERASER) {
                eraserPaths[pointerId]?.add(ImmutableVec(event.getX(i), event.getY(i)))
            } else {
                inkView.addToStroke(event, pointerId)
            }
        }
    }

    private fun handlePointerUp(event: MotionEvent, pointerIndex: Int) {
        val pointerId = event.getPointerId(pointerIndex)
        val tool = toolKindFor(event, pointerIndex)
        if (tool == ToolKind.ERASER) {
            val points = eraserPaths.remove(pointerId)
            if (!points.isNullOrEmpty()) {
                eraseStrokes(points)
            }
            return
        }

        inkView.finishStroke(event, pointerId)
    }

    private fun handleCancel(event: MotionEvent) {
        for (i in 0 until event.pointerCount) {
            val pointerId = event.getPointerId(i)
            val tool = toolKindFor(event, i)
            if (tool == ToolKind.ERASER) {
                eraserPaths.remove(pointerId)
            } else {
                inkView.cancelStroke(event, pointerId)
            }
        }
    }

    private fun brushFor(tool: ToolKind): Brush {
        return when (tool) {
            ToolKind.PEN -> penBrush
            ToolKind.FINGER -> fingerBrush
            ToolKind.ERASER -> penBrush
        }
    }

    private fun eraseStrokes(points: List<ImmutableVec>) {
        if (points.size < 2 || finishedStrokes.isEmpty()) {
            return
        }

        val strokeEntries = finishedStrokes.entries.toList()
        val toRemove = mutableSetOf<InProgressStrokeId>()
        val eraserRadius = max(dpToPx(brushConfig.eraserSize), 1f) / 2f

        for (i in 0 until points.size - 1) {
            val start = points[i]
            val end = points[i + 1]
            val segment = ImmutableSegment(start, end)
            val segMinX = min(start.x, end.x) - eraserRadius
            val segMaxX = max(start.x, end.x) + eraserRadius
            val segMinY = min(start.y, end.y) - eraserRadius
            val segMaxY = max(start.y, end.y) + eraserRadius

            for ((id, stroke) in strokeEntries) {
                if (id in toRemove) continue
                val box = stroke.shape.computeBoundingBox() ?: continue
                if (
                    segMaxX < box.xMin ||
                        segMinX > box.xMax ||
                        segMaxY < box.yMin ||
                        segMinY > box.yMax
                ) {
                    continue
                }
                if (segment.intersects(stroke.shape, AffineTransform.IDENTITY)) {
                    toRemove.add(id)
                }
            }
        }

        if (toRemove.isNotEmpty()) {
            inkView.removeFinishedStrokes(toRemove)
            toRemove.forEach { finishedStrokes.remove(it) }
            invalidate()
        }
    }

    private fun reportTool(tool: ToolKind) {
        if (tool != lastTool) {
            lastTool = tool
            onToolChanged?.invoke(tool)
        }
    }

    private fun toolKindFor(event: MotionEvent, pointerIndex: Int): ToolKind {
        return when (event.getToolType(pointerIndex)) {
            MotionEvent.TOOL_TYPE_ERASER -> ToolKind.ERASER
            MotionEvent.TOOL_TYPE_STYLUS -> ToolKind.PEN
            MotionEvent.TOOL_TYPE_FINGER -> ToolKind.FINGER
            MotionEvent.TOOL_TYPE_MOUSE -> ToolKind.PEN
            else -> brushConfig.tool
        }
    }

    private fun buildPenBrush(config: BrushConfig): Brush {
        val sizePx = dpToPx(config.size)
        val epsilon = min(sizePx * 0.1f, sizePx)
        return Brush.createWithColorIntArgb(
            StockBrushes.pressurePen(),
            config.color,
            sizePx,
            max(epsilon, 0.1f),
        )
    }

    private fun buildFingerBrush(config: BrushConfig): Brush {
        val sizePx = dpToPx(config.size)
        val epsilon = min(sizePx * 0.1f, sizePx)
        return Brush.createWithColorIntArgb(
            StockBrushes.marker(),
            config.color,
            sizePx,
            max(epsilon, 0.1f),
        )
    }

    private fun dpToPx(dp: Float): Float {
        val density = context.resources.displayMetrics.density
        return dp * density
    }
}
