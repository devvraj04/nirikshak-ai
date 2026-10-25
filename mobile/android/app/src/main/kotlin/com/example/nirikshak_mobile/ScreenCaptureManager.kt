package com.example.nirikshak_mobile

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.Image
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.DisplayMetrics
import android.view.WindowManager

object ScreenCaptureManager {
    var mediaProjectionResultCode: Int = 0
    var mediaProjectionData: Intent? = null
    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
    private var pendingCallback: ((Bitmap?) -> Unit)? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var isCapturing = false

    fun isReady(): Boolean = mediaProjection != null || (mediaProjectionData != null && mediaProjectionResultCode != 0)

    fun setPermissionResult(resultCode: Int, data: Intent?) {
        mediaProjectionResultCode = resultCode
        mediaProjectionData = data
        releaseSession()
    }

    fun releaseSession() {
        pendingCallback?.invoke(null)
        pendingCallback = null
        try {
            imageReader?.setOnImageAvailableListener(null, null)
            virtualDisplay?.release()
            imageReader?.close()
            mediaProjection?.stop()
        } catch (_: Exception) {}
        virtualDisplay = null
        imageReader = null
        mediaProjection = null
        isCapturing = false
    }

    private fun ensureSession(context: Context): Boolean {
        if (mediaProjection != null && virtualDisplay != null && imageReader != null) {
            return true
        }
        val data = mediaProjectionData ?: return false
        val mgr = context.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as? MediaProjectionManager
            ?: return false

        try {
            if (mediaProjection == null) {
                val proj = mgr.getMediaProjection(mediaProjectionResultCode, data) ?: return false
                proj.registerCallback(object : MediaProjection.Callback() {
                    override fun onStop() {
                        releaseSession()
                        mediaProjectionData = null
                    }
                }, mainHandler)
                mediaProjection = proj
            }

            val proj = mediaProjection ?: return false

            val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
            val metrics = DisplayMetrics()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val bounds = wm.currentWindowMetrics.bounds
                metrics.widthPixels = bounds.width()
                metrics.heightPixels = bounds.height()
                metrics.densityDpi = context.resources.configuration.densityDpi
            } else {
                @Suppress("DEPRECATION")
                wm.defaultDisplay.getRealMetrics(metrics)
            }

            val width = metrics.widthPixels
            val height = metrics.heightPixels
            val density = metrics.densityDpi

            if (width <= 0 || height <= 0) return false

            val reader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2)
            imageReader = reader

            reader.setOnImageAvailableListener({ r ->
                val callback = pendingCallback
                if (callback != null) {
                    pendingCallback = null
                    isCapturing = false
                    val bitmap = extractBitmapFromReader(r, width, height)
                    callback(bitmap)
                } else {
                    // Drain buffer so SurfaceFlinger queue never starves
                    try {
                        val img = r.acquireLatestImage()
                        img?.close()
                    } catch (_: Exception) {}
                }
            }, mainHandler)

            virtualDisplay = proj.createVirtualDisplay(
                "NirikshakContinuousMirror",
                width,
                height,
                density,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                reader.surface,
                null,
                mainHandler
            )
            return true
        } catch (e: Exception) {
            e.printStackTrace()
            releaseSession()
            mediaProjectionData = null
            return false
        }
    }

    fun captureScreenshot(context: Context, onResult: (Bitmap?) -> Unit) {
        if (!ensureSession(context)) {
            onResult(null)
            return
        }

        val reader = imageReader
        if (reader == null) {
            onResult(null)
            return
        }

        val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val metrics = DisplayMetrics()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val bounds = wm.currentWindowMetrics.bounds
            metrics.widthPixels = bounds.width()
            metrics.heightPixels = bounds.height()
        } else {
            @Suppress("DEPRECATION")
            wm.defaultDisplay.getRealMetrics(metrics)
        }
        val width = metrics.widthPixels
        val height = metrics.heightPixels

        // First attempt: check if a fresh image is already available in the reader
        val immediateBitmap = try {
            extractBitmapFromReader(reader, width, height)
        } catch (_: Exception) {
            null
        }

        if (immediateBitmap != null) {
            onResult(immediateBitmap)
            return
        }

        // Otherwise, register pending callback and wait for next frame from onImageAvailableListener
        isCapturing = true
        pendingCallback = onResult

        // Timeout fallback after 1200ms
        mainHandler.postDelayed({
            if (pendingCallback != null) {
                val cb = pendingCallback
                pendingCallback = null
                isCapturing = false
                val fallbackBmp = try {
                    extractBitmapFromReader(reader, width, height)
                } catch (_: Exception) {
                    null
                }
                cb?.invoke(fallbackBmp)
            }
        }, 1200)
    }

    private fun extractBitmapFromReader(reader: ImageReader, width: Int, height: Int): Bitmap? {
        var image: Image? = null
        try {
            image = reader.acquireLatestImage() ?: return null
            val planes = image.planes
            val buffer = planes[0].buffer
            val pixelStride = planes[0].pixelStride
            val rowStride = planes[0].rowStride
            val rowPadding = rowStride - pixelStride * width

            val bitmap = Bitmap.createBitmap(
                width + rowPadding / pixelStride,
                height,
                Bitmap.Config.ARGB_8888
            )
            bitmap.copyPixelsFromBuffer(buffer)

            return if (rowPadding == 0) {
                bitmap
            } else {
                val cropped = Bitmap.createBitmap(bitmap, 0, 0, width, height)
                bitmap.recycle()
                cropped
            }
        } catch (e: Exception) {
            e.printStackTrace()
            return null
        } finally {
            image?.close()
        }
    }
}
