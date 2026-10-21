// Copyright (C) 2026 Laurin Feichter
//
// This file is part of digitales_register.
//
// digitales_register is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// digitales_register is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with digitales_register.  If not, see <http://www.gnu.org/licenses/>.

package it.digitalesregisterapp

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONObject
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.LocalTime
import java.time.temporal.ChronoUnit

/**
 * The home screen widgets.
 *
 * The app sends a snapshot of its data (see lib/home_widgets.dart) whenever
 * it changes; it is kept here and every widget is drawn from it. What depends
 * on today — which day is "Heute", "in 3 Tagen", the next lesson — is worked
 * out while drawing, so the widgets stay right while the app is closed.
 */
object HomeWidgets {
    private const val PREFS = "dr_home_widgets"
    private const val KEY = "snapshot"

    fun save(context: Context, json: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putString(KEY, json).apply()
        updateAll(context)
    }

    private fun load(context: Context): JSONObject? {
        val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY, null) ?: return null
        return try {
            JSONObject(raw)
        } catch (e: Exception) {
            null
        }
    }

    fun updateAll(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        for (kind in WidgetKind.values()) {
            val ids = manager.getAppWidgetIds(ComponentName(context, kind.provider))
            for (id in ids) render(context, manager, id, kind)
        }
    }

    /** The views of [kind] as they would be drawn now; for the debug gallery. */
    fun preview(context: Context, kind: WidgetKind, heightDp: Int): RemoteViews =
        Renderer(context, load(context), LocalDate.now(), LocalTime.now(), heightDp).build(kind)

    fun render(context: Context, manager: AppWidgetManager, id: Int, kind: WidgetKind) {
        val options = manager.getAppWidgetOptions(id)
        val height = options?.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT) ?: 0
        val views = try {
            Renderer(context, load(context), LocalDate.now(), LocalTime.now(), height).build(kind)
        } catch (e: Exception) {
            // A broken snapshot must not leave a widget saying "Problem
            // loading widget" for good; the next snapshot fixes it.
            Renderer(context, null, LocalDate.now(), LocalTime.now(), height).build(kind)
        }
        manager.updateAppWidget(id, views)
    }
}

/** Every widget there is, with the class Android knows it by. */
enum class WidgetKind(val provider: Class<out AppWidgetProvider>) {
    TODAY(TodayWidget::class.java),
    TOMORROW(TomorrowWidget::class.java),
    UPCOMING(UpcomingWidget::class.java),
    EXAMS(ExamsWidget::class.java),
    HOMEWORK(HomeworkWidget::class.java),
    REMINDERS(RemindersWidget::class.java),
    WEEK(WeekWidget::class.java),
    TIMETABLE_TODAY(TimetableTodayWidget::class.java),
    TIMETABLE_TOMORROW(TimetableTomorrowWidget::class.java),
    NEXT_LESSON(NextLessonWidget::class.java),
    GRADES_SUBJECTS(GradesSubjectsWidget::class.java),
    GRADES_RECENT(GradesRecentWidget::class.java),
    AVERAGE(AverageWidget::class.java),
    NEXT_EXAM(NextExamWidget::class.java),
    ABSENCES(AbsencesWidget::class.java),
    ABSENCE_BUDGET(AbsenceBudgetWidget::class.java),
    HOLIDAYS(HolidaysWidget::class.java),
    SCHOOL_END(SchoolEndWidget::class.java),
    MESSAGES(MessagesWidget::class.java),
    UNREAD(UnreadWidget::class.java),
    OVERVIEW(OverviewWidget::class.java),
}

abstract class DrWidgetProvider(private val kind: WidgetKind) : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) HomeWidgets.render(context, manager, id, kind)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context, manager: AppWidgetManager, id: Int, options: Bundle
    ) {
        // Resized: more or fewer rows fit now.
        HomeWidgets.render(context, manager, id, kind)
    }
}

