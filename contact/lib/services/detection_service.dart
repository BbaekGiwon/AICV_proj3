import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:tflite_v2/tflite_v2.dart';
import 'package:path_provider/path_provider.dart';

class DetectionResult {
  final double fakeProb;
  final Rect? faceRect;
  final int imageWidth;
  final int imageHeight;
  final String? croppedFacePath;

  bool get isFake => fakeProb >= 0.5;

  DetectionResult({
    required this.fakeProb,
    required this.faceRect,
    required this.imageWidth,
    required this.imageHeight,
    this.croppedFacePath,
  });
}

class _IsolateParams {
  final RootIsolateToken token;
  final String filePath;
  final Rect boundingBox;
  final String tempDirPath;

  _IsolateParams(this.token, this.filePath, this.boundingBox, this.tempDirPath);
}

Future<Map<String, dynamic>?> _imageProcessingIsolate(
    _IsolateParams params) async {
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
  String? _loadedModelPath;

  DetectionService()
      : _faceDetector = FaceDetector(
          options: FaceDetectorOptions(
            performanceMode: FaceDetectorMode.fast,
          ),
        );

  String getModelPath() => _loadedModelPath != null ? p.basename(_loadedModelPath!) : 'N/A';

  Future<void> loadModel() async {
    _loadedModelPath = "assets/best_efficientnet_v13.tflite";
    await Tflite.loadModel(
      model: _loadedModelPath!,
      labels: "assets/best_efficientnet_v13_labels.txt",
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

    final tempDir = await getTemporaryDirectory();
    final token = RootIsolateToken.instance!;

    final processingResult = await compute(
        _imageProcessingIsolate,
        _IsolateParams(
            token, filePath, mainFace.boundingBox, tempDir.path));

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
