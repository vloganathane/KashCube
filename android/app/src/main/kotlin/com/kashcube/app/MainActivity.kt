package com.kashcube.app

import android.util.Log
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

    private val installReferrerChannelName = "com.kashcube/install_referrer"
    private val webRtcPeerOpsChannelName = "kashcube/webrtc_peer_ops"
    private val webRtcRuntimeEventMethod = "onRuntimeEvent"

    private val peerStateBySession = mutableMapOf<String, PeerSessionState>()
    private var webRtcPeerOpsChannel: MethodChannel? = null

    private data class PeerSessionState(
        var localOfferSdp: String? = null,
        var remoteAnswerSdp: String? = null,
        val remoteIceCandidates: MutableList<Map<String, Any?>> = mutableListOf(),
        var dataChannelEnsured: Boolean = false,
    )

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, installReferrerChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getReferrer" -> fetchInstallReferrer(
                        onSuccess = { referrer -> result.success(referrer) },
                        onError   = { result.success(null) },   // null = nothing to process
                    )
                    else -> result.notImplemented()
                }
            }

        webRtcPeerOpsChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, webRtcPeerOpsChannelName)
        webRtcPeerOpsChannel
            ?.setMethodCallHandler { call, result ->
                handleWebRtcPeerOpsMethod(call, result)
            }
    }

    private fun handleWebRtcPeerOpsMethod(
        call: io.flutter.plugin.common.MethodCall,
        result: MethodChannel.Result,
    ) {
        val args = call.arguments as? Map<*, *>
        val sessionId = args?.get("session_id") as? String
        if (sessionId.isNullOrBlank()) {
            result.error("MISSING_SESSION_ID", "session_id is required", null)
            return
        }

        when (call.method) {
            "createPeerSession" -> {
                if (peerStateBySession.containsKey(sessionId)) {
                    result.error(
                        "SESSION_ALREADY_EXISTS",
                        "Peer session already exists for session_id",
                        null,
                    )
                    return
                }
                val state = PeerSessionState()
                peerStateBySession[sessionId] = state
                logPeerState("createPeerSession", sessionId, state)
                emitRuntimeEvent(sessionId, "PEER_SESSION_CREATED")
                result.success(null)
            }

            "closePeerSession" -> {
                val state = peerStateBySession.remove(sessionId)
                if (state == null) {
                    result.error(
                        "SESSION_NOT_FOUND",
                        "Peer session not found for session_id",
                        null,
                    )
                    return
                }
                logPeerState("closePeerSession", sessionId, state)
                emitRuntimeEvent(sessionId, "PEER_SESSION_CLOSED")
                result.success(null)
            }

            "setLocalOfferSdp" -> {
                val state = peerStateBySession[sessionId]
                if (state == null) {
                    result.error("SESSION_NOT_FOUND", "Call createPeerSession first", null)
                    return
                }
                val sdp = args["sdp"] as? String
                if (sdp.isNullOrBlank()) {
                    result.error("MISSING_SDP", "sdp is required", null)
                    return
                }
                state.localOfferSdp = sdp
                logPeerState("setLocalOfferSdp", sessionId, state)
                result.success(null)
            }

            "setRemoteAnswerSdp" -> {
                val state = peerStateBySession[sessionId]
                if (state == null) {
                    result.error("SESSION_NOT_FOUND", "Call createPeerSession first", null)
                    return
                }
                val sdp = args["sdp"] as? String
                if (sdp.isNullOrBlank()) {
                    result.error("MISSING_SDP", "sdp is required", null)
                    return
                }
                state.remoteAnswerSdp = sdp
                logPeerState("setRemoteAnswerSdp", sessionId, state)
                result.success(null)
            }

            "addRemoteIceCandidate" -> {
                val state = peerStateBySession[sessionId]
                if (state == null) {
                    result.error("SESSION_NOT_FOUND", "Call createPeerSession first", null)
                    return
                }
                @Suppress("UNCHECKED_CAST")
                val candidate = args["candidate"] as? Map<String, Any?>
                if (candidate == null || candidate.isEmpty()) {
                    result.error("MISSING_CANDIDATE", "candidate is required", null)
                    return
                }
                state.remoteIceCandidates.add(candidate.toMap())
                logPeerState("addRemoteIceCandidate", sessionId, state)
                result.success(null)
            }

            "ensureDataChannel" -> {
                val state = peerStateBySession[sessionId]
                if (state == null) {
                    result.error("SESSION_NOT_FOUND", "Call createPeerSession first", null)
                    return
                }
                state.dataChannelEnsured = true
                logPeerState("ensureDataChannel", sessionId, state)
                emitRuntimeEvent(sessionId, "DATA_CHANNEL_READY")
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    private fun logPeerState(action: String, sessionId: String, state: PeerSessionState) {
        Log.d(
            "KashCubeWebRtcPeerOps",
            "action=$action session=$sessionId hasOffer=${!state.localOfferSdp.isNullOrBlank()} " +
                "hasAnswer=${!state.remoteAnswerSdp.isNullOrBlank()} " +
                "iceCount=${state.remoteIceCandidates.size} " +
                "dataChannel=${state.dataChannelEnsured}",
        )
    }

    private fun emitRuntimeEvent(sessionId: String, event: String) {
        webRtcPeerOpsChannel?.invokeMethod(
            webRtcRuntimeEventMethod,
            mapOf(
                "session_id" to sessionId,
                "event" to event,
            ),
        )
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
