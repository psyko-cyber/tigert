package it.tigert.app

import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // aggiornamento dentro l'app: apre l'installer di Android sull'APK scaricato
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tigert/update").setMethodCallHandler { call, result ->
            if (call.method != "installApk") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            try {
                val uri = FileProvider.getUriForFile(this, "$packageName.updates", File(call.arguments as String))
                startActivity(
                    Intent(Intent.ACTION_VIEW)
                        .setDataAndType(uri, "application/vnd.android.package-archive")
                        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                )
                result.success(true)
            } catch (e: Exception) {
                result.error("install", e.message, null)
            }
        }
    }
}
