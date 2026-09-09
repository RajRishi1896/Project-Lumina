package com.edumesh.android

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Receives Android PiP RemoteAction PendingIntents and forwards the small,
 * validated action value to the live Flutter Activity.
 *
 * This is manifest-declared so PendingIntent.getBroadcast() can target an
 * explicit component. The receiver is private to this application.
 */
class PipActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.getStringExtra("action")) {
            "play_pause", "forward" -> {
                MainActivity.dispatchPipAction(intent.getStringExtra("action")!!)
            }
        }
    }
}
