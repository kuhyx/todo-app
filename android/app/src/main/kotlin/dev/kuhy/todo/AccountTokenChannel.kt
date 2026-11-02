package dev.kuhy.todo

import android.accounts.Account
import android.accounts.AccountManager
import android.accounts.AccountManagerFuture
import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** System account chooser, then an ID token from AccountManager. No browser. */
class AccountTokenChannel(private val activity: Activity) :
    MethodChannel.MethodCallHandler {

    private var pending: MethodChannel.Result? = null
    private var audience: String = ""

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "idToken") {
            result.notImplemented()
            return
        }
        if (pending != null) {
            result.error("busy", "sign-in already running", null)
            return
        }
        audience = call.argument<String>("serverClientId") ?: ""
        pending = result
        val chooser = AccountManager.newChooseAccountIntent(
            null, null, arrayOf("com.google"), null, null, null, null,
        )
        activity.startActivityForResult(chooser, REQUEST_CHOOSE)
    }

    fun onActivityResult(request: Int, code: Int, data: Intent?): Boolean {
        if (request != REQUEST_CHOOSE) return false
        val name = data?.getStringExtra(AccountManager.KEY_ACCOUNT_NAME)
        val type = data?.getStringExtra(AccountManager.KEY_ACCOUNT_TYPE)
        if (code != Activity.RESULT_OK || name == null || type == null) {
            finish { it.success(null) }
        } else {
            fetchToken(Account(name, type))
        }
        return true
    }

    private fun fetchToken(account: Account) {
        val manager = AccountManager.get(activity)
        val type = "audience:server:client_id:$audience"
        // Activity argument: the framework launches any consent screen itself.
        manager.getAuthToken(account, type, Bundle(), activity, { future ->
            deliver(future)
        }, Handler(Looper.getMainLooper()))
    }

    private fun deliver(future: AccountManagerFuture<Bundle>) {
        try {
            val bundle = future.result
            val token = bundle.getString(AccountManager.KEY_AUTHTOKEN)
            if (token != null) {
                finish { it.success(token) }
            } else {
                finish { it.error("no_token", "keys: ${bundle.keySet()}", null) }
            }
        } catch (e: Exception) {
            finish { it.error("auth_failed", e.toString(), null) }
        }
    }

    private fun finish(block: (MethodChannel.Result) -> Unit) {
        val result = pending ?: return
        pending = null
        block(result)
    }

    companion object {
        const val CHANNEL = "dev.kuhy.todo/account_token"
        private const val REQUEST_CHOOSE = 7421
    }
}
