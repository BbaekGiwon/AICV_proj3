import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

import '../services/firestore_service.dart';
import '../services/storage_service.dart';

class ReportRepository {
  final FirestoreService _firestore;
  final StorageService _storage;

  ReportRepository(this._firestore, this._storage);

  /// Firestore에서 특정 통화 기록의 변경 사항을 실시간으로 스트리밍합니다.
  Stream<DocumentSnapshot> getCallRecordStream(String recordId) {
    return _firestore.getCallRecordStream(recordId); // 수정된 부분
  }

  /// 서버에 보고서 생성 요청 → 분석 파이프라인 실행
  Future<Map<String, dynamic>> requestReportGeneration({
    required String serverUrl, // ex: "https://api.myserver.com/generateReport"
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

    // ✅ 서버의 실제 응답을 JSON으로 파싱하여 반환하도록 수정합니다.
    return json.decode(response.body) as Map<String, dynamic>;
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
    // --------------------------- (이하 다운로드 및 업로드 로직은 동일) ---------------------------
    List<File> keyFrameFiles = [];
    for (int i = 0; i < keyFrameUrlsFromServer.length; i++) {
      final f = await _downloadFile(
        keyFrameUrlsFromServer[i],
        "key_$i.jpg",
      );
      keyFrameFiles.add(f);
    }
    final keyFrameUrls = await _storage.uploadKeyFrames(recordId: recordId, files: keyFrameFiles);

    List<File> gradcamFiles = [];
    for (int i = 0; i < gradcamUrlsFromServer.length; i++) {
      final f = await _downloadFile(
        gradcamUrlsFromServer[i],
        "grad_$i.jpg",
      );
      gradcamFiles.add(f);
    }
    final gradcamUrls = await _storage.uploadGradcamImages(recordId: recordId, files: gradcamFiles);

    final pdfFile = await _downloadFile(reportPdfUrlFromServer, "report.pdf");
    final pdfUrl = await _storage.uploadReportPdf(
      recordId: recordId,
      file: pdfFile,
    );

    // ------------------- ✅ 여러번 호출하던 로직을 하나로 통합 -------------------

    // 1. 업데이트할 모든 데이터를 하나의 Map으로 구성합니다.
    final finalReportData = {
      // FieldValue.arrayUnion을 사용하여 기존 배열에 새로운 URL들을 추가합니다.
      'key_frames': FieldValue.arrayUnion(keyFrameUrls),
      'gradcam_images': FieldValue.arrayUnion(gradcamUrls),
      'report_pdf_url': pdfUrl,
      'max_fake_prob': maxProb,
      'risk_level': riskLevel,
      'status': 'done', // 최종적으로 상태를 'done'으로 변경
    };

    // 2. 하나의 통일된 함수를 호출하여 데이터를 한 번에 업데이트합니다.
    await _firestore.updateCallRecord(recordId, finalReportData);
  }
}
