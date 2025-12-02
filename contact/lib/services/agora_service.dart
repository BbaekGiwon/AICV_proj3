import 'dart:async';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import '../utils/constants.dart';

typedef VoidCallback = void Function();
typedef IntCallback = void Function(int uid);
typedef StringCallback = void Function(String filePath);

class AgoraService {
  RtcEngine? _engine;
  RtcEngine? get engine => _engine;

  Future<void> init({
    required VoidCallback onJoinSuccess,
    required IntCallback onRemoteJoined,
    required VoidCallback onCallEnd,
    required StringCallback onSnapshotTaken,
  }) async {
    _engine = createAgoraRtcEngine();
    await _engine!.initialize(const RtcEngineContext(appId: AGORA_APP_ID));

    _engine!.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (connection, elapsed) => onJoinSuccess(),
        onUserJoined: (connection, uid, elapsed) => onRemoteJoined(uid),
        onLeaveChannel: (connection, stats) => onCallEnd(),
        onSnapshotTaken: (connection, uid, filePath, width, height, errCode) {
          if (errCode == 0) {
            onSnapshotTaken(filePath);
          } else {
            print('🔥 스냅샷 촬영 실패: $errCode');
          }
        },
        onError: (err, msg) => print("⚠️ Agora Error: $err, $msg"),
      ),
    );

    // 채널 프로필과 역할을 초기화 시점에 설정합니다.
    await _engine!.setChannelProfile(ChannelProfileType.channelProfileLiveBroadcasting);
    await _engine!.setClientRole(role: ClientRoleType.clientRoleBroadcaster);
  }

  Future<void> joinChannel({required String channelId, required int uid}) async {
    // 채널 접속 직전에 비디오를 활성화하고 미리보기를 시작합니다.
    await _engine?.enableVideo();
    await _engine?.startPreview();
    
    await _engine!.joinChannel(
      token: AGORA_TOKEN,
      channelId: channelId,
      uid: uid,
      options: const ChannelMediaOptions(),
    );
  }

  Future<void> takeSnapshot(int uid) async {
    final tempPath = '/data/user/0/com.example.contact/cache/${DateTime.now().millisecondsSinceEpoch}.jpg';
    await _engine?.takeSnapshot(uid: uid, filePath: tempPath);
  }

  Future<void> dispose() async {
    await _engine?.leaveChannel();
    await _engine?.stopPreview();
    await _engine?.release();
    _engine = null;
  }

  Future<void> muteLocalAudio(bool mute) async {
    await _engine?.muteLocalAudioStream(mute);
  }

  Future<void> muteLocalVideo(bool mute) async {
    await _engine?.muteLocalVideoStream(mute);
  }

  Future<void> switchCamera() async {
    await _engine?.switchCamera();
  }
}