class TodayWidget : DrWidgetProvider(WidgetKind.TODAY)
class TomorrowWidget : DrWidgetProvider(WidgetKind.TOMORROW)
class UpcomingWidget : DrWidgetProvider(WidgetKind.UPCOMING)
class ExamsWidget : DrWidgetProvider(WidgetKind.EXAMS)
class HomeworkWidget : DrWidgetProvider(WidgetKind.HOMEWORK)
class RemindersWidget : DrWidgetProvider(WidgetKind.REMINDERS)
class WeekWidget : DrWidgetProvider(WidgetKind.WEEK)
class TimetableTodayWidget : DrWidgetProvider(WidgetKind.TIMETABLE_TODAY)
class TimetableTomorrowWidget : DrWidgetProvider(WidgetKind.TIMETABLE_TOMORROW)
class NextLessonWidget : DrWidgetProvider(WidgetKind.NEXT_LESSON)
class GradesSubjectsWidget : DrWidgetProvider(WidgetKind.GRADES_SUBJECTS)
class GradesRecentWidget : DrWidgetProvider(WidgetKind.GRADES_RECENT)
class AverageWidget : DrWidgetProvider(WidgetKind.AVERAGE)
class NextExamWidget : DrWidgetProvider(WidgetKind.NEXT_EXAM)
class AbsencesWidget : DrWidgetProvider(WidgetKind.ABSENCES)
class AbsenceBudgetWidget : DrWidgetProvider(WidgetKind.ABSENCE_BUDGET)
class HolidaysWidget : DrWidgetProvider(WidgetKind.HOLIDAYS)
class SchoolEndWidget : DrWidgetProvider(WidgetKind.SCHOOL_END)
class MessagesWidget : DrWidgetProvider(WidgetKind.MESSAGES)
class UnreadWidget : DrWidgetProvider(WidgetKind.UNREAD)
class OverviewWidget : DrWidgetProvider(WidgetKind.OVERVIEW)

/** One line of a list widget. */
private data class Row(
    val title: String,
    val subtitle: String = "",
    val badge: String? = null,
    val badgeSmall: String? = null,
    val value: String? = null,
    val urgent: Boolean = false,
    /** A grade below 6. */
    val low: Boolean = false,
    /** Marks today in a list of days. */
    val today: Boolean = false,
)

