import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';

class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  /// raw frames 여러 장 업로드
  Future<List<String>> uploadRawFrames({
    required String recordId,
    required List<File> files,
  }) async {
    List<String> urls = [];

    for (int i = 0; i < files.length; i++) {
      final fileName = "frame_${i.toString().padLeft(3, '0')}.jpg";
      final ref = _storage.ref().child("call_records/$recordId/raw_frames/$fileName");

      await ref.putFile(files[i]);
      urls.add(await ref.getDownloadURL());
    }

    return urls;
  }

  /// ✅ 단일 키 프레임 업로드 (최고 확률 스냅샷용)
  Future<String> uploadSingleKeyFrame({
    required String recordId,
    required String filePath,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception("File not found at: $filePath");
    }
    
    final fileName = "highest_prob_keyframe.jpg";
    final ref = _storage.ref().child("call_records/$recordId/$fileName");

    await ref.putFile(file);
    return await ref.getDownloadURL();
  }

  /// key frames 업로드
  Future<List<String>> uploadKeyFrames({
    required String recordId,
    required List<File> files,
  }) async {
    List<String> urls = [];

    for (int i = 0; i < files.length; i++) {
      final fileName = "key_${i.toString().padLeft(3, '0')}.jpg";
      final ref = _storage.ref().child("call_records/$recordId/key_frames/$fileName");

      await ref.putFile(files[i]);
      urls.add(await ref.getDownloadURL());
    }

    return urls;
  }

  /// gradcam 이미지 업로드
  Future<List<String>> uploadGradcamImages({
    required String recordId,
    required List<File> files,
  }) async {
    List<String> urls = [];

    for (int i = 0; i < files.length; i++) {
      final fileName = "grad_${i.toString().padLeft(3, '0')}.jpg";
      final ref =
      _storage.ref().child("call_records/$recordId/gradcam/$fileName");

      await ref.putFile(files[i]);
      urls.add(await ref.getDownloadURL());
    }

    return urls;
  }

  /// 보고서 PDF 업로드
  Future<String> uploadReportPdf({
    required String recordId,
    required File file,
  }) async {
    final ref = _storage
        .ref()
        .child("call_records/$recordId/report/report.pdf");

    await ref.putFile(file);
    return await ref.getDownloadURL();
  }
}