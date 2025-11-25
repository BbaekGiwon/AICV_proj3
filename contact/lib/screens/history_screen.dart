import 'package:flutter/material.dart';
import '../models/call_record.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  @override
  Widget build(BuildContext context) {
    final reversedHistory = callHistory.reversed.toList();

    if (reversedHistory.isEmpty) {
      return const Center(child: Text('통화 기록이 없습니다.'));
    }

    return ListView.builder(
      itemCount: reversedHistory.length,
      itemBuilder: (context, index) {
        final record = reversedHistory[index];
        return ListTile(
          leading: const Icon(Icons.videocam_outlined, color: Colors.grey),
          title: Text(
            record.phoneNumber,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          subtitle: Text(
            record.startTime.toLocal().toString().substring(0, 16),
          ),
          trailing: Text('${record.duration.inSeconds}초'),
        );
      },
    );
  }
}