private class Renderer(
    private val context: Context,
    private val snapshot: JSONObject?,
    private val today: LocalDate,
    private val time: LocalTime,
    private val heightDp: Int,
) {
    private val weekdays = arrayOf("Mo", "Di", "Mi", "Do", "Fr", "Sa", "So")

    private fun short(date: LocalDate) =
        "${weekdays[date.dayOfWeek.value - 1]} ${date.dayOfMonth}.${date.monthValue}."

    private fun dayKey(date: LocalDate) = date.toString()

    private fun parse(day: String?): LocalDate? = try {
        if (day == null || day.isEmpty() || day == "null") null else LocalDate.parse(day)
    } catch (e: Exception) {
        null
    }

    private fun JSONObject.str(key: String): String? =
        if (isNull(key)) null else optString(key).takeIf { it.isNotEmpty() }

    private fun JSONArray?.objects(): List<JSONObject> {
        if (this == null) return emptyList()
        return (0 until length()).mapNotNull { optJSONObject(it) }
    }

    private fun daysLabel(days: Long): Pair<String, String> = when {
        days <= 0L -> "Heute" to ""
        days == 1L -> "1" to "Tag"
        else -> "$days" to "Tage"
    }

    /** How many rows fit; a guess from the height Android reports. */
    private fun rowsThatFit(): Int {
        if (heightDp <= 0) return 4
        return ((heightDp - 44) / 40).coerceIn(1, 12)
    }

    fun build(kind: WidgetKind): RemoteViews {
        val snapshot = this.snapshot
        if (snapshot == null) {
            return big("Digitales Register", "–", "App öffnen, um Daten zu laden")
        }
        if (!snapshot.optBoolean("loggedIn", true)) {
            return big("Digitales Register", "–", "In der App anmelden")
        }
        return when (kind) {
            WidgetKind.TODAY -> day(snapshot, today, "Heute")
            WidgetKind.TOMORROW -> day(snapshot, today.plusDays(1), "Morgen")
            WidgetKind.UPCOMING -> upcoming(snapshot, "Demnächst", null)
            WidgetKind.EXAMS -> upcoming(snapshot, "Prüfungen", "exam")
            WidgetKind.HOMEWORK -> upcoming(snapshot, "Hausaufgaben", "homework")
            WidgetKind.REMINDERS -> upcoming(snapshot, "Erinnerungen", "reminder")
            WidgetKind.WEEK -> week(snapshot)
            WidgetKind.TIMETABLE_TODAY -> timetable(snapshot, today, "Stundenplan heute")
            WidgetKind.TIMETABLE_TOMORROW ->
                timetable(snapshot, today.plusDays(1), "Stundenplan morgen")
            WidgetKind.NEXT_LESSON -> nextLesson(snapshot)
            WidgetKind.GRADES_SUBJECTS -> gradesBySubject(snapshot)
            WidgetKind.GRADES_RECENT -> recentGrades(snapshot)
            WidgetKind.AVERAGE -> average(snapshot)
            WidgetKind.NEXT_EXAM -> nextExam(snapshot)
            WidgetKind.ABSENCES -> absences(snapshot)
            WidgetKind.ABSENCE_BUDGET -> absenceBudget(snapshot)
            WidgetKind.HOLIDAYS -> holidays(snapshot)
            WidgetKind.SCHOOL_END -> schoolEnd(snapshot)
            WidgetKind.MESSAGES -> messages(snapshot)
            WidgetKind.UNREAD -> unread(snapshot)
            WidgetKind.OVERVIEW -> overview(snapshot)
        }
    }

    // --- lists -------------------------------------------------------------

    private fun entryRow(entry: JSONObject, date: LocalDate? = null): Row {
        val kind = entry.optString("k")
        val badge: Pair<String, String> = if (date != null) {
            daysLabel(ChronoUnit.DAYS.between(today, date))
        } else when (kind) {
            "exam" -> "!" to "Test"
            "reminder" -> "•" to "Notiz"
            else -> "HA" to ""
        }
        val days = date?.let { ChronoUnit.DAYS.between(today, it) } ?: 0
        return Row(
            title = entry.optString("t"),
            subtitle = entry.optString("s"),
            badge = badge.first,
            badgeSmall = badge.second,
            urgent = kind == "exam" && days <= 2,
        )
    }

    private fun lessonRow(lesson: JSONObject): Row {
        val from = lesson.str("from")
        val to = lesson.str("to")
        // Time and room share the second line; next to the subject the time
        // left no room for it in a narrow widget.
        val time = if (from != null && to != null) "$from–$to" else from
        return Row(
            title = lesson.optString("t"),
            subtitle = listOfNotNull(time, lesson.optString("r").takeIf { it.isNotEmpty() })
                .joinToString(" · "),
            badge = lesson.optString("h"),
        )
    }

    private fun day(snapshot: JSONObject, date: LocalDate, label: String): RemoteViews {
        val day = snapshot.optJSONObject("days")?.optJSONObject(dayKey(date))
        val rows = day?.optJSONArray("entries").objects().map { entryRow(it) } +
            day?.optJSONArray("lessons").objects().map { lessonRow(it) }
        val weekend = date.dayOfWeek == DayOfWeek.SATURDAY || date.dayOfWeek == DayOfWeek.SUNDAY
        return list(
            "$label · ${short(date)}",
            null,
            rows,
            if (weekend) "Wochenende" else "Nichts eingetragen",
        )
    }

    private fun upcoming(snapshot: JSONObject, title: String, onlyKind: String?): RemoteViews {
        val rows = snapshot.optJSONArray("upcoming").objects()
            .filter { onlyKind == null || it.optString("k") == onlyKind }
            .mapNotNull { entry ->
                val date = parse(entry.str("d")) ?: return@mapNotNull null
                if (date.isBefore(today)) null else entryRow(entry, date)
            }
        val empty = when (onlyKind) {
            "exam" -> "Keine Prüfung in Sicht"
            "homework" -> "Keine offenen Hausaufgaben"
            "reminder" -> "Keine Erinnerungen"
            else -> "Nichts eingetragen"
        }
        return list(title, if (rows.isEmpty()) null else "${rows.size}", rows, empty)
    }

    private fun week(snapshot: JSONObject): RemoteViews {
        // Saturday and Sunday look ahead to the coming week.
        val monday = if (today.dayOfWeek.value >= 6)
            today.plusDays((8 - today.dayOfWeek.value).toLong())
        else today.minusDays((today.dayOfWeek.value - 1).toLong())
        val days = snapshot.optJSONObject("days")
        val rows = (0L until 5L).map { offset ->
            val date = monday.plusDays(offset)
            val entries = days?.optJSONObject(dayKey(date))?.optJSONArray("entries").objects()
                .filter { it.optString("k") != "reminder" }
            val exam = entries.any { it.optString("k") == "exam" }
            Row(
                title = if (entries.isEmpty()) "–" else entries.first().optString("t") +
                    entries.first().optString("s").let { if (it.isEmpty()) "" else " · $it" },
                subtitle = entries.drop(1).joinToString(" · ") { it.optString("t") },
                badge = weekdays[date.dayOfWeek.value - 1],
                badgeSmall = "${date.dayOfMonth}.",
                urgent = exam,
                today = date == today,
            )
        }
        return list("Woche ab ${monday.dayOfMonth}.${monday.monthValue}.", null, rows, "")
    }

    private fun timetable(snapshot: JSONObject, date: LocalDate, title: String): RemoteViews {
        val lessons = snapshot.optJSONObject("days")?.optJSONObject(dayKey(date))
            ?.optJSONArray("lessons").objects().map { lessonRow(it) }
        return list("$title · ${short(date)}", null, lessons, "Kein Unterricht")
    }

    private fun gradesBySubject(snapshot: JSONObject): RemoteViews {
        val grades = snapshot.optJSONObject("grades")
            ?: return big("Noten", "–", "Noch keine Noten geladen")
        val rows = grades.optJSONArray("subjects").objects().map {
            Row(title = it.optString("t"), value = it.optString("v"), low = it.optBoolean("low"))
        }
        return list("Noten nach Fach", grades.str("overall"), rows, "Noch keine Noten")
    }

    private fun recentGrades(snapshot: JSONObject): RemoteViews {
        val grades = snapshot.optJSONObject("grades")
            ?: return big("Letzte Noten", "–", "Noch keine Noten geladen")
        val rows = grades.optJSONArray("recent").objects().map {
            val date = parse(it.str("d"))
            Row(
                title = it.optString("t"),
                subtitle = listOfNotNull(
                    it.str("s"),
                    date?.let { d -> "${d.dayOfMonth}.${d.monthValue}." },
                ).joinToString(" · "),
                badge = it.optString("v"),
                low = it.optBoolean("low"),
            )
        }
        return list("Letzte Noten", null, rows, "Noch keine Noten")
    }

    private fun messages(snapshot: JSONObject): RemoteViews {
        val messages = snapshot.optJSONObject("messages")
        val unread = messages?.optInt("unread") ?: 0
        val rows = messages?.optJSONArray("items").objects().map {
            Row(title = it.optString("t"), subtitle = it.optString("s"), badge = "✉")
        }
        val empty = if (messages?.optBoolean("loaded") == true)
            "Keine ungelesenen Mitteilungen" else "Mitteilungen einmal in der App öffnen"
        return list("Mitteilungen", if (unread > 0) "$unread" else null, rows, empty)
    }

    // --- single values -----------------------------------------------------

    private fun nextLesson(snapshot: JSONObject): RemoteViews {
        val days = snapshot.optJSONObject("days")
        val todays = days?.optJSONObject(dayKey(today))?.optJSONArray("lessons").objects()
        fun at(text: String?) = try {
            if (text == null) null else LocalTime.parse(text)
        } catch (e: Exception) {
            null
        }
        for (lesson in todays) {
            val from = at(lesson.str("from")) ?: continue
            val to = at(lesson.str("to")) ?: continue
            if (!time.isBefore(from) && time.isBefore(to)) {
                return big("Jetzt · ${lesson.optString("h")} Stunde", lesson.optString("t"),
                    listOf(lesson.optString("r"), "bis ${lesson.optString("to")}")
                        .filter { it.isNotEmpty() }.joinToString(" · "))
            }
            if (time.isBefore(from)) {
                return big("Ab ${lesson.optString("from")} · ${lesson.optString("h")} Stunde",
                    lesson.optString("t"), lesson.optString("r"))
            }
        }
        for (offset in 1L..14L) {
            val date = today.plusDays(offset)
            val first = days?.optJSONObject(dayKey(date))?.optJSONArray("lessons").objects()
                .firstOrNull() ?: continue
            return big("${short(date)} · ${first.optString("from")}",
                first.optString("t"), first.optString("r"))
        }
        return big("Nächste Stunde", "–", "Kein Unterricht in Sicht")
    }

    private fun average(snapshot: JSONObject): RemoteViews {
        val grades = snapshot.optJSONObject("grades")
        val overall = grades?.str("overall")
            ?: return big("Notenschnitt", "–", "Noch keine Noten")
        val trend = grades.str("trend")
        return big("Notenschnitt", overall,
            if (trend == null) "" else "Trend $trend pro Monat",
            alert = grades.optBoolean("overallLow"))
    }

    private fun nextExam(snapshot: JSONObject): RemoteViews {
        for (entry in snapshot.optJSONArray("upcoming").objects()) {
            if (entry.optString("k") != "exam") continue
            val date = parse(entry.str("d")) ?: continue
            if (date.isBefore(today)) continue
            val days = ChronoUnit.DAYS.between(today, date)
            return big(
                when (days) {
                    0L -> "Prüfung heute"
                    1L -> "Prüfung morgen"
                    else -> "Prüfung in"
                },
                if (days <= 1L) entry.optString("t") else "$days Tagen",
                if (days <= 1L) entry.optString("s")
                else "${entry.optString("t")} · ${entry.optString("s")}",
                alert = days <= 2L,
            )
        }
        return big("Nächste Prüfung", "–", "Keine Prüfung in Sicht")
    }

    private fun absences(snapshot: JSONObject): RemoteViews {
        val absences = snapshot.optJSONObject("absences")
            ?: return big("Absenzen", "–", "Absenzen einmal in der App öffnen")
        val percent = absences.str("percent") ?: "–"
        val open = absences.optInt("open")
        return big(
            "Absenzen",
            "$percent %",
            listOfNotNull(
                "${absences.optInt("missed")} Std. versäumt",
                if (open > 0) "$open offen" else null,
            ).joinToString(" · "),
            alert = absences.optBoolean("overLimit"),
        )
    }

    private fun absenceBudget(snapshot: JSONObject): RemoteViews {
        val absences = snapshot.optJSONObject("absences")
        if (absences == null || absences.isNull("remaining")) {
            return big("Noch fehlbar", "–", "Absenzen einmal in der App öffnen")
        }
        val remaining = absences.optInt("remaining")
        val limit = absences.optInt("limit")
        return if (remaining < 0) big("Über der Grenze", "${-remaining}",
            "Stunden über $limit %", alert = true)
        else big("Noch fehlbar", "$remaining", "Stunden bis zur $limit-%-Grenze")
    }

    private fun holidays(snapshot: JSONObject): RemoteViews {
        var best: Triple<String, LocalDate, LocalDate>? = null
        for (h in snapshot.optJSONArray("holidays").objects()) {
            val from = parse(h.str("from")) ?: continue
            val to = parse(h.str("to")) ?: continue
            if (to.isBefore(today)) continue
            if (best == null || from.isBefore(best.second)) best = Triple(h.optString("t"), from, to)
        }
        val (name, from, to) = best ?: return big("Ferien", "–", "Keine Ferien eingetragen")
        if (!today.isBefore(from)) {
            val left = ChronoUnit.DAYS.between(today, to)
            return big(name, "Ferien!", if (left <= 0L) "letzter Tag" else "noch $left Tage")
        }
        val days = ChronoUnit.DAYS.between(today, from)
        return big(name, if (days == 1L) "morgen" else "$days",
            if (days == 1L) "geht's los" else "Tage · ab ${short(from)}")
    }

    private fun schoolEnd(snapshot: JSONObject): RemoteViews {
        val last = parse(snapshot.str("lastSchoolDay"))
        if (last == null || last.isBefore(today)) {
            return big("Schulende", "–", "Kein Schulende eingetragen")
        }
        val days = ChronoUnit.DAYS.between(today, last)
        return big("Schulende", if (days == 0L) "heute" else "$days",
            if (days == 0L) "letzter Schultag" else "Tage · ${short(last)}")
    }

    private fun unread(snapshot: JSONObject): RemoteViews {
        val messages = snapshot.optJSONObject("messages")
        val unread = messages?.optInt("unread") ?: 0
        val first = messages?.optJSONArray("items").objects().firstOrNull()
        return big(
            if (unread == 1) "Ungelesene Mitteilung" else "Ungelesene Mitteilungen",
            "$unread",
            first?.optString("t") ?: "Alles gelesen",
            alert = unread > 0,
        )
    }

    private fun overview(snapshot: JSONObject): RemoteViews {
        val grades = snapshot.optJSONObject("grades")
        val absences = snapshot.optJSONObject("absences")
        val exam = snapshot.optJSONArray("upcoming").objects().firstOrNull { entry ->
            entry.optString("k") == "exam" &&
                parse(entry.str("d"))?.let { !it.isBefore(today) } == true
        }
        val examDays = exam?.let { ChronoUnit.DAYS.between(today, parse(it.str("d"))) }
        val views = RemoteViews(context.packageName, R.layout.widget_stats)
        views.removeAllViews(R.id.cells)
        fun cell(value: String, label: String, alert: Boolean = false) {
            val cell = RemoteViews(context.packageName, R.layout.widget_stat_cell)
            cell.setTextViewText(R.id.value, value)
            cell.setTextViewText(R.id.label, label)
            cell.setTextColor(R.id.value, color(if (alert) R.color.widget_error else R.color.widget_text))
            views.addView(R.id.cells, cell)
        }
        cell(grades?.str("overall") ?: "–", "Schnitt", grades?.optBoolean("overallLow") == true)
        cell((absences?.str("percent") ?: "–") + " %", "Absenzen",
            absences?.optBoolean("overLimit") == true)
        cell(
            when (examDays) {
                null -> "–"
                0L -> "heute"
                1L -> "morgen"
                else -> "$examDays T."
            },
            exam?.optString("t")?.takeIf { it.isNotEmpty() } ?: "Prüfung",
            examDays != null && examDays <= 2L,
        )
        val unread = snapshot.optJSONObject("messages")?.optInt("unread") ?: 0
        cell("$unread", "Ungelesen", unread > 0)
        open(views)
        return views
    }

    // --- building blocks ---------------------------------------------------

    private fun color(id: Int) = context.resources.getColor(id, context.theme)

    private fun open(views: RemoteViews) {
        val intent = Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val pending = PendingIntent.getActivity(
            context, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        views.setOnClickPendingIntent(R.id.widget_root, pending)
    }

    private fun list(title: String, headerValue: String?, rows: List<Row>, empty: String): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_list)
        views.setTextViewText(R.id.title, title)
        views.setTextViewText(R.id.header_value, headerValue ?: "")
        views.setViewVisibility(R.id.header_value, if (headerValue == null) View.GONE else View.VISIBLE)
        views.removeAllViews(R.id.rows)
        val shown = rows.take(rowsThatFit())
        for (row in shown) {
            val item = RemoteViews(context.packageName, R.layout.widget_row)
            item.setTextViewText(R.id.row_title, row.title)
            item.setTextViewText(R.id.row_subtitle, row.subtitle)
            item.setViewVisibility(R.id.row_subtitle, if (row.subtitle.isEmpty()) View.GONE else View.VISIBLE)
            if (row.badge == null) {
                item.setViewVisibility(R.id.badge, View.GONE)
            } else {
                item.setTextViewText(R.id.badge_top, row.badge)
                item.setTextViewText(R.id.badge_bottom, row.badgeSmall ?: "")
                item.setViewVisibility(R.id.badge_bottom,
                    if (row.badgeSmall.isNullOrEmpty()) View.GONE else View.VISIBLE)
                item.setInt(R.id.badge, "setBackgroundResource",
                    when {
                        row.urgent || row.low -> R.drawable.widget_badge_urgent
                        row.today -> R.drawable.widget_badge_today
                        else -> R.drawable.widget_badge
                    })
            }
            item.setTextViewText(R.id.row_value, row.value ?: "")
            item.setViewVisibility(R.id.row_value, if (row.value == null) View.GONE else View.VISIBLE)
            item.setTextColor(R.id.row_value,
                color(if (row.low && row.badge == null) R.color.widget_error else R.color.widget_text))
            views.addView(R.id.rows, item)
        }
        val more = rows.size - shown.size
        views.setTextViewText(R.id.empty, if (rows.isEmpty()) empty else "+ $more weitere")
        views.setViewVisibility(R.id.empty, if (rows.isEmpty() || more > 0) View.VISIBLE else View.GONE)
        open(views)
        return views
    }

    private fun big(label: String, value: String, caption: String, alert: Boolean = false): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_big)
        views.setTextViewText(R.id.label, label)
        views.setTextViewText(R.id.value, value)
        views.setTextViewText(R.id.caption, caption)
        views.setViewVisibility(R.id.caption, if (caption.isEmpty()) View.GONE else View.VISIBLE)
        views.setTextColor(R.id.value, color(if (alert) R.color.widget_error else R.color.widget_text))
        open(views)
        return views
    }
}
