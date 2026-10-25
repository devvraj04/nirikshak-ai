package com.example.nirikshak_mobile

import android.content.Context
import android.graphics.*
import android.graphics.drawable.GradientDrawable
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import kotlin.concurrent.thread

/**
 * Native floating bottom summary overlay with a frosted translucent glassmorphism aesthetic.
 * Persists seamlessly over external apps (e.g. Blinkit, Zepto, Amazon, Swiggy Instamart).
 *
 * Features:
 * 1. Semi-transparent glass card (allows underlying shopping app to remain visible).
 * 2. Multi-angle slots (Front, Back, Nutrition, Ingredients - up to 4 angles).
 * 3. Instant OCR entity chips (Brand, MRP, Net Qty) extracted in background.
 * 4. "+ Add Angle" button to snap the next packaging face without leaving the current shopping screen.
 * 5. "🚀 Proceed to Review" button that launches Nirikshak App ONLY when clicked!
 */
class BottomSummaryOverlayView(
    context: Context,
    private val onAddMoreClicked: () -> Unit,
    private val onProceedToReviewClicked: (List<File>) -> Unit,
    private val onDismissClicked: () -> Unit
) : FrameLayout(context) {

    private val stagedAngleFiles = mutableListOf<File>()
    private val slotFrames = mutableListOf<FrameLayout>()
    private val slotImageViews = mutableListOf<ImageView>()
    private val slotBadgeViews = mutableListOf<TextView>()

    private lateinit var contentCard: LinearLayout
    private lateinit var countBadge: TextView
    private lateinit var entitiesContainer: LinearLayout
    private lateinit var statusText: TextView
    private lateinit var proceedButton: TextView

    private val slotTitles = listOf("Front", "Back", "Nutrition", "Ingredients")

    init {
        setupLayout()
    }

    private fun setupLayout() {
        val density = resources.displayMetrics.density

        // Translucent Glassmorphism Card Container
        contentCard = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            val padH = (14 * density).toInt()
            setPadding(padH, (10 * density).toInt(), padH, (14 * density).toInt())

            // Translucent frosted glass effect: 60% opacity dark slate with emerald glowing rim
            background = GradientDrawable().apply {
                setColor(Color.argb(160, 15, 23, 42)) // Semi-transparent Slate 900
                cornerRadius = 24 * density
                setStroke((1.5 * density).toInt(), Color.argb(110, 52, 211, 153)) // Soft emerald neon border
            }
            elevation = 16f
        }

        // Top drag handle
        val handle = View(context).apply {
            background = GradientDrawable().apply {
                setColor(Color.argb(140, 148, 163, 184))
                cornerRadius = 2 * density
            }
        }
        val handleParams = LinearLayout.LayoutParams((36 * density).toInt(), (3.5 * density).toInt()).apply {
            gravity = Gravity.CENTER_HORIZONTAL
            bottomMargin = (8 * density).toInt()
        }
        contentCard.addView(handle, handleParams)

        // Header Row: Logo, Title, Staged Count Badge, Dismiss
        val headerRow = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }

        val logoIcon = ImageView(context).apply {
            try {
                val resId = resources.getIdentifier("nirikshak_logo", "drawable", context.packageName)
                if (resId != 0) setImageResource(resId) else setImageResource(R.mipmap.ic_launcher)
            } catch (_: Exception) {
                setImageResource(R.mipmap.ic_launcher)
            }
            scaleType = ImageView.ScaleType.CENTER_CROP
        }
        val logoParams = LinearLayout.LayoutParams((22 * density).toInt(), (22 * density).toInt()).apply {
            rightMargin = (8 * density).toInt()
        }
        headerRow.addView(logoIcon, logoParams)

        val titleTv = TextView(context).apply {
            text = "Packaging Capture Summary"
            setTextColor(Color.WHITE)
            textSize = 13f
            typeface = Typeface.DEFAULT_BOLD
        }
        headerRow.addView(titleTv, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))

        countBadge = TextView(context).apply {
            text = "0 / 4"
            setTextColor(Color.parseColor("#34D399"))
            textSize = 11f
            typeface = Typeface.DEFAULT_BOLD
            setPadding((8 * density).toInt(), (3 * density).toInt(), (8 * density).toInt(), (3 * density).toInt())
            background = GradientDrawable().apply {
                setColor(Color.argb(150, 30, 41, 59))
                cornerRadius = 10 * density
                setStroke(1, Color.argb(90, 52, 211, 153))
            }
        }
        val countParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply {
            rightMargin = (8 * density).toInt()
        }
        headerRow.addView(countBadge, countParams)

        val closeBtn = TextView(context).apply {
            text = "✕"
            setTextColor(Color.parseColor("#94A3B8"))
            textSize = 14f
            setPadding((6 * density).toInt(), 0, (4 * density).toInt(), 0)
            setOnClickListener {
                onDismissClicked()
            }
        }
        headerRow.addView(closeBtn)

        contentCard.addView(headerRow)

        // 4 Angle Slots Row
        val slotsRow = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            setPadding(0, (10 * density).toInt(), 0, (8 * density).toInt())
        }

        val slotSize = (60 * density).toInt()
        for (i in 0 until 4) {
            val slotFrame = FrameLayout(context).apply {
                background = GradientDrawable().apply {
                    setColor(Color.argb(120, 30, 41, 59)) // Translucent glass badge
                    cornerRadius = 12 * density
                    setStroke(1, Color.argb(60, 255, 255, 255))
                }
            }
            slotFrames.add(slotFrame)

            val imgView = ImageView(context).apply {
                scaleType = ImageView.ScaleType.CENTER_CROP
                setPadding((2 * density).toInt(), (2 * density).toInt(), (2 * density).toInt(), (2 * density).toInt())
            }
            slotImageViews.add(imgView)
            slotFrame.addView(imgView, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))

            val badge = TextView(context).apply {
                text = "+ ${slotTitles[i]}"
                setTextColor(Color.parseColor("#94A3B8"))
                textSize = 9f
                gravity = Gravity.CENTER
                setPadding((5 * density).toInt(), (2 * density).toInt(), (5 * density).toInt(), (2 * density).toInt())
                background = GradientDrawable().apply {
                    setColor(Color.argb(180, 15, 23, 42))
                    cornerRadius = 6 * density
                }
            }
            slotBadgeViews.add(badge)
            val badgeParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
            ).apply {
                bottomMargin = (4 * density).toInt()
            }
            slotFrame.addView(badge, badgeParams)

            val slotParams = LinearLayout.LayoutParams(slotSize, slotSize).apply {
                if (i > 0) leftMargin = (8 * density).toInt()
            }
            slotsRow.addView(slotFrame, slotParams)
        }
        contentCard.addView(slotsRow)

        // Status / OCR extraction indicator
        statusText = TextView(context).apply {
            text = "✨ Snip up to 4 packaging angles (Front, Back, Nutrition, Ingredients)"
            setTextColor(Color.parseColor("#6EE7B7"))
            textSize = 10.5f
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(0, 0, 0, (6 * density).toInt())
        }
        contentCard.addView(statusText)

        // Chips Container for live OCR entities
        entitiesContainer = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_HORIZONTAL
            visibility = View.GONE
            setPadding(0, 0, 0, (8 * density).toInt())
        }
        contentCard.addView(entitiesContainer)

        // Action Buttons Row
        val btnRow = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }

        // "+ Add Angle" button (Glassmorphism look)
        val addMoreBtn = TextView(context).apply {
            text = "＋ Add Angle"
            setTextColor(Color.WHITE)
            textSize = 12f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setPadding((12 * density).toInt(), (9 * density).toInt(), (12 * density).toInt(), (9 * density).toInt())
            background = GradientDrawable().apply {
                setColor(Color.argb(150, 30, 41, 59))
                cornerRadius = 12 * density
                setStroke((1.2 * density).toInt(), Color.argb(140, 52, 211, 153))
            }
            setOnClickListener {
                onAddMoreClicked()
            }
        }
        val addParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply {
            rightMargin = (8 * density).toInt()
        }
        btnRow.addView(addMoreBtn, addParams)

        // "Proceed to Review in Nirikshak App" button (Glowing Emerald)
        proceedButton = TextView(context).apply {
            text = "🚀 Proceed to Review"
            setTextColor(Color.parseColor("#0F172A"))
            textSize = 12.5f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setPadding((16 * density).toInt(), (9 * density).toInt(), (16 * density).toInt(), (9 * density).toInt())
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#10B981")) // Emerald 500
                cornerRadius = 12 * density
            }
            setOnClickListener {
                if (stagedAngleFiles.isNotEmpty()) {
                    onProceedToReviewClicked(stagedAngleFiles)
                }
            }
        }
        btnRow.addView(proceedButton, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))

        contentCard.addView(btnRow)

        val cardLayoutParams = LayoutParams(
            LayoutParams.MATCH_PARENT,
            LayoutParams.WRAP_CONTENT,
            Gravity.BOTTOM
        ).apply {
            leftMargin = (12 * density).toInt()
            rightMargin = (12 * density).toInt()
            bottomMargin = (14 * density).toInt()
        }
        addView(contentCard, cardLayoutParams)
    }

    /**
     * Adds a newly snipped packaging angle image to the staged list
     * and triggers fast background OCR for live entity chips.
     */
    fun addAngle(file: File) {
        if (stagedAngleFiles.size >= 4) {
            stagedAngleFiles[3] = file
        } else {
            stagedAngleFiles.add(file)
        }

        updateSlotThumbnails()
        fetchQuickOcr(file)
    }

    private fun updateSlotThumbnails() {
        val density = resources.displayMetrics.density
        countBadge.text = "${stagedAngleFiles.size} / 4"

        for (i in 0 until 4) {
            val slotFrame = slotFrames[i]
            val imgView = slotImageViews[i]
            val badge = slotBadgeViews[i]

            if (i < stagedAngleFiles.size) {
                val file = stagedAngleFiles[i]
                try {
                    val bitmap = BitmapFactory.decodeFile(file.absolutePath)
                    imgView.setImageBitmap(bitmap)
                    badge.setTextColor(Color.parseColor("#34D399"))
                    badge.text = "✓ ${slotTitles[i]}"

                    // Highlight frame with glowing emerald rim
                    slotFrame.background = GradientDrawable().apply {
                        setColor(Color.argb(160, 30, 41, 59))
                        cornerRadius = 12 * density
                        setStroke((1.5 * density).toInt(), Color.parseColor("#10B981"))
                    }
                } catch (e: Exception) {
                    imgView.setImageBitmap(null)
                }
            } else {
                imgView.setImageBitmap(null)
                badge.setTextColor(Color.parseColor("#94A3B8"))
                badge.text = "+ ${slotTitles[i]}"

                // Default unfilled subtle glass frame
                slotFrame.background = GradientDrawable().apply {
                    setColor(Color.argb(120, 30, 41, 59))
                    cornerRadius = 12 * density
                    setStroke(1, Color.argb(60, 255, 255, 255))
                }
            }
        }

        if (stagedAngleFiles.isNotEmpty()) {
            statusText.text = "Angle ${stagedAngleFiles.size} captured! Tap '+ Add Angle' or 'Proceed to Review'."
            statusText.setTextColor(Color.parseColor("#34D399"))
        }
    }

    private fun fetchQuickOcr(file: File) {
        statusText.text = "🔍 Extracting packaging declarations..."
        val handler = Handler(Looper.getMainLooper())

        thread {
            try {
                val url = URL("http://127.0.0.1:8080/scans/quick-ocr")
                val conn = url.openConnection() as HttpURLConnection
                conn.requestMethod = "POST"
                conn.connectTimeout = 8000
                conn.readTimeout = 15000
                conn.doOutput = true

                val boundary = "==NirikshakBoundary==" + System.currentTimeMillis()
                conn.setRequestProperty("Content-Type", "multipart/form-data; boundary=$boundary")

                val out = conn.outputStream
                val writer = out.bufferedWriter()

                writer.write("--$boundary\r\n")
                writer.write("Content-Disposition: form-data; name=\"file\"; filename=\"${file.name}\"\r\n")
                writer.write("Content-Type: image/jpeg\r\n\r\n")
                writer.flush()

                file.inputStream().use { input ->
                    input.copyTo(out)
                }
                out.flush()

                writer.write("\r\n--$boundary--\r\n")
                writer.flush()
                writer.close()

                val respCode = conn.responseCode
                if (respCode == 200) {
                    val respText = conn.inputStream.bufferedReader().use { it.readText() }
                    val json = JSONObject(respText)
                    val entities = json.optJSONObject("entities")

                    handler.post {
                        renderEntities(entities)
                    }
                } else {
                    handler.post {
                        statusText.text = "Angle ${stagedAngleFiles.size} ready. Click Proceed to Review."
                    }
                }
                conn.disconnect()
            } catch (e: Exception) {
                handler.post {
                    statusText.text = "Angle ${stagedAngleFiles.size} ready for review."
                }
            }
        }
    }

    private fun renderEntities(entities: JSONObject?) {
        if (entities == null || entities.length() == 0) {
            statusText.text = "Angle captured! Proceed to Review or add more angles."
            return
        }

        entitiesContainer.removeAllViews()
        entitiesContainer.visibility = View.VISIBLE
        val density = resources.displayMetrics.density

        val keysToShow = listOf("product_name", "brand", "mrp", "net_quantity")
        var chipCount = 0

        for (k in keysToShow) {
            val v = entities.opt(k)
            if (v != null && v.toString().isNotBlank() && v.toString() != "null") {
                val label = when (k) {
                    "product_name" -> "🏷️ $v"
                    "brand" -> "🏢 $v"
                    "mrp" -> "₹ $v"
                    "net_quantity" -> "⚖️ $v"
                    else -> "$k: $v"
                }

                val chip = TextView(context).apply {
                    text = label
                    setTextColor(Color.WHITE)
                    textSize = 9.5f
                    typeface = Typeface.DEFAULT_BOLD
                    setPadding((7 * density).toInt(), (3 * density).toInt(), (7 * density).toInt(), (3 * density).toInt())
                    background = GradientDrawable().apply {
                        setColor(Color.argb(160, 30, 41, 59))
                        cornerRadius = 8 * density
                        setStroke(1, Color.argb(90, 52, 211, 153))
                    }
                }
                val chipParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT
                ).apply {
                    rightMargin = (6 * density).toInt()
                }
                entitiesContainer.addView(chip, chipParams)
                chipCount++
                if (chipCount >= 3) break
            }
        }

        statusText.text = "⚡ Instant OCR match! Ready for compliance review."
        statusText.setTextColor(Color.parseColor("#10B981"))
    }
}
