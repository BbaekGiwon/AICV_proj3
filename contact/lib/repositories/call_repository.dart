import 'dart:io';
import '../models/call_record.dart';
import '../services/firestore_service.dart';
import '../services/storage_service.dart';

class CallRecordRepository {
  final FirestoreService _firestore;
  final StorageService _storage;

  CallRecordRepository(this._firestore, this._storage);

  // ✅ CallRecord 객체를 통째로 받아 Firestore 문서를 생성하거나 업데이트합니다.
  Future<void> createOrUpdateCallRecord(CallRecord record) async {
    // 모델을 Firestore가 이해할 수 있는 Map 형태로 변환합니다.
    final data = {
      'channelId': record.channelId,
      'call_started_at': record.callStartedAt.toIso8601String(),
      'call_ended_at': record.callEndedAt?.toIso8601String(),
      'duration': record.durationInSeconds,
      'max_fake_prob': record.maxFakeProbability,
      'risk_level': record.riskLevel.toString().split('.').last,
      'status': record.status.toString().split('.').last,
      'report_pdf_url': record.reportPdfUrl,
    };

    if (record.durationInSeconds == 0) { // 통화 시간이 0이면 새 문서로 취급
      await _firestore.createCallRecord(record.id, data);
    } else {
      await _firestore.updateCallRecord(record.id, data);
    }
  }

  // 아래 함수들은 추후 리포트 생성 서버에서 사용될 수 있으므로 유지합니다.

  /// RAW frame 여러 장 업로드
  Future<void> uploadRawFrames({
    required String recordId,
    required List<File> files,
  }) async {
    final urls = await _storage.uploadRawFrames(
      recordId: recordId,
      files: files,
    );

    await _firestore.addUrls(
      recordId: recordId,
      rawFrames: urls,
    );
  }

  /// key frames 여러 장 업로드
  Future<void> uploadKeyFrames({
    required String recordId,
    required List<File> files,
  }) async {
    final urls = await _storage.uploadKeyFrames(
      recordId: recordId,
      files: files,
    );

    await _firestore.addUrls(
      recordId: recordId,
      keyFrames: urls,
    );
  }

  /// gradcam 여러 장 업로드
  Future<void> uploadGradcamImages({
    required String recordId,
    required List<File> files,
  }) async {
    final urls = await _storage.uploadGradcamImages(
      recordId: recordId,
      files: files,
    );

    await _firestore.addUrls(
      recordId: recordId,
      gradcamImages: urls,
    );
  }
}
