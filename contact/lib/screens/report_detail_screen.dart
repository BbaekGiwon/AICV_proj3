import 'package:contact/models/call_record.dart';
import 'package:contact/repositories/call_repository.dart';
import 'package:contact/services/firestore_service.dart';
import 'package:contact/services/storage_service.dart';
import 'package:flutter/material.dart';

class ReportDetailScreen extends StatefulWidget {
  final CallRecord record;

  const ReportDetailScreen({super.key, required this.record});

  @override
  State<ReportDetailScreen> createState() => _ReportDetailScreenState();
}

class _ReportDetailScreenState extends State<ReportDetailScreen> {
  late CallRecord _record;
  late final CallRecordRepository _repository;
  late final TextEditingController _memoController;
  bool _isEditingMemo = false;

  @override
  void initState() {
    super.initState();
    _record = widget.record;
    final firestoreService = FirestoreService();
    final storageService = StorageService();
    _repository = CallRecordRepository(firestoreService, storageService);
    _memoController = TextEditingController(text: _record.userMemo);
  }

  @override
  void dispose() {
    _memoController.dispose();
    super.dispose();
  }

  void _saveMemo() async {
    final newMemo = _memoController.text;
    try {
      await _repository.updateMemo(_record.id, newMemo);
      setState(() {
        _record = _record.copyWith(userMemo: newMemo);
        _isEditingMemo = false;
      });

      final history = List<CallRecord>.from(callHistoryNotifier.value);
      final index = history.indexWhere((r) => r.id == _record.id);
      if (index != -1) {
        history[index] = _record;
        callHistoryNotifier.value = history;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('메모가 저장되었습니다.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('메모 저장에 실패했습니다: $e')));
      }
    }
  }

  void _enterEditMode() {
    setState(() => _isEditingMemo = true);
  }

  void _exitEditMode() {
    setState(() {
      _memoController.text = _record.userMemo ?? '';
      _isEditingMemo = false;
    });
  }

  Color _getColorFromProbability(double probability) {
    if (probability >= 0.85) return Colors.red[700]!;
    if (probability >= 0.7) return Colors.red[400]!;
    if (probability >= 0.5) return Colors.orange;
    return Colors.green;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('상세 통화 기록'), elevation: 0),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('통화 개요'),
            _buildInfoCard(children: [
              _buildInfoRow('채널 ID', _record.channelId),
              _buildInfoRow('통화 시작', _record.callStartedAt.toLocal().toString().substring(0, 16)),
              _buildInfoRow('통화 종료', _record.callEndedAt?.toLocal().toString().substring(0, 16) ?? 'N/A'),
              _buildInfoRow('총 통화시간', '${_record.durationInSeconds}초'),
            ]),
            const SizedBox(height: 24),
            _buildSectionTitle('AI 분석 결과'),
            _buildInfoCard(highlight: true, children: [
              _buildInfoRow('평균 딥페이크 확률', '${(_record.averageProbability * 100).toStringAsFixed(1)}%',
                  valueColor: _getColorFromProbability(_record.averageProbability)),
              _buildInfoRow('딥페이크 탐지', '${_record.deepfakeDetections}회'),
              _buildInfoRow('최대 의심 확률', '${(_record.maxFakeProbability * 100).toStringAsFixed(1)}%',
                  valueColor: _getColorFromProbability(_record.maxFakeProbability)),
            ]),
            const SizedBox(height: 24),
            _buildSectionTitle('상세 분석 자료'),
            const SizedBox(height: 8),
            if (_record.keyFrames.isNotEmpty) ...[
              _buildAnalysisFrames(),
              const SizedBox(height: 16),
            ],
            _buildSectionTitle('사용자 메모'),
            _buildMemoCard(),
            _buildEnvironmentInfo(),
            const SizedBox(height: 24),
            if (_record.reportPdfUrl != null)
              Center(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('종합 보고서 다운로드'),
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
                ),
              ),
            // ✅✅✅ 경고 문구 위젯 추가
            _buildDisclaimer(),
          ],
        ),
      ),
    );
  }

  // ✅✅✅ 경고 문구 위젯
  Widget _buildDisclaimer() {
    return Padding(
      padding: const EdgeInsets.only(top: 32.0, bottom: 16.0),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, color: Colors.grey, size: 18),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'AI 탐지 결과는 100% 정확하지 않을 수 있습니다. 최종 판단은 반드시 사용자 또는 담당자의 종합적인 검토가 필요합니다.',
                style: TextStyle(fontSize: 12, color: Colors.black54, height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEnvironmentInfo() {
    final hasDeviceInfo = _record.deviceInfo.entries.isNotEmpty;
    final hasServerInfo = _record.serverInfo.entries.isNotEmpty;

    if (!hasDeviceInfo && !hasServerInfo) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        _buildSectionTitle('분석 환경 정보'),
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Column(
            children: [
              if (hasDeviceInfo)
                ..._buildTableRows(_record.deviceInfo, '데이터 수집 디바이스'),
              if (hasDeviceInfo && hasServerInfo)
                const Divider(height: 1, indent: 16, endIndent: 16),
              if (hasServerInfo)
                ..._buildTableRows(_record.serverInfo, '서버 분석 환경'),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _buildTableRows(Map<String, String> data, String title) {
    List<Widget> rows = [
      ListTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ),
    ];

    rows.addAll(data.entries.map((entry) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(entry.key, style: TextStyle(color: Colors.grey[600])),
            const SizedBox(width: 16),
            Flexible(
              child: Text(
                entry.value,
                textAlign: TextAlign.end,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      );
    }));

    rows.add(const SizedBox(height: 8));

    return rows;
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildInfoCard({required List<Widget> children, bool highlight = false}) {
    return Card(
      elevation: 2,
      color: highlight ? Colors.blue[50] : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(padding: const EdgeInsets.all(16.0), child: Column(children: children)),
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600])),
          Text(value, style: TextStyle(fontWeight: FontWeight.w500, color: valueColor ?? Colors.black)),
        ],
      ),
    );
  }

  Widget _buildMemoCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _isEditingMemo ? null : _enterEditMode,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: _isEditingMemo ? _buildMemoEditor() : _buildMemoViewer(),
        ),
      ),
    );
  }

  Widget _buildMemoViewer() {
    bool hasMemo = _record.userMemo != null && _record.userMemo!.isNotEmpty;
    return Container(
      constraints: const BoxConstraints(minHeight: 80),
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            hasMemo ? _record.userMemo! : '저장된 메모가 없습니다.\n탭하여 메모를 작성하세요...',
            style: TextStyle(color: hasMemo ? Colors.black : Colors.grey, height: 1.5),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(child: Text(hasMemo ? '수정' : '작성'), onPressed: _enterEditMode),
          ),
        ],
      ),
    );
  }

  Widget _buildMemoEditor() {
    return Column(
      children: [
        TextField(
          controller: _memoController,
          autofocus: true,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: '통화에 대한 내용을 자유롭게 메모하세요.',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(child: const Text('취소'), onPressed: _exitEditMode),
            const SizedBox(width: 8),
            ElevatedButton(child: const Text('저장'), onPressed: _saveMemo),
          ],
        )
      ],
    );
  }

  Widget _buildAnalysisFrames() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('주요 의심 프레임 (최대 4개)', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
        const SizedBox(height: 12),
        Column(
          children: _record.keyFrames.map((keyFrame) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        const Text('원본 프레임', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        _buildImageCard(keyFrame.url, keyFrame),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      children: [
                        const Text('Grad-CAM', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        keyFrame.gradCamUrl != null
                            ? _buildImageCard(keyFrame.gradCamUrl!, keyFrame)
                            : _buildLoadingCard(),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildImageCard(String imageUrl, KeyFrame keyFrame) {
    final status = _DetectionStatus.fromProbability(keyFrame.probability);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: status.color, width: 3),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: AspectRatio(
          aspectRatio: 0.8,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                imageUrl,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) =>
                    progress == null ? child : const Center(child: CircularProgressIndicator()),
                errorBuilder: (context, error, stackTrace) => const Icon(Icons.error),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                  color: Colors.black.withAlpha(153),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(status.icon, color: status.color, size: 16),
                      const SizedBox(width: 4),
                      Text(status.text, style: TextStyle(color: status.color, fontWeight: FontWeight.bold, fontSize: 12)),
                      const Spacer(),
                      Text('${(keyFrame.probability * 100).toStringAsFixed(1)}%', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingCard() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey, width: 3),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: AspectRatio(
          aspectRatio: 0.8,
          child: Container(
            color: Colors.grey[200],
            child: const Center(
              child: CircularProgressIndicator(),
            ),
          ),
        ),
      ),
    );
  }
}

class _DetectionStatus {
  final Color color;
  final IconData icon;
  final String text;

  _DetectionStatus(this.color, this.icon, this.text);

  factory _DetectionStatus.fromProbability(double p) {
    if (p >= 0.85) return _DetectionStatus(Colors.red[700]!, Icons.gpp_bad, '위험');
    if (p >= 0.7) return _DetectionStatus(Colors.red[400]!, Icons.warning_amber, '경고');
    if (p >= 0.5) return _DetectionStatus(Colors.orange, Icons.error_outline, '주의');
    return _DetectionStatus(Colors.green, Icons.help_outline, '알 수 없음');
  }
}
