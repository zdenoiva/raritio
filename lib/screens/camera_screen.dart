import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  String? _error;
  bool _isTakingPicture = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras()
          .timeout(const Duration(seconds: 10), onTimeout: () => <CameraDescription>[]);
      if (_cameras == null || _cameras!.isEmpty) {
        if (mounted) {
          setState(() => _error =
              "Kamera sa nepodarilo spustiť.\nSkontroluj povolenie kamery v nastaveniach aplikácie.");
        }
        return;
      }

      // Try every back camera first (Samsung phones expose several), then the rest.
      final candidates = <CameraDescription>[
        ..._cameras!.where((c) => c.lensDirection == CameraLensDirection.back),
        ..._cameras!.where((c) => c.lensDirection != CameraLensDirection.back),
      ];

      Object? lastError;
      for (final camera in candidates) {
        CameraController? controller;
        try {
          controller = CameraController(
            camera,
            ResolutionPreset.medium,
            enableAudio: false, // Photos only: never request the microphone
          );
          await controller.initialize().timeout(
            const Duration(seconds: 20),
            onTimeout: () => throw Exception("Kamera nereaguje (timeout)."),
          );
          try {
            await controller.setFocusMode(FocusMode.auto);
          } catch (_) {
            // Focus mode is a nice-to-have; ignore devices that do not support it.
          }
          if (!mounted) {
            await controller.dispose();
            return;
          }
          setState(() {
            _controller = controller;
            _error = null;
          });
          return;
        } catch (e) {
          lastError = e;
          await controller?.dispose();
        }
      }

      if (mounted) {
        setState(() => _error =
            "Kameru sa nepodarilo spustiť.\nSkontroluj povolenie kamery v nastaveniach aplikácie.\n\n$lastError");
      }
    } catch (e) {
      print("Camera init error: $e");
      if (mounted) setState(() => _error = "Chyba kamery: $e");
    }
  }

  Future<void> _takePicture() async {
    if (_isTakingPicture ||
        _controller == null ||
        !_controller!.value.isInitialized) {
      return;
    }
    setState(() => _isTakingPicture = true);
    try {
      final XFile file = await _controller!.takePicture();
      if (mounted) Navigator.pop(context, file.path);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isTakingPicture = false;
          _error = "Nepodarilo sa odfotiť: $e";
        });
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.red, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    _controller?.dispose();
                    _controller = null;
                    setState(() => _error = null);
                    _initializeCamera();
                  },
                  child: const Text("Skúsiť znova"),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_controller == null || !_controller!.value.isInitialized) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 20),
              Text("Spúšťam kameru...", style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Stack(
        children: [
          Center(child: CameraPreview(_controller!)),
          Positioned.fill(
            child: IgnorePointer(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    "Umiestni kartu do rámu",
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FractionallySizedBox(
                    widthFactor: 0.72,
                    child: AspectRatio(
                      aspectRatio: 2.5 / 3.5,
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white70, width: 3),
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _isTakingPicture ? null : _takePicture,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 4),
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                  child: _isTakingPicture
                      ? const Padding(
                          padding: EdgeInsets.all(22),
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 3,
                          ),
                        )
                      : null,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
