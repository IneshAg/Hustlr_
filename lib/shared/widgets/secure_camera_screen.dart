import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show WriteBuffer;
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

enum CameraMode {
  kycFace,    // strictly front camera, requires clear face matching
  kycAadhaar, // back camera, macro focus for document scanning
  claim,      // back camera, general scene capture
}

class SecureCameraScreen extends StatefulWidget {
  final CameraMode mode;
  final String title;
  final String instructions;
  final bool enforceLiveGesture;
  final String? expectedGesture;

  const SecureCameraScreen({
    super.key,
    required this.mode,
    required this.title,
    required this.instructions,
    this.enforceLiveGesture = false,
    this.expectedGesture,
  });

  @override
  State<SecureCameraScreen> createState() => _SecureCameraScreenState();
}

class _SecureCameraScreenState extends State<SecureCameraScreen>
    with SingleTickerProviderStateMixin {
  CameraController? _controller;
  CameraDescription? _selectedCamera;
  List<CameraDescription> _cameras = [];
  bool _isInit = false;
  String? _errorMsg;
  String? _liveHint;
  late AnimationController _borderAnim;
  late Animation<double> _borderOpacity;
  FaceDetector? _faceDetector;
  bool _isProcessingFrame = false;
  bool _isCapturing = false;
  bool _isStreaming = false;
  double? _baselineYaw;
  int _baselineSamples = 0;
  String? _detectedDirection;
  Timer? _captureDebounce;

  @override
  void initState() {
    super.initState();
    _borderAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _borderOpacity = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _borderAnim, curve: Curves.easeInOut),
    );
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() => _errorMsg = 'No cameras available on this device');
        return;
      }

      CameraDescription? selectedCamera;

      if (widget.mode == CameraMode.kycFace) {
        selectedCamera = _cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.front,
          orElse: () => _cameras.first,
        );
      } else {
        selectedCamera = _cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
          orElse: () => _cameras.first,
        );
      }

      _controller = CameraController(
        selectedCamera,
        ResolutionPreset.high,
        enableAudio: false,
      );
      _selectedCamera = selectedCamera;

      await _controller!.initialize();

      if (widget.mode == CameraMode.kycFace && widget.enforceLiveGesture) {
        _faceDetector = FaceDetector(
          options: FaceDetectorOptions(
            performanceMode: FaceDetectorMode.fast,
            enableClassification: false,
            enableContours: false,
            enableLandmarks: false,
          ),
        );
        await _startLiveGestureStream();
      }

      if (!mounted) return;
      setState(() => _isInit = true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMsg = 'Camera access denied or failed: ${e.toString()}');
    }
  }

  @override
  void dispose() {
    _captureDebounce?.cancel();
    if (_isStreaming) {
      unawaited(_controller?.stopImageStream());
    }
    _faceDetector?.close();
    _controller?.dispose();
    _borderAnim.dispose();
    super.dispose();
  }

  Future<void> _startLiveGestureStream() async {
    if (_controller == null || !_controller!.value.isInitialized || _isStreaming) {
      return;
    }
    _liveHint = 'Center your face in the oval';
    await _controller!.startImageStream(_onCameraImage);
    _isStreaming = true;
  }

  Future<void> _onCameraImage(CameraImage image) async {
    if (_isProcessingFrame || _isCapturing || _faceDetector == null) return;
    _isProcessingFrame = true;
    try {
      final bytes = _concatenatePlanes(image.planes);
      final rotation = InputImageRotationValue.fromRawValue(
            _selectedCamera?.sensorOrientation ?? 0,
          ) ??
          InputImageRotation.rotation0deg;
      final format = InputImageFormatValue.fromRawValue(image.format.raw) ??
          InputImageFormat.nv21;

      final metadata = InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes.first.bytesPerRow,
      );

      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: metadata,
      );

      final faces = await _faceDetector!.processImage(inputImage);
      if (!mounted) return;

      if (faces.length != 1) {
        setState(() {
          _liveHint = faces.isEmpty
              ? 'Face not found. Move closer.'
              : 'Only one face should be visible.';
        });
        return;
      }

      final face = faces.first;
      final rect = face.boundingBox;
      final imgW = image.width.toDouble();
      final imgH = image.height.toDouble();
      
      // Basic centering check (normalized 0-1)
      final centerX = rect.center.dx / imgW;
      final centerY = rect.center.dy / imgH;
      
      if (centerX < 0.2 || centerX > 0.8 || centerY < 0.2 || centerY > 0.8) {
        setState(() {
          _liveHint = 'Center your face in the oval';
        });
        return;
      }

      final yaw = faces.first.headEulerAngleY ?? 0.0;

      // Build a neutral baseline before looking for a turn.
      if (_baselineYaw == null || _baselineSamples < 5) {
        _baselineYaw = ((_baselineYaw ?? 0.0) * _baselineSamples + yaw) /
            (_baselineSamples + 1);
        _baselineSamples += 1;
        setState(() {
          _liveHint = 'Hold still... calibrating identity';
        });
        return;
      }

      final delta = yaw - (_baselineYaw ?? 0.0);
      final turned = delta.abs() >= 18.0;

      if (!turned) {
        setState(() {
          _liveHint = widget.expectedGesture ?? 'Turn your face as instructed';
        });
        return;
      }

      final direction = delta > 0 ? 'right' : 'left';
      _detectedDirection = direction;
      setState(() {
        _liveHint = 'Detected ${direction.toUpperCase()} turn. Capturing...';
      });

      _captureDebounce?.cancel();
      _captureDebounce = Timer(const Duration(milliseconds: 350), () {
        if (mounted) {
          unawaited(_capture(autoTriggered: true));
        }
      });
    } catch (_) {
      // Keep camera flow resilient.
    } finally {
      _isProcessingFrame = false;
    }
  }

  Uint8List _concatenatePlanes(List<Plane> planes) {
    final allBytes = WriteBuffer();
    for (final plane in planes) {
      allBytes.putUint8List(plane.bytes);
    }
    return allBytes.done().buffer.asUint8List();
  }

  Future<void> _capture({bool autoTriggered = false}) async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_controller!.value.isTakingPicture) return;
    if (_isCapturing) return;

    _isCapturing = true;

    try {
      if (_isStreaming) {
        await _controller!.stopImageStream();
        _isStreaming = false;
      }
      final XFile photo = await _controller!.takePicture();
      final bytes = await photo.readAsBytes();
      final base64String = base64Encode(bytes);

      if (mounted) {
        Navigator.pop(context, {
          'base64': base64String,
          'path': photo.path,
          if (autoTriggered) 'liveGesture': true,
          if (_detectedDirection != null) 'detectedDirection': _detectedDirection,
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to capture photo: $e')),
        );
      }
    } finally {
      _isCapturing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context, null),
                  ),
                  Expanded(
                    child: Text(
                      widget.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 48), // balance
                ],
              ),
            ),

            // Camera / error area
            Expanded(
              child: _errorMsg != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _errorMsg!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      ),
                    )
                  : !_isInit || _controller == null
                      ? const Center(child: CircularProgressIndicator(color: Color(0xFF4CAF50)))
                      : _buildCameraPreview(),
            ),

            // Instructions strip at bottom
            if (_isInit && _errorMsg == null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
                child: Text(
                  widget.mode == CameraMode.kycFace
                      ? '${widget.instructions}\n\nCentre your face within the oval. Keep eyes, nose, and chin visible.'
                      : widget.instructions,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ),

            const SizedBox(height: 16),
            _buildCaptureButton(),
            if (widget.mode == CameraMode.kycFace && widget.enforceLiveGesture)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  _liveHint ?? widget.instructions,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFA7DDAF),
                    fontSize: 13,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraPreview() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final previewW = constraints.maxWidth;
        final previewH = constraints.maxHeight;
        // Larger oval guide so the full face can fit comfortably.
        final ovalW = previewW * 0.82;
        final ovalH = previewH * 0.70;

        return Stack(
          fit: StackFit.expand,
          children: [
            // Full-screen camera feed
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _controller!.value.previewSize?.height ?? 1,
                height: _controller!.value.previewSize?.width ?? 1,
                child: CameraPreview(_controller!),
              ),
            ),

            if (widget.mode == CameraMode.kycFace) ...[
              // Top instruction card for face movement challenge.
              Positioned(
                top: 20,
                left: 16,
                right: 16,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        widget.instructions,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Dark cutout overlay — draws dark everywhere except the oval
              CustomPaint(
                painter: _OvalCutoutPainter(
                  ovalWidth: ovalW,
                  ovalHeight: ovalH,
                ),
                child: const SizedBox.expand(),
              ),

              // Animated oval border ring
              AnimatedBuilder(
                animation: _borderOpacity,
                builder: (_, __) => Center(
                  child: Container(
                    width: ovalW,
                    height: ovalH,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(ovalW / 2),
                      border: Border.all(
                        color: const Color(0xFF4CAF50)
                            .withValues(alpha: _borderOpacity.value),
                        width: 3,
                      ),
                    ),
                  ),
                ),
              ),

              // "Position face here" label inside oval
              Align(
                alignment: const Alignment(0, 0.85),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Fill your face in the oval',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ),
            ] else if (widget.mode == CameraMode.kycAadhaar)
              _buildDocumentOverlay(),
          ],
        );
      },
    );
  }

  Widget _buildDocumentOverlay() {
    return Center(
      child: Container(
        width: 320,
        height: 200,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 2),
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  Widget _buildCaptureButton() {
    // Always show the capture button to allow manual fallback
    // if automatic detection is slow or failing.
    
    return GestureDetector(
      onTap: () => _capture(autoTriggered: false),
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF4CAF50), width: 4),
          color: Colors.transparent,
        ),
        child: Center(
          child: Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints a dark semi-transparent overlay with an oval cutout.
/// The cutout reveals the camera feed clearly, dimming everything outside.
class _OvalCutoutPainter extends CustomPainter {
  final double ovalWidth;
  final double ovalHeight;

  _OvalCutoutPainter({required this.ovalWidth, required this.ovalHeight});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    final oval = Path()
      ..addOval(Rect.fromCenter(
        center: Offset(cx, cy),
        width: ovalWidth,
        height: ovalHeight,
      ));

    final cutout = Path.combine(PathOperation.difference, path, oval);

    canvas.drawPath(
      cutout,
      Paint()..color = Colors.black.withValues(alpha: 0.45),
    );
  }

  @override
  bool shouldRepaint(_OvalCutoutPainter oldDelegate) =>
      oldDelegate.ovalWidth != ovalWidth || oldDelegate.ovalHeight != ovalHeight;
}
