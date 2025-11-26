
package com.example.contact

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.tensorflow.lite.support.audio.TensorAudio
import org.tensorflow.lite.support.label.Category
import org.tensorflow.lite.task.audio.classifier.AudioClassifier
import java.util.concurrent.Executors

class VoiceDetectHandler(
    private val context: Context,
    private val methodChannel: MethodChannel,
    private val eventChannel: EventChannel
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private var audioClassifier: AudioClassifier? = null
    private var audioRecord: AudioRecord? = null
    private var eventSink: EventChannel.EventSink? = null

    private val executor = Executors.newSingleThreadExecutor()
    private val handler = Handler(Looper.getMainLooper())

    private val modelPath = "yamnet_classifier_fp16.tflite"
    private val probabilityThreshold = 0.3f // fake일 확률 임계값 (필요시 조절)
    private var isRecording = false

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
    }

    override fun onMethodCall(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startDetection" -> {
                if (checkPermission()) {
                    startRecording()
                    result.success(null)
                } else {
                    result.error("PERMISSION_DENIED", "Audio recording permission not granted.", null)
                }
            }
            "stopDetection" -> {
                stopRecording()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        this.eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        this.eventSink = null
    }

    private fun checkPermission(): Boolean {
        return ActivityCompat.checkSelfPermission(
            context,
            Manifest.permission.RECORD_AUDIO
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun startRecording() {
        if (isRecording) return

        try {
            // ✅ setNumThreads(2) 옵션 제거
            val options = AudioClassifier.AudioClassifierOptions.builder()
                .setScoreThreshold(probabilityThreshold)
                .setMaxResults(1) // 가장 확률 높은 1개 결과만 받기
                .build()

            audioClassifier = AudioClassifier.createFromFileAndOptions(context, modelPath, options)
            val tensorAudio = audioClassifier?.createInputTensorAudio()

            val record = audioClassifier?.createAudioRecord()
            record?.startRecording()
            isRecording = true

            this.audioRecord = record

            executor.execute {
                while (isRecording) {
                    tensorAudio?.load(record)
                    val output = audioClassifier?.classify(tensorAudio)
                    val filteredOutput = output?.flatMap { it.categories }
                                             ?.filter { it.label == "fake" }
                                             ?.maxByOrNull { it.score }
                    
                    val fakeProbability = filteredOutput?.score ?: 0.0f
                    
                    handler.post {
                        eventSink?.success(fakeProbability.toDouble())
                    }
                }
            }

        } catch (e: Exception) {
            handler.post {
                eventSink?.error("INIT_ERROR", e.message, null)
            }
        }
    }

    private fun stopRecording() {
        if (!isRecording) return
        
        isRecording = false
        audioRecord?.stop()
        audioRecord?.release()
        audioRecord = null
        audioClassifier?.close()
        audioClassifier = null
    }
}
