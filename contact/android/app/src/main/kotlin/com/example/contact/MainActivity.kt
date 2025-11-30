package com.example.contact

import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import io.agora.rtc2.RtcEngine
import io.agora.rtc2.RtcEngineConfig
import io.agora.rtc2.RtcEngineEx

class MainActivity: FlutterActivity() {

    private val CHANNEL = "com.contact.voice"
    private lateinit var methodChannel: MethodChannel

    private var engineEx: RtcEngineEx? = null
    private var detector: DeepVoiceDetector? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        methodChannel = MethodChannel(flutterEngine!!.dartExecutor.binaryMessenger, CHANNEL)

        initAgora()
    }

    private fun initAgora() {
        val config = RtcEngineConfig()
        config.mContext = this
        config.mAppId = "fc72b3363009410b8aca359a17879619"

        engineEx = RtcEngineEx.create(config)
        detector = DeepVoiceDetector(this)
    }

    private fun registerObserver() {

        val observer = MyAudioObserver { pcmShorts, samples ->
            val score = detector?.predict(pcmShorts) ?: 0.0f
            methodChannel.invokeMethod("onVoiceScore", score)
        }

        engineEx?.registerAudioFrameObserver(observer)
        Log.d("MainActivity", "Audio Observer Registered")
    }

    private fun unregisterObserver() {
        engineEx?.registerAudioFrameObserver(null)
    }

    override fun configureFlutterEngine(flutterEngine: io.flutter.embedding.engine.FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "registerObserver" -> {
                    registerObserver()
                    result.success(null)
                }
                "unregisterObserver" -> {
                    unregisterObserver()
                    result.success(null)
                }
            }
        }
    }
}