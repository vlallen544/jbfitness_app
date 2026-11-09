package com.jbfitness.jbfitness

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel("jbfitness_updates", "JB Fitness updates", NotificationManager.IMPORTANCE_DEFAULT)
            channel.description = "Coaching and membership updates"
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }
}
