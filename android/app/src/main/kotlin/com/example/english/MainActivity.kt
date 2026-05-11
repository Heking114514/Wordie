package com.example.english

import android.Manifest
import android.content.ContentValues
import android.content.pm.PackageManager
import android.provider.CalendarContract
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Calendar
import java.util.TimeZone

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.english/calendar"
    private val PERM_REQ_CODE = 1001
    private var pendingResult: MethodChannel.Result? = null
    private var pendingCallArgs: Map<String, Any?>? = null
    private var pendingAction: String = ""

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "addEvent" || call.method == "removeEvent") {
                if (ContextCompat.checkSelfPermission(this, Manifest.permission.WRITE_CALENDAR) != PackageManager.PERMISSION_GRANTED) {
                    pendingResult = result
                    pendingAction = call.method
                    pendingCallArgs = call.arguments as? Map<String, Any?>
                    ActivityCompat.requestPermissions(
                        this,
                        arrayOf(Manifest.permission.READ_CALENDAR, Manifest.permission.WRITE_CALENDAR),
                        PERM_REQ_CODE
                    )
                } else {
                    handleCalendarAction(call.method, call.arguments as? Map<String, Any?>, result)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PERM_REQ_CODE) {
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                pendingResult?.let { handleCalendarAction(pendingAction, pendingCallArgs, it) }
            } else {
                pendingResult?.error("DENIED", "日历权限被拒绝", null)
            }
            pendingResult = null
        }
    }

    private fun handleCalendarAction(action: String, args: Map<String, Any?>?, result: MethodChannel.Result) {
        try {
            if (action == "addEvent") {
                val title = args?.get("title") as? String ?: "学习提醒"
                val desc = args?.get("description") as? String ?: ""
                val timeStr = args?.get("time") as? String ?: "20:00"

                val parts = timeStr.split(":")
                val cal = Calendar.getInstance()
                cal.set(Calendar.HOUR_OF_DAY, parts[0].toInt())
                cal.set(Calendar.MINUTE, parts[1].toInt())
                cal.set(Calendar.SECOND, 0)
                if (cal.timeInMillis < System.currentTimeMillis()) {
                    cal.add(Calendar.DAY_OF_YEAR, 1)
                }

                var calId: Long = 1
                val cursor = contentResolver.query(CalendarContract.Calendars.CONTENT_URI, arrayOf(CalendarContract.Calendars._ID), null, null, null)
                if (cursor != null && cursor.moveToFirst()) {
                    calId = cursor.getLong(0)
                    cursor.close()
                }

                val values = ContentValues().apply {
                    put(CalendarContract.Events.DTSTART, cal.timeInMillis)
                    put(CalendarContract.Events.DTEND, cal.timeInMillis + 30 * 60 * 1000)
                    put(CalendarContract.Events.TITLE, title)
                    put(CalendarContract.Events.DESCRIPTION, desc)
                    put(CalendarContract.Events.CALENDAR_ID, calId)
                    put(CalendarContract.Events.EVENT_TIMEZONE, TimeZone.getDefault().id)
                    put(CalendarContract.Events.RRULE, "FREQ=DAILY")
                    put(CalendarContract.Events.HAS_ALARM, 1)
                }
                val uri = contentResolver.insert(CalendarContract.Events.CONTENT_URI, values)
                val eventId = uri?.lastPathSegment

                if (eventId != null) {
                    val remValues = ContentValues().apply {
                        put(CalendarContract.Reminders.EVENT_ID, eventId.toLong())
                        put(CalendarContract.Reminders.MINUTES, 0)
                        put(CalendarContract.Reminders.METHOD, CalendarContract.Reminders.METHOD_ALERT)
                    }
                    contentResolver.insert(CalendarContract.Reminders.CONTENT_URI, remValues)
                }
                result.success(eventId)

            } else if (action == "removeEvent") {
                val eventId = args?.get("eventId") as? String
                if (eventId != null) {
                    val deleteUri = CalendarContract.Events.CONTENT_URI.buildUpon().appendPath(eventId).build()
                    contentResolver.delete(deleteUri, null, null)
                }
                result.success(true)
            }
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }
}
