import 'dart:io';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import '../utils/constants.dart';

typedef JoinCallback = void Function();
typedef RemoteJoinCallback = void Function(int uid);
typedef SnapshotCallback = void Function(String filePath);

class AgoraService {
  RtcEngine? engine;

  Future<void> init({
    required JoinCallback onJoinSuccess,
    required RemoteJoinCallback onRemoteJoined,
    required SnapshotCallback onSnapshotTaken,
  }) async {
    engine = createAgoraRtcEngine();
    await engine!.initialize(const RtcEngineContext(appId: AGORA_APP_ID));

    await engine!.setChannelProfile(
      ChannelProfileType.channelProfileCommunication,
    );
    await engine!.setClientRole(
      role: ClientRoleType.clientRoleBroadcaster,
    );

    engine!.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (connection, elapsed) {
          onJoinSuccess();
        },
        onUserJoined: (connection, uid, elapsed) {
          onRemoteJoined(uid);
        },
        onSnapshotTaken:
            (connection, uid, filePath, width, height, errCode) {
          if (errCode == 0 && filePath.isNotEmpty) {
            onSnapshotTaken(filePath);
          }
        },
        onError: (err, msg) {
          print("⚠️ Agora Error: $err, $msg");
        },
      ),
    );

    // ✅ 아래 두 줄을 제거하여 초기화 순서를 변경합니다.
    // await engine!.enableVideo();
    // await engine!.startPreview();
  }

  Future<void> joinChannel({
    required String channelId,
    required int uid,
  }) async {
    // ✅ 채널 접속 전에 토큰과 비디오 옵션을 설정
    await engine?.enableVideo();
    await engine?.startPreview();
    
    await engine!.joinChannel(
      token: AGORA_TOKEN,
      channelId: channelId,
      uid: uid,
      options: const ChannelMediaOptions(),
    );
  }

  Future<void> takeSnapshot(int uid) async {
    if (engine == null) return;

    final dir = Directory.systemTemp;
    final path = '${dir.path}/temp_frame.jpg';
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }

    await engine!.takeSnapshot(uid: uid, filePath: path);
  }

  Future<void> muteLocalAudio(bool mute) async {
    await engine?.muteLocalAudioStream(mute);
  }

  Future<void> muteLocalVideo(bool mute) async {
    await engine?.muteLocalVideoStream(mute);
  }

  Future<void> switchCamera() async {
    await engine?.switchCamera();
  }

  Future<void> dispose() async {
    try {
      await engine?.leaveChannel();
      await engine?.stopPreview();
      await engine?.release();
    } catch (_) {}
  }
}
