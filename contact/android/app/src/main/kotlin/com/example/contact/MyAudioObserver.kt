package com.example.contact

import android.util.Log
import io.agora.rtc2.audio.AudioPcmFrame
import io.agora.rtc2.IRawAudioFrameObserver

class MyAudioObserver(
    private val onPcmCaptured: (ShortArray, Int) -> Unit
) : IRawAudioFrameObserver {

    override fun onRecordAudioFrame(frame: AudioPcmFrame?): Boolean {
        return true
    }

    override fun onPlaybackAudioFrame(frame: AudioPcmFrame?): Boolean {
        if (frame == null) return true

        // PCM 샘플(short[]) 직접 전달
        val pcm = frame.data       // ShortArray
        val samples = frame.samplesPerChannel

        Log.d("MyAudioObserver", "PCM length = ${pcm.size}, samples = $samples")

        // 딥보이스 처리 콜백
        onPcmCaptured(pcm, samples)

        return true
    }

    override fun onMixedAudioFrame(frame: AudioPcmFrame?): Boolean {
        return true
    }

    override fun onPlaybackAudioFrameBeforeMixing(
        channelId: String?,
        uid: Int,
        frame: AudioPcmFrame?
    ): Boolean {
        return true
    }
}