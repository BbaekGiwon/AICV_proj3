import '../models/call_record.dart';
import '../services/firestore_service.dart';
import '../services/storage_service.dart';

class CallRecordRepository {
  final FirestoreService _firestore;
  final StorageService _storage;

  CallRecordRepository(this._firestore, this._storage);

  Future<void> createOrUpdateCallRecord(CallRecord record) async {
    // ✨ KeyFrame 객체 리스트를 Firestore에 저장 가능한 Map 리스트로 변환합니다.
    final keyFramesAsMap = record.keyFrames.map((kf) => kf.toMap()).toList();

    final data = {
      'channelId': record.channelId,
      'call_started_at': record.callStartedAt.toIso8601String(),
      'call_ended_at': record.callEndedAt?.toIso8601String(),
      'duration': record.durationInSeconds,
      'deepfake_detections': record.deepfakeDetections,
      'max_fake_prob': record.maxFakeProbability,
      'highest_prob_image_name': record.highestProbImageName,
      'risk_level': record.riskLevel.toString().split('.').last,
      'status': record.status.toString().split('.').last,
      'report_pdf_url': record.reportPdfUrl,
      // ✨ 변환된 Map 리스트를 저장합니다.
      'key_frames': keyFramesAsMap,
      'highest_prob_key_frame_url': record.highestProbKeyFrameUrl,
    };

    await _firestore.createCallRecord(record.id, data);
  }
}
