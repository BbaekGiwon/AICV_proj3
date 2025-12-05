import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class KeyFrame {
  final String url;
  final double probability;
  final String? gradCamUrl;

  KeyFrame({
    required this.url,
    required this.probability,
    this.gradCamUrl,
  });

  Map<String, dynamic> toMap() {
    return {
      'url': url,
      'probability': probability,
      'gradCamUrl': gradCamUrl,
    };
  }

  factory KeyFrame.fromMap(Map<String, dynamic> map) {
    return KeyFrame(
      url: map['url'] ?? '',
      probability: (map['probability'] as num?)?.toDouble() ?? 0.0,
      gradCamUrl: map['gradCamUrl'],
    );
  }
}

enum CallStatus { processing, done, error }

class CallRecord {
  final String id;
  final String channelId;
  final DateTime callStartedAt;
  final DateTime? callEndedAt;
  final int durationInSeconds;
  final CallStatus status;
  final String? reportPdfUrl;
  final List<KeyFrame> keyFrames;
  final String? userMemo;
  final Map<String, String> deviceInfo;
  final Map<String, String> serverInfo;

  // 1차 온디바이스 분석 결과 (초기값으로 사용)
  final int deepfakeDetections;
  final double maxFakeProbability;
  final double averageProbability;

  // ✅ 2차 서버 정밀 분석 결과 (서버 작업 완료 후 채워짐)
  final int? secondStageDetections;
  final double? maxSecondStageProb;
  final double? avgSecondStageProb;

  CallRecord({
    required this.id,
    required this.channelId,
    required this.callStartedAt,
    this.callEndedAt,
    this.durationInSeconds = 0,
    this.status = CallStatus.processing,
    this.reportPdfUrl,
    this.keyFrames = const [],
    this.userMemo,
    this.deviceInfo = const {},
    this.serverInfo = const {},
    // 1차 결과
    this.deepfakeDetections = 0,
    this.maxFakeProbability = 0.0,
    this.averageProbability = 0.0,
    // 2차 결과
    this.secondStageDetections,
    this.maxSecondStageProb,
    this.avgSecondStageProb,
  });

  factory CallRecord.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return CallRecord.fromMap(doc.id, data);
  }

  factory CallRecord.fromMap(String id, Map<String, dynamic> map) {
    T _enumFromString<T>(List<T> values, String? value, T defaultValue) {
      if (value == null) return defaultValue;
      return values.firstWhere(
        (v) => v.toString().split('.').last == value,
        orElse: () => defaultValue,
      );
    }

    return CallRecord(
      id: id,
      channelId: map['channelId'] ?? '',
      callStartedAt: (map['callStartedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      callEndedAt: (map['callEndedAt'] as Timestamp?)?.toDate(),
      durationInSeconds: map['durationInSeconds'] ?? 0,
      status: _enumFromString(CallStatus.values, map['status'], CallStatus.processing),
      reportPdfUrl: map['report_pdf_url'],
      keyFrames: (map['keyFrames'] as List<dynamic>?)
              ?.map((kf) => KeyFrame.fromMap(kf as Map<String, dynamic>))
              .toList() ??
          [],
      userMemo: map['userMemo'],
      deviceInfo: Map<String, String>.from(map['deviceInfo'] ?? {}),
      serverInfo: Map<String, String>.from(map['serverInfo'] ?? {}),
      // 1차 결과 읽기
      deepfakeDetections: map['deepfakeDetections'] ?? 0,
      maxFakeProbability: (map['maxFakeProbability'] as num?)?.toDouble() ?? 0.0,
      averageProbability: (map['averageProbability'] as num?)?.toDouble() ?? 0.0,
      // ✅ 2차 결과 읽기
      secondStageDetections: map['secondStageDetections'],
      maxSecondStageProb: (map['maxSecondStageProb'] as num?)?.toDouble(),
      avgSecondStageProb: (map['avgSecondStageProb'] as num?)?.toDouble(),
    );
  }

  CallRecord copyWith({
    String? id,
    String? channelId,
    DateTime? callStartedAt,
    DateTime? callEndedAt,
    int? durationInSeconds,
    CallStatus? status,
    String? reportPdfUrl,
    List<KeyFrame>? keyFrames,
    String? userMemo,
    Map<String, String>? deviceInfo,
    Map<String, String>? serverInfo,
    int? deepfakeDetections,
    double? maxFakeProbability,
    double? averageProbability,
    int? secondStageDetections,
    double? maxSecondStageProb,
    double? avgSecondStageProb,
  }) {
    return CallRecord(
      id: id ?? this.id,
      channelId: channelId ?? this.channelId,
      callStartedAt: callStartedAt ?? this.callStartedAt,
      callEndedAt: callEndedAt ?? this.callEndedAt,
      durationInSeconds: durationInSeconds ?? this.durationInSeconds,
      status: status ?? this.status,
      reportPdfUrl: reportPdfUrl ?? this.reportPdfUrl,
      keyFrames: keyFrames ?? this.keyFrames,
      userMemo: userMemo ?? this.userMemo,
      deviceInfo: deviceInfo ?? this.deviceInfo,
      serverInfo: serverInfo ?? this.serverInfo,
      deepfakeDetections: deepfakeDetections ?? this.deepfakeDetections,
      maxFakeProbability: maxFakeProbability ?? this.maxFakeProbability,
      averageProbability: averageProbability ?? this.averageProbability,
      // ✅ 2차 결과 복사
      secondStageDetections: secondStageDetections ?? this.secondStageDetections,
      maxSecondStageProb: maxSecondStageProb ?? this.maxSecondStageProb,
      avgSecondStageProb: avgSecondStageProb ?? this.avgSecondStageProb,
    );
  }
}

final ValueNotifier<List<CallRecord>> callHistoryNotifier = ValueNotifier([]);
