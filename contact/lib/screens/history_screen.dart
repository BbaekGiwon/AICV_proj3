import 'package:contact/repositories/call_repository.dart';
import 'package:contact/screens/report_detail_screen.dart';
import 'package:contact/services/firestore_service.dart';
import 'package:contact/services/storage_service.dart';
import 'package:flutter/material.dart';
import '../models/call_record.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  bool _isSelectionMode = false;
  final Set<String> _selectedRecordIds = {};
  late final CallRecordRepository _repository;

  @override
  void initState() {
    super.initState();
    final firestoreService = FirestoreService();
    final storageService = StorageService();
    _repository = CallRecordRepository(firestoreService, storageService);
  }

  void _enterSelectionMode() {
    setState(() => _isSelectionMode = true);
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedRecordIds.clear();
    });
  }

  void _toggleSelection(String recordId) {
    setState(() {
      if (_selectedRecordIds.contains(recordId)) {
        _selectedRecordIds.remove(recordId);
      } else {
        _selectedRecordIds.add(recordId);
      }
    });
  }

  void _navigateToDetail(BuildContext context, CallRecord record) {
    if (record.status == CallStatus.done) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => ReportDetailScreen(record: record)),
      );
    }
  }

  void _deleteSelectedRecords() async {
    if (_selectedRecordIds.isEmpty) return;

    final bool? shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${_selectedRecordIds.length}개의 기록 삭제'),
        content: const Text('선택한 통화 기록과 관련 이미지 파일을 영구적으로 삭제하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
          ),
        ],
      ),
    );

    if (shouldDelete == true) {
      try {
        await _repository.deleteCallRecords(_selectedRecordIds.toList());
        final currentHistory = List<CallRecord>.from(callHistoryNotifier.value)
          ..removeWhere((record) => _selectedRecordIds.contains(record.id));
        callHistoryNotifier.value = currentHistory;
        _exitSelectionMode();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('선택한 기록을 삭제했습니다.')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('기록 삭제에 실패했습니다: $e')));
        }
      }
    }
  }

  Widget _buildControlsBar() {
    if (!_isSelectionMode) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '기록 삭제',
              onPressed: _enterSelectionMode,
            ),
          ],
        ),
      );
    }

    return Material(
      elevation: 2,
      color: Colors.blue[50],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        child: Row(
          children: [
            IconButton(icon: const Icon(Icons.close), onPressed: _exitSelectionMode),
            const SizedBox(width: 12),
            Text('${_selectedRecordIds.length}개 선택', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const Spacer(),
            IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: _deleteSelectedRecords),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildControlsBar(),
        Expanded(
          child: ValueListenableBuilder<List<CallRecord>>(
            valueListenable: callHistoryNotifier,
            builder: (context, history, child) {
              if (history.isEmpty) {
                return const Center(child: Text('통화 기록이 없습니다.'));
              }

              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 80),
                itemCount: history.length,
                itemBuilder: (context, index) {
                  final record = history[index];
                  final isProcessing = record.status == CallStatus.processing;
                  final isSelected = _selectedRecordIds.contains(record.id);

                  final Color riskColor;
                  final IconData riskIcon;

                  if (isProcessing) {
                    riskColor = Colors.grey;
                    riskIcon = Icons.hourglass_empty;
                  } else {
                    // ✅✅✅ record.riskLevel 대신 record.averageProbability를 사용하도록 변경
                    final p = record.averageProbability;
                    if (p >= 0.85) {
                      riskColor = Colors.red[700]!;
                      riskIcon = Icons.gpp_bad;
                    } else if (p >= 0.7) {
                      riskColor = Colors.red[400]!;
                      riskIcon = Icons.warning_amber;
                    } else if (p >= 0.5) {
                      riskColor = Colors.orange;
                      riskIcon = Icons.error_outline;
                    } else {
                      riskColor = Colors.green;
                      riskIcon = Icons.verified_user;
                    }
                  }

                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    color: isSelected ? Colors.blue[100] : null,
                    child: ListTile(
                      onTap: () {
                        if (_isSelectionMode) {
                          _toggleSelection(record.id);
                        } else {
                          _navigateToDetail(context, record);
                        }
                      },
                      onLongPress: () {
                        if (!_isSelectionMode) {
                          _enterSelectionMode();
                          _toggleSelection(record.id);
                        }
                      },
                      contentPadding: const EdgeInsets.all(12),
                      leading: isSelected
                          ? Icon(Icons.check_circle, color: Theme.of(context).primaryColor, size: 40)
                          : Icon(riskIcon, color: riskColor, size: 40),
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
                              '탐지: ${record.deepfakeDetections}회 / 평균 딥페이크 확률: ${(record.averageProbability * 100).toStringAsFixed(1)}%',
                              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                            ),
                        ],
                      ),
                      trailing: isProcessing
                          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text('${record.durationInSeconds}초'),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
