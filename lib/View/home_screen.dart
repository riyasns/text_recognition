import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import '../main.dart';


class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  CameraController? _cameraController;
  late TextRecognizer _textRecognizer;

  bool _isProcessing = false;
  bool _isCameraLoading = false;

  String _vehicleNumber = "No plate detected";

  Rect? _plateRect;
  Size? _imageSize;

  @override
  void initState() {
    super.initState();
    _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    _openCamera();
  }

  // 🔤 Clean OCR text
  String _cleanText(String text) {
    return text
        .toUpperCase()
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(RegExp(r'IND|INDIA'), '')
        .replaceAll(RegExp(r'[^A-Z0-9]'), '');
  }

  // 📷 Open camera
  Future<void> _openCamera() async {
    if (_isCameraLoading) return;

    setState(() => _isCameraLoading = true);

    final controller = CameraController(
      cameras.firstWhere(
              (c) => c.lensDirection == CameraLensDirection.back),
      ResolutionPreset.medium,
      enableAudio: false,
    );

    await controller.initialize();

    setState(() {
      _cameraController = controller;
      _isCameraLoading = false;
    });
  }

  // ✂ Crop center (plate area)
  Future<File> _cropCenter(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    final decoded = img.decodeImage(bytes)!;

    _imageSize = Size(
      decoded.width.toDouble(),
      decoded.height.toDouble(),
    );

    final cropped = img.copyCrop(
      decoded,
      x: decoded.width ~/ 10,
      y: decoded.height ~/ 3,
      width: decoded.width * 8 ~/ 10,
      height: decoded.height ~/ 3,
    );

    final file = File('${imageFile.path}_crop.jpg');
    await file.writeAsBytes(img.encodeJpg(cropped));
    return file;
  }

  // 🔍 Scan number plate
  Future<void> _scanNumberPlate() async {
    if (_cameraController == null || _isProcessing) return;

    setState(() {
      _isProcessing = true;
      _plateRect = null;
    });

    final photo = await _cameraController!.takePicture();
    final imageFile = await _cropCenter(File(photo.path));

    final inputImage = InputImage.fromFile(imageFile);
    final recognizedText =
    await _textRecognizer.processImage(inputImage);

    final plateRegex =
    RegExp(r'[A-Z]{2}\d{1,2}[A-Z]{1,2}\d{4}');

    String detected = "No plate detected";

    for (final block in recognizedText.blocks) {
      for (final line in block.lines) {
        final cleaned = _cleanText(line.text);
        final match = plateRegex.firstMatch(cleaned);

        if (match != null) {
          detected = match.group(0)!;
          _plateRect = line.boundingBox;
          break;
        }
      }
    }

    setState(() {
      _vehicleNumber = detected;
      _isProcessing = false;
    });
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _textRecognizer.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Car Number Plate Scanner")),
      body: _isCameraLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          const SizedBox(height: 12),

          /// 📷 Camera + Bounding Box
          if (_cameraController != null)
            Center(
              child: SizedBox(
                height: 300, // 👈 SET YOUR HEIGHT
                width: 350,  // 👈 SET YOUR WIDTH
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CameraPreview(_cameraController!),

                      if (_plateRect != null && _imageSize != null)
                        CustomPaint(
                          painter: PlatePainter(
                            plateRect: _plateRect!,
                            imageSize: _imageSize!,
                            previewSize: Size(
                              _cameraController!
                                  .value.previewSize!.height,
                              _cameraController!
                                  .value.previewSize!.width,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),


          const SizedBox(height: 16),

          Text(
            _vehicleNumber,
            style: const TextStyle(
                fontSize: 22, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 16),

          ElevatedButton(
            onPressed: _scanNumberPlate,
            child: _isProcessing
                ? const CircularProgressIndicator(
                color: Colors.white)
                : const Text("Scan Number Plate"),
          ),
        ],
      ),
    );
  }
}
class PlatePainter extends CustomPainter {
  final Rect plateRect;
  final Size imageSize;
  final Size previewSize;

  PlatePainter({
    required this.plateRect,
    required this.imageSize,
    required this.previewSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.green
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    final scaleX = previewSize.width / imageSize.width;
    final scaleY = previewSize.height / imageSize.height;

    final rect = Rect.fromLTRB(
      plateRect.left * scaleX,
      plateRect.top * scaleY,
      plateRect.right * scaleX,
      plateRect.bottom * scaleY,
    );

    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}
