package app.folio.folio

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// local_auth (biometric app lock) needs a FragmentActivity on Android; audio_service (lock-screen controls for
// "Listen") needs its own variant of it so both can share the app's engine.
import com.ryanheise.audioservice.AudioServiceFragmentActivity

class MainActivity : AudioServiceFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Prayer alarms: phones that "optimise" an app's battery may hold its alarms back.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "folio/battery").setMethodCallHandler { call, result ->
            when (call.method) {
                "isUnrestricted" -> {
                    val pm = getSystemService(POWER_SERVICE) as PowerManager
                    result.success(Build.VERSION.SDK_INT < 23 || pm.isIgnoringBatteryOptimizations(packageName))
                }
                "askUnrestricted" -> {
                    result.success(
                        open(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$packageName"))) ||
                            open(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)),
                    )
                }
                "declination" -> {
                    val lat = call.argument<Double>("lat")
                    val lng = call.argument<Double>("lng")
                    if (lat == null || lng == null) result.success(null) else result.success(declination(lat, lng).toDouble())
                }
                "openAppSettings" -> {
                    result.success(open(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))))
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun declination(lat: Double, lng: Double): Float =
        android.hardware.GeomagneticField(lat.toFloat(), lng.toFloat(), 0f, System.currentTimeMillis()).declination

    private fun open(intent: Intent): Boolean = try {
        startActivity(intent)
        true
    } catch (e: Exception) {
        false
    }
}
