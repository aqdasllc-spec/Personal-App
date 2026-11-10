package app.folio.folio

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import java.io.File
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// local_auth (biometric app lock) needs a FragmentActivity on Android; audio_service (lock-screen controls for
// "Listen") needs its own variant of it so both can share the app's engine.
import com.ryanheise.audioservice.AudioServiceFragmentActivity

class MainActivity : AudioServiceFragmentActivity() {
    // "Open with Folio" / "Share to Folio": a PDF handed over by another app, copied into the cache for Dart to add.
    private var pendingPdf: String? = null
    private var openChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        takePdf(intent)?.let { pendingPdf = it }
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        val path = takePdf(intent)
        super.onNewIntent(intent)
        if (path != null) {
            val ch = openChannel
            if (ch != null) ch.invokeMethod("opened", path) else pendingPdf = path
        }
    }

    /** If [intent] hands over a PDF, copies it into the cache, removes it from the intent (so Flutter does not read
     *  its address as a page of the app) and returns the copy's path. */
    private fun takePdf(intent: Intent?): String? {
        if (intent == null) return null
        val uri: Uri? = when (intent.action) {
            Intent.ACTION_VIEW -> intent.data?.takeIf { it.scheme == "content" || it.scheme == "file" }
            Intent.ACTION_SEND -> if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                else @Suppress("DEPRECATION") (intent.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri)
            else -> null
        }
        if (uri == null) return null
        val type = intent.type ?: contentResolver.getType(uri) ?: ""
        if (type != "application/pdf" && !(uri.lastPathSegment ?: "").endsWith(".pdf", ignoreCase = true)) return null
        return try {
            var name = "document.pdf"
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                if (c.moveToFirst() && !c.isNull(0)) name = c.getString(0)
            }
            name = name.replace(Regex("[^A-Za-z0-9 ._()-]"), "_").ifBlank { "document.pdf" }
            if (!name.endsWith(".pdf", ignoreCase = true)) name += ".pdf"
            val dir = File(cacheDir, "opened").apply { mkdirs() }
            val out = File(dir, name)
            contentResolver.openInputStream(uri)?.use { input -> out.outputStream().use { input.copyTo(it) } } ?: return null
            intent.data = null
            intent.removeExtra(Intent.EXTRA_STREAM)
            out.absolutePath
        } catch (e: Exception) {
            null
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        openChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "folio/open").apply {
            setMethodCallHandler { call, result ->
                if (call.method == "initial") {
                    result.success(pendingPdf)
                    pendingPdf = null
                } else {
                    result.notImplemented()
                }
            }
        }
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
                "widget" -> {
                    PrayerWidget.save(this, call.argument<String>("lines") ?: "")
                    result.success(true)
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
