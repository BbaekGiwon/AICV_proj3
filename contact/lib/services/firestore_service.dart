import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ✅ 통화 시작 시, 초기 문서를 생성하는 역할만 수행합니다. (set 사용)
  Future<void> createCallRecord(String recordId, Map<String, dynamic> data) async {
    final docRef = _db.collection("call_records").doc(recordId);
    data['created_at'] = FieldValue.serverTimestamp();
    data['updated_at'] = FieldValue.serverTimestamp();
    await docRef.set(data);
  }

  // ✅ 통화 종료 시, 기존 문서를 업데이트하는 역할만 수행합니다. (update 사용)
  Future<void> updateCallRecord(String recordId, Map<String, dynamic> data) async {
    final docRef = _db.collection("call_records").doc(recordId);
    data['updated_at'] = FieldValue.serverTimestamp();
    await docRef.update(data);
  }

  // ✅ 리포트 생성 서버가 사용할 수 있으므로, 이 함수는 유지합니다.
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
}
