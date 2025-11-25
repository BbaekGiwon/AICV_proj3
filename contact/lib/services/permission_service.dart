import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  static Future<bool> requestCameraAndMic() async {
    final camera = await Permission.camera.request();
    final mic = await Permission.microphone.request();

    return camera.isGranted && mic.isGranted;
  }
}