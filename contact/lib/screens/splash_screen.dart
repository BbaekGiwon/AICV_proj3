import 'dart:async';
import 'package:flutter/material.dart';
import '../models/call_record.dart';
import '../repositories/call_repository.dart'; 
import '../services/firestore_service.dart';
import '../services/storage_service.dart';
import 'main_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDataAndNavigate();
    });
  }

  Future<void> _loadDataAndNavigate() async {
    final timer = Future.delayed(const Duration(seconds: 2));
    
    print('🔄 [DEBUG] SplashScreen에서 데이터 로딩을 시작합니다...');
    await _loadInitialData();

    await timer;
    
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainScreen()),
      );
    }
  }

  Future<void> _loadInitialData() async {
    try {
      final firestoreService = FirestoreService();
      final storageService = StorageService();
      final callRepository = CallRecordRepository(firestoreService, storageService);
      
      // ✅✅✅ 주석을 풀고, 정상적으로 데이터를 불러옵니다. ✅✅✅
      final records = await callRepository.getAllCallRecords(); 

      callHistoryNotifier.value = records;
      print('✅ [DEBUG] Firestore에서 ${records.length}개의 통화 기록을 불러왔습니다.');
    } catch (e) {
      print('❌ [ERROR] 데이터 로딩 중 오류 발생: $e');
      callHistoryNotifier.value = []; 
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.blueAccent,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.videocam_rounded, size: 100, color: Colors.white),
            SizedBox(height: 20),
            Text(
              'Deepfake Killer',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 40),
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
