import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pro_image_editor/pro_image_editor.dart';
import 'status_finalize_screen.dart';

/// Layar kamera-pertama ala WhatsApp: pilih Foto/Video, ganti kamera
/// depan/belakang, flash, pintasan galeri. Foto → editor → finalisasi.
class StatusCameraScreen extends StatefulWidget {
  const StatusCameraScreen({super.key});

  @override
  State<StatusCameraScreen> createState() => _StatusCameraScreenState();
}

class _StatusCameraScreenState extends State<StatusCameraScreen>
    with WidgetsBindingObserver {
  List<CameraDescription> _cameras = [];
  CameraController? _controller;
  int _camIndex = 0;
  bool _videoMode = false;
  bool _recording = false;
  FlashMode _flash = FlashMode.off;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCameras();
  }

  Future<void> _initCameras() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isNotEmpty) await _setCamera(0);
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  Future<void> _setCamera(int index) async {
    if (_cameras.isEmpty) return;
    await _controller?.dispose();
    final c = CameraController(
      _cameras[index],
      ResolutionPreset.high,
      enableAudio: true,
    );
    _controller = c;
    _camIndex = index;
    try {
      await c.initialize();
      await c.setFlashMode(_flash);
    } catch (_) {}
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      c.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _setCamera(_camIndex);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  void _switchCamera() {
    if (_cameras.length < 2) return;
    _setCamera((_camIndex + 1) % _cameras.length);
  }

  Future<void> _toggleFlash() async {
    _flash = _flash == FlashMode.off ? FlashMode.torch : FlashMode.off;
    try {
      await _controller?.setFlashMode(_flash);
    } catch (_) {}
    setState(() {});
  }

  Future<void> _capture() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _busy) return;
    if (_videoMode) {
      if (_recording) {
        setState(() => _busy = true);
        try {
          final file = await c.stopVideoRecording();
          setState(() {
            _recording = false;
            _busy = false;
          });
          await _finalizeVideo(file);
        } catch (_) {
          setState(() {
            _recording = false;
            _busy = false;
          });
        }
      } else {
        try {
          await c.startVideoRecording();
          setState(() => _recording = true);
        } catch (_) {}
      }
    } else {
      setState(() => _busy = true);
      try {
        final x = await c.takePicture();
        final bytes = await x.readAsBytes();
        await _editPhoto(bytes);
      } catch (_) {}
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickFromGallery() async {
    final x = await ImagePicker().pickMedia();
    if (x == null || !mounted) return;
    final name = x.name.toLowerCase();
    final isVideo = name.endsWith('.mp4') ||
        name.endsWith('.mov') ||
        name.endsWith('.webm') ||
        name.endsWith('.mkv') ||
        name.endsWith('.m4v') ||
        name.endsWith('.3gp');
    if (isVideo) {
      await _finalizeVideo(x);
    } else {
      await _editPhoto(await x.readAsBytes());
    }
  }

  /// Buka editor foto (teks, pen, stiker, crop, filter) lalu finalisasi.
  Future<void> _editPhoto(Uint8List bytes) async {
    final edited = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        builder: (_) => ProImageEditor.memory(
          bytes,
          callbacks: ProImageEditorCallbacks(
            onImageEditingComplete: (Uint8List out) async {
              Navigator.of(context).pop(out);
            },
          ),
        ),
      ),
    );
    if (edited == null || !mounted) return;
    final sent = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => StatusFinalizeScreen(imageBytes: edited),
      ),
    );
    if (sent == true && mounted) Navigator.of(context).pop(true);
  }

  Future<void> _finalizeVideo(XFile file) async {
    final sent = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => StatusFinalizeScreen(video: file),
      ),
    );
    if (sent == true && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final ready = c != null && c.value.isInitialized;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (ready)
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: c.value.previewSize?.height ?? 1,
                height: c.value.previewSize?.width ?? 1,
                child: CameraPreview(c),
              ),
            )
          else
            const Center(child: CircularProgressIndicator(color: Colors.white)),
          // Top bar: close + flash
          SafeArea(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                if (!_videoMode)
                  IconButton(
                    icon: Icon(
                      _flash == FlashMode.off
                          ? Icons.flash_off_rounded
                          : Icons.flash_on_rounded,
                      color: Colors.white,
                    ),
                    onPressed: _toggleFlash,
                  ),
              ],
            ),
          ),
          // Bottom controls
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Toggle Foto/Video
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _modeChip('FOTO', !_videoMode,
                            () => setState(() => _videoMode = false)),
                        const SizedBox(width: 24),
                        _modeChip('VIDEO', _videoMode,
                            () => setState(() => _videoMode = true)),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton(
                          iconSize: 30,
                          icon: const Icon(Icons.photo_library_rounded,
                              color: Colors.white),
                          onPressed: _pickFromGallery,
                        ),
                        // Tombol shutter
                        GestureDetector(
                          onTap: _capture,
                          child: Container(
                            width: 76,
                            height: 76,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _recording
                                  ? const Color(0xFFEF4444)
                                  : Colors.white24,
                              border: Border.all(color: Colors.white, width: 4),
                            ),
                            child: _videoMode
                                ? Icon(
                                    _recording
                                        ? Icons.stop_rounded
                                        : Icons.videocam_rounded,
                                    color: Colors.white,
                                    size: 30)
                                : null,
                          ),
                        ),
                        IconButton(
                          iconSize: 30,
                          icon: const Icon(Icons.cameraswitch_rounded,
                              color: Colors.white),
                          onPressed: _switchCamera,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeChip(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Text(
        label,
        style: TextStyle(
          color: active ? Colors.amber : Colors.white70,
          fontWeight: FontWeight.w700,
          fontSize: 13,
          letterSpacing: 1,
        ),
      ),
    );
  }
}
