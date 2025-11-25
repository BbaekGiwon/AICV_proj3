import 'package:flutter/material.dart';
import 'video_call_screen.dart';

class DialScreen extends StatefulWidget {
  final VoidCallback onCallEnded;

  const DialScreen({super.key, required this.onCallEnded});

  @override
  State<DialScreen> createState() => _DialScreenState();
}

class _DialScreenState extends State<DialScreen> {
  String _dialedNumber = '';

  void _onKeyPressed(String value) {
    if (!mounted) return;
    setState(() {
      if (_dialedNumber.length < 20) {
        _dialedNumber += value;
      }
    });
  }

  void _onBackspace() {
    if (!mounted || _dialedNumber.isEmpty) return;
    setState(() {
      _dialedNumber =
          _dialedNumber.substring(0, _dialedNumber.length - 1);
    });
  }

  Future<void> _onCallPressed() async {
    if (_dialedNumber.isEmpty) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoCallScreen(phoneNumber: _dialedNumber),
      ),
    );
    widget.onCallEnded();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          const SizedBox(height: 24),
          Text(
            _dialedNumber.isEmpty ? '번호를 입력하세요' : _dialedNumber,
            style:
            const TextStyle(fontSize: 26, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildKeypadRow(['1', '2', '3']),
                  const SizedBox(height: 10),
                  _buildKeypadRow(['4', '5', '6']),
                  const SizedBox(height: 10),
                  _buildKeypadRow(['7', '8', '9']),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildKeypadButton('*'),
                      _buildKeypadButton('0'),
                      _buildBackspaceButton(),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(bottom: 20.0),
            child: ElevatedButton.icon(
              onPressed: _dialedNumber.isEmpty ? null : _onCallPressed,
              icon: const Icon(Icons.videocam),
              label: const Text('영상통화', style: TextStyle(fontSize: 18)),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(220, 50),
                shape: const StadiumBorder(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKeypadRow(List<String> values) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: values.map(_buildKeypadButton).toList(),
    );
  }

  Widget _buildKeypadButton(String value) {
    return SizedBox(
      width: 70,
      height: 70,
      child: ElevatedButton(
        onPressed: () => _onKeyPressed(value),
        style: ElevatedButton.styleFrom(shape: const CircleBorder()),
        child: Text(value, style: const TextStyle(fontSize: 24)),
      ),
    );
  }

  Widget _buildBackspaceButton() {
    return SizedBox(
      width: 70,
      height: 70,
      child: ElevatedButton(
        onPressed: _onBackspace,
        style: ElevatedButton.styleFrom(shape: const CircleBorder()),
        child: const Icon(Icons.backspace),
      ),
    );
  }
}