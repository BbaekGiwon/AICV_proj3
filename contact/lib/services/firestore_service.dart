import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// call_records/{record_id} 문서 생성 (통화 시작 시)
  Future<void> createCallRecord({
    required String recordId,
    required String userId,
    required String opponentId,
    required String channelId,
    required DateTime callStartedAt,
  }) async {
    await _db.collection("call_records").doc(recordId).set({
      "user_id": userId,
      "opponent_id": opponentId,
      "channel_id": channelId,
      "call_started_at": callStartedAt.toIso8601String(),
      "call_ended_at": null,
      "duration": null,
      "max_fake_prob": null,
      "risk_level": null,
      "raw_frames": [],
      "gradcam_images": [],
      "key_frames": [],
      "report_pdf_url": null,
      "status": "processing",
      "created_at": FieldValue.serverTimestamp(),
      "updated_at": FieldValue.serverTimestamp(),
    });
  }

  /// 통화 종료 정보 업데이트
  Future<void> finalizeCallRecord({
    required String recordId,
    required DateTime endedAt,
    required int duration,
  }) async {
    await _db.collection("call_records").doc(recordId).update({
      "call_ended_at": endedAt.toIso8601String(),
      "duration": duration,
      "updated_at": FieldValue.serverTimestamp(),
    });
  }

  /// raw_frames / key_frames / gradcam_images 배열에 URL 추가
  Future<void> addUrls({
    required String recordId,
    List<String>? rawFrames,
    List<String>? keyFrames,
    List<String>? gradcamImages,
  }) async {
    final updates = <String, dynamic>{};

    if (rawFrames != null && rawFrames.isNotEmpty) {
      updates["raw_frames"] = FieldValue.arrayUnion(rawFrames);
    }
    if (keyFrames != null && keyFrames.isNotEmpty) {
      updates["key_frames"] = FieldValue.arrayUnion(keyFrames);
    }
    if (gradcamImages != null && gradcamImages.isNotEmpty) {
      updates["gradcam_images"] = FieldValue.arrayUnion(gradcamImages);
    }

    updates["updated_at"] = FieldValue.serverTimestamp();

    await _db.collection("call_records").doc(recordId).update(updates);
  }

  /// 위험도 / 최대조작확률 업데이트
  Future<void> updateRiskInfo({
    required String recordId,
    required double maxProb,
    required String riskLevel,
  }) async {
    await _db.collection("call_records").doc(recordId).update({
      "max_fake_prob": maxProb,
      "risk_level": riskLevel,
      "updated_at": FieldValue.serverTimestamp(),
    });
  }

  /// PDF URL 업데이트 (처리 완료)
  Future<void> updateReportUrl({
    required String recordId,
    required String pdfUrl,
  }) async {
    await _db.collection("call_records").doc(recordId).update({
      "report_pdf_url": pdfUrl,
      "status": "done",
      "updated_at": FieldValue.serverTimestamp(),
    });
  }

  /// 📌 Partial update 기능 — 필요한 필드만 업데이트 가능!
  Future<void> updateCallRecord({
    required String recordId,
    required Map<String, dynamic> data,
  }) async {
    data["updated_at"] = FieldValue.serverTimestamp();

    await _db.collection("call_records").doc(recordId).update(data);
  }
}