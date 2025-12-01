import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:contact/repositories/call_repository.dart';
import 'package:contact/services/firestore_service.dart';
import 'package:contact/services/storage_service.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../models/call_record.dart';
import '../services/agora_service.dart';
import '../services/detection_service.dart';
import '../services/permission_service.dart';
import '../utils/timer_formatter.dart';

class VideoCallScreen extends StatefulWidget {
  final String channelId;

  const VideoCallScreen({super.key, required this.channelId});

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  final AgoraService _agoraService = AgoraService();
  final DetectionService _detectionService = DetectionService();
  late final CallRecordRepository _repository;

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
  final List<(String, double, Rect)> _detectionSnapshots = [];
  final List<double> _allFrameProbabilities = [];

  Rect? _faceRect;
  Size? _snapshotImageSize;

  Offset _localViewPosition = const Offset(20.0, 40.0);

  @override
  void initState() {
    super.initState();
    _myUid = Random().nextInt(999999999);
    final firestoreService = FirestoreService();
    final storageService = StorageService();
    _repository = CallRecordRepository(firestoreService, storageService);
    _initServices();
  }

  @override
  void dispose() {
    if (!_hasEnded) {
      _leaveChannel();
    }
    super.dispose();
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
        }

        if (_isDetectionOn) {
          _startDetectionLoop();
        }
      },
      onSnapshotTaken: (filePath) async {
        await _runDetection(filePath);
      },
      onCallEnd: () async {
        if (mounted) {
          await _leaveChannel();
        }
      },
    );

    await _agoraService.engine?.enableVideo();
    await _agoraService.engine?.startPreview();

    await _agoraService.joinChannel(
      channelId: widget.channelId,
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
      if (!mounted) return;

      if (result.faceRect == null ||
          result.imageWidth == 0 ||
          result.imageHeight == 0) {
        setState(() {
          _lastDetectionProbability = 0.0;
          _faceRect = null;
          _snapshotImageSize = null;
        });
        _allFrameProbabilities.add(0.0);
      } else {
        final fakeProb = result.fakeProb;
        _allFrameProbabilities.add(fakeProb);

        if (fakeProb >= 0.5) {
          _detectionSnapshots.add((filePath, fakeProb, result.faceRect!));
        }

        setState(() {
          _lastDetectionProbability = fakeProb;
          _faceRect = result.faceRect;
          _snapshotImageSize =
              Size(result.imageWidth.toDouble(), result.imageHeight.toDouble());
          if (fakeProb >= 0.7) {
            _deepfakeDetections++;
          }
        });
      }
    } catch (e) {
      print('AI 분석 오류: $e');
    } finally {
      if (mounted) {
        _isProcessing = false;
      }
    }
  }

  Future<void> _leaveChannel() async {
    if (_hasEnded) return;
    _hasEnded = true;

    _callTimer?.cancel();
    _stopDetectionLoop();

    if (_remoteUid != null) {
      _processAndSaveCallRecord();
    }

    if (mounted) {
      Navigator.pop(context);
    }

    await _agoraService.dispose();
    await _detectionService.dispose();
  }

  void _processAndSaveCallRecord() {
    Future(() async {
      final now = DateTime.now();
      final datePart = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
      final timePart = "${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}-${now.second.toString().padLeft(2, '0')}";
      final recordId = "${datePart}_${timePart}_${widget.channelId}";

      double maxProb = 0.0;
      if (_detectionSnapshots.isNotEmpty) {
        maxProb = _detectionSnapshots.map((e) => e.$2).reduce(max);
      }

      double averageProb = 0.0;
      if (_allFrameProbabilities.isNotEmpty) {
        averageProb =
            _allFrameProbabilities.reduce((a, b) => a + b) / _allFrameProbabilities.length;
      }

      final placeholderRecord = CallRecord(
        id: recordId,
        channelId: widget.channelId,
        callStartedAt: _callStartTime,
        durationInSeconds: _duration.inSeconds,
        status: CallStatus.processing,
        callEndedAt: DateTime.now(),
      );
      callHistoryNotifier.value = [placeholderRecord, ...callHistoryNotifier.value];

      try {
        List<KeyFrame> localKeyFrames = [];
        _detectionSnapshots.sort((a, b) => b.$2.compareTo(a.$2));
        final topSnapshots = _detectionSnapshots.take(4);
        for (final snapshot in topSnapshots) {
          final croppedImagePath = await _cropAndSaveFace(snapshot.$1, snapshot.$3);
          if (croppedImagePath != null) {
            localKeyFrames.add(KeyFrame(url: croppedImagePath, probability: snapshot.$2));
          }
        }

        final deviceInfo = await _getDeviceInfo();
        final serverInfo = _getServerInfo();

        print('⏳ Firebase에 업로드 시작: $recordId');
        final uploadedKeyFrames = await _repository.uploadKeyFrames(recordId, localKeyFrames);

        final finalRecord = placeholderRecord.copyWith(
          deepfakeDetections: _deepfakeDetections,
          maxFakeProbability: maxProb,
          averageProbability: averageProb,
          keyFrames: uploadedKeyFrames,
          status: CallStatus.done,
          deviceInfo: deviceInfo,
          serverInfo: serverInfo,
        );

        await _repository.createOrUpdateCallRecord(finalRecord);

        final index = callHistoryNotifier.value.indexWhere((rec) => rec.id == recordId);
        if (index != -1) {
          final newList = List<CallRecord>.from(callHistoryNotifier.value);
          newList[index] = finalRecord;
          callHistoryNotifier.value = newList;
          print('✅ Firebase에 업로드 성공: $recordId');
        }

      } catch (e) {
        print('🚨 Firebase 전체 저장 과정 오류: $e');
        final errorRecord = placeholderRecord.copyWith(status: CallStatus.error);
        final index = callHistoryNotifier.value.indexWhere((rec) => rec.id == recordId);
        if (index != -1) {
          final newList = List<CallRecord>.from(callHistoryNotifier.value);
          newList[index] = errorRecord;
          callHistoryNotifier.value = newList;
        }
      }
    });
  }

  Future<Map<String, String>> _getDeviceInfo() async {
    final deviceInfoPlugin = DeviceInfoPlugin();
    final packageInfo = await PackageInfo.fromPlatform();
    String? ipAddress;

    try {
      final response = await Dio().get('https://api.ipify.org');
      ipAddress = response.data;
    } catch (e) {
      ipAddress = 'N/A';
    }

    String deviceModel = 'N/A';
    String osVersion = 'N/A';

    if (Platform.isAndroid) {
      final androidInfo = await deviceInfoPlugin.androidInfo;
      deviceModel = "${androidInfo.manufacturer} ${androidInfo.model}";
      osVersion = "Android ${androidInfo.version.release}";
    } else if (Platform.isIOS) {
      final iosInfo = await deviceInfoPlugin.iosInfo;
      deviceModel = iosInfo.utsname.machine;
      osVersion = "iOS ${iosInfo.systemVersion}";
    }

    return {
      'Device Model': deviceModel,
      'OS Version': osVersion,
      'App Version': packageInfo.version,
      'IP Address': ipAddress ?? 'N/A',
    };
  }

  Map<String, String> _getServerInfo() {
    return {
      'Server Region': 'asia-northeast3 (Seoul)',
      'Analysis Engine': 'AICV-Detector-v1.0',
      // ✅✅✅ 오류 해결을 위해 임시로 하드코딩으로 복원합니다.
      'AI Model': 'best_efficientnet_v13.tflite',
    };
  }

  Future<String?> _cropAndSaveFace(String originalPath, Rect rect) async {
    try {
      final originalFile = File(originalPath);
      if (!await originalFile.exists()) return null;

      final img.Image? originalImage = img.decodeImage(await originalFile.readAsBytes());
      if (originalImage == null) return null;

      final croppedImage = img.copyCrop(
        originalImage,
        x: rect.left.toInt(),
        y: rect.top.toInt(),
        width: rect.width.toInt(),
        height: rect.height.toInt(),
      );

      final tempDir = await getTemporaryDirectory();
      final newPath = '${tempDir.path}/cropped_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final newFile = File(newPath);
      await newFile.writeAsBytes(img.encodeJpg(croppedImage, quality: 95));

      return newPath;
    } catch (e) {
      print('Error cropping image: $e');
      return null;
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

    if (_faceRect == null) {
      return const SizedBox.shrink();
    }

    final p = _lastDetectionProbability;
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
        _lastDetectionProbability < 0.5) {
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

            final double viewAspectRatio = viewW / viewH;
            final double imgAspectRatio = imgW / imgH;

            double scale;
            double offsetX = 0;
            double offsetY = 0;

            if (viewAspectRatio > imgAspectRatio) {
                scale = viewH / imgH;
                offsetX = (viewW - (imgW * scale)) / 2.0;
            } else {
                scale = viewW / imgW;
                offsetY = (viewH - (imgH * scale)) / 2.0;
            }

            final left = rect.left * scale + offsetX;
            final top = rect.top * scale + offsetY;
            final width = rect.width * scale;
            final height = rect.height * scale;

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
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if(didPop) return;
        await _leaveChannel();
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
      padding: const EdgeInsets.symmetric(
        vertical: 10,
        horizontal: 10,
      ),
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
          onTap: _onToggleVideo,
        ),
        _buildControlButton(
          icon: _isMuted ? Icons.mic_off : Icons.mic,
          label: '음소거',
          onTap: _onToggleMute,
        ),
        _buildControlButton(
          icon: _isDetectionOn ? Icons.shield : Icons.shield_outlined,
          label: _isDetectionOn ? '탐지 ON' : '탐지 OFF',
          color: _isDetectionOn ? Colors.teal : Colors.redAccent,
          onTap: _onToggleDetection,
        ),
        _buildControlButton(
          icon: Icons.cameraswitch,
          label: '카메라 전환',
          onTap: _onSwitchCamera,
        ),
        _buildControlButton(
          icon: Icons.call_end,
          label: '종료',
          color: Colors.red,
          onTap: _leaveChannel,
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
                    canvas: VideoCanvas(uid: _remoteUid!),
                    connection: RtcConnection(channelId: widget.channelId),
                  ),
                ),
        ),
        Positioned(
          left: _localViewPosition.dx,
          top: _localViewPosition.dy,
          child: GestureDetector(
            onPanUpdate: (details) {
              setState(() {
                _localViewPosition += details.delta;
              });
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
                child: const Icon(
                  Icons.videocam_off,
                  color: Colors.white,
                  size: 30,
                ),
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
