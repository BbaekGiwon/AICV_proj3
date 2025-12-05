import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Splash Screen을 위한 일회성 데이터 로더
  Future<QuerySnapshot> getAllCallRecords() {
    return _db.collection("call_records").get();
  }

  // 삭제 시, 특정 레코드의 최신 정보를 가져오기 위한 함수
  Future<DocumentSnapshot> getCallRecord(String recordId) {
    return _db.collection("call_records").doc(recordId).get();
  }

  // History Screen을 위한 실시간 스트림
  Stream<QuerySnapshot> getAllCallRecordsStream() {
    return _db.collection("call_records").snapshots();
  }

  // Report Detail Screen을 위한 단일 레코드 실시간 스트림
  Stream<DocumentSnapshot> getCallRecordStream(String recordId) {
    return _db.collection("call_records").doc(recordId).snapshots();
  }

  Future<void> createCallRecord(String recordId, Map<String, dynamic> data) async {
    final docRef = _db.collection("call_records").doc(recordId);
    data['createdAt'] = FieldValue.serverTimestamp();
    data['updatedAt'] = FieldValue.serverTimestamp();
    await docRef.set(data);
  }

  Future<void> updateCallRecord(String recordId, Map<String, dynamic> data) async {
    final docRef = _db.collection("call_records").doc(recordId);
    data['updatedAt'] = FieldValue.serverTimestamp();
    await docRef.update(data);
  }

  Future<void> deleteCallRecord(String recordId) async {
    await _db.collection("call_records").doc(recordId).delete();
  }
}
