import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart'; // ✨ RootIsolateToken을 위해 추가
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_v2/tflite_v2.dart';
import 'package:path_provider/path_provider.dart';

class DetectionResult {
  final double fakeProb;
  final Rect? faceRect;
  final int imageWidth;
  final int imageHeight;
  final String? croppedFacePath;

  DetectionResult({
    required this.fakeProb,
    required this.faceRect,
    required this.imageWidth,
    required this.imageHeight,
    this.croppedFacePath,
  });
}

// ✨ Isolate에 전달할 데이터 구조체에 '출입증'(RootIsolateToken) 추가
class _IsolateParams {
  final RootIsolateToken token;
  final String filePath;
  final Rect boundingBox;
  final String tempDirPath;

  _IsolateParams(this.token, this.filePath, this.boundingBox, this.tempDirPath);
}

// ✨ Isolate에서 실행될 최상위 함수 (별도 작업실)
Future<Map<String, dynamic>?> _imageProcessingIsolate(
    _IsolateParams params) async {
  // ✨ 이 한 줄이 핵심! 별도 작업실에서 네이티브 기능을 사용할 수 있도록 출입증을 등록합니다.
  BackgroundIsolateBinaryMessenger.ensureInitialized(params.token);

  try {
    final fileBytes = await File(params.filePath).readAsBytes();
    final originalImage = img.decodeImage(fileBytes);

    if (originalImage == null) return null;

    final box = params.boundingBox;
    final croppedImage = img.copyCrop(
      originalImage,
      x: box.left.toInt(),
      y: box.top.toInt(),
      width: box.width.toInt(),
      height: box.height.toInt(),
    );

    final croppedFacePath =
        '${params.tempDirPath}/${DateTime.now().millisecondsSinceEpoch}_face.jpg';
    await File(croppedFacePath).writeAsBytes(img.encodeJpg(croppedImage));

    return {
      'imageWidth': originalImage.width,
      'imageHeight': originalImage.height,
      'croppedFacePath': croppedFacePath,
    };
  } catch (e) {
    print('Isolate error: $e');
    return null;
  }
}

class DetectionService {
  final FaceDetector _faceDetector;

  DetectionService()
      : _faceDetector = FaceDetector(
          options: FaceDetectorOptions(
            performanceMode: FaceDetectorMode.fast,
          ),
        );

  Future<void> loadModel() async {
    await Tflite.loadModel(
      model: "assets/efficientnet_v02.tflite",
      labels: "assets/efficientnet_v02_labels.txt",
      isAsset: true,
    );
  }

  Future<void> dispose() async {
    await _faceDetector.close();
    await Tflite.close();
  }

  Future<DetectionResult> analyze(String filePath) async {
    final originalFile = File(filePath);
    if (!await originalFile.exists() || await originalFile.length() == 0) {
      return DetectionResult(
          fakeProb: 0.0, faceRect: null, imageWidth: 0, imageHeight: 0);
    }

    final inputImage = InputImage.fromFilePath(filePath);
    final faces = await _faceDetector.processImage(inputImage);

    if (faces.isEmpty) {
      await originalFile.delete().catchError((e) {});
      return DetectionResult(
          fakeProb: 0.0, faceRect: null, imageWidth: 0, imageHeight: 0);
    }

    Face mainFace = faces[0];
    if (faces.length > 1) {
      double maxArea = mainFace.boundingBox.width * mainFace.boundingBox.height;
      for (final f in faces.skip(1)) {
        final area = f.boundingBox.width * f.boundingBox.height;
        if (area > maxArea) {
          maxArea = area;
          mainFace = f;
        }
      }
    }

    // ✨ 메인 작업실에서 미리 임시 폴더 주소와 '출입증'을 발급받습니다.
    final tempDir = await getTemporaryDirectory();
    final token = RootIsolateToken.instance!;

    // ✨ 무거운 이미지 처리를 Isolate로 보내면서, 출입증과 주소도 함께 전달합니다.
    final processingResult = await compute(
        _imageProcessingIsolate,
        _IsolateParams(
            token, filePath, mainFace.boundingBox, tempDir.path));

    await originalFile.delete().catchError((e) {});

    if (processingResult == null) {
      return DetectionResult(
          fakeProb: 0.0, faceRect: null, imageWidth: 0, imageHeight: 0);
    }

    final croppedFacePath = processingResult['croppedFacePath'] as String;

    final recognitions = await Tflite.runModelOnImage(
      path: croppedFacePath,
      imageMean: 127.5,
      imageStd: 127.5,
      numResults: 2,
      threshold: 0.1,
      asynch: true,
    );

    double fakeProb = 0.0;
    if (recognitions != null && recognitions.isNotEmpty) {
      for (var r in recognitions) {
        if (r['label'] == 'fake') {
          fakeProb = (r['confidence'] as double?) ?? 0.0;
          break;
        }
      }
    }

    return DetectionResult(
      fakeProb: fakeProb,
      faceRect: mainFace.boundingBox,
      imageWidth: processingResult['imageWidth'],
      imageHeight: processingResult['imageHeight'],
      croppedFacePath: croppedFacePath,
    );
  }
}
