package com.kashcube.kash_cube

import com.android.installreferrer.api.InstallReferrerClient
import com.android.installreferrer.api.InstallReferrerStateListener
import com.android.installreferrer.api.ReferrerDetails
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * MainActivity — adds a MethodChannel bridge for the Play Store install
 * referrer so Flutter can retrieve the deferred deep-link vCard on first
 * launch (Option B acquisition flow).
 *
 * The channel name must match AppConfig.installReferrerChannel in Dart.
 */
class MainActivity : FlutterActivity() {

    private val channelName = "com.kashcube/install_referrer"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getReferrer" -> fetchInstallReferrer(
                        onSuccess = { referrer -> result.success(referrer) },
                        onError   = { result.success(null) },   // null = nothing to process
                    )
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Connects to the Play Install Referrer API and returns the referrer
     * string via [onSuccess].  Always calls one of the two callbacks.
     *
     * The referrer for Kash Cube contact links is the base64url-encoded vCard
     * set by the landing page at kashcube.com/c.
     */
    private fun fetchInstallReferrer(
        onSuccess: (String?) -> Unit,
        onError:   ()        -> Unit,
    ) {
        val client = InstallReferrerClient.newBuilder(this).build()
        client.startConnection(object : InstallReferrerStateListener {

            override fun onInstallReferrerSetupFinished(responseCode: Int) {
                when (responseCode) {
                    InstallReferrerClient.InstallReferrerResponse.OK -> {
                        try {
                            val details: ReferrerDetails = client.installReferrer
                            val referrer = details.installReferrer
                            client.endConnection()
                            onSuccess(referrer.takeIf { it.isNotEmpty() })
                        } catch (e: Exception) {
                            client.endConnection()
                            onError()
                        }
                    }
                    else -> {
                        client.endConnection()
                        onSuccess(null)   // No referrer available — ignore silently
                    }
                }
            }

            override fun onInstallReferrerServiceDisconnected() {
                onError()
            }
        })
    }
}
