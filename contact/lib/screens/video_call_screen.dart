import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';

import '../models/call_record.dart';
import '../services/agora_service.dart';
import '../services/detection_service.dart';
import '../services/permission_service.dart';
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

  bool _joined = false;
  int? _remoteUid;
  bool _isMuted = false;
  bool _isVideoOn = true;
  bool _isDetectionOn = true;

  late final int _myUid;

  Timer? _callTimer;
  Timer? _detectionTimer;
  Duration _duration = Duration.zero;
  late DateTime _callStartTime;
  bool _timerStarted = false;

  bool _isProcessing = false;
  bool _hasEnded = false;

  double _lastDetectionProbability = 0.0;
  int _deepfakeDetections = 0;

  Rect? _faceRect;
  Size? _snapshotImageSize;

  @override
  void initState() {
    super.initState();
    _myUid = Random().nextInt(999999999);
    _initServices();
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
          _lastDetectionProbability = 0.0;
          _faceRect = null;
          _snapshotImageSize = null;
        }

        if (_isDetectionOn) {
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
              _isDetectionOn &&
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
          _lastDetectionProbability = 0.0;
          _faceRect = null;
          _snapshotImageSize = null;
        });
      } else {
        final fakeProb = result.fakeProb;
        setState(() {
          _lastDetectionProbability = fakeProb;
          _faceRect = result.faceRect;
          _snapshotImageSize =
              Size(result.imageWidth.toDouble(), result.imageHeight.toDouble());
          if (fakeProb >= 0.7) {
            _deepfakeDetections++;
          }
        });

        print('✅ Fake 확률: ${(fakeProb * 100).toStringAsFixed(2)}%');
      }
    } catch (e) {
      print('AI 분석 오류: $e');
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _leaveChannel({bool saveRecord = true}) async {
    if (_hasEnded) return;
    _hasEnded = true;

    _callTimer?.cancel();
    _stopDetectionLoop();

    if (saveRecord) {
      callHistory.add(
        CallRecord(
          phoneNumber: widget.phoneNumber,
          startTime: _callStartTime,
          duration: _duration,
          deepfakeDetections: _deepfakeDetections,
          highestProbability: _lastDetectionProbability,
        ),
      );
    }

    await _agoraService.dispose();
    await _detectionService.dispose();

    if (mounted) {
      Navigator.pop(context);
    }
  }

  Color _currentStatusColor() {
    final p = _lastDetectionProbability;
    if (p >= 0.85) {
      return Colors.red[700]!;
    } else if (p >= 0.7) {
      return Colors.red[400]!;
    } else if (p >= 0.5) {
      return Colors.orange;
    } else if (p >= 0.3) {
      return Colors.green[600]!;
    } else {
      return Colors.green[800]!;
    }
  }

  Widget _buildDetectionStatus() {
    if (!_isDetectionOn || _remoteUid == null) {
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
              'AI 탐지 중...',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      );
    }

    final p = _lastDetectionProbability;
    if (p == 0.0 && _joined) {
      return const SizedBox.shrink();
    }

    String statusText;
    final statusColor = _currentStatusColor();

    if (p >= 0.85) {
      statusText =
      '🚨 위험: 딥페이크 확신! (${(p * 100).toStringAsFixed(1)}%)';
    } else if (p >= 0.7) {
      statusText =
      '⚠️ 경고: 딥페이크 의심 (${(p * 100).toStringAsFixed(1)}%)';
    } else if (p >= 0.5) {
      statusText =
      '🤔 주의: 딥페이크 가능성 (${(p * 100).toStringAsFixed(1)}%)';
    } else if (p >= 0.3) {
      statusText =
      '✅ 안전: Real 가능성 높음 (${(p * 100).toStringAsFixed(1)}%)';
    } else {
      statusText =
      '✨ 안전: Real 확신 (${(p * 100).toStringAsFixed(1)}%)';
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
            color: statusColor.withOpacity(0.8),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            statusText,
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
    if (!_isDetectionOn ||
        _remoteUid == null ||
        _snapshotImageSize == null ||
        _faceRect == null ||
        _lastDetectionProbability == 0.0) {
      return const SizedBox.shrink();
    }

    final boxColor = _currentStatusColor();
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

  void _onToggleDetection() {
    if (!mounted) return;
    setState(() {
      _isDetectionOn = !_isDetectionOn;
      if (!_isDetectionOn) {
        _lastDetectionProbability = 0.0;
        _faceRect = null;
        _snapshotImageSize = null;
        _stopDetectionLoop();
      } else {
        _startDetectionLoop();
      }
    });
  }

  @override
  void dispose() {
    _callTimer?.cancel();
    _stopDetectionLoop();
    _agoraService.dispose();
    _detectionService.dispose();
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
        bottomNavigationBar: _joined
            ? Container(
          color: Colors.black,
          padding: const EdgeInsets.symmetric(
            vertical: 10,
            horizontal: 18,
          ),
          child: SafeArea(
            child: Row(
              mainAxisAlignment:
              MainAxisAlignment.spaceBetween,
              children: [
                _buildControlButton(
                  icon: _isVideoOn
                      ? Icons.videocam
                      : Icons.videocam_off,
                  label:
                  _isVideoOn ? '화면 끄기' : '화면 켜기',
                  onTap: _onToggleVideo,
                ),
                _buildControlButton(
                  icon: _isMuted
                      ? Icons.mic_off
                      : Icons.mic,
                  label:
                  _isMuted ? '음소거 해제' : '음소거',
                  onTap: _onToggleMute,
                ),
                _buildControlButton(
                  icon: Icons.cameraswitch,
                  label: '카메라 전환',
                  onTap: _onSwitchCamera,
                ),
                _buildControlButton(
                  icon: Icons.call_end,
                  label: '통화 종료',
                  color: Colors.red,
                  onTap: () => _leaveChannel(),
                ),
                _buildControlButton(
                  icon: _isDetectionOn
                      ? Icons.shield
                      : Icons.shield_outlined,
                  label:
                  _isDetectionOn ? '탐지 ON' : '탐지 OFF',
                  color: _isDetectionOn
                      ? Colors.greenAccent
                      : Colors.redAccent,
                  onTap: _onToggleDetection,
                ),
              ],
            ),
          ),
        )
            : null,
      ),
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
              ? AgoraVideoView(
            controller: VideoViewController(
              rtcEngine: _agoraService.engine!,
              canvas: const VideoCanvas(uid: 0),
            ),
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
        _buildDetectionStatus(),
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
          child: CircleAvatar(
            radius: 24,
            backgroundColor: color ?? Colors.grey[800],
            child: Icon(icon, color: Colors.white),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}