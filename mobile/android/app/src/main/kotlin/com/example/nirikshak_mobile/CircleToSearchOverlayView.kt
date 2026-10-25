package com.example.nirikshak_mobile

import android.content.Context
import android.graphics.*
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import java.io.File
import java.io.FileOutputStream
import kotlin.math.max
import kotlin.math.min

enum class SelectionMode {
    CIRCLE,
    BOX,
    LASSO
}

class CircleToSearchOverlayView(
    context: Context,
    private val screenshotBitmap: Bitmap,
    private val windowManager: WindowManager,
    private val stagedAngleCount: Int = 0,
    private val onDismiss: () -> Unit,
    private val onSnipReady: (File) -> Unit
) : FrameLayout(context) {

    private var currentMode = SelectionMode.BOX

    // Lasso state
    private val lassoPath = Path()
    private val lassoPoints = mutableListOf<PointF>()

    // Box / Circle drag state
    private var startX = 0f
    private var startY = 0f
    private var currentX = 0f
    private var currentY = 0f
    private var isDrawing = false
    private var croppedSnipFile: File? = null

    // UI elements
    private lateinit var canvasDrawingView: View
    private lateinit var topToolbarContainer: LinearLayout
    private lateinit var topHintText: TextView
    private lateinit var bottomReviewCard: LinearLayout
    private lateinit var snipThumbnail: ImageView
    private lateinit var stageSubtitle: TextView

    // Mode tab buttons
    private lateinit var btnCircle: TextView
    private lateinit var btnBox: TextView
    private lateinit var btnLasso: TextView

    // Glow paints
    private val outerGlowPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 14f * resources.displayMetrics.density
        color = Color.parseColor("#34D399")
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
        maskFilter = BlurMaskFilter(16f, BlurMaskFilter.Blur.NORMAL)
    }

    private val innerStrokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 3.5f * resources.displayMetrics.density
        color = Color.WHITE
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }

    private val dimPaint = Paint().apply {
        color = Color.argb(110, 15, 23, 42) // Slate 900 45% translucent veil
    }

    private val clearHolePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        xfermode = PorterDuffXfermode(PorterDuff.Mode.CLEAR)
    }

    init {
        setupViews()
    }

    private fun setupViews() {
        val density = resources.displayMetrics.density

        // 1. Fullscreen Drawing Canvas
        canvasDrawingView = object : View(context) {
            init {
                // Required for PorterDuffXfermode CLEAR cutout to work over screenshot
                setLayerType(LAYER_TYPE_SOFTWARE, null)
            }

            override fun onDraw(canvas: Canvas) {
                super.onDraw(canvas)

                // Draw frozen screenshot of underlying app
                canvas.drawBitmap(screenshotBitmap, 0f, 0f, null)

                // Draw dim translucent veil
                canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), dimPaint)

                if (!isDrawing && lassoPoints.isEmpty()) {
                    return
                }

                when (currentMode) {
                    SelectionMode.BOX -> {
                        val left = min(startX, currentX)
                        val top = min(startY, currentY)
                        val right = max(startX, currentX)
                        val bottom = max(startY, currentY)
                        val rect = RectF(left, top, right, bottom)

                        if (rect.width() > 5 && rect.height() > 5) {
                            // Cutout transparent spotlight through dim layer
                            canvas.drawRoundRect(rect, 14 * density, 14 * density, clearHolePaint)
                            // Glowing illuminated border
                            canvas.drawRoundRect(rect, 14 * density, 14 * density, outerGlowPaint)
                            canvas.drawRoundRect(rect, 14 * density, 14 * density, innerStrokePaint)
                        }
                    }
                    SelectionMode.CIRCLE -> {
                        val left = min(startX, currentX)
                        val top = min(startY, currentY)
                        val right = max(startX, currentX)
                        val bottom = max(startY, currentY)
                        val rect = RectF(left, top, right, bottom)

                        if (rect.width() > 5 && rect.height() > 5) {
                            // Cutout transparent spotlight through dim layer
                            canvas.drawOval(rect, clearHolePaint)
                            // Glowing illuminated oval
                            canvas.drawOval(rect, outerGlowPaint)
                            canvas.drawOval(rect, innerStrokePaint)
                        }
                    }
                    SelectionMode.LASSO -> {
                        if (lassoPoints.size > 1) {
                            canvas.drawPath(lassoPath, outerGlowPaint)
                            canvas.drawPath(lassoPath, innerStrokePaint)
                        }
                    }
                }
            }

            override fun onTouchEvent(event: MotionEvent): Boolean {
                if (bottomReviewCard.visibility == View.VISIBLE) {
                    return false
                }

                val x = event.x
                val y = event.y

                when (event.action) {
                    MotionEvent.ACTION_DOWN -> {
                        isDrawing = true
                        startX = x
                        startY = y
                        currentX = x
                        currentY = y

                        if (currentMode == SelectionMode.LASSO) {
                            lassoPath.reset()
                            lassoPath.moveTo(x, y)
                            lassoPoints.clear()
                            lassoPoints.add(PointF(x, y))
                        }
                        invalidate()
                        return true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        if (isDrawing) {
                            currentX = x
                            currentY = y
                            if (currentMode == SelectionMode.LASSO) {
                                lassoPath.lineTo(x, y)
                                lassoPoints.add(PointF(x, y))
                            }
                            invalidate()
                        }
                        return true
                    }
                    MotionEvent.ACTION_UP -> {
                        if (isDrawing) {
                            isDrawing = false
                            currentX = x
                            currentY = y
                            if (currentMode == SelectionMode.LASSO) {
                                lassoPath.close()
                            }
                            invalidate()
                            handleSelectionCompleted()
                        }
                        return true
                    }
                }
                return super.onTouchEvent(event)
            }
        }
        addView(canvasDrawingView, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))

        // 2. Sleek Top Mode Selector Toolbar Container
        topToolbarContainer = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
        }

        val modePill = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding((6 * density).toInt(), (5 * density).toInt(), (10 * density).toInt(), (5 * density).toInt())

            // Translucent glassmorphism pill background
            background = GradientDrawable().apply {
                setColor(Color.argb(210, 15, 23, 42)) // Slate 900 82%
                cornerRadius = 28 * density
                setStroke((1.5 * density).toInt(), Color.argb(120, 52, 211, 153))
            }
            elevation = 16f
        }

        // Mode buttons: Circle, Box, Lasso
        btnCircle = createModeButton("⭕ Circle", SelectionMode.CIRCLE)
        btnBox = createModeButton("🔲 Box", SelectionMode.BOX)
        btnLasso = createModeButton("✏️ Lasso", SelectionMode.LASSO)

        modePill.addView(btnCircle)
        modePill.addView(btnBox)
        modePill.addView(btnLasso)

        // Divider
        val divider = View(context).apply {
            background = GradientDrawable().apply {
                setColor(Color.argb(80, 148, 163, 184))
            }
        }
        val divParams = LinearLayout.LayoutParams((1 * density).toInt(), (18 * density).toInt()).apply {
            leftMargin = (8 * density).toInt()
            rightMargin = (8 * density).toInt()
        }
        modePill.addView(divider, divParams)

        // Dismiss X button
        val closeBtn = TextView(context).apply {
            text = "✕"
            setTextColor(Color.parseColor("#94A3B8"))
            textSize = 14f
            gravity = Gravity.CENTER
            setPadding((6 * density).toInt(), (4 * density).toInt(), (6 * density).toInt(), (4 * density).toInt())
            setOnClickListener { onDismiss() }
        }
        modePill.addView(closeBtn)

        topToolbarContainer.addView(modePill)

        // Dynamic hint subtitle below pill
        topHintText = TextView(context).apply {
            text = "✨ Drag to box packaging or declaration"
            setTextColor(Color.parseColor("#A7F3D0"))
            textSize = 11.5f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setShadowLayer(4f, 0f, 1f, Color.BLACK)
            setPadding(0, (8 * density).toInt(), 0, 0)
        }
        topToolbarContainer.addView(topHintText)

        val topParams = LayoutParams(
            LayoutParams.WRAP_CONTENT,
            LayoutParams.WRAP_CONTENT,
            Gravity.TOP or Gravity.CENTER_HORIZONTAL
        ).apply {
            topMargin = (52 * density).toInt()
        }
        addView(topToolbarContainer, topParams)

        updateModeTabStyles()

        // 3. Floating Bottom Review Card (Translucent Glassmorphism)
        bottomReviewCard = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            visibility = View.GONE
            setPadding((16 * density).toInt(), (14 * density).toInt(), (16 * density).toInt(), (18 * density).toInt())

            // Translucent glass card background
            background = GradientDrawable().apply {
                setColor(Color.argb(215, 15, 23, 42)) // Translucent Slate 900
                cornerRadius = 24 * density
                setStroke((2 * density).toInt(), Color.argb(140, 16, 185, 129)) // Glowing emerald border
            }
            elevation = 20f

            // Top drag handle
            val handle = View(context).apply {
                background = GradientDrawable().apply {
                    setColor(Color.parseColor("#475569"))
                    cornerRadius = 2 * density
                }
            }
            val handleParams = LinearLayout.LayoutParams((36 * density).toInt(), (4 * density).toInt()).apply {
                gravity = Gravity.CENTER_HORIZONTAL
                bottomMargin = (12 * density).toInt()
            }
            addView(handle, handleParams)

            // Header row with thumbnail and title
            val headerRow = LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
            }

            snipThumbnail = ImageView(context).apply {
                scaleType = ImageView.ScaleType.CENTER_CROP
                background = GradientDrawable().apply {
                    setColor(Color.argb(160, 30, 41, 59))
                    cornerRadius = 12 * density
                    setStroke(1, Color.argb(120, 52, 211, 153))
                }
            }
            val thumbParams = LinearLayout.LayoutParams((56 * density).toInt(), (56 * density).toInt()).apply {
                rightMargin = (12 * density).toInt()
            }
            headerRow.addView(snipThumbnail, thumbParams)

            val titleCol = LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
            }
            val titleTv = TextView(context).apply {
                text = "Packaging Angle Snipped"
                setTextColor(Color.WHITE)
                textSize = 14f
                typeface = Typeface.DEFAULT_BOLD
            }
            stageSubtitle = TextView(context).apply {
                text = "Angle ${stagedAngleCount + 1} of 4 ready for compliance review"
                setTextColor(Color.parseColor("#34D399"))
                textSize = 11.5f
            }
            titleCol.addView(titleTv)
            titleCol.addView(stageSubtitle)
            headerRow.addView(titleCol, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))

            addView(headerRow)

            // Spacing
            val sep = View(context)
            addView(sep, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, (12 * density).toInt()))

            // Button Row
            val btnRow = LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
            }

            // Add to Summary Button (Vibrant Emerald)
            val submitBtn = TextView(context).apply {
                text = "✓ Add Angle to Summary"
                setTextColor(Color.parseColor("#0F172A"))
                textSize = 12.5f
                typeface = Typeface.DEFAULT_BOLD
                gravity = Gravity.CENTER
                setPadding((14 * density).toInt(), (10 * density).toInt(), (14 * density).toInt(), (10 * density).toInt())
                background = GradientDrawable().apply {
                    setColor(Color.parseColor("#10B981"))
                    cornerRadius = 12 * density
                }
                setOnClickListener {
                    val file = croppedSnipFile
                    if (file != null) {
                        onSnipReady(file)
                    }
                }
            }
            val submitParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1.4f).apply {
                rightMargin = (8 * density).toInt()
            }
            btnRow.addView(submitBtn, submitParams)

            // Redraw Button (Allows retaking immediately)
            val redrawBtn = TextView(context).apply {
                text = "↺ Redraw"
                setTextColor(Color.parseColor("#E2E8F0"))
                textSize = 12f
                typeface = Typeface.DEFAULT_BOLD
                gravity = Gravity.CENTER
                setPadding((12 * density).toInt(), (10 * density).toInt(), (12 * density).toInt(), (10 * density).toInt())
                background = GradientDrawable().apply {
                    setColor(Color.argb(160, 30, 41, 59))
                    cornerRadius = 12 * density
                    setStroke(1, Color.argb(100, 148, 163, 184))
                }
                setOnClickListener {
                    resetDrawingState()
                }
            }
            val redrawParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                rightMargin = (8 * density).toInt()
            }
            btnRow.addView(redrawBtn, redrawParams)

            // Cancel Button
            val cancelBtn = TextView(context).apply {
                text = "Cancel"
                setTextColor(Color.parseColor("#94A3B8"))
                textSize = 12f
                gravity = Gravity.CENTER
                setPadding((10 * density).toInt(), (10 * density).toInt(), (10 * density).toInt(), (10 * density).toInt())
                background = GradientDrawable().apply {
                    setColor(Color.argb(120, 15, 23, 42))
                    cornerRadius = 12 * density
                    setStroke(1, Color.argb(80, 71, 85, 105))
                }
                setOnClickListener { onDismiss() }
            }
            btnRow.addView(cancelBtn)

            addView(btnRow)
        }

        val cardParams = LayoutParams(
            LayoutParams.MATCH_PARENT,
            LayoutParams.WRAP_CONTENT,
            Gravity.BOTTOM
        ).apply {
            leftMargin = (16 * density).toInt()
            rightMargin = (16 * density).toInt()
            bottomMargin = (32 * density).toInt()
        }
        addView(bottomReviewCard, cardParams)
    }

    private fun createModeButton(label: String, mode: SelectionMode): TextView {
        val density = resources.displayMetrics.density
        return TextView(context).apply {
            text = label
            textSize = 12f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setPadding((12 * density).toInt(), (6 * density).toInt(), (12 * density).toInt(), (6 * density).toInt())
            setOnClickListener {
                if (currentMode != mode) {
                    currentMode = mode
                    updateModeTabStyles()
                    resetDrawingState()
                }
            }
        }
    }

    private fun updateModeTabStyles() {
        val density = resources.displayMetrics.density

        fun applyTabStyle(tv: TextView, isSelected: Boolean) {
            if (isSelected) {
                tv.setTextColor(Color.parseColor("#0F172A"))
                tv.background = GradientDrawable().apply {
                    setColor(Color.parseColor("#10B981"))
                    cornerRadius = 20 * density
                }
            } else {
                tv.setTextColor(Color.parseColor("#CBD5E1"))
                tv.background = null
            }
        }

        applyTabStyle(btnCircle, currentMode == SelectionMode.CIRCLE)
        applyTabStyle(btnBox, currentMode == SelectionMode.BOX)
        applyTabStyle(btnLasso, currentMode == SelectionMode.LASSO)

        topHintText.text = when (currentMode) {
            SelectionMode.BOX -> "✨ Drag to box packaging or declaration"
            SelectionMode.CIRCLE -> "✨ Drag to circle packaging / symbol"
            SelectionMode.LASSO -> "✨ Draw freehand contour around packaging"
        }
    }

    private fun resetDrawingState() {
        lassoPath.reset()
        lassoPoints.clear()
        startX = 0f
        startY = 0f
        currentX = 0f
        currentY = 0f
        isDrawing = false
        croppedSnipFile = null

        bottomReviewCard.visibility = View.GONE
        topToolbarContainer.visibility = View.VISIBLE
        canvasDrawingView.invalidate()
    }

    private fun handleSelectionCompleted() {
        val padding = 16 * resources.displayMetrics.density
        var left = 0
        var top = 0
        var right = 0
        var bottom = 0

        when (currentMode) {
            SelectionMode.BOX, SelectionMode.CIRCLE -> {
                val minX = min(startX, currentX)
                val minY = min(startY, currentY)
                val maxX = max(startX, currentX)
                val maxY = max(startY, currentY)

                if ((maxX - minX) < 25 || (maxY - minY) < 25) {
                    resetDrawingState()
                    return
                }

                left = max(0, (minX - padding).toInt())
                top = max(0, (minY - padding).toInt())
                right = min(screenshotBitmap.width, (maxX + padding).toInt())
                bottom = min(screenshotBitmap.height, (maxY + padding).toInt())
            }
            SelectionMode.LASSO -> {
                if (lassoPoints.size < 5) {
                    resetDrawingState()
                    return
                }

                val bounds = RectF()
                lassoPath.computeBounds(bounds, true)

                if (bounds.width() < 25 || bounds.height() < 25) {
                    resetDrawingState()
                    return
                }

                left = max(0, (bounds.left - padding).toInt())
                top = max(0, (bounds.top - padding).toInt())
                right = min(screenshotBitmap.width, (bounds.right + padding).toInt())
                bottom = min(screenshotBitmap.height, (bounds.bottom + padding).toInt())
            }
        }

        val width = right - left
        val height = bottom - top

        if (width <= 10 || height <= 10) {
            resetDrawingState()
            return
        }

        try {
            val croppedBitmap = Bitmap.createBitmap(screenshotBitmap, left, top, width, height)

            val file = File(context.cacheDir, "snip_${System.currentTimeMillis()}.png")
            FileOutputStream(file).use { out ->
                croppedBitmap.compress(Bitmap.CompressFormat.PNG, 95, out)
            }
            croppedSnipFile = file

            snipThumbnail.setImageBitmap(croppedBitmap)
            topToolbarContainer.visibility = View.GONE
            bottomReviewCard.visibility = View.VISIBLE
        } catch (e: Exception) {
            e.printStackTrace()
            resetDrawingState()
        }
    }
}
