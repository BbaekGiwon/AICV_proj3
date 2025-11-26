
import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/call_record.dart';
import '../services/agora_service.dart';
import '../services/detection_service.dart';
import '../services/permission_service.dart';
import '../services/voice_detect_services.dart';
import '../utils/timer_formatter.dart';

class VideoCallScreen extends StatefulWidget {
  final String phoneNumber;

  const VideoCallScreen({super.key, required this.phoneNumber});

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  final AgoraService _agoraService = AgoraService();
  final DetectionService _detectionService = DetectionService();
  final VoiceDetectService _voiceDetectService = VoiceDetectService.instance;

  bool _joined = false;
  int? _remoteUid;
  bool _isMuted = false;
  bool _isVideoOn = true;
  bool _isVideoDetectionOn = true;
  bool _isVoiceDetectionOn = false;

  late final int _myUid;

  Timer? _callTimer;
  Timer? _detectionTimer;
  Duration _duration = Duration.zero;
  late DateTime _callStartTime;
  bool _timerStarted = false;

  bool _isProcessing = false;
  bool _hasEnded = false;

  // 영상 탐지 관련 변수
  double _lastVideoFakeProbability = 0.0;
  int _deepfakeDetections = 0;
  Rect? _faceRect;
  Size? _snapshotImageSize;

  // 음성 탐지 관련 변수
  StreamSubscription? _voiceFakeProbSub;
  double _lastVoiceFakeProbability = 0.0;

  @override
  void initState() {
    super.initState();
    _myUid = Random().nextInt(999999999);
    _initServices();
    _initVoiceDetection();
  }

  void _initVoiceDetection() {
    _voiceFakeProbSub = _voiceDetectService.fakeProbabilityStream.listen((prob) {
      if (mounted) {
        setState(() {
          _lastVoiceFakeProbability = prob;
        });
      }
    });
  }

  Future<void> _initServices() async {
    await PermissionService.requestCameraAndMic();
    await _detectionService.loadModel();

    await _agoraService.init(
      onJoinSuccess: () {
        if (!mounted) return;
        setState(() {
          _joined = true;
        });
      },
      onRemoteJoined: (uid) {
        if (!mounted) return;
        setState(() {
          _remoteUid = uid;
        });

        if (!_timerStarted) {
          _timerStarted = true;
          _startCallTimer();
          _lastVideoFakeProbability = 0.0;
          _faceRect = null;
          _snapshotImageSize = null;
        }

        if (_isVideoDetectionOn) {
          _startDetectionLoop();
        }
      },
      onSnapshotTaken: (filePath) async {
        await _runDetection(filePath);
      },
    );

    await _agoraService.joinChannel(
      channelId: widget.phoneNumber,
      uid: _myUid,
    );
  }

