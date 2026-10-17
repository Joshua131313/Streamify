package com.streamify.app.ui

import android.app.Activity
import android.content.Intent
import android.provider.Settings
import android.widget.Toast

/** Uses the phone's available wireless-display routes, not a direct Cast media session. */
fun openCastToTv(activity:Activity) {
    try { activity.startActivity(Intent(Settings.ACTION_CAST_SETTINGS)) }
    catch (_: android.content.ActivityNotFoundException) {
        Toast.makeText(activity,"Open Smart View or Google Home to mirror your screen to a TV.",Toast.LENGTH_LONG).show()
    }
}
