import 'package:contact/screens/report_detail_screen.dart';
import 'package:flutter/material.dart';
import '../models/call_record.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late List<CallRecord> _history;

  @override
  void initState() {
    super.initState();
    _history = callHistoryNotifier.value;
    callHistoryNotifier.addListener(_onHistoryChanged);
  }

  @override
  void dispose() {
    callHistoryNotifier.removeListener(_onHistoryChanged);
    super.dispose();
  }

  void _onHistoryChanged() {
    setState(() {
      _history = callHistoryNotifier.value;
    });
  }

  void _navigateToDetail(CallRecord record) {
    // ✅ 분석이 완료된 항목만 상세 화면으로 이동
    if (record.status == CallStatus.done) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ReportDetailScreen(record: record),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_history.isEmpty) {
      return const Center(child: Text('통화 기록이 없습니다.'));
    }

    return ListView.builder(
      itemCount: _history.length,
      itemBuilder: (context, index) {
        final record = _history[index];
        final isProcessing = record.status == CallStatus.processing;

        final Color riskColor;
        final IconData riskIcon;

        if (isProcessing) {
          riskColor = Colors.grey;
          riskIcon = Icons.hourglass_empty;
        } else {
          switch (record.riskLevel) {
            case RiskLevel.danger:
              riskColor = Colors.red;
              riskIcon = Icons.gpp_bad;
              break;
            case RiskLevel.warning:
              riskColor = Colors.orange;
              riskIcon = Icons.shield;
              break;
            case RiskLevel.caution:
              riskColor = Colors.yellow[700]!;
              riskIcon = Icons.shield_outlined;
              break;
            default:
              riskColor = Colors.green;
              riskIcon = Icons.verified_user;
              break;
          }
        }

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: ListTile(
            onTap: () => _navigateToDetail(record),
            contentPadding: const EdgeInsets.all(12),
            leading: Icon(riskIcon, color: riskColor, size: 40),
            title: Text(
              record.channelId,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 16),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  record.callStartedAt.toLocal().toString().substring(0, 16),
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 2),
                if (isProcessing)
                  const Text(
                    '분석 중입니다...',
                    style: TextStyle(fontSize: 12, color: Colors.blueAccent),
                  )
                else
                  Text(
                    '탐지: ${record.deepfakeDetections}회 / 위험도: ${(record.maxFakeProbability * 100).toStringAsFixed(1)}%',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
              ],
            ),
            trailing: isProcessing
                ? const SizedBox(
                    width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                : Text('${record.durationInSeconds}초'),
          ),
        );
      },
    );
  }
}
