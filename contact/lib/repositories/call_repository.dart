import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path/path.dart' as p;
import '../models/call_record.dart';
import '../services/firestore_service.dart';
import '../services/storage_service.dart';

class CallRecordRepository {
  final FirestoreService _firestore;
  final StorageService _storage;

  CallRecordRepository(this._firestore, this._storage);

  Future<List<CallRecord>> fetchAllRecordsOnce() async {
    final snapshot = await _firestore.getAllCallRecords();
    final records = snapshot.docs
        .map((doc) => CallRecord.fromFirestore(doc))
        .toList();
    records.sort((a, b) => b.callStartedAt.compareTo(a.callStartedAt));
    return records;
  }

  Stream<List<CallRecord>> getAllRecordsStream() {
    return _firestore.getAllCallRecordsStream().map((snapshot) {
      final records = snapshot.docs
          .map((doc) => CallRecord.fromFirestore(doc))
          .toList();
      records.sort((a, b) => b.callStartedAt.compareTo(a.callStartedAt));
      return records;
    });
  }

  Stream<CallRecord?> getRecordStream(String recordId) {
    return _firestore.getCallRecordStream(recordId).map((snapshot) {
      if (snapshot.exists) {
        return CallRecord.fromFirestore(snapshot);
      }
      return null;
    });
  }

  Future<void> updateMemo(String recordId, String memo) async {
    await _firestore.updateCallRecord(recordId, {'userMemo': memo});
  }

  Future<void> deleteCallRecords(List<String> recordIds) async {
    List<Future> deleteFutures = [];

    for (String id in recordIds) {
      // DB에서 최신 레코드 정보를 직접 조회
      final doc = await _firestore.getCallRecord(id);
      if (!doc.exists) continue;

      final record = CallRecord.fromFirestore(doc);

      // Storage 파일 삭제 로직
      for (final keyFrame in record.keyFrames) {
        if (keyFrame.url.isNotEmpty) {
          deleteFutures.add(_storage.deleteFileByUrl(keyFrame.url));
        }
        if (keyFrame.gradCamUrl != null && keyFrame.gradCamUrl!.isNotEmpty) {
          deleteFutures.add(_storage.deleteFileByUrl(keyFrame.gradCamUrl!));
        }
      }
      if (record.reportPdfUrl != null && record.reportPdfUrl!.isNotEmpty) {
        deleteFutures.add(_storage.deleteFileByUrl(record.reportPdfUrl!));
      }
      
      // Firestore 문서 삭제 로직
      deleteFutures.add(_firestore.deleteCallRecord(id));
    }

    // 모든 삭제 작업을 동시에 실행
    final results = await Future.wait(deleteFutures.map((f) => f.catchError((e) => e)));
    results.where((res) => res is Exception).forEach((err) => print('🚨 삭제 중 오류 발생: $err'));
  }

  Future<List<KeyFrame>> uploadKeyFrames(
      String recordId, List<KeyFrame> localKeyFrames) async {
    if (localKeyFrames.isEmpty) return [];

    final uploadedKeyFrames = <KeyFrame>[];

    for (final frame in localKeyFrames) {
      final file = File(frame.url);
      String? downloadUrl;
      if (await file.exists()) {
        final fileName = p.basename(file.path);
        final uploadPath = 'call_records/$recordId/key_frames/$fileName';
        downloadUrl = await _storage.uploadFile(uploadPath, file);
        try {
          await file.delete();
        } catch (e) {
          print('🚨 원본 프레임 임시 파일 삭제 실패: $e');
        }
      }

      if (downloadUrl == null) continue;

      uploadedKeyFrames.add(KeyFrame(
        url: downloadUrl,
        probability: frame.probability,
        gradCamUrl: null, 
      ));
    }
    return uploadedKeyFrames;
  }

  Future<void> createOrUpdateCallRecord(CallRecord record) async {
    final keyFramesAsMap = record.keyFrames.map((kf) => kf.toMap()).toList();

    final data = {
      'channelId': record.channelId,
      'callStartedAt': Timestamp.fromDate(record.callStartedAt),
      'callEndedAt': record.callEndedAt != null ? Timestamp.fromDate(record.callEndedAt!) : null,
      'durationInSeconds': record.durationInSeconds,
      'status': record.status.toString().split('.').last,
      'reportPdfUrl': record.reportPdfUrl,
      'keyFrames': keyFramesAsMap,
      'userMemo': record.userMemo,
      'deviceInfo': record.deviceInfo,
      'serverInfo': record.serverInfo,
      'deepfakeDetections': record.deepfakeDetections,
      'maxFakeProbability': record.maxFakeProbability,
      'averageProbability': record.averageProbability,
    };

    await _firestore.createCallRecord(record.id, data);
  }
}
