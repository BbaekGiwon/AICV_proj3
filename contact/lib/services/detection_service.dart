import 'dart:io';
import 'dart:ui';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_v2/tflite_v2.dart';
import 'package:path_provider/path_provider.dart';

class DetectionResult {
  final double fakeProb;
  final Rect? faceRect;
  final int imageWidth;
  final int imageHeight;

  DetectionResult({
    required this.fakeProb,
    required this.faceRect,
    required this.imageWidth,
    required this.imageHeight,
  });
}

class DetectionService {
  final FaceDetector _faceDetector;

  DetectionService()
      : _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.fast,
      enableLandmarks: false,
      enableContours: false,
      enableClassification: false,
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
    final file = File(filePath);
    if (!await file.exists() || await file.length() == 0) {
      return DetectionResult(
        fakeProb: 0.0,
        faceRect: null,
        imageWidth: 0,
        imageHeight: 0,
      );
    }

    // 1) 얼굴 검출
    final inputImage = InputImage.fromFilePath(filePath);
    final faces = await _faceDetector.processImage(inputImage);
    if (faces.isEmpty) {
      return DetectionResult(
        fakeProb: 0.0,
        faceRect: null,
        imageWidth: 0,
        imageHeight: 0,
      );
    }

    Face mainFace = faces[0];
    double maxArea = mainFace.boundingBox.width *
        mainFace.boundingBox.height;
    for (final f in faces.skip(1)) {
      final area =
          f.boundingBox.width * f.boundingBox.height;
      if (area > maxArea) {
        maxArea = area;
        mainFace = f;
      }
    }

    final bytes = await file.readAsBytes();
    final original = img.decodeImage(bytes);
    if (original == null) {
      return DetectionResult(
        fakeProb: 0.0,
        faceRect: null,
        imageWidth: 0,
        imageHeight: 0,
      );
    }

    final imgW = original.width;
    final imgH = original.height;

    final box = mainFace.boundingBox;
    int x = box.left.floor().clamp(0, imgW - 1);
    int y = box.top.floor().clamp(0, imgH - 1);
    int w = box.width.floor().clamp(1, imgW - x);
    int h = box.height.floor().clamp(1, imgH - y);

    final cropped = img.copyCrop(original, x: x, y: y, width: w, height: h);

    final tempDir = await getTemporaryDirectory();
    final croppedPath = '${tempDir.path}/temp_face.jpg';
    final croppedFile = File(croppedPath);
    await croppedFile.writeAsBytes(img.encodeJpg(cropped));

    final recognitions = await Tflite.runModelOnImage(
      path: croppedPath,
      imageMean: 127.5,
      imageStd: 127.5,
      numResults: 1,
      threshold: 0.1,
      asynch: true,
    );

    if (await croppedFile.exists()) {
      await croppedFile.delete();
    }
    if (await file.exists()) {
      await file.delete();
    }

    double fakeProb = 0.0;
    if (recognitions != null && recognitions.isNotEmpty) {
      fakeProb = (recognitions[0]['confidence'] as double?) ?? 0.0;
    }

    return DetectionResult(
      fakeProb: fakeProb,
      faceRect: box,
      imageWidth: imgW,
      imageHeight: imgH,
    );
  }
}