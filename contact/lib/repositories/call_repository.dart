import 'dart:io';
import '../services/firestore_service.dart';
import '../services/storage_service.dart';

class CallRecordRepository {
  final FirestoreService _firestore;
  final StorageService _storage;

  CallRecordRepository(this._firestore, this._storage);

  /// 통화 시작 시 record 문서 생성
  Future<void> startCall({
    required String recordId,
    required String userId,
    required String opponentId,
    required String channelId,
    required DateTime startedAt,
  }) async {
    await _firestore.createCallRecord(
      recordId: recordId,
      userId: userId,
      opponentId: opponentId,
      channelId: channelId,
      callStartedAt: startedAt,
    );
  }

  /// 통화 종료 시 duration / endedAt 기록
  Future<void> endCall({
    required String recordId,
    required DateTime endedAt,
    required int duration,
  }) async {
    await _firestore.finalizeCallRecord(
      recordId: recordId,
      endedAt: endedAt,
      duration: duration,
    );
  }

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