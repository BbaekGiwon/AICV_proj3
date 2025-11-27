import 'package:flutter/foundation.dart';

// ✅ Firebase의 'call_records' 문서 구조와 100% 동일하게 모델을 최종 확장합니다.

// 통화 상태를 나타내는 Enum
enum CallStatus { processing, done, error }

// 위험도 수준을 나타내는 Enum
enum RiskLevel { safe, caution, warning, danger, unknown }

class CallRecord {
  final String id; // Firestore 문서 ID
  final String channelId; // 전화번호 또는 채널명
  final DateTime callStartedAt;
  final DateTime? callEndedAt;
  final int durationInSeconds;

  // AI 분석 결과
  final int deepfakeDetections;
  final double maxFakeProbability;
  final RiskLevel riskLevel;

  // ✅ 가장 높은 확률의 이미지를 저장할 필드 추가
  final String? highestProbKeyFrameUrl;
  final String? highestProbGradCamUrl;

  // 리포트 및 상태
  final CallStatus status;
  final String? reportPdfUrl;

  // ✅ 상세 보고서에 필요한 이미지 URL 리스트 필드를 추가합니다.
  final List<String> keyFrames;
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
    this.keyFrames = const [], // 기본값으로 빈 리스트를 설정합니다.
    this.gradcamImages = const [], // 기본값으로 빈 리스트를 설정합니다.
    this.highestProbKeyFrameUrl,
    this.highestProbGradCamUrl,
  });

  // 객체를 복사하면서 일부 필드만 변경할 수 있게 해주는 유용한 메서드입니다.
  CallRecord copyWith({
    DateTime? callEndedAt,
    int? durationInSeconds,
    int? deepfakeDetections,
    double? maxFakeProbability,
    RiskLevel? riskLevel,
    CallStatus? status,
    String? reportPdfUrl,
    List<String>? keyFrames,
    List<String>? gradcamImages,
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
      highestProbKeyFrameUrl: highestProbKeyFrameUrl ?? this.highestProbKeyFrameUrl,
      highestProbGradCamUrl: highestProbGradCamUrl ?? this.highestProbGradCamUrl,
    );
  }
}

// 앱 전체에서 통화 기록 목록을 관리하고, 변경 알림을 제공합니다.
final ValueNotifier<List<CallRecord>> callHistoryNotifier = ValueNotifier([]);