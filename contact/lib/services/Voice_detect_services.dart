// lib/services/voice_detect_service.dart
import 'dart:async';
import 'package:flutter/services.dart';

/// 딥보이스(YAMNet) 탐지를 담당하는 서비스.
/// - 네이티브(Android)에서 오는 fake 확률(double)을 스트림으로 받음
/// - 탐지 시작/중지를 네이티브에 요청
class VoiceDetectService {
  // 싱글톤(앱 전체에서 하나만 쓰기)
  VoiceDetectService._internal();
  static final VoiceDetectService instance = VoiceDetectService._internal();

  // 🔗 네이티브와 통신할 채널 이름 (Android에서도 똑같이 써야 함)
  static const MethodChannel _methodChannel =
  MethodChannel('voice_detect/method');
  static const EventChannel _eventChannel =
  EventChannel('voice_detect/events');

  // fake 확률을 흘려보낼 파이프(스트림 컨트롤러)
  final StreamController<double> _fakeProbController =
  StreamController<double>.broadcast();

  StreamSubscription? _eventSub;

  /// 딥보이스 fake 확률 스트림 (0.0 ~ 1.0)
  Stream<double> get fakeProbabilityStream => _fakeProbController.stream;

  bool _isListening = false;

  /// 네이티브 EventChannel을 구독 시작
  void initListening() {
    if (_isListening) return;
    _isListening = true;

    _eventSub = _eventChannel
        .receiveBroadcastStream()
        .listen((event) {
      try {
        // 네이티브에서 double 그대로 보내준다고 가정
        final double prob = (event as num).toDouble();
        _fakeProbController.add(prob);
      } catch (e) {
        _fakeProbController.add(0.0);
      }
    }, onError: (error) {
      _fakeProbController.add(0.0);
    });
  }

  /// 네이티브에 "탐지 시작" 요청
  Future<void> startDetection() async {
    initListening(); // 혹시 안 되어 있으면 스트림 구독도 같이 시작
    try {
      await _methodChannel.invokeMethod('startDetection');
    } on PlatformException {
      // 실패해도 앱 터지지 않게 그냥 무시
    }
  }

  /// 네이티브에 "탐지 중지" 요청
  Future<void> stopDetection() async {
    try {
      await _methodChannel.invokeMethod('stopDetection');
    } on PlatformException {
      // 실패해도 앱 터지지 않게 그냥 무시
    }
  }

  /// 앱 종료 시 혹은 더 이상 안 쓸 때 정리
  void dispose() {
    _eventSub?.cancel();
    _fakeProbController.close();
    _isListening = false;
  }
}
