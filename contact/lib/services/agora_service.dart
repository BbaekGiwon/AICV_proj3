import 'dart:io';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/services.dart';
import '../utils/constants.dart';

typedef JoinCallback = void Function();
typedef RemoteJoinCallback = void Function(int uid);
typedef SnapshotCallback = void Function(String filePath);
typedef VoiceScoreCallback = void Function(double score);

class AgoraService {
  RtcEngine? engine;

  VoiceScoreCallback? onVoiceScoreUpdated;

  static const MethodChannel _voiceChannel =
  MethodChannel('contact/voice_detect');

  AgoraService() {
    _voiceChannel.setMethodCallHandler((call) async {
      if (call.method == 'onVoiceScore') {
        final score = (call.arguments as num).toDouble();
        onVoiceScoreUpdated?.call(score);
      }
      return null;
    });
  }

  void setVoiceScoreCallback(VoiceScoreCallback callback) {
    onVoiceScoreUpdated = callback;
  }

  Future<void> muteLocalVideo(bool mute) async {
    await engine?.muteLocalVideoStream(mute);
  }

  Future<void> muteLocalAudio(bool mute) async {
    await engine?.muteLocalAudioStream(mute);
  }

  Future<void> switchCamera() async {
    await engine?.switchCamera();
  }

  Future<void> init({
    required JoinCallback onJoinSuccess,
    required RemoteJoinCallback onRemoteJoined,
    required SnapshotCallback onSnapshotTaken,
  }) async {
    engine = createAgoraRtcEngine();
    await engine!.initialize(const RtcEngineContext(appId: AGORA_APP_ID));

    await engine!.setChannelProfile(
        ChannelProfileType.channelProfileCommunication);
    await engine!.setClientRole(role: ClientRoleType.clientRoleBroadcaster);

    engine!.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (_, __) => onJoinSuccess(),
        onUserJoined: (_, uid, __) => onRemoteJoined(uid),
        onSnapshotTaken: (_, uid, filePath, __, ____, errCode) {
          if (errCode == 0 && filePath.isNotEmpty) {
            onSnapshotTaken(filePath);
          }
        },
      ),
    );
  }

  Future<void> joinChannel({
    required String channelId,
    required int uid,
  }) async {
    await engine?.enableVideo();
    await engine?.startPreview();

    await engine!.joinChannel(
      token: AGORA_TOKEN,
      channelId: channelId,
      uid: uid,
      options: const ChannelMediaOptions(),
    );
  }

  Future<void> registerAudioFrameObserver() async {
    await _voiceChannel.invokeMethod('registerObserver');
  }

  Future<void> unregisterAudioFrameObserver() async {
    await _voiceChannel.invokeMethod('unregisterObserver');
  }

  Future<void> takeSnapshot(int uid) async {
    final path = '${Directory.systemTemp.path}/temp_frame.jpg';
    final file = File(path);
    if (await file.exists()) file.deleteSync();

    await engine!.takeSnapshot(uid: uid, filePath: path);
  }

  Future<void> dispose() async {
    try {
      await unregisterAudioFrameObserver();
      await engine?.leaveChannel();
      await engine?.stopPreview();
      await engine?.release();
    } catch (_) {}
  }
}