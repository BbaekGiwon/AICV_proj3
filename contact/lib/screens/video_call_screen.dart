import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../models/call_record.dart';
import '../repositories/call_repository.dart';
import '../services/agora_service.dart';
import '../services/detection_service.dart';
import '../services/firestore_service.dart';
import '../services/permission_service.dart';
import '../services/storage_service.dart';
import '../utils/timer_formatter.dart';

class _RankedImage {
  final String path;
  final double probability;
  _RankedImage(this.path, this.probability);
}

class VideoCallScreen extends StatefulWidget {
  final String phoneNumber;

  const VideoCallScreen({super.key, required this.phoneNumber});

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  final AgoraService _agoraService = AgoraService();
  final DetectionService _detectionService = DetectionService();
  final FirestoreService _firestoreService = FirestoreService();
  final StorageService _storageService = StorageService();
  late final CallRecordRepository _callRecordRepository;

  CallRecord? _currentCall;

  bool _joined = false;
  int? _remoteUid;
  bool _isMuted = false;
  bool _isVideoOn = true;
  bool _isDetectionOn = true;

  late final int _myUid;

  Timer? _callTimer;
  Timer? _detectionTimer;
  Duration _duration = Duration.zero;
  bool _timerStarted = false;

  bool _isProcessing = false;
  bool _hasEnded = false;

  int _deepfakeDetections = 0;
  final List<_RankedImage> _rankedImages = [];
  double _lastDetectionProbability = 0.0;
  Rect? _faceRect;
  Size? _snapshotImageSize;

  Offset _localViewPosition = const Offset(20.0, 40.0);

  @override
  void initState() {
    super.initState();
    _myUid = Random().nextInt(999999999);
    _callRecordRepository =
        CallRecordRepository(_firestoreService, _storageService);
    _initServices();
  }

  Future<void> _initServices() async {
    await PermissionService.requestCameraAndMic();
    await _detectionService.loadModel();

    await _agoraService.init(
      onJoinSuccess: () {
        if (!mounted) return;
        setState(() => _joined = true);
      },
      onRemoteJoined: (uid) {
        if (!mounted) return;
        setState(() => _remoteUid = uid);
        if (!_timerStarted) {
          _timerStarted = true;
          _startCall();
        }
        if (_isDetectionOn) {
          _startDetectionLoop();
        }
      },
      onSnapshotTaken: (filePath) async {
        await _runDetection(filePath);
      },
    );

    await _agoraService.engine?.enableVideo();
    await _agoraService.engine?.startPreview();

    await _agoraService.joinChannel(
      channelId: widget.phoneNumber,
      uid: _myUid,
    );
  }

