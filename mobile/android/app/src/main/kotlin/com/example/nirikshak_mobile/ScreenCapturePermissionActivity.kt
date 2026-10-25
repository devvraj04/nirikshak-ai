package com.example.nirikshak_mobile

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Bundle

/**
 * Transparent activity that requests MediaProjection permission
 * without interrupting the user or opening the full app UI.
 */
class ScreenCapturePermissionActivity : Activity() {

    companion object {
        const val REQUEST_CODE_CAPTURE = 3001
        var onPermissionResult: ((Int, Intent?) -> Unit)? = null
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val mgr = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as? MediaProjectionManager
        if (mgr != null) {
            startActivityForResult(mgr.createScreenCaptureIntent(), REQUEST_CODE_CAPTURE)
        } else {
            onPermissionResult?.invoke(Activity.RESULT_CANCELED, null)
            onPermissionResult = null
            finish()
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_CODE_CAPTURE) {
            onPermissionResult?.invoke(resultCode, data)
            onPermissionResult = null
        }
        finish()
    }
}
