import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path/path.dart' as p;

class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  /// ✅✅✅ URL을 이용하여 파일을 삭제하는 메서드를 추가합니다. ✅✅✅
  Future<void> deleteFileByUrl(String url) async {
    // URL이 비어있으면 아무 작업도 하지 않음
    if (url.isEmpty) return;

    try {
      // URL로부터 참조를 가져와서 삭제
      final ref = _storage.refFromURL(url);
      await ref.delete();
    } on FirebaseException catch (e) {
      // 파일이 존재하지 않는 등의 오류는 무시하고, 다른 오류는 출력
      if (e.code != 'object-not-found') {
        print('🔥 Storage 파일 삭제 실패: $url, 오류: $e');
      }
    }
  }

  /// ✅✅✅ 범용 파일 업로드 메서드를 추가합니다. ✅✅✅
  /// 주어진 경로(path)에 파일(file)을 업로드하고 다운로드 URL을 반환합니다.
  Future<String> uploadFile(String path, File file) async {
    final ref = _storage.ref().child(path);
    await ref.putFile(file);
    return await ref.getDownloadURL();
  }

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
