import 'package:dio/dio.dart';
import '../models/call_record.dart';

class VerificationService {
  final Dio _dio = Dio();
  final String _serverUrl = 'http://ec2-98-94-181-161.compute-1.amazonaws.com:8000/verify-frames';

  /// 2차 검증 서버에 분석을 요청합니다. (Fire-and-Forget)
  Future<void> requestVerification(String recordId, List<KeyFrame> keyFrames) async {
    try {
      final keyFramesData = keyFrames.map((kf) => {
        'url': kf.url,
        'probability': kf.probability,
      }).toList();

      print('🚀 2차 검증 요청 시작: $recordId');
      // 서버에 요청을 보내고 응답을 기다리지 않습니다.
      await _dio.post(
        _serverUrl,
        data: {
          'record_id': recordId,
          'key_frames': keyFramesData,
        },
      );
      print('✅ 2차 검증 요청 전송 완료: $recordId');
    } catch (e) {
      print('🚨 2차 검증 요청 오류: $e');
      // TODO: 요청 실패 시 Firestore의 레코드 상태를 'error'로 업데이트하는 로직을 추가할 수 있습니다.
    }
  }
}
