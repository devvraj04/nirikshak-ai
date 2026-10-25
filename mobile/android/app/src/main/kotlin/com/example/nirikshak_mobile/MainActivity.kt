package com.example.nirikshak_mobile

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.nirikshak.overlay"
    private var methodChannel: MethodChannel? = null
    private val REQUEST_MEDIA_PROJECTION = 4001

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "isPermissionGranted" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        result.success(Settings.canDrawOverlays(this))
                    } else {
                        result.success(true)
                    }
                }
                "requestPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        val intent = Intent(
                            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:$packageName")
                        ).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        }
                        startActivity(intent)
                        result.success(true)
                    } else {
                        result.success(true)
                    }
                }
                "requestScreenCapturePermission" -> {
                    val mgr = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as? MediaProjectionManager
                    if (mgr != null) {
                        startActivityForResult(mgr.createScreenCaptureIntent(), REQUEST_MEDIA_PROJECTION)
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                "isScreenCaptureReady" -> {
                    result.success(ScreenCaptureManager.isReady())
                }
                "startOverlay" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
                        result.error("PERMISSION_DENIED", "Overlay permission not granted", null)
                        return@setMethodCallHandler
                    }
                    val intent = Intent(this, OverlayBubbleService::class.java)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(true)
                }
                "stopOverlay" -> {
                    val intent = Intent(this, OverlayBubbleService::class.java)
                    stopService(intent)
                    result.success(true)
                }
                "isOverlayRunning" -> {
                    result.success(OverlayBubbleService.isRunning)
                }
                else -> result.notImplemented()
            }
        }

        // Check if started from overlay tap or snip submit
        handleIncomingAction(intent)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_MEDIA_PROJECTION && resultCode == Activity.RESULT_OK && data != null) {
            ScreenCaptureManager.setPermissionResult(resultCode, data)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIncomingAction(intent)
    }

    private fun handleIncomingAction(intent: Intent?) {
        val action = intent?.getStringExtra("action")
        if (action == "circle_to_search") {
            methodChannel?.invokeMethod("onCircleToSearchTriggered", null)
        } else if (action == "circle_to_search_snip_ready") {
            val snipPath = intent.getStringExtra("snip_path")
            if (snipPath != null) {
                methodChannel?.invokeMethod("onSnipSubmitted", mapOf("image_path" to snipPath))
            }
        } else if (action == "circle_to_search_review_ready") {
            val stagedPaths = intent.getStringArrayListExtra("staged_paths")
            if (stagedPaths != null && stagedPaths.isNotEmpty()) {
                methodChannel?.invokeMethod("onReviewSubmitted", mapOf("image_paths" to stagedPaths))
            }
        }
    }
}
