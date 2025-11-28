import 'package:flutter/material.dart';
import '../models/call_record.dart';

// ✨ 확률에 따라 UI 스타일(색상, 아이콘, 텍스트)을 결정하는 헬퍼 클래스
class _DetectionStatus {
  final Color color;
  final IconData icon;
  final String text;

  _DetectionStatus(this.color, this.icon, this.text);

  factory _DetectionStatus.fromProbability(double p) {
    if (p >= 0.85) {
      return _DetectionStatus(Colors.red[700]!, Icons.gpp_bad, '위험');
    } else if (p >= 0.7) {
      return _DetectionStatus(Colors.red[400]!, Icons.warning_amber, '경고');
    } else if (p >= 0.5) {
      return _DetectionStatus(Colors.orange, Icons.error_outline, '주의');
    } else {
      // 50% 미만은 원칙적으로 저장되지 않지만, 안전장치로 추가
      return _DetectionStatus(Colors.grey, Icons.help_outline, '알 수 없음');
    }
  }
}

class ReportDetailScreen extends StatelessWidget {
  final CallRecord record;

  const ReportDetailScreen({super.key, required this.record});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('상세 통화 기록'),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('통화 개요'),
            _buildInfoCard(
              children: [
                _buildInfoRow('채널 ID', record.channelId),
                _buildInfoRow('통화 시작',
                    record.callStartedAt.toLocal().toString().substring(0, 16)),
                _buildInfoRow('통화 종료',
                    record.callEndedAt?.toLocal().toString().substring(0, 16) ??
                        'N/A'),
                _buildInfoRow('총 통화시간', '${record.durationInSeconds}초'),
              ],
            ),
            const SizedBox(height: 24),
            _buildSectionTitle('AI 분석 결과'),
            _buildInfoCard(
              highlight: true,
              children: [
                _buildInfoRow(
                    '위험도',
                    record.riskLevel.toString().split('.').last.toUpperCase(),
                    valueColor: _getRiskColor(record.riskLevel)),
                _buildInfoRow('딥페이크 탐지', '${record.deepfakeDetections}회'),
                _buildInfoRow('최대 의심 확률',
                    '${(record.maxFakeProbability * 100).toStringAsFixed(1)}%'),
              ],
            ),
            const SizedBox(height: 24),
            _buildSectionTitle('상세 분석 자료'),
            const SizedBox(height: 8),

            // ✅ 위험도 기준 안내 위젯 추가
            _buildRiskLegend(),
            const SizedBox(height: 24),

            if (record.keyFrames.isNotEmpty) ...[
              _buildKeyFrameGrid('주요 의심 프레임 (최대 4개)', record.keyFrames),
              const SizedBox(height: 16),
            ],
            if (record.reportPdfUrl != null)
              Center(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('종합 보고서 다운로드'),
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildInfoCard(
      {required List<Widget> children, bool highlight = false}) {
    return Card(
      elevation: 2,
      color: highlight ? Colors.blue[50] : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(children: children),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600])),
          Text(
            value,
            style: TextStyle(
                fontWeight: FontWeight.w500,
                color: valueColor ?? Colors.black),
          ),
        ],
      ),
    );
  }

  // ✅ 새로 추가된 위험도 기준 안내 위젯
  Widget _buildRiskLegend() {
    return _buildInfoCard(
      children: [
        const Text(
          '위험도 기준 안내',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        _buildLegendRow(_DetectionStatus.fromProbability(0.85)),
        const SizedBox(height: 8),
        _buildLegendRow(_DetectionStatus.fromProbability(0.7)),
        const SizedBox(height: 8),
        _buildLegendRow(_DetectionStatus.fromProbability(0.5)),
      ],
    );
  }

  // ✅ 위험도 기준의 한 줄을 만드는 헬퍼 위젯
  Widget _buildLegendRow(_DetectionStatus status) {
    String description;
    if (status.text == '위험') {
      description = '확률 85% 이상';
    } else if (status.text == '경고') {
      description = '확률 70% 이상';
    } else {
      description = '확률 50% 이상';
    }

    return Row(
      children: [
        Icon(status.icon, color: status.color, size: 22),
        const SizedBox(width: 12),
        Text(
          status.text,
          style: TextStyle(
              fontWeight: FontWeight.bold, color: status.color, fontSize: 15),
        ),
        const Spacer(),
        Text(
          description,
          textAlign: TextAlign.right,
          style: TextStyle(color: Colors.grey[700], fontSize: 14),
        ),
      ],
    );
  }

  Widget _buildKeyFrameGrid(String title, List<KeyFrame> keyFrames) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.8, // 이미지와 텍스트 공간 확보를 위해 비율 조정
          ),
          itemCount: keyFrames.length,
          itemBuilder: (context, index) {
            final keyFrame = keyFrames[index];
            final status = _DetectionStatus.fromProbability(keyFrame.probability);

            return Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: status.color, width: 3),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      keyFrame.url,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, progress) =>
                          progress == null
                              ? child
                              : const Center(child: CircularProgressIndicator()),
                      errorBuilder: (context, error, stackTrace) =>
                          const Icon(Icons.error),
                    ),
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 4, horizontal: 6),
                        color: Colors.black.withOpacity(0.6),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(status.icon, color: status.color, size: 16),
                            const SizedBox(width: 4),
                            Text(
                              status.text,
                              style: TextStyle(
                                color: status.color,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '${(keyFrame.probability * 100).toStringAsFixed(1)}%',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Color _getRiskColor(RiskLevel riskLevel) {
    switch (riskLevel) {
      case RiskLevel.danger:
        return Colors.red;
      case RiskLevel.warning:
        return Colors.orange;
      case RiskLevel.caution:
        return Colors.amber;
      default:
        return Colors.green;
    }
  }
}
