package com.example.nirikshak_mobile

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageView
import androidx.core.app.NotificationCompat
import kotlin.math.abs

class OverlayBubbleService : Service() {

    private var windowManager: WindowManager? = null
    private var bubbleView: View? = null
    private var params: WindowManager.LayoutParams? = null
    private var activeCircleOverlay: View? = null
    private var activeSummaryOverlay: BottomSummaryOverlayView? = null
    private val stagedAngleFiles = mutableListOf<java.io.File>()

    companion object {
        const val CHANNEL_ID = "nirikshak_overlay_channel"
        const val NOTIFICATION_ID = 2001
        var isRunning = false
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        isRunning = true
        createNotificationChannel()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                buildForegroundNotification(),
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            )
        } else {
            startForeground(NOTIFICATION_ID, buildForegroundNotification())
        }

        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        initFloatingBubble()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Nirikshak Floating Assistant",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Active floating extension for instant Circle-to-Search compliance audits"
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }
    }

    private fun buildForegroundNotification(): Notification {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this, 0, launchIntent,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Nirikshak AI Assistant Active")
            .setContentText("Tap overlay on any shopping app for instant Circle-to-Search audit")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun initFloatingBubble() {
        val layoutType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        val sizePx = (58 * resources.displayMetrics.density).toInt()

        params = WindowManager.LayoutParams(
            sizePx,
            sizePx,
            layoutType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = 24
            y = 350
        }

        // Circular root container with glowing emerald border
        val frameLayout = FrameLayout(this).apply {
            val bg = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#0F172A")) // Slate 900
                setStroke((2.5 * resources.displayMetrics.density).toInt(), Color.parseColor("#10B981")) // Emerald 500
            }
            background = bg
            elevation = 16f
        }

        // Inner Nirikshak Logo ImageView
        val logoImageView = ImageView(this).apply {
            val padding = (4 * resources.displayMetrics.density).toInt()
            setPadding(padding, padding, padding, padding)
            scaleType = ImageView.ScaleType.CENTER_CROP

            // Load nirikshak_logo from drawable
            try {
                val resId = resources.getIdentifier("nirikshak_logo", "drawable", packageName)
                if (resId != 0) {
                    setImageResource(resId)
                } else {
                    setImageResource(R.mipmap.ic_launcher)
                }
            } catch (e: Exception) {
                setImageResource(R.mipmap.ic_launcher)
            }

            // Clip to circle
            outlineProvider = object : android.view.ViewOutlineProvider() {
                override fun getOutline(view: View, outline: android.graphics.Outline) {
                    outline.setOval(0, 0, view.width, view.height)
                }
            }
            clipToOutline = true
        }

        val innerParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT,
            Gravity.CENTER
        )
        frameLayout.addView(logoImageView, innerParams)

        bubbleView = frameLayout

        // Draggable touch listener with edge-snapping and tap detection
        frameLayout.setOnTouchListener(object : View.OnTouchListener {
            private var initialX = 0
            private var initialY = 0
            private var initialTouchX = 0f
            private var initialTouchY = 0f
            private val touchSlop = 10 * resources.displayMetrics.density

            override fun onTouch(v: View, event: MotionEvent): Boolean {
                val curParams = params ?: return false
                when (event.action) {
                    MotionEvent.ACTION_DOWN -> {
                        initialX = curParams.x
                        initialY = curParams.y
                        initialTouchX = event.rawX
                        initialTouchY = event.rawY
                        return true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        curParams.x = initialX + (event.rawX - initialTouchX).toInt()
                        curParams.y = initialY + (event.rawY - initialTouchY).toInt()
                        windowManager?.updateViewLayout(bubbleView, curParams)
                        return true
                    }
                    MotionEvent.ACTION_UP -> {
                        val dx = abs(event.rawX - initialTouchX)
                        val dy = abs(event.rawY - initialTouchY)

                        if (dx < touchSlop && dy < touchSlop) {
                            // TAP DETECTED: Take screenshot of current page & show Circle-to-Search over it
                            onBubbleClicked()
                        } else {
                            // DRAG FINISHED: Snap to nearest screen edge (left or right)
                            val screenWidth = resources.displayMetrics.widthPixels
                            val snapTarget = if (event.rawX < screenWidth / 2) 20 else (screenWidth - sizePx - 20)
                            curParams.x = snapTarget
                            windowManager?.updateViewLayout(bubbleView, curParams)
                        }
                        return true
                    }
                }
                return false
            }
        })

        try {
            windowManager?.addView(bubbleView, params)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun onBubbleClicked() {
        if (activeCircleOverlay != null) {
            return
        }

        // If user already captured angles and summary overlay exists, clicking bubble can toggle summary view
        if (activeSummaryOverlay != null && stagedAngleFiles.isNotEmpty()) {
            if (activeSummaryOverlay?.visibility == View.VISIBLE) {
                // Take another angle screenshot
                performScreenCaptureAndShowOverlay()
            } else {
                activeSummaryOverlay?.visibility = View.VISIBLE
            }
            return
        }

        performScreenCaptureAndShowOverlay()
    }

    private fun performScreenCaptureAndShowOverlay() {
        if (!ScreenCaptureManager.isReady()) {
            // Request MediaProjection permission via transparent activity
            ScreenCapturePermissionActivity.onPermissionResult = { resultCode, data ->
                if (resultCode == Activity.RESULT_OK && data != null) {
                    ScreenCaptureManager.setPermissionResult(resultCode, data)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        startForeground(
                            NOTIFICATION_ID,
                            buildForegroundNotification(),
                            android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE or
                                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
                        )
                    }
                    performScreenCaptureAndShowOverlay()
                }
            }
            val intent = Intent(this, ScreenCapturePermissionActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            startActivity(intent)
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                buildForegroundNotification(),
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE or
                    android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
            )
        }

        // Hide bubble temporarily so it's not captured in screenshot
        bubbleView?.visibility = View.INVISIBLE

        Handler(Looper.getMainLooper()).postDelayed({
            ScreenCaptureManager.captureScreenshot(this) { bitmap ->
                bubbleView?.visibility = View.VISIBLE

                if (bitmap != null) {
                    showCircleToSearchCanvas(bitmap)
                } else if (!ScreenCaptureManager.isReady()) {
                    // Session died or revoked, re-prompt permission seamlessly
                    ScreenCapturePermissionActivity.onPermissionResult = { resultCode, data ->
                        if (resultCode == Activity.RESULT_OK && data != null) {
                            ScreenCaptureManager.setPermissionResult(resultCode, data)
                            performScreenCaptureAndShowOverlay()
                        }
                    }
                    val intent = Intent(this, ScreenCapturePermissionActivity::class.java).apply {
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    }
                    startActivity(intent)
                }
            }
        }, 50)
    }

    private fun showCircleToSearchCanvas(bitmap: Bitmap) {
        val wm = windowManager ?: return

        // Hide summary overlay if it was showing so user has a clean canvas
        activeSummaryOverlay?.visibility = View.GONE

        val overlayView = CircleToSearchOverlayView(
            context = this,
            screenshotBitmap = bitmap,
            windowManager = wm,
            stagedAngleCount = stagedAngleFiles.size,
            onDismiss = {
                dismissCircleOverlay()
                // Restore summary overlay if we have staged images
                if (stagedAngleFiles.isNotEmpty()) {
                    activeSummaryOverlay?.visibility = View.VISIBLE
                }
            },
            onSnipReady = { snipFile ->
                dismissCircleOverlay()
                // DO NOT navigate away from the shopping app!
                // Add the snipped angle into our persistent bottom summary overlay
                stagedAngleFiles.add(snipFile)
                showOrUpdateBottomSummaryOverlay(snipFile)
            }
        )

        val layoutType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        val overlayParams = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            layoutType,
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        )

        try {
            wm.addView(overlayView, overlayParams)
            activeCircleOverlay = overlayView
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun showOrUpdateBottomSummaryOverlay(newFile: java.io.File?) {
        val wm = windowManager ?: return

        if (activeSummaryOverlay == null) {
            val summaryView = BottomSummaryOverlayView(
                context = this,
                onAddMoreClicked = {
                    // Tap "+ Add Angle": dismiss canvas/minimize and allow user to circle next packaging face
                    dismissCircleOverlay()
                    performScreenCaptureAndShowOverlay()
                },
                onProceedToReviewClicked = { files ->
                    // ONLY here do we launch MainActivity to open the review screen!
                    dismissSummaryOverlay()
                    val launchIntent = Intent(this, MainActivity::class.java).apply {
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                        putExtra("action", "circle_to_search_review_ready")
                        putStringArrayListExtra("staged_paths", ArrayList(files.map { it.absolutePath }))
                    }
                    startActivity(launchIntent)
                },
                onDismissClicked = {
                    dismissSummaryOverlay()
                }
            )

            val layoutType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            }

            val summaryParams = WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.WRAP_CONTENT,
                layoutType,
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                    WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH,
                PixelFormat.TRANSLUCENT
            ).apply {
                gravity = Gravity.BOTTOM
            }

            try {
                wm.addView(summaryView, summaryParams)
                activeSummaryOverlay = summaryView
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }

        activeSummaryOverlay?.visibility = View.VISIBLE
        if (newFile != null) {
            activeSummaryOverlay?.addAngle(newFile)
        }
    }

    private fun dismissSummaryOverlay() {
        if (activeSummaryOverlay != null) {
            try {
                windowManager?.removeView(activeSummaryOverlay)
            } catch (_: Exception) {}
            activeSummaryOverlay = null
        }
        stagedAngleFiles.clear()
    }

    private fun dismissCircleOverlay() {
        if (activeCircleOverlay != null) {
            try {
                windowManager?.removeView(activeCircleOverlay)
            } catch (_: Exception) {}
            activeCircleOverlay = null
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        isRunning = false
        dismissCircleOverlay()
        dismissSummaryOverlay()
        ScreenCaptureManager.releaseSession()
        if (bubbleView != null) {
            windowManager?.removeView(bubbleView)
            bubbleView = null
        }
    }
}
