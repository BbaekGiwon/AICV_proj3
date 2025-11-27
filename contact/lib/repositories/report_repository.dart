import 'dart:io';
import 'package:http/http.dart' as http;

import '../services/firestore_service.dart';
import '../services/storage_service.dart';

class ReportRepository {
  final FirestoreService _firestore;
  final StorageService _storage;

  ReportRepository(this._firestore, this._storage);

  /// 서버에 보고서 생성 요청 → 분석 파이프라인 실행
  Future<Map<String, dynamic>> requestReportGeneration({
    required String serverUrl,        // ex: "https://api.myserver.com/generateReport"
    required String recordId,
  }) async {
    final response = await http.post(
      Uri.parse(serverUrl),
      headers: {"Content-Type": "application/json"},
      body: '{"record_id": "$recordId"}',
    );

    if (response.statusCode != 200) {
      throw Exception("보고서 생성 요청 실패: ${response.body}");
    }

    /// response body 예시:
    /// {
    ///   "key_frames": ["http://.../key1.jpg", ...],
    ///   "gradcam": ["http://.../grad1.jpg", ...],
    ///   "report_pdf": "http://.../report.pdf",
    ///   "max_prob": 0.92,
    ///   "risk_level": "high"
    /// }

    return {
      "key_frames": [],  // 서버 응답 파싱 (지금은 mock 구조)
      "gradcam": [],
      "report_pdf": "",
      "max_prob": 0.0,
      "risk_level": "",
    };
  }

  /// URL → 실제 파일 다운로드
  Future<File> _downloadFile(String url, String tempName) async {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception("파일 다운로드 실패: $url");
    }

    final tempDir = Directory.systemTemp;
    final file = File("${tempDir.path}/$tempName");
    await file.writeAsBytes(response.bodyBytes);
    return file;
  }

  /// 보고서 생성 완료 후, 완성된 파일들을 Storage + Firestore에 반영
  Future<void> processReportResults({
    required String recordId,
    required List<String> keyFrameUrlsFromServer,
    required List<String> gradcamUrlsFromServer,
    required String reportPdfUrlFromServer,
    required double maxProb,
    required String riskLevel,
  }) async {

    // ---------------------------
    // 1) Key frames 다운로드 후 업로드
    // ---------------------------
    List<File> keyFrameFiles = [];
    for (int i = 0; i < keyFrameUrlsFromServer.length; i++) {
      final f = await _downloadFile(
        keyFrameUrlsFromServer[i],
        "key_$i.jpg",
      );
      keyFrameFiles.add(f);
    }

    final keyFrameUrls =
    await _storage.uploadKeyFrames(recordId: recordId, files: keyFrameFiles);

    // Firestore 반영
    await _firestore.addUrls(
      recordId: recordId,
      keyFrames: keyFrameUrls,
    );

    // ---------------------------
    // 2) GradCAM 이미지 다운로드 → Storage 업로드
    // ---------------------------
    List<File> gradcamFiles = [];
    for (int i = 0; i < gradcamUrlsFromServer.length; i++) {
      final f = await _downloadFile(
        gradcamUrlsFromServer[i],
        "grad_$i.jpg",
      );
      gradcamFiles.add(f);
    }

    final gradcamUrls =
    await _storage.uploadGradcamImages(recordId: recordId, files: gradcamFiles);

    await _firestore.addUrls(
      recordId: recordId,
      gradcamImages: gradcamUrls,
    );

    // ---------------------------
    // 3) Report PDF 다운로드 → Storage 업로드
    // ---------------------------
    final pdfFile =
    await _downloadFile(reportPdfUrlFromServer, "report.pdf");

    final pdfUrl = await _storage.uploadReportPdf(
      recordId: recordId,
      file: pdfFile,
    );

    await _firestore.updateReportUrl(
      recordId: recordId,
      pdfUrl: pdfUrl,
    );

    // ---------------------------
    // 4) 위험도 정보 업데이트
    // ---------------------------
    await _firestore.updateRiskInfo(
      recordId: recordId,
      maxProb: maxProb,
      riskLevel: riskLevel,
    );
  }
}