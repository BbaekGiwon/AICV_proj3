import 'package:flutter/foundation.dart';

// ✨ 보고서 화면에 필요한 'URL과 확률'을 한 세트로 묶는 클래스
class KeyFrame {
  final String url;
  final double probability;

  KeyFrame({required this.url, required this.probability});

  // Firestore에 저장하기 위해 Map 형태로 변환하는 메서드
  Map<String, dynamic> toMap() {
    return {
      'url': url,
      'probability': probability,
    };
  }
}

enum CallStatus { processing, done, error }

enum RiskLevel { safe, caution, warning, danger, unknown }

class CallRecord {
  final String id;
  final String channelId;
  final DateTime callStartedAt;
  final DateTime? callEndedAt;
  final int durationInSeconds;

  final int deepfakeDetections;
  final double maxFakeProbability;
  final RiskLevel riskLevel;

  final String? highestProbImageName;
  final String? highestProbKeyFrameUrl;
  final String? highestProbGradCamUrl;

  final CallStatus status;
  final String? reportPdfUrl;

  // ✨ String 리스트가 아닌, KeyFrame 객체의 리스트로 변경
  final List<KeyFrame> keyFrames;
  final List<String> gradcamImages;

  CallRecord({
    required this.id,
    required this.channelId,
    required this.callStartedAt,
    this.callEndedAt,
    this.durationInSeconds = 0,
    this.deepfakeDetections = 0,
    this.maxFakeProbability = 0.0,
    this.riskLevel = RiskLevel.unknown,
    this.status = CallStatus.processing,
    this.reportPdfUrl,
    this.keyFrames = const [], // 생성자에 반영
    this.gradcamImages = const [],
    this.highestProbImageName,
    this.highestProbKeyFrameUrl,
    this.highestProbGradCamUrl,
  });

  CallRecord copyWith({
    DateTime? callEndedAt,
    int? durationInSeconds,
    int? deepfakeDetections,
    double? maxFakeProbability,
    RiskLevel? riskLevel,
    CallStatus? status,
    String? reportPdfUrl,
    List<KeyFrame>? keyFrames, // copyWith에 반영
    List<String>? gradcamImages,
    String? highestProbImageName,
    String? highestProbKeyFrameUrl,
    String? highestProbGradCamUrl,
  }) {
    return CallRecord(
      id: id,
      channelId: channelId,
      callStartedAt: callStartedAt,
      callEndedAt: callEndedAt ?? this.callEndedAt,
      durationInSeconds: durationInSeconds ?? this.durationInSeconds,
      deepfakeDetections: deepfakeDetections ?? this.deepfakeDetections,
      maxFakeProbability: maxFakeProbability ?? this.maxFakeProbability,
      riskLevel: riskLevel ?? this.riskLevel,
      status: status ?? this.status,
      reportPdfUrl: reportPdfUrl ?? this.reportPdfUrl,
      keyFrames: keyFrames ?? this.keyFrames,
      gradcamImages: gradcamImages ?? this.gradcamImages,
      highestProbImageName: highestProbImageName ?? this.highestProbImageName,
      highestProbKeyFrameUrl:
          highestProbKeyFrameUrl ?? this.highestProbKeyFrameUrl,
      highestProbGradCamUrl:
          highestProbGradCamUrl ?? this.highestProbGradCamUrl,
    );
  }
}

final ValueNotifier<List<CallRecord>> callHistoryNotifier = ValueNotifier([]);
