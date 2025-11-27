import 'package:flutter/material.dart';
import '../models/call_record.dart';

// ✅ 상세 보고서 화면을 위한 새로운 StatelessWidget을 추가합니다.
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
            // --- 1. 기본 통화 정보 섹션 ---
            _buildSectionTitle('통화 개요'),
            _buildInfoCard(
              children: [
                _buildInfoRow('채널 ID', record.channelId),
                _buildInfoRow('통화 시작', record.callStartedAt.toLocal().toString().substring(0, 16)),
                _buildInfoRow('통화 종료', record.callEndedAt?.toLocal().toString().substring(0, 16) ?? 'N/A'),
                _buildInfoRow('총 통화시간', '${record.durationInSeconds}초'),
              ],
            ),
            const SizedBox(height: 24),

            // --- 2. AI 분석 결과 섹션 ---
            _buildSectionTitle('AI 분석 결과'),
            _buildInfoCard(
              highlight: true,
              children: [
                _buildInfoRow('위험도', record.riskLevel.toString().split('.').last.toUpperCase(),
                    valueColor: _getRiskColor(record.riskLevel)),
                _buildInfoRow('딥페이크 탐지', '${record.deepfakeDetections}회'),
                _buildInfoRow(
                    '최대 의심 확률', '${(record.maxFakeProbability * 100).toStringAsFixed(1)}%'),
              ],
            ),
            const SizedBox(height: 24),

            // --- 3. 상세 분석 자료 섹션 ---
            _buildSectionTitle('상세 분석 자료'),
            const SizedBox(height: 8),

            // ✅ 가장 높게 탐지된 순간을 보여주는 새로운 섹션
            if (record.highestProbKeyFrameUrl != null && record.highestProbGradCamUrl != null) ...[
              _buildHighlightImageSection(
                context,
                '가장 높게 탐지된 순간',
                record.highestProbKeyFrameUrl!,
                record.highestProbGradCamUrl!,
              ),
              const SizedBox(height: 24),
            ],

            // 키 프레임 이미지 목록
            if (record.keyFrames.isNotEmpty) ...[
              _buildImageGrid('전체 주요 프레임', record.keyFrames),
              const SizedBox(height: 16),
            ],

            // Grad-CAM 이미지 목록
            if (record.gradcamImages.isNotEmpty) ...[
              _buildImageGrid('전체 AI 판단 근거 (Grad-CAM)', record.gradcamImages),
              const SizedBox(height: 16),
            ],

            // PDF 보고서 다운로드 버튼
            if (record.reportPdfUrl != null)
              Center(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('종합 보고서 다운로드'),
                  onPressed: () {
                    // TODO: PDF 파일 열기/다운로드 로직 구현
                  },
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

  // 섹션 제목을 꾸미는 위젯
  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }

  // 정보 카드 UI
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

  // "항목: 값" 형태의 정보 행
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
  
  // ✅ 가장 의심스러운 순간을 보여주기 위한 위젯
  Widget _buildHighlightImageSection(BuildContext context, String title, String keyFrameUrl, String gradCamUrl) {
    Widget imageWidget(String url) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          url,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, progress) =>
              progress == null ? child : const Center(child: CircularProgressIndicator()),
          errorBuilder: (context, error, stackTrace) => const Icon(Icons.error, size: 40),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
        const SizedBox(height: 12),
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      const Text("원본 프레임", style: TextStyle(fontWeight: FontWeight.w500)),
                      const SizedBox(height: 8),
                      imageWidget(keyFrameUrl),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    children: [
                      const Text("AI 판단 근거", style: TextStyle(fontWeight: FontWeight.w500)),
                      const SizedBox(height: 8),
                      imageWidget(gradCamUrl),
                    ],
                  ),
                ),
              ],
            ),
          ),
        )
      ],
    );
  }

  // 이미지 그리드 UI
  Widget _buildImageGrid(String title, List<String> imageUrls) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: imageUrls.length,
          itemBuilder: (context, index) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                imageUrls[index],
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) =>
                    progress == null ? child : const Center(child: CircularProgressIndicator()),
                errorBuilder: (context, error, stackTrace) =>
                    const Icon(Icons.error),
              ),
            );
          },
        ),
      ],
    );
  }

  // 위험도에 따른 색상 반환
  Color _getRiskColor(RiskLevel riskLevel) {
    switch (riskLevel) {
      case RiskLevel.danger:
        return Colors.red;
      case RiskLevel.warning:
        return Colors.orange;
      case RiskLevel.caution:
        return Colors.amber;
      default:
        // ✅ 'unknown'을 포함한 나머지 경우는 초록색으로 표시
        return Colors.green;
    }
  }
}