  void _startCallTimer() {
    _callStartTime = DateTime.now();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _duration = DateTime.now().difference(_callStartTime);
      });
    });
  }

  void _startDetectionLoop() {
    _detectionTimer?.cancel();
    _detectionTimer =
        Timer.periodic(const Duration(milliseconds: 1500), (_) async {
          if (_remoteUid != null &&
              _isVideoDetectionOn &&
              !_isProcessing) {
            await _agoraService.takeSnapshot(_remoteUid!);
          }
        });
  }

  void _stopDetectionLoop() {
    _detectionTimer?.cancel();
    _detectionTimer = null;
  }

  Future<void> _runDetection(String filePath) async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      final result = await _detectionService.analyze(filePath);

      if (!mounted) return;

      if (result.faceRect == null ||
          result.imageWidth == 0 ||
          result.imageHeight == 0) {
        setState(() {
          _lastVideoFakeProbability = 0.0;
          _faceRect = null;
          _snapshotImageSize = null;
        });
      } else {
        final fakeProb = result.fakeProb;
        setState(() {
          _lastVideoFakeProbability = fakeProb;
          _faceRect = result.faceRect;
          _snapshotImageSize =
              Size(result.imageWidth.toDouble(), result.imageHeight.toDouble());
          if (fakeProb >= 0.7) {
            _deepfakeDetections++;
          }
        });

        print('✅ 영상 Fake 확률: ${(fakeProb * 100).toStringAsFixed(2)}%');
      }
    } catch (e) {
      print('AI 분석 오류: $e');
    } finally {
      _isProcessing = false;
    }
  }

  // ✅ `saveRecord`의 기본값을 false로 변경하고, 실제 통화가 시작되었는지 여부로 저장 결정
  Future<void> _leaveChannel() async {
    if (_hasEnded) return;
    _hasEnded = true;

    _callTimer?.cancel();
    _stopDetectionLoop();
    await _voiceDetectService.stopDetection();

    // ✅ 실제 통화가 시작되었을 때만 기록 저장 (상대방이 접속했을 때)
    if (_remoteUid != null) {
      callHistory.add(
        CallRecord(
          phoneNumber: widget.phoneNumber,
          startTime: _callStartTime,
          duration: _duration,
          deepfakeDetections: _deepfakeDetections,
          highestProbability: _lastVideoFakeProbability,
        ),
      );
    }

    await _agoraService.dispose();
    await _detectionService.dispose();

    if (mounted) {
      Navigator.pop(context);
    }
  }


  Color _currentStatusColor(double probability) {
    if (probability >= 0.85) {
      return Colors.red[700]!;
    } else if (probability >= 0.7) {
      return Colors.red[400]!;
    } else if (probability >= 0.5) {
      return Colors.orange;
    } else if (probability >= 0.3) {
      return Colors.green[600]!;
    } else {
      return Colors.green[800]!;
    }
  }
  
  String _getStatusText(double p, String type) {
    if (p >= 0.85) {
      return '🚨 위험: $type 확신! (${(p * 100).toStringAsFixed(1)}%)';
    } else if (p >= 0.7) {
      return '⚠️ 경고: $type 의심 (${(p * 100).toStringAsFixed(1)}%)';
    } else if (p >= 0.5) {
      return '🤔 주의: $type 가능성 (${(p * 100).toStringAsFixed(1)}%)';
    } else if (p >= 0.3) {
      return '✅ 안전: Real 가능성 높음 (${(p * 100).toStringAsFixed(1)}%)';
    } else {
      return '✨ 안전: Real 확신 (${(p * 100).toStringAsFixed(1)}%)';
    }
  }

  Widget _buildVideoDetectionStatus() {
    if (!_isVideoDetectionOn || _remoteUid == null) {
      return const SizedBox.shrink();
    }

    if (_isProcessing) {
      return Positioned(
        top: 90,
        left: 0,
        right: 0,
        child: Center(
          child: Container(
            padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.8),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              '영상 AI 탐지 중...',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      );
    }

    final p = _lastVideoFakeProbability;
    if (p == 0.0 && _joined) {
      return const SizedBox.shrink();
    }

    return Positioned(
      top: 90,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _currentStatusColor(p).withOpacity(0.8),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            _getStatusText(p, '딥페이크'),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVoiceDetectionStatus() {
    if (!_isVoiceDetectionOn || _remoteUid == null) {
      return const SizedBox.shrink();
    }

    final p = _lastVoiceFakeProbability;
    if (p == 0.0 && _joined) {
      return const SizedBox.shrink();
    }

    return Positioned(
      top: 125, 
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _currentStatusColor(p).withOpacity(0.8),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            _getStatusText(p, '딥보이스'),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }


  Widget _buildFaceBoxesOverlay() {
    if (!_isVideoDetectionOn ||
        _remoteUid == null ||
        _snapshotImageSize == null ||
        _faceRect == null ||
        _lastVideoFakeProbability == 0.0) {
      return const SizedBox.shrink();
    }

    final boxColor = _currentStatusColor(_lastVideoFakeProbability);
    final rect = _faceRect!;

    return Positioned.fill(
      child: IgnorePointer(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final viewW = constraints.maxWidth;
            final viewH = constraints.maxHeight;

            final imgW = _snapshotImageSize!.width;
            final imgH = _snapshotImageSize!.height;

            final left = rect.left / imgW * viewW;
            final top = rect.top / imgH * viewH;
            final width = rect.width / imgW * viewW;
            final height = rect.height / imgH * viewH;

            return Stack(
              children: [
                Positioned(
                  left: left,
                  top: top,
                  width: width,
                  height: height,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: boxColor, width: 3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _onToggleMute() {
    if (!mounted) return;
    setState(() => _isMuted = !_isMuted);
    _agoraService.muteLocalAudio(_isMuted);
  }

  void _onToggleVideo() {
    if (!mounted) return;
    setState(() => _isVideoOn = !_isVideoOn);
    _agoraService.muteLocalVideo(!_isVideoOn);
  }

  void _onSwitchCamera() {
    _agoraService.switchCamera();
  }

  void _onToggleVideoDetection() {
    if (!mounted) return;
    setState(() {
      _isVideoDetectionOn = !_isVideoDetectionOn;
      if (!_isVideoDetectionOn) {
        _lastVideoFakeProbability = 0.0;
        _faceRect = null;
        _snapshotImageSize = null;
        _stopDetectionLoop();
      } else {
        _startDetectionLoop();
      }
    });
  }

  Future<void> _onToggleVoiceDetection() async {
    if (!mounted) return;

    final newStatus = !_isVoiceDetectionOn;
    if (newStatus) {
      var status = await Permission.microphone.request();
      if (status.isGranted) {
        _voiceDetectService.startDetection();
        setState(() => _isVoiceDetectionOn = true);
      } else {
         print("마이크 권한이 거부되었습니다.");
      }
    } else {
      _voiceDetectService.stopDetection();
      setState(() {
         _isVoiceDetectionOn = false;
         _lastVoiceFakeProbability = 0.0;
      });
    }
  }


  @override
  void dispose() {
    _callTimer?.cancel();
    _stopDetectionLoop();
    _voiceFakeProbSub?.cancel();
    _agoraService.dispose();
    _detectionService.dispose();
    _voiceDetectService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        await _leaveChannel();
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: _buildBody(),
        // ✅ 항상 하단 네비게이션 바가 보이도록 수정
        bottomNavigationBar: _buildBottomNavigationBar(),
      ),
    );
  }

  // ✅ 하단 네비게이션 바를 만드는 위젯
  Widget _buildBottomNavigationBar() {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(
        vertical: 10,
        horizontal: 10,
      ),
      child: SafeArea(
        child: _joined ? _buildConnectedControls() : _buildConnectingControls(),
      ),
    );
  }

  // ✅ 연결 중일 때 (통화 종료 버튼만 보임)
  Widget _buildConnectingControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildControlButton(
          icon: Icons.call_end,
          label: '취소',
          color: Colors.red,
          onTap: _leaveChannel, // 기록 없이 종료
        ),
      ],
    );
  }

  // ✅ 연결된 후 (모든 버튼 보임)
  Widget _buildConnectedControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _buildControlButton(
          icon: _isVideoOn ? Icons.videocam : Icons.videocam_off,
          label: '화면',
          onTap: _onToggleVideo,
        ),
        _buildControlButton(
          icon: _isMuted ? Icons.mic_off : Icons.mic,
          label: '음소거',
          onTap: _onToggleMute,
        ),
        _buildControlButton(
          icon: _isVideoDetectionOn ? Icons.shield : Icons.shield_outlined,
          label: '영상탐지',
          color: _isVideoDetectionOn ? Colors.teal : Colors.grey[700],
          onTap: _onToggleVideoDetection,
        ),
        _buildControlButton(
          icon: _isVoiceDetectionOn ? Icons.multitrack_audio : Icons.multitrack_audio_outlined,
          label: '음성탐지',
          color: _isVoiceDetectionOn ? Colors.blueAccent : Colors.grey[700],
          onTap: _onToggleVoiceDetection,
        ),
        _buildControlButton(
          icon: Icons.call_end,
          label: '종료',
          color: Colors.red,
          onTap: _leaveChannel, // 기록과 함께 종료
        ),
      ],
    );
  }


  Widget _buildBody() {
    if (!_joined) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text(
              '채널에 연결하는 중입니다...',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        Center(
          child: _remoteUid == null
              ? const Text(
            "상대방 접속 대기 중...",
            style: TextStyle(color: Colors.white),
          )
              : AgoraVideoView(
            controller: VideoViewController.remote(
              rtcEngine: _agoraService.engine!,
              canvas: VideoCanvas(uid: _remoteUid),
              connection: RtcConnection(
                channelId: widget.phoneNumber,
              ),
            ),
          ),
        ),
        Positioned(
          top: 40,
          right: 20,
          width: 120,
          height: 160,
          child: _isVideoOn
              ? Stack(
                  children: [
                    AgoraVideoView(
                      controller: VideoViewController(
                        rtcEngine: _agoraService.engine!,
                        canvas: const Canvas(uid: 0),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: InkWell(
                        onTap: _onSwitchCamera,
                        child: CircleAvatar(
                          radius: 12,
                          backgroundColor: Colors.black.withOpacity(0.5),
                          child: const Icon(Icons.cameraswitch, color: Colors.white, size: 14),
                        ),
                      ),
                    ),
                  ],
                )
              : Container(
            color: Colors.grey[900],
            alignment: Alignment.center,
            child: const Icon(
              Icons.videocam_off,
              color: Colors.white,
              size: 30,
            ),
          ),
        ),
        Positioned(
          top: 50,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                formatDuration(_duration),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ),
        _buildVideoDetectionStatus(),
        _buildVoiceDetectionStatus(),
        _buildFaceBoxesOverlay(),
      ],
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(30),
          child: CircleAvatar(
            radius: 26, 
            backgroundColor: color ?? Colors.grey[800],
            child: Icon(icon, color: Colors.white, size: 28),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12, 
          ),
        ),
      ],
    );
  }
}
