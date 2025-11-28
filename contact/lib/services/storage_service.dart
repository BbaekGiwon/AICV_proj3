import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path/path.dart' as p;

class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  /// ✅ 단일 키 프레임 업로드 (가장 일반적인 업로드 함수)
  /// 이제 파일의 실제 이름을 사용하여 저장하므로 여러 파일을 올릴 수 있습니다.
  Future<String> uploadSingleKeyFrame({
    required String recordId,
    required String filePath,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception("File not found at: $filePath");
    }

    // ✨ 파일의 전체 경로에서 순수한 파일 이름(예: 167..._face.jpg)을 추출합니다.
    final fileName = p.basename(filePath);

    // ✨ 추출한 실제 파일 이름으로 Storage에 저장합니다.
    final ref = _storage.ref().child("call_records/$recordId/key_frames/$fileName");

    await ref.putFile(file);
    return await ref.getDownloadURL();
  }

  // 아래 함수들은 현재 사용되지 않지만, 추후 확장성을 위해 유지합니다.

  Future<List<String>> uploadRawFrames({
    required String recordId,
    required List<File> files,
  }) async {
    List<String> urls = [];

    for (int i = 0; i < files.length; i++) {
      final fileName = "frame_${i.toString().padLeft(3, '0')}.jpg";
      final ref =
          _storage.ref().child("call_records/$recordId/raw_frames/$fileName");

      await ref.putFile(files[i]);
      urls.add(await ref.getDownloadURL());
    }

    return urls;
  }

  Future<List<String>> uploadKeyFrames({
    required String recordId,
    required List<File> files,
  }) async {
    List<String> urls = [];

    for (int i = 0; i < files.length; i++) {
      final fileName = "key_${i.toString().padLeft(3, '0')}.jpg";
      final ref =
          _storage.ref().child("call_records/$recordId/key_frames/$fileName");

      await ref.putFile(files[i]);
      urls.add(await ref.getDownloadURL());
    }

    return urls;
  }

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

  Future<String> uploadReportPdf({
    required String recordId,
    required File file,
  }) async {
    final ref = _storage.ref().child("call_records/$recordId/report/report.pdf");

    await ref.putFile(file);
    return await ref.getDownloadURL();
  }
}
