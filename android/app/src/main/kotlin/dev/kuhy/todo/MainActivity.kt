package dev.kuhy.todo

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var tokens: AccountTokenChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = AccountTokenChannel(this)
        tokens = channel
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            AccountTokenChannel.CHANNEL,
        ).setMethodCallHandler(channel)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(request: Int, code: Int, data: Intent?) {
        if (tokens?.onActivityResult(request, code, data) == true) return
        @Suppress("DEPRECATION")
        super.onActivityResult(request, code, data)
    }
}
