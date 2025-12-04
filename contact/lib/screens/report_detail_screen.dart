import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

import '../models/call_record.dart';
import '../repositories/report_repository.dart';
import '../services/firestore_service.dart';
import '../services/storage_service.dart';

class ReportDetailScreen extends StatefulWidget {
  final String recordId;

  const ReportDetailScreen({super.key, required this.recordId});

  @override
  State<ReportDetailScreen> createState() => _ReportDetailScreenState();
}

class _ReportDetailScreenState extends State<ReportDetailScreen> {
  late final ReportRepository _reportRepository;
  late final Stream<DocumentSnapshot> _recordStream;

  @override
  void initState() {
    super.initState();
    // Firestore와 Storage 서비스 인스턴스를 생성합니다.
    final firestoreService = FirestoreService();
    final storageService = StorageService();
    // ReportRepository를 초기화합니다.
    _reportRepository = ReportRepository(firestoreService, storageService);
    _recordStream = _reportRepository.getCallRecordStream(widget.recordId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('통화 분석 리포트'),
        centerTitle: true,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: _recordStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('오류가 발생했습니다: ${snapshot.error}'));
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text('통화 기록을 찾을 수 없습니다.'));
          }

          final record = CallRecord.fromFirestore(snapshot.data!);

          // status 값에 따라 다른 UI를 보여줍니다.
          switch (record.status) {
            case CallStatus.processing:
              return _buildProcessingWidget(record);
            case CallStatus.error:
              return _buildErrorWidget(record);
            case CallStatus.done:
            default:
              return _buildReportContent(record);
          }
        },
      ),
    );
  }

  // "분석 중" 상태일 때 보여줄 위젯
  Widget _buildProcessingWidget(CallRecord record) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          const Text(
            '서버에서 2차 검증을 진행하고 있습니다.',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            '분석이 완료되면 이 화면이 자동으로 새로고침됩니다.',
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 30),
          _buildSimpleInfoCard(record),
        ],
      ),
    );
  }

  // "오류" 상태일 때 보여줄 위젯
  Widget _buildErrorWidget(CallRecord record) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, color: Colors.red[400], size: 60),
          const SizedBox(height: 20),
          const Text(
            '리포트 생성 중 오류가 발생했습니다.',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            '네트워크 상태를 확인하거나 잠시 후 다시 시도해주세요.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 30),
          _buildSimpleInfoCard(record),
        ],
      ),
    );
  }

  // "완료" 상태일 때 보여줄 메인 리포트 위젯
  Widget _buildReportContent(CallRecord record) {
    final keyFrames = record.keyFrames;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSimpleInfoCard(record),
          const SizedBox(height: 24),
          _buildSectionTitle('탐지된 주요 프레임', '딥페이크 확률이 가장 높게 나타난 프레임입니다.'),
          const SizedBox(height: 12),
          keyFrames.isEmpty
              ? const Text('탐지된 프레임이 없습니다.')
              : _buildKeyFrameGallery(keyFrames),
          const SizedBox(height: 24),
          _buildSectionTitle('분석 정보', '통화 및 분석 환경에 대한 정보입니다.'),
          const SizedBox(height: 12),
          _buildInfoTable(record),
        ],
      ),
    );
  }

  // 모든 상태에서 공통으로 사용할 간단한 정보 카드
  Widget _buildSimpleInfoCard(CallRecord record) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildInfoRow(
                Icons.calendar_today, '통화 일시', DateFormat('yyyy-MM-dd HH:mm').format(record.callStartedAt)),
            const SizedBox(height: 8),
            _buildInfoRow(Icons.timer_outlined, '통화 시간', '${record.durationInSeconds}초'),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(subtitle, style: const TextStyle(fontSize: 14, color: Colors.grey)),
      ],
    );
  }

  Widget _buildKeyFrameGallery(List<KeyFrame> keyFrames) {
    return SizedBox(
      height: 200,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: keyFrames.length,
        itemBuilder: (context, index) {
          final frame = keyFrames[index];
          return GestureDetector(
            onTap: () {
              _openPhotoGallery(context, keyFrames, index);
            },
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Image.network(
                      frame.gradCamUrl ?? frame.url, // Grad-CAM이 있으면 보여주고, 없으면 원본 URL 표시
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, progress) {
                        return progress == null ? child : const Center(child: CircularProgressIndicator());
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return const Center(child: Icon(Icons.error));
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      '딥페이크 확률: ${(frame.probability * 100).toStringAsFixed(1)}%',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _openPhotoGallery(BuildContext context, List<KeyFrame> keyFrames, int initialIndex) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(),
          body: PhotoViewGallery.builder(
            itemCount: keyFrames.length,
            builder: (context, index) {
              final frame = keyFrames[index];
              // Grad-CAM URL이 있으면 사용하고, 없으면 원본 키프레임 URL을 사용합니다.
              final imageUrl = frame.gradCamUrl ?? frame.url;
              return PhotoViewGalleryPageOptions(
                imageProvider: NetworkImage(imageUrl),
                minScale: PhotoViewComputedScale.contained * 0.8,
                maxScale: PhotoViewComputedScale.covered * 2,
              );
            },
            scrollPhysics: const BouncingScrollPhysics(),
            backgroundDecoration: const BoxDecoration(
              color: Colors.black,
            ),
            pageController: PageController(initialPage: initialIndex),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoTable(CallRecord record) {
    final allInfo = {
      '통화 정보': {
        '최대 딥페이크 확률': '${(record.maxFakeProbability * 100).toStringAsFixed(1)}%',
        '평균 딥페이크 확률': '${(record.averageProbability * 100).toStringAsFixed(1)}%',
        '딥페이크 의심 횟수': '${record.deepfakeDetections}회',
      },
      '디바이스 정보': record.deviceInfo,
      '서버 정보': record.serverInfo,
    };

    return Card(
      child: Column(
        children: allInfo.entries.map((entry) {
          return ExpansionTile(
            title: Text(entry.key, style: const TextStyle(fontWeight: FontWeight.bold)),
            initiallyExpanded: entry.key == '통화 정보',
            children: entry.value.entries.map((item) {
              return ListTile(
                title: Text(item.key),
                trailing: Text(item.value, style: const TextStyle(color: Colors.grey)),
              );
            }).toList(),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 12),
        Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const Spacer(),
        Text(value, style: const TextStyle(fontSize: 16)),
      ],
    );
  }
}
