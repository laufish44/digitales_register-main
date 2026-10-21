package it.digitalesregisterapp

import android.app.Activity
import android.os.Bundle
import android.util.TypedValue
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

/**
 * Debug builds only: draws every home screen widget below each other, from
 * the stored snapshot, so they can be looked at without placing 21 widgets
 * on a home screen.
 *
 *   adb shell am start -n it.digitalesregisterapp.debug/it.digitalesregisterapp.WidgetGalleryActivity
 *
 * An optional "only" extra (comma-separated kind names) limits the list.
 */
class WidgetGalleryActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val json = intent.getStringExtra("snapshot")
            ?: intent.getStringExtra("snapshot_file")?.let { java.io.File(filesDir, it).readText() }
        if (json != null) HomeWidgets.save(this, json)
        val only = intent.getStringExtra("only")?.split(",")?.map { it.trim() }

        fun dp(value: Int) = TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP, value.toFloat(), resources.displayMetrics).toInt()

        val column = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(12), dp(12), dp(12), dp(12))
        }
        val cell = 74
        for (kind in WidgetKind.values()) {
            if (only != null && kind.name !in only) continue
            val info = packageManager.getReceiverInfo(
                android.content.ComponentName(this, kind.provider),
                android.content.pm.PackageManager.GET_META_DATA)
            val parser = resources.getXml(info.metaData.getInt("android.appwidget.provider"))
            var cw = 2
            var ch = 1
            while (parser.next() != org.xmlpull.v1.XmlPullParser.END_DOCUMENT) {
                if (parser.eventType == org.xmlpull.v1.XmlPullParser.START_TAG &&
                    parser.name == "appwidget-provider") {
                    for (i in 0 until parser.attributeCount) {
                        when (parser.getAttributeName(i)) {
                            "targetCellWidth" -> cw = parser.getAttributeValue(i).toInt()
                            "targetCellHeight" -> ch = parser.getAttributeValue(i).toInt()
                        }
                    }
                }
            }
            column.addView(TextView(this).apply {
                text = "${kind.name}  (${cw}×${ch})"
                setPadding(0, dp(10), 0, dp(4))
            })
            val frame = FrameLayout(this)
            val heightDp = cell * ch
            frame.addView(HomeWidgets.preview(this, kind, heightDp).apply(this, frame))
            column.addView(frame, LinearLayout.LayoutParams(dp(cell * cw), dp(heightDp)))
        }
        setContentView(ScrollView(this).apply { addView(column) })
    }
}
