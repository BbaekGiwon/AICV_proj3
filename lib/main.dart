  import 'dart:async';
  import 'dart:io';
  import 'dart:math';

  import 'package:flutter/material.dart';
  import 'package:firebase_core/firebase_core.dart';
  import 'firebase_options.dart';
  
  import 'package:flutter/material.dart';
  import 'package:permission_handler/permission_handler.dart';
  import 'package:agora_rtc_engine/agora_rtc_engine.dart';
  import 'package:tflite_v2/tflite_v2.dart';
  import 'package:path_provider/path_provider.dart';
  
  // ML Kit 얼굴 검출
  import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
  // 이미지 크롭용
  import 'package:image/image.dart' as img;
  
  // ================== Agora 설정 ==================
  // ⚠️ 주의: 토큰이 만료되었을 수 있습니다. 테스트 전 Agora 콘솔에서 유효한 토큰으로 교체하세요.
  const String appId = "fc72b3363009410b8aca359a17879619";
  const String token = "007eJxTYGDY1ZFl4qhvyz/Ta779b9cXz0pFleYwV9/vlFl1w27zLSMFhrRkc6MkY2MzYwMDSxNDgySLxOREY1PLRENzC3NLM0PLLf9VMhsCGRm29B1jZGSAQBCfhcHQyNiEgQEAtjkdNg==";
  
  // ================== 통화 기록 모델 ==================
  class CallRecord {
    final String phoneNumber;
    final DateTime startTime;
    final Duration duration;
    final int deepfakeDetections;
    final double highestProbability;
  
    CallRecord({
      required this.phoneNumber,
      required this.startTime,
      required this.duration,
      this.deepfakeDetections = 0,
      this.highestProbability = 0.0,
    });
  }
  
  final List<CallRecord> callHistory = [];
  
  
  // ================== 앱 시작 ==================

  Future<void> main() async {
    // ✅ 제일 먼저 호출
    WidgetsFlutterBinding.ensureInitialized();

    // ✅ 그 다음에 Firebase 초기화
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // ✅ 마지막에 runApp
    runApp(const MyApp());
  }


  class MyApp extends StatelessWidget {
    const MyApp({super.key});
  
    @override
    Widget build(BuildContext context) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: false,
          brightness: Brightness.light,
          scaffoldBackgroundColor: Colors.white,
  
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
          ),
        ),
        home: const SplashScreen(),
      );
    }
  }
  
  // ================== 스플래시 화면 ==================
  class SplashScreen extends StatefulWidget {
    const SplashScreen({super.key});
  
    @override
    State<SplashScreen> createState() => _SplashScreenState();
  }
  
  class _SplashScreenState extends State<SplashScreen> {
    @override
    void initState() {
      super.initState();
      Timer(const Duration(seconds: 2), () {
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const MainScreen()),
          );
        }
      });
    }
  
    @override
    Widget build(BuildContext context) {
      return const Scaffold(
        backgroundColor: Colors.blueAccent,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.videocam_rounded, size: 100, color: Colors.white),
              SizedBox(height: 20),
              Text(
                'Deepfake Killer',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }
  }
  
  // ================== 메인 화면 (하단 탭)  =====================
  class MainScreen extends StatefulWidget {
    const MainScreen({super.key});
  
    @override
    State<MainScreen> createState() => _MainScreenState();
  }
  
  class _MainScreenState extends State<MainScreen> {
    int _selectedIndex = 0;
    late final List<Widget> _pages;
  
    @override
    void initState() {
      super.initState();
      // 💡 통화 종료 시 상태 갱신 및 History 탭으로 이동하는 콜백 연결
      _pages = [
        DialScreen(onCallEnded: _refreshAndNavigateToHistory),
        const HistoryScreen(),
      ];
    }
  
    void _refreshAndNavigateToHistory() {
      if (mounted) {
        setState(() {
          _selectedIndex = 1; // 통화 기록 탭으로 이동
        });
      }
    }
  
    void _onItemTapped(int index) {
      if (!mounted) return;
      setState(() {
        _selectedIndex = index;
      });
    }
  
    @override
    Widget build(BuildContext context) {
      return Scaffold(
        appBar: AppBar(
          title: Text(_selectedIndex == 0 ? 'Deepfake Killer' : '통화 기록'),
          centerTitle: true,
        ),
        body: IndexedStack(
          index: _selectedIndex,
          children: _pages,
        ),
        bottomNavigationBar: BottomNavigationBar(
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.dialpad),
              label: '키패드',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.history),
              label: '통화 기록',
            ),
          ],
          currentIndex: _selectedIndex,
          onTap: _onItemTapped,
          selectedItemColor: Colors.blueAccent,
          unselectedItemColor: Colors.grey,
        ),
      );
    }
  }
  
  // ================== 키패드 화면 ==================
  class DialScreen extends StatefulWidget {
    final VoidCallback onCallEnded;
  
    const DialScreen({super.key, required this.onCallEnded});
  
    @override
    State<DialScreen> createState() => _DialScreenState();
  }
  
  class _DialScreenState extends State<DialScreen> {
    String _dialedNumber = '';
  
    void _onKeyPressed(String value) {
      if (!mounted) return;
      setState(() {
        if (_dialedNumber.length < 20) {
          _dialedNumber += value;
        }
      });
    }
  
    void _onBackspace() {
      if (_dialedNumber.isEmpty || !mounted) return;
      setState(() {
        _dialedNumber = _dialedNumber.substring(0, _dialedNumber.length - 1);
      });
    }
  
    void _onCallPressed() async {
      if (_dialedNumber.isEmpty) return;
  
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VideoCallScreen(phoneNumber: _dialedNumber),
        ),
      );
      // VideoCallScreen에서 pop된 후 통화 종료 콜백 호출
      widget.onCallEnded();
    }
  
    @override
    Widget build(BuildContext context) {
      return SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 24),
            Text(
              _dialedNumber.isEmpty ? '번호를 입력하세요' : _dialedNumber,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildKeypadRow(['1', '2', '3']),
                    const SizedBox(height: 10),
                    _buildKeypadRow(['4', '5', '6']),
                    const SizedBox(height: 10),
                    _buildKeypadRow(['7', '8', '9']),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildKeypadButton('*'),
                        _buildKeypadButton('0'),
                        _buildBackspaceButton(),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 20.0),
              child: ElevatedButton.icon(
                onPressed: _dialedNumber.isEmpty ? null : _onCallPressed,
                icon: const Icon(Icons.videocam),
                label: const Text('영상통화', style: TextStyle(fontSize: 18)),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(220, 50),
                  shape: const StadiumBorder(),
                ),
              ),
            ),
          ],
        ),
      );
    }
  
    Widget _buildKeypadRow(List<String> values) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: values.map((v) => _buildKeypadButton(v)).toList(),
      );
    }
  
    Widget _buildKeypadButton(String value) {
      return SizedBox(
        width: 70,
        height: 70,
        child: ElevatedButton(
          onPressed: () => _onKeyPressed(value),
          style: ElevatedButton.styleFrom(shape: const CircleBorder()),
          child: Text(value, style: const TextStyle(fontSize: 24)),
        ),
      );
    }
  
    Widget _buildBackspaceButton() {
      return SizedBox(
        width: 70,
        height: 70,
        child: ElevatedButton(
          onPressed: _onBackspace,
          style: ElevatedButton.styleFrom(shape: const CircleBorder()),
          child: const Icon(Icons.backspace),
        ),
      );
    }
  }
  
  // ================== 통화 기록 화면 ==================
  class HistoryScreen extends StatefulWidget {
    const HistoryScreen({super.key});
  
    @override
    State<HistoryScreen> createState() => _HistoryScreenState();
  }
  
  class _HistoryScreenState extends State<HistoryScreen> {
    @override
    Widget build(BuildContext context) {
      final reversedHistory = callHistory.reversed.toList();
  
      if (reversedHistory.isEmpty) {
        return const Center(child: Text('통화 기록이 없습니다.'));
      }
  
      return ListView.builder(
        itemCount: reversedHistory.length,
        itemBuilder: (context, index) {
          final record = reversedHistory[index];
          return ListTile(
            leading: const Icon(Icons.videocam_outlined, color: Colors.grey),
            title: Text(
              record.phoneNumber,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            subtitle: Text(
              record.startTime.toLocal().toString().substring(0, 16),
            ),
            trailing: Text('${record.duration.inSeconds}초'),
          );
        },
      );
    }
  }
  
  // ================== 영상통화 화면 (딥페이크 + 얼굴박스) ==================
  class VideoCallScreen extends StatefulWidget {
    final String phoneNumber;
  
    const VideoCallScreen({super.key, required this.phoneNumber});
  
    @override
    State<VideoCallScreen> createState() => _VideoCallScreenState();
  }
  
  class _VideoCallScreenState extends State<VideoCallScreen> {
    RtcEngine? _engine;
    int? _remoteUid;
    bool _joined = false;
    bool _isMuted = false;
    bool _isVideoOn = true;
    bool _isDetectionOn = true;
  
    Timer? _callTimer;
    Timer? _detectionTimer;
    Duration _duration = Duration.zero;
    bool _isProcessing = false;
  
    late final int _myUid;
    late DateTime _callStartTime;
  
    double _lastDetectionProbability = 0.0;
    int _deepfakeDetections = 0;
  
    bool _timerStarted = false;
  
    // ML Kit 얼굴 검출기
    late final FaceDetector _faceDetector;
  
    // 얼굴 박스 오버레이용 데이터
    List<Rect> _faceRects = [];
    Size? _snapshotImageSize;
  
    // ⭐ 여러 경로에서 중복 종료 방지용 플래그
    bool _hasEnded = false;
  
    @override
    void initState() {
      super.initState();
      _myUid = Random().nextInt(999999999);
  
      // ML Kit FaceDetector 설정
      final options = FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
        enableLandmarks: false,
        enableContours: false,
        enableClassification: false,
      );
      _faceDetector = FaceDetector(options: options);
  
      _loadModel();
      _initAgora();
    }
  
    // ================== TFLite 모델 로드 ==================
    Future<void> _loadModel() async {
      try {
        await Tflite.loadModel(
          model: "assets/efficientnet_v02.tflite",
          labels: "assets/efficientnet_v02_labels.txt", // fake 한 줄
          isAsset: true,
        );
        print('✅ EfficientNet + labels 모델 로드 성공');
      } catch (e) {
        print('🚨 모델 로드 실패: $e');
      }
    }
  
    // ================== Agora 초기화 ==================
    Future<void> _initAgora() async {
      await [Permission.camera, Permission.microphone].request();
  
      _engine = createAgoraRtcEngine();
      await _engine!.initialize(const RtcEngineContext(appId: appId));
  
      _engine!.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (connection, elapsed) {
            if (!mounted) return;
            setState(() {
              _joined = true;
            });
          },
          onUserJoined: (connection, uid, elapsed) {
            if (!mounted) return;
            setState(() => _remoteUid = uid);
  
            if (!_timerStarted) {
              _timerStarted = true;
              _startCallTimer();
              _lastDetectionProbability = 0.0;
              _faceRects = [];
            }
  
            // ✅ 상대 들어오면 탐지 시작
            if (_isDetectionOn) {
              _startDetectionLoop();
            }
            // 상대방이 나가더라도, 사용자가 어떻게 나가는지에 따라
            // _leaveChannel()이 호출되며 기록이 저장됨
          },
          onSnapshotTaken: (connection, uid, filePath, width, height, errCode) {
            if (uid == _remoteUid) {
              _runAiOnSnapshot(filePath);
            }
          },
          onError: (err, msg) => print("⚠️ Agora Error: $err, $msg"),
        ),
      );
  
      await _engine!.setChannelProfile(
        ChannelProfileType.channelProfileCommunication,
      );
      await _engine!.setClientRole(
        role: ClientRoleType.clientRoleBroadcaster,
      );
      await _engine!.enableVideo();
      await _engine!.startPreview();
  
      await _engine!.joinChannel(
        token: token,
        channelId: widget.phoneNumber,
        uid: _myUid,
        options: const ChannelMediaOptions(),
      );
    }
  
    // ================== 감지 루프 (스냅샷) ==================
    void _startDetectionLoop() {
      _detectionTimer?.cancel();
      _detectionTimer =
          Timer.periodic(const Duration(milliseconds: 1500), (timer) {
            if (_remoteUid != null && _isDetectionOn && !_isProcessing) {
              _takeSnapshot();
            }
          });
    }
  
    void _stopDetectionLoop() {
      _detectionTimer?.cancel();
      _detectionTimer = null;
    }
  
    Future<void> _takeSnapshot() async {
      if (_remoteUid == null || _engine == null) return;
  
      try {
        final directory = await getTemporaryDirectory();
        final String path = '${directory.path}/temp_frame.jpg';
  
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
  
        await _engine!.takeSnapshot(
          uid: _remoteUid!,
          filePath: path,
        );
      } catch (e) {
        print("스냅샷 요청 실패: $e");
      }
    }
  
    // ================== TFLite + ML Kit (얼굴 검출 + 크롭) ==================
    Future<void> _runAiOnSnapshot(String filePath) async {
      if (_isProcessing) return;
      _isProcessing = true;
  
      try {
        final file = File(filePath);
        if (!await file.exists() || await file.length() == 0) {
          print("🚨 이미지 없음 또는 0바이트. 분석 스킵");
          _isProcessing = false;
          return;
        }
  
        // 1) ML Kit으로 얼굴 검출
        final inputImage = InputImage.fromFilePath(filePath);
        final faces = await _faceDetector.processImage(inputImage);
  
        if (faces.isEmpty) {
          print("🙂 얼굴이 안 보임 → 딥페이크 탐지 스킵");
          if (mounted) {
            setState(() {
              _faceRects = [];
              _snapshotImageSize = null;
              _lastDetectionProbability = 0.0;
            });
          }
          _isProcessing = false;
          return;
        }
  
        // 2) 원본 이미지 디코딩 (크롭 + 오버레이 좌표용)
        final bytes = await file.readAsBytes();
        final originalImage = img.decodeImage(bytes);
        if (originalImage == null) {
          print("🚨 이미지 디코딩 실패");
          _isProcessing = false;
          return;
        }
  
        final imgWidth = originalImage.width;
        final imgHeight = originalImage.height;
  
        // ML Kit boundingBox 기준으로 가장 큰 얼굴 하나 선택
        Face mainFace = faces[0];
        double maxArea =
            mainFace.boundingBox.width * mainFace.boundingBox.height;
        for (final f in faces.skip(1)) {
          final area = f.boundingBox.width * f.boundingBox.height;
          if (area > maxArea) {
            maxArea = area;
            mainFace = f;
          }
        }
  
        final box = mainFace.boundingBox;
  
        // 좌표 clamp
        int x = box.left.floor().clamp(0, imgWidth - 1);
        int y = box.top.floor().clamp(0, imgHeight - 1);
        int w = box.width.floor().clamp(1, imgWidth - x);
        int h = box.height.floor().clamp(1, imgHeight - y);
  
        // 3) 얼굴 크롭
        final cropped = img.copyCrop(
          originalImage,
          x: x,
          y: y,
          width: w,
          height: h,
        );
  
        final tempDir = await getTemporaryDirectory();
        final croppedPath = '${tempDir.path}/temp_face.jpg';
        final croppedFile = File(croppedPath);
        await croppedFile.writeAsBytes(img.encodeJpg(cropped));
  
        // 오버레이용 데이터 저장
        if (mounted) {
          setState(() {
            _snapshotImageSize = Size(
              imgWidth.toDouble(),
              imgHeight.toDouble(),
            );
            _faceRects = [box]; // 메인 얼굴만 박스
          });
        }
  
        // 4) 크롭된 얼굴에 대해 TFLite 실행
        final recognitions = await Tflite.runModelOnImage(
          path: croppedPath,
          imageMean: 127.5,
          imageStd: 127.5,
          numResults: 1, // 출력 1개짜리 모델
          threshold: 0.1,
          asynch: true,
        );
  
        await croppedFile.delete(); // 크롭 파일 삭제
        await file.delete(); // 원본 스냅샷도 삭제
  
        if (recognitions != null && recognitions.isNotEmpty) {
          final result = recognitions[0];
          final double fakeProb =
              (result['confidence'] as double?) ?? 0.0; // 0~1
  
          if (mounted) {
            setState(() {
              _lastDetectionProbability = fakeProb;
              if (_lastDetectionProbability >= 0.7) {
                _deepfakeDetections++;
              }
            });
          }
  
          print('✅ AI 인식 결과: $recognitions');
          print(
              '✅ Fake 확률 (얼굴 크롭 기준): ${(fakeProb * 100).toStringAsFixed(2)}%');
        }
      } catch (e) {
        print("AI 분석 오류 (ML Kit/TFLite): $e");
      } finally {
        _isProcessing = false;
      }
    }
  
    // ================== 일반 통화 로직 ==================
    void _startCallTimer() {
      _callStartTime = DateTime.now();
      _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {
          _duration = DateTime.now().difference(_callStartTime);
        });
      });
    }
  
    String _formatDuration(Duration duration) {
      String twoDigits(int n) => n.toString().padLeft(2, '0');
      final minutes = twoDigits(duration.inMinutes.remainder(60));
      final seconds = twoDigits(duration.inSeconds.remainder(60));
      return '$minutes:$seconds';
    }
  
    @override
    void dispose() {
      _callTimer?.cancel();
      _detectionTimer?.cancel();
  
      Tflite.close();
      _faceDetector.close();
  
      _engine?.leaveChannel();
      _engine?.stopPreview();
      _engine?.release();
  
      super.dispose();
    }
  
    Future<void> _leaveChannel({bool saveRecord = true}) async {
      // 이미 종료 처리했다면 또 하지 않기
      if (_hasEnded) return;
      _hasEnded = true;
  
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
  
      try {
        await _engine?.leaveChannel();
        await _engine?.stopPreview();
        await _engine?.release();
      } catch (_) {}
  
      if (mounted) {
        Navigator.pop(context);
      }
    }
  
    void _onToggleMute() {
      if (!mounted) return;
      setState(() => _isMuted = !_isMuted);
      _engine?.muteLocalAudioStream(_isMuted);
    }
  
    void _onToggleVideo() {
      if (!mounted) return;
      setState(() => _isVideoOn = !_isVideoOn);
      _engine?.muteLocalVideoStream(!_isVideoOn);
    }
  
    void _onSwitchCamera() => _engine?.switchCamera();
  
    void _onToggleDetection() {
      if (!mounted) return;
      setState(() {
        _isDetectionOn = !_isDetectionOn;
        if (!_isDetectionOn) {
          _lastDetectionProbability = 0.0;
          _faceRects = [];
          _snapshotImageSize = null;
          _stopDetectionLoop();
        } else {
          _startDetectionLoop();
        }
      });
    }
  
    // ================== 상태별 색상 공통 함수 ==================
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
  
    // ================== 딥페이크 상태 텍스트 UI ==================
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
                    color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        );
      }
  
      final probability = _lastDetectionProbability;
  
      if (probability == 0.0 && _joined) {
        // 아직 탐지 결과 없음 → 메시지 숨김
        return const SizedBox.shrink();
      }
  
      String statusText;
      Color statusColor = _currentStatusColor();
  
      if (probability >= 0.85) {
        statusText =
        '🚨 위험: 딥페이크 확신! (${(probability * 100).toStringAsFixed(1)}%)';
      } else if (probability >= 0.7) {
        statusText =
        '⚠️ 경고: 딥페이크 의심 (${(probability * 100).toStringAsFixed(1)}%)';
      } else if (probability >= 0.5) {
        statusText =
        '🤔 주의: 딥페이크 가능성 (${(probability * 100).toStringAsFixed(1)}%)';
      } else if (probability >= 0.3) {
        statusText =
        '✅ 안전: Real 가능성 높음 (${(probability * 100).toStringAsFixed(1)}%)';
      } else {
        statusText =
        '✨ 안전: Real 확신 (${(probability * 100).toStringAsFixed(1)}%)';
      }
  
      return Positioned(
        top: 90,
        left: 0,
        right: 0,
        child: Center(
          child: Container(
            padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.8),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              statusText,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      );
    }
  
    // ================== 얼굴 박스 오버레이 ==================
    Widget _buildFaceBoxesOverlay() {
      if (!_isDetectionOn ||
          _remoteUid == null ||
          _snapshotImageSize == null ||
          _faceRects.isEmpty ||
          _lastDetectionProbability == 0.0) {
        return const SizedBox.shrink();
      }
  
      final boxColor = _currentStatusColor();
  
      return Positioned.fill(
        child: IgnorePointer(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final viewW = constraints.maxWidth;
              final viewH = constraints.maxHeight;
  
              final imgW = _snapshotImageSize!.width;
              final imgH = _snapshotImageSize!.height;
  
              return Stack(
                children: _faceRects.map((r) {
                  final left = r.left / imgW * viewW;
                  final top = r.top / imgH * viewH;
                  final width = r.width / imgW * viewW;
                  final height = r.height / imgH * viewH;
  
                  return Positioned(
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
                  );
                }).toList(),
              );
            },
          ),
        ),
      );
    }
  
    // ================== 화면/버튼 UI ==================
    @override
    Widget build(BuildContext context) {
      return WillPopScope(
        onWillPop: () async {
          // 뒤로가기(◀/제스처)도 항상 _leaveChannel()을 통해 종료 + 기록 저장
          await _leaveChannel();
          // 우리가 직접 pop 했으니 기본 pop은 막기
          return false;
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: _buildBody(),
          bottomNavigationBar: _joined
              ? Container(
            color: Colors.black,
            padding: const EdgeInsets.symmetric(
                vertical: 10, horizontal: 18),
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
                    icon:
                    _isMuted ? Icons.mic_off : Icons.mic,
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
                    label: _isDetectionOn
                        ? '탐지 ON'
                        : '탐지 OFF',
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
                rtcEngine: _engine!,
                canvas: VideoCanvas(uid: _remoteUid),
                connection: RtcConnection(
                    channelId: widget.phoneNumber),
              ),
            ),
          ),
          // 내 화면
          Positioned(
            top: 40,
            right: 20,
            width: 120,
            height: 160,
            child: _isVideoOn
                ? AgoraVideoView(
              controller: VideoViewController(
                rtcEngine: _engine!,
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
          // 타이머
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
                  _formatDuration(_duration),
                  style: const TextStyle(
                      color: Colors.white, fontSize: 16),
                ),
              ),
            ),
          ),
          _buildDetectionStatus(),
          _buildFaceBoxesOverlay(), // 얼굴 박스 (색 = 상태 색)
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