  void _startCall() {
    final callStartTime = DateTime.now();
    final date =
        '${callStartTime.year}-${callStartTime.month.toString().padLeft(2, '0')}-${callStartTime.day.toString().padLeft(2, '0')}';
    final time =
        '${callStartTime.hour.toString().padLeft(2, '0')}-${callStartTime.minute.toString().padLeft(2, '0')}-${callStartTime.second.toString().padLeft(2, '0')}';
    final safeChannelId = widget.phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
    final newRecordId = '${date}_${time}_$safeChannelId';

    _currentCall = CallRecord(
      id: newRecordId,
      channelId: widget.phoneNumber,
      callStartedAt: callStartTime,
      status: CallStatus.processing, // ✅ 분석 중 상태로 생성
    );

    final currentHistory = callHistoryNotifier.value;
    callHistoryNotifier.value = [_currentCall!, ...currentHistory];

    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final newDuration = DateTime.now().difference(callStartTime);
      setState(() => _duration = newDuration);
    });
  }

  void _startDetectionLoop() {
    _detectionTimer?.cancel();
    _detectionTimer =
        Timer.periodic(const Duration(milliseconds: 1000), (_) async {
      if (_remoteUid != null && _isDetectionOn && !_isProcessing) {
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
      if (!mounted) {
        if (result.croppedFacePath != null) {
          File(result.croppedFacePath!).delete().catchError((e) {});
        }
        return;
      }

      if (result.faceRect == null || result.imageWidth == 0) {
        setState(() {
          _faceRect = null;
          _snapshotImageSize = null;
          _lastDetectionProbability = 0.0;
        });
      } else {
        final fakeProb = result.fakeProb;
        setState(() {
          _lastDetectionProbability = fakeProb;
          if (fakeProb >= 0.7) _deepfakeDetections++;
          _faceRect = result.faceRect;
          _snapshotImageSize =
              Size(result.imageWidth.toDouble(), result.imageHeight.toDouble());
        });

        if (fakeProb >= 0.5 && result.croppedFacePath != null) {
          _rankedImages.add(_RankedImage(result.croppedFacePath!, fakeProb));
          _rankedImages.sort((a, b) => b.probability.compareTo(a.probability));
          if (_rankedImages.length > 4) {
            final removed = _rankedImages.removeLast();
            File(removed.path).delete().catchError((e) {});
          }
        } else if (result.croppedFacePath != null) {
          File(result.croppedFacePath!).delete().catchError((e) {});
        }

        print('✅ 영상 Fake 확률: ${(fakeProb * 100).toStringAsFixed(2)}%');
      }
    } catch (e) {
      print('AI 분석 오류: $e');
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      } else {
        _isProcessing = false;
      }
    }
  }

  void _leaveChannel() {
    if (_hasEnded) return;
    _hasEnded = true;

    _callTimer?.cancel();
    _stopDetectionLoop();

    if (mounted) {
      Navigator.pop(context);
    }

    _saveAndCleanupInBackground();
  }

  Future<void> _saveAndCleanupInBackground() async {
    if (_currentCall != null) {
      List<KeyFrame> keyFrames = [];
      String? highestProbImageName;
      double maxFakeProbability = 0.0;

      if (_rankedImages.isNotEmpty) {
        final topImage = _rankedImages.first;
        maxFakeProbability = topImage.probability;
        highestProbImageName = p.basename(topImage.path);

        for (final rankedImage in _rankedImages) {
          try {
            final url = await _storageService.uploadSingleKeyFrame(
              recordId: _currentCall!.id,
              filePath: rankedImage.path,
            );
            keyFrames.add(KeyFrame(url: url, probability: rankedImage.probability));
          } catch (e) {
            print('🚨 [DEBUG] 키 프레임 이미지 업로드 실패: ${rankedImage.path} - $e');
          } finally {
            File(rankedImage.path)
                .delete()
                .catchError((e) => print('🚨 [DEBUG] 임시 파일 삭제 실패: $e'));
          }
        }
      }

      final finalRecord = _currentCall!.copyWith(
        callEndedAt: DateTime.now(),
        durationInSeconds: _duration.inSeconds,
        deepfakeDetections: _deepfakeDetections,
        maxFakeProbability: maxFakeProbability,
        status: CallStatus.done,
        highestProbImageName: highestProbImageName, // ✅ 원래대로 복구
        highestProbKeyFrameUrl:
            keyFrames.isNotEmpty ? keyFrames.first.url : null,
        keyFrames: keyFrames,
      );

      final currentHistory = callHistoryNotifier.value;
      final index = currentHistory.indexWhere((c) => c.id == finalRecord.id);
      if (index != -1) {
        currentHistory[index] = finalRecord;
        callHistoryNotifier.value = List.from(currentHistory);
      }

      try {
        await _callRecordRepository.createOrUpdateCallRecord(finalRecord);
        print('✅ [DEBUG] 최종 통화 기록 원격 저장 완료.');
      } catch (e) {
        print('🚨 [DEBUG] 최종 통화 기록 원격 저장 실패: $e');
      }
    }

    await _agoraService.dispose();
    await _detectionService.dispose();

    _clearRankedImages();
  }

  void _clearRankedImages() {
    for (final image in _rankedImages) {
      File(image.path).delete().catchError((e) {});
    }
    _rankedImages.clear();
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
        _faceRect = null;
        _snapshotImageSize = null;
        _clearRankedImages();
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
    if (!_hasEnded) {
      _agoraService.dispose();
      _detectionService.dispose();
      _clearRankedImages();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_hasEnded) return false;
        _leaveChannel();
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: _buildBody(),
        bottomNavigationBar: _buildBottomNavigationBar(),
      ),
    );
  }

  Widget _buildBottomNavigationBar() {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
      child: SafeArea(
        child: _joined ? _buildConnectedControls() : _buildConnectingControls(),
      ),
    );
  }

  Widget _buildConnectingControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildControlButton(
          icon: Icons.call_end,
          label: '취소',
          color: Colors.red,
          onTap: _leaveChannel,
        ),
      ],
    );
  }

  Widget _buildConnectedControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _buildControlButton(
            icon: _isVideoOn ? Icons.videocam : Icons.videocam_off,
            label: '화면',
            onTap: _onToggleVideo),
        _buildControlButton(
            icon: _isMuted ? Icons.mic_off : Icons.mic,
            label: '음소거',
            onTap: _onToggleMute),
        _buildControlButton(
          icon: _isDetectionOn ? Icons.shield : Icons.shield_outlined,
          label: _isDetectionOn ? '탐지 ON' : '탐지 OFF',
          color: _isDetectionOn ? Colors.teal : Colors.redAccent,
          onTap: _onToggleDetection,
        ),
        _buildControlButton(
            icon: Icons.cameraswitch, label: '카메라 전환', onTap: _onSwitchCamera),
        _buildControlButton(
            icon: Icons.call_end,
            label: '종료',
            color: Colors.red,
            onTap: _leaveChannel),
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
            Text('채널에 연결하는 중입니다...', style: TextStyle(color: Colors.white)),
          ],
        ),
      );
    }
    return Stack(
      children: [
        Center(
          child: _remoteUid == null
              ? const Text("상대방 접속 대기 중...",
                  style: TextStyle(color: Colors.white))
              : AgoraVideoView(
                  controller: VideoViewController.remote(
                    rtcEngine: _agoraService.engine!,
                    canvas: VideoCanvas(uid: _remoteUid!),
                    connection: RtcConnection(channelId: widget.phoneNumber),
                  ),
                ),
        ),
        Positioned(
          left: _localViewPosition.dx,
          top: _localViewPosition.dy,
          child: GestureDetector(
            onPanUpdate: (details) {
              setState(() => _localViewPosition += details.delta);
            },
            child: SizedBox(
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
                      child: const Icon(Icons.videocam_off,
                          color: Colors.white, size: 30),
                    ),
            ),
          ),
        ),
        Positioned(
          top: 50,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(formatDuration(_duration),
                  style: const TextStyle(color: Colors.white, fontSize: 16)),
            ),
          ),
        ),
        _buildDetectionStatus(),
        _buildFaceBoxesOverlay(),
      ],
    );
  }

  Widget _buildDetectionStatus() {
    if (!_isDetectionOn || _remoteUid == null) return const SizedBox.shrink();

    String statusText;
    Color statusColor;

    if (_isProcessing) {
      statusText = 'AI 탐지 중...';
      statusColor = Colors.blue;
    } else {
      final p = _lastDetectionProbability;
      if (p == 0.0 && _joined) return const SizedBox.shrink();

      if (p >= 0.85) {
        statusText = '🚨 위험: 딥페이크 확신! (${(p * 100).toStringAsFixed(1)}%)';
        statusColor = Colors.red[700]!;
      } else if (p >= 0.7) {
        statusText = '⚠️ 경고: 딥페이크 의심 (${(p * 100).toStringAsFixed(1)}%)';
        statusColor = Colors.red[400]!;
      } else if (p >= 0.5) {
        statusText = '🤔 주의: 딥페이크 가능성 (${(p * 100).toStringAsFixed(1)}%)';
        statusColor = Colors.orange;
      } else if (p >= 0.3) {
        statusText = '✅ 안전: Real 가능성 높음 (${(p * 100).toStringAsFixed(1)}%)';
        statusColor = Colors.green[600]!;
      } else {
        statusText = '✨ 안전: Real 확신 (${(p * 100).toStringAsFixed(1)}%)';
        statusColor = Colors.green[800]!;
      }
    }

    return Positioned(
      top: 90,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.8),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(statusText,
              style:
                  const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  Widget _buildFaceBoxesOverlay() {
    if (!_isDetectionOn ||
        _remoteUid == null ||
        _snapshotImageSize == null ||
        _faceRect == null ||
        _lastDetectionProbability < 0.5) {
      return const SizedBox.shrink();
    }

    Color boxColor;
    final p = _lastDetectionProbability;
    if (p >= 0.85) {
      boxColor = Colors.red[700]!;
    } else if (p >= 0.7) {
      boxColor = Colors.red[400]!;
    } else {
      boxColor = Colors.orange;
    }

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
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
      ],
    );
  }
}
