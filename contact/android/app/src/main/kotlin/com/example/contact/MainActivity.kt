package com.example.contact

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val methodChannelName = "voice_detect/method"
    private val eventChannelName = "voice_detect/events"

    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var voiceDetectHandler: VoiceDetectHandler? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName)
        eventChannel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannelName)

        voiceDetectHandler = VoiceDetectHandler(this, methodChannel!!, eventChannel!!)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        super.cleanUpFlutterEngine(flutterEngine)

        methodChannel?.setMethodCallHandler(null)
        eventChannel?.setStreamHandler(null)
        methodChannel = null
        eventChannel = null
        voiceDetectHandler = null
    }
}
