import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/voice_detect_services.dart';

class VoiceDetectScreen extends StatefulWidget {
  const VoiceDetectScreen({super.key});

  @override
  State<VoiceDetectScreen> createState() => _VoiceDetectScreenState();
}

class _VoiceDetectScreenState extends State<VoiceDetectScreen> {
  final VoiceDetectService _voiceDetectService = VoiceDetectService.instance;
  StreamSubscription? _probSubscription;

  bool _isDetecting = false;
  double _fakeProbability = 0.0;

  @override
  void initState() {
    super.initState();
    _probSubscription = _voiceDetectService.fakeProbabilityStream.listen((prob) {
      if (mounted) {
        setState(() {
          _fakeProbability = prob;
        });
      }
    });
  }

  @override
  void dispose() {
    _probSubscription?.cancel();
    // 화면이 꺼질 때 탐지를 중지하도록 보장
    if (_isDetecting) {
      _voiceDetectService.stopDetection();
    }
    super.dispose();
  }

  Future<void> _toggleDetection() async {
    if (_isDetecting) {
      await _voiceDetectService.stopDetection();
      if (mounted) {
        setState(() {
          _isDetecting = false;
          _fakeProbability = 0.0;
        });
      }
    } else {
      final status = await Permission.microphone.request();
      if (status.isGranted) {
        await _voiceDetectService.startDetection();
        if (mounted) {
          setState(() {
            _isDetecting = true;
          });
        }
      } else {
        // 권한 거부 시 사용자에게 알림
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('음성 탐지를 위해 마이크 권한이 필요합니다.')),
        );
      }
    }
  }

  Color _getStatusColor() {
    final p = _fakeProbability;
    if (p >= 0.7) {
      return Colors.red[600]!;
    } else if (p >= 0.5) {
      return Colors.orange[600]!;
    } else {
      return Colors.green[600]!;
    }
  }

  String _getStatusText() {
    final p = _fakeProbability;
     if (p >= 0.85) {
      return '딥보이스 확신';
    } else if (p >= 0.7) {
      return '딥보이스 의심';
    } else if (p >= 0.5) {
      return '딥보이스 가능성';
    } else if (p >= 0.3) {
      return 'Real 가능성 높음';
    } else {
      return 'Real 확신';
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text(
              '딥보이스 탐지 확률',
              style: TextStyle(fontSize: 22, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Text(
              '${(_fakeProbability * 100).toStringAsFixed(1)}%',
              style: TextStyle(
                fontSize: 72,
                fontWeight: FontWeight.bold,
                color: _isDetecting ? _getStatusColor() : Colors.black,
              ),
            ),
             const SizedBox(height: 8),
            if(_isDetecting)
              Text(
                _getStatusText(),
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w500,
                  color: _getStatusColor(),
                ),
              ),
            const SizedBox(height: 60),
            ElevatedButton.icon(
              onPressed: _toggleDetection,
              icon: Icon(_isDetecting ? Icons.stop : Icons.mic, size: 28),
              label: Text(
                _isDetecting ? '탐지 중지' : '탐지 시작',
                style: const TextStyle(fontSize: 20),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isDetecting ? Colors.redAccent : Colors.blueAccent,
                foregroundColor: Colors.white,
                minimumSize: const Size(200, 60),
                shape: const StadiumBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
