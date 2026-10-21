package it.digitalesregisterapp

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // The home screen widgets get their data from here, see
        // lib/home_widgets.dart and HomeWidgets.kt.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "it.digitalesregisterapp/home_widgets")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "update" -> {
                        val json = call.arguments as? String
                        if (json == null) {
                            result.error("bad_args", "expected the snapshot as a JSON string", null)
                        } else {
                            HomeWidgets.save(applicationContext, json)
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        // Updates installed by the app itself, see SelfUpdate.kt.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "it.digitalesregisterapp/self_update")
            .setMethodCallHandler { call, result ->
                if (call.method != "install") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val path = call.arguments as? String
                if (path == null) {
                    result.error("bad_args", "expected the APK path", null)
                    return@setMethodCallHandler
                }
                try {
                    SelfUpdate.install(applicationContext, java.io.File(path))
                    result.success(null)
                } catch (e: Exception) {
                    result.error("install_failed", e.message, null)
                }
            }
    }
}
