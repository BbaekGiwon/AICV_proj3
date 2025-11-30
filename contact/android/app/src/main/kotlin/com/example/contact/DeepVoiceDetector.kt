package com.example.contact

import android.content.Context
import android.util.Log
import org.tensorflow.lite.Interpreter
import java.nio.ByteBuffer
import java.nio.ByteOrder

class DeepVoiceDetector(context: Context) {

    private val interpreter: Interpreter

    init {
        // 모델 로드
        val asset = context.assets.open("yamnet.tflite")
        val bytes = asset.readBytes()
        val bb = ByteBuffer.allocateDirect(bytes.size)
        bb.order(ByteOrder.nativeOrder())
        bb.put(bytes)
        interpreter = Interpreter(bb)
        Log.d("DeepVoiceDetector", "Model loaded. Size=${bytes.size}")
    }

    // 🔥 여기서 ShortArray → FloatArray 변환 후 inference
    fun predict(shortPcm: ShortArray): Float {
        val floatInput = FloatArray(shortPcm.size)
        for (i in shortPcm.indices)
            floatInput[i] = shortPcm[i] / 32768f

        val input = arrayOf(floatInput)
        val output = Array(1) { FloatArray(521) }

        interpreter.run(input, output)

        val fakeProb = output[0][0]
        return fakeProb
    }
}