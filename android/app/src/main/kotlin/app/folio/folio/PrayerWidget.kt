package app.folio.folio

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.SystemClock
import android.text.format.DateFormat
import android.view.View
import android.widget.RemoteViews
import java.util.Date

/**
 * Home-screen widget: the next prayer, its time and a live countdown. The app saves the coming weeks' times
 * ("epochMillis|English|Urdu" per line) whenever it sets the prayer reminders; the widget picks the next one itself and
 * asks to be woken again when that time comes.
 */
class PrayerWidget : AppWidgetProvider() {
    companion object {
        private const val PREFS = "folio_prayer_widget"
        private const val KEY = "times"
        private const val ACTION_TICK = "app.folio.folio.PRAYER_WIDGET_TICK"

        fun save(context: Context, lines: String) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY, lines).apply()
            refreshAll(context)
        }

        fun refreshAll(context: Context) {
            val mgr = AppWidgetManager.getInstance(context)
            val ids = mgr.getAppWidgetIds(ComponentName(context, PrayerWidget::class.java))
            if (ids.isNotEmpty()) render(context, mgr, ids)
        }

        private data class Next(val at: Long, val english: String, val urdu: String)

        private fun next(context: Context, now: Long): Next? {
            val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, null) ?: return null
            return raw.lineSequence().mapNotNull { line ->
                val p = line.split('|')
                val at = p.getOrNull(0)?.toLongOrNull() ?: return@mapNotNull null
                if (at <= now || p.size < 3) null else Next(at, p[1], p[2])
            }.minByOrNull { it.at }
        }

        private fun render(context: Context, mgr: AppWidgetManager, ids: IntArray) {
            val now = System.currentTimeMillis()
            val n = next(context, now)
            val views = RemoteViews(context.packageName, R.layout.prayer_widget)
            val open = Intent(context, MainActivity::class.java).apply {
                action = Intent.ACTION_VIEW
                data = Uri.parse("folio://app/home/prayer")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            views.setOnClickPendingIntent(
                R.id.prayer_widget_root,
                PendingIntent.getActivity(context, 0, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE),
            )
            if (n == null) {
                views.setTextViewText(R.id.prayer_widget_name, "Prayer times")
                views.setTextViewText(R.id.prayer_widget_urdu, "")
                views.setTextViewText(R.id.prayer_widget_time, "Open Folio to set your place")
                views.setViewVisibility(R.id.prayer_widget_countdown, View.GONE)
            } else {
                views.setTextViewText(R.id.prayer_widget_name, n.english)
                views.setTextViewText(R.id.prayer_widget_urdu, n.urdu)
                views.setTextViewText(R.id.prayer_widget_time, DateFormat.getTimeFormat(context).format(Date(n.at)))
                views.setViewVisibility(R.id.prayer_widget_countdown, View.VISIBLE)
                val base = SystemClock.elapsedRealtime() + (n.at - now)
                views.setChronometer(R.id.prayer_widget_countdown, base, "in %s", true)
                if (Build.VERSION.SDK_INT >= 24) views.setChronometerCountDown(R.id.prayer_widget_countdown, true)
                wakeAt(context, n.at + 1000)
            }
            mgr.updateAppWidget(ids, views)
        }

        private fun wakeAt(context: Context, at: Long) {
            val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val pi = PendingIntent.getBroadcast(
                context,
                0,
                Intent(context, PrayerWidget::class.java).setAction(ACTION_TICK),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            try {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC, at, pi)
            } catch (e: SecurityException) {
                am.setWindow(AlarmManager.RTC, at, 60_000, pi)
            }
        }
    }

    override fun onUpdate(context: Context, mgr: AppWidgetManager, ids: IntArray) = render(context, mgr, ids)

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        when (intent.action) {
            ACTION_TICK, Intent.ACTION_TIME_CHANGED, Intent.ACTION_TIMEZONE_CHANGED -> refreshAll(context)
        }
    }
}
