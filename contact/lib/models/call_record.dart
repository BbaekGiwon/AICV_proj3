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
  final int deepfakeDetections;
  final double maxFakeProbability;
  final double averageProbability;
  final CallStatus status;
  final String? reportPdfUrl;
  final List<KeyFrame> keyFrames;
  final String? userMemo;
  final Map<String, String> deviceInfo;
  final Map<String, String> serverInfo;

  CallRecord({
    required this.id,
    required this.channelId,
    required this.callStartedAt,
    this.callEndedAt,
    this.durationInSeconds = 0,
    this.deepfakeDetections = 0,
    this.maxFakeProbability = 0.0,
    this.averageProbability = 0.0,
    this.status = CallStatus.processing,
    this.reportPdfUrl,
    this.keyFrames = const [],
    this.userMemo,
    this.deviceInfo = const {},
    this.serverInfo = const {},
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
      deepfakeDetections: map['deepfakeDetections'] ?? 0,
      maxFakeProbability: (map['maxFakeProbability'] as num?)?.toDouble() ?? 0.0,
      averageProbability: (map['averageProbability'] as num?)?.toDouble() ?? 0.0,
      status: _enumFromString(CallStatus.values, map['status'], CallStatus.processing),
      reportPdfUrl: map['report_pdf_url'],
      keyFrames: (map['keyFrames'] as List<dynamic>?)
              ?.map((kf) => KeyFrame.fromMap(kf as Map<String, dynamic>))
              .toList() ??
          [],
      userMemo: map['userMemo'],
      deviceInfo: Map<String, String>.from(map['deviceInfo'] ?? {}),
      serverInfo: Map<String, String>.from(map['serverInfo'] ?? {}),
    );
  }

  CallRecord copyWith({
    String? id,
    String? channelId,
    DateTime? callStartedAt,
    DateTime? callEndedAt,
    int? durationInSeconds,
    int? deepfakeDetections,
    double? maxFakeProbability,
    double? averageProbability,
    CallStatus? status,
    String? reportPdfUrl,
    List<KeyFrame>? keyFrames,
    String? userMemo,
    Map<String, String>? deviceInfo,
    Map<String, String>? serverInfo,
  }) {
    return CallRecord(
      id: id ?? this.id,
      channelId: channelId ?? this.channelId,
      callStartedAt: callStartedAt ?? this.callStartedAt,
      callEndedAt: callEndedAt ?? this.callEndedAt,
      durationInSeconds: durationInSeconds ?? this.durationInSeconds,
      deepfakeDetections: deepfakeDetections ?? this.deepfakeDetections,
      maxFakeProbability: maxFakeProbability ?? this.maxFakeProbability,
      averageProbability: averageProbability ?? this.averageProbability,
      status: status ?? this.status,
      reportPdfUrl: reportPdfUrl ?? this.reportPdfUrl,
      keyFrames: keyFrames ?? this.keyFrames,
      userMemo: userMemo ?? this.userMemo,
      deviceInfo: deviceInfo ?? this.deviceInfo,
      serverInfo: serverInfo ?? this.serverInfo,
    );
  }
}

final ValueNotifier<List<CallRecord>> callHistoryNotifier = ValueNotifier([]);
