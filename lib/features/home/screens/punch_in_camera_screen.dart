import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/theme/app_theme.dart';

class PunchInCameraScreen extends StatefulWidget {
  const PunchInCameraScreen({super.key});

  @override
  State<PunchInCameraScreen> createState() => _PunchInCameraScreenState();
}

class _PunchInCameraScreenState extends State<PunchInCameraScreen>
    with TickerProviderStateMixin {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isCapturing = false;
  late AnimationController _shutterController;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _shutterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      // Request permission first — camera will not initialise without it
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Camera permission is required to punch in.')),
          );
          Navigator.of(context).pop();
        }
        return;
      }

      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        if (mounted) Navigator.of(context).pop();
        return;
      }

      final frontCamera = _cameras!.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras!.first,
      );

      _controller = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _controller!.initialize();
      if (mounted) setState(() {});
    } on CameraException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera error: ${e.description}')),
        );
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _capture() async {
    if (_controller == null || !_controller!.value.isInitialized || _isCapturing) return;
    setState(() => _isCapturing = true);
    await _shutterController.forward();

    try {
      final xFile = await _controller!.takePicture();
      final file = File(xFile.path);
      if (mounted) Navigator.of(context).pop(file);
    } catch (_) {
      setState(() => _isCapturing = false);
      _shutterController.reset();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _shutterController.dispose();
    _pulseController.dispose();
    super.dispose();
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                  const Expanded(
                    child: Text(
                      'Take a Selfie to Punch In',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Sora',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),

            // Camera preview
            Expanded(
              child: _controller?.value.isInitialized == true
                  ? Stack(
                      alignment: Alignment.center,
                      children: [
                        // Mirror for front camera feel
                        Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.rotationY(3.14159),
                          child: CameraPreview(_controller!),
                        ),
                        // Oval face guide
                        AnimatedBuilder(
                          animation: _pulseController,
                          builder: (_, __) => Container(
                            width: 200,
                            height: 260,
                            decoration: BoxDecoration(
                              shape: BoxShape.rectangle,
                              borderRadius: BorderRadius.circular(130),
                              border: Border.all(
                                color: Colors.white.withOpacity(
                                  0.4 + _pulseController.value * 0.4,
                                ),
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                        // Shutter flash overlay
                        AnimatedBuilder(
                          animation: _shutterController,
                          builder: (_, __) => Opacity(
                            opacity: _shutterController.value,
                            child: Container(color: Colors.white),
                          ),
                        ),
                      ],
                    )
                  : const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
            ),

            // Instructions + capture button
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Column(
                children: [
                  Text(
                    'Position your face in the oval',
                    style: TextStyle(
                      fontFamily: 'Sora',
                      fontSize: 13,
                      color: Colors.white.withOpacity(0.7),
                    ),
                  ),
                  const SizedBox(height: 28),
                  GestureDetector(
                    onTap: _capture,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        color: Colors.white.withOpacity(0.1),
                      ),
                      child: Center(
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _isCapturing ? AppTheme.accent : Colors.white,
                          ),
                        ),
                      ),
                    ).animate(
                      onPlay: (c) => c.repeat(reverse: true),
                    ).scaleXY(
                      begin: 1.0,
                      end: 1.04,
                      duration: 1200.ms,
                      curve: Curves.easeInOut,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
