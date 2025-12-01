import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<QuerySnapshot> getAllCallRecords() {
    // ✅ orderBy를 제거하여, 필드 존재 여부와 상관없이 모든 문서를 가져오도록 수정
    return _db.collection("call_records").get();
  }

  Future<void> createCallRecord(String recordId, Map<String, dynamic> data) async {
    final docRef = _db.collection("call_records").doc(recordId);
    data['created_at'] = FieldValue.serverTimestamp();
    data['updated_at'] = FieldValue.serverTimestamp();
    await docRef.set(data);
  }

  Future<void> updateCallRecord(String recordId, Map<String, dynamic> data) async {
    final docRef = _db.collection("call_records").doc(recordId);
    data['updated_at'] = FieldValue.serverTimestamp();
    await docRef.update(data);
  }

  // ✅✅✅ 통화 기록 삭제 메서드를 추가합니다. ✅✅✅
  Future<void> deleteCallRecord(String recordId) async {
    await _db.collection("call_records").doc(recordId).delete();
  }

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
