import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/call_record.dart';
import '../services/firestore_service.dart';
import '../services/storage_service.dart';

class CallRecordRepository {
  final FirestoreService _firestore;
  final StorageService _storage;

  CallRecordRepository(this._firestore, this._storage);

  Future<List<CallRecord>> getAllCallRecords() async {
    final snapshot = await _firestore.getAllCallRecords();
    final records = snapshot.docs
        .map((doc) => CallRecord.fromMap(doc.id, doc.data() as Map<String, dynamic>))
        .toList();
    records.sort((a, b) => b.callStartedAt.compareTo(a.callStartedAt));
    return records;
  }

  Future<void> updateMemo(String recordId, String memo) async {
    await _firestore.updateCallRecord(recordId, {'user_memo': memo});
  }

  Future<void> deleteCallRecords(List<String> recordIds) async {
    final recordsToDelete = callHistoryNotifier.value
        .where((record) => recordIds.contains(record.id))
        .toList();

    List<Future> deleteImageFutures = [];
    for (final record in recordsToDelete) {
      for (final keyFrame in record.keyFrames) {
        if (keyFrame.url.isNotEmpty) {
          deleteImageFutures.add(_storage.deleteFileByUrl(keyFrame.url));
        }
        if (keyFrame.gradCamUrl != null && keyFrame.gradCamUrl!.isNotEmpty) {
          deleteImageFutures.add(_storage.deleteFileByUrl(keyFrame.gradCamUrl!));
        }
      }
      if (record.reportPdfUrl != null && record.reportPdfUrl!.isNotEmpty) {
        deleteImageFutures.add(_storage.deleteFileByUrl(record.reportPdfUrl!));
      }
    }
    await Future.wait(deleteImageFutures.map((f) => f.catchError((e) => print(e))));

    final deleteDbFutures = recordIds.map((id) => _firestore.deleteCallRecord(id));
    await Future.wait(deleteDbFutures);
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

      String? gradCamDownloadUrl;
      if (frame.gradCamUrl != null && frame.gradCamUrl!.isNotEmpty) {
        final gradCamFile = File(frame.gradCamUrl!);
        if (await gradCamFile.exists()) {
          final fileName = p.basename(gradCamFile.path);
          final uploadPath = 'call_records/$recordId/grad_cams/$fileName';
          gradCamDownloadUrl = await _storage.uploadFile(uploadPath, gradCamFile);
          try {
            await gradCamFile.delete();
          } catch (e) {
            print('🚨 Grad-CAM 임시 파일 삭제 실패: $e');
          }
        }
      }

      uploadedKeyFrames.add(KeyFrame(
        url: downloadUrl,
        probability: frame.probability,
        gradCamUrl: gradCamDownloadUrl,
      ));
    }
    return uploadedKeyFrames;
  }

  Future<void> createOrUpdateCallRecord(CallRecord record) async {
    final keyFramesAsMap = record.keyFrames.map((kf) => kf.toMap()).toList();

    final data = {
      'channelId': record.channelId,
      'call_started_at': record.callStartedAt.toIso8601String(),
      'call_ended_at': record.callEndedAt?.toIso8601String(),
      'duration': record.durationInSeconds,
      'deepfake_detections': record.deepfakeDetections,
      'max_fake_prob': record.maxFakeProbability,
      'average_probability': record.averageProbability,
      'status': record.status.toString().split('.').last,
      'report_pdf_url': record.reportPdfUrl,
      'key_frames': keyFramesAsMap,
      'user_memo': record.userMemo,
      // ✅✅✅ 보고서 정보 필드 저장
      'deviceInfo': record.deviceInfo,
      'serverInfo': record.serverInfo,
    };

    await _firestore.createCallRecord(record.id, data);
  }
}
