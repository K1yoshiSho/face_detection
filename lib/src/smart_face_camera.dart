import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../face_camera.dart';
import 'handlers/enum_handler.dart';
import 'handlers/face_identifier.dart';
import 'paints/face_painter.dart';
import 'paints/hole_painter.dart';
import 'res/builders.dart';
import 'utils/logger.dart';

/// A widget that wraps the [CameraPreview] widget and provides a face detection overlay.

/// This class is used to control the InnerDrawer.
class SmartFaceController {
  late _SmartFaceCameraState _smartFaceCameraState;

  // This method is used to attach the _InnerDrawerState to the InnerDrawerController.
  // ignore: library_private_types_in_public_api
  void attach(_SmartFaceCameraState smartFaceCameraState) {
    _smartFaceCameraState = smartFaceCameraState;
  }

  Future<void> takePicture() async {
    _smartFaceCameraState._onTakePictureButtonPressed();
  }

  Future<void> startCamera() async {
    _smartFaceCameraState._startImageStream();
  }

  Future<void> stopCamera() async {
    if (_smartFaceCameraState._controller!.value.isStreamingImages) {
      _smartFaceCameraState._controller?.stopImageStream();
    }
  }
}

class SmartFaceCamera extends StatefulWidget {
  final ImageResolution imageResolution;
  final SmartFaceController controller;
  final CameraLens? defaultCameraLens;
  final CameraFlashMode defaultFlashMode;
  final bool enableAudio;
  final bool autoCapture;
  final bool showControls;
  final bool showCaptureControl;
  final bool showFlashControl;
  final bool showCameraLensControl;
  final String? message;
  final TextStyle messageStyle;
  final CameraOrientation? orientation;
  final void Function(File? image) onCapture;
  final void Function(Face? face)? onFaceDetected;
  final Widget? captureControlIcon;
  final Widget? lensControlIcon;
  final FlashControlBuilder? flashControlBuilder;
  final MessageBuilder? messageBuilder;
  final bool isLoading;
  final bool isError;
  final bool isFetched;

  const SmartFaceCamera({
    this.imageResolution = ImageResolution.medium,
    this.defaultCameraLens,
    this.enableAudio = true,
    this.autoCapture = false,
    this.showControls = true,
    this.showCaptureControl = true,
    this.showFlashControl = true,
    this.showCameraLensControl = true,
    this.message,
    this.defaultFlashMode = CameraFlashMode.auto,
    this.orientation = CameraOrientation.portraitUp,
    this.messageStyle = const TextStyle(fontSize: 14, height: 1.5, fontWeight: FontWeight.w400),
    required this.onCapture,
    this.onFaceDetected,
    this.captureControlIcon,
    this.lensControlIcon,
    this.flashControlBuilder,
    this.messageBuilder,
    Key? key,
    required this.controller,
    required this.isLoading,
    required this.isError,
    required this.isFetched,
  }) : super(key: key);

  @override
  State<SmartFaceCamera> createState() => _SmartFaceCameraState();
}

class _SmartFaceCameraState extends State<SmartFaceCamera> with WidgetsBindingObserver, TickerProviderStateMixin {
  CameraController? _controller;

  bool _alreadyCheckingImage = false;

  DetectedFace? _detectedFace;

  int _currentFlashMode = 0;
  final List<CameraFlashMode> _availableFlashMode = [CameraFlashMode.off, CameraFlashMode.auto, CameraFlashMode.always];

  int _currentCameraLens = 0;
  final List<CameraLens> _availableCameraLens = [];

  Future<void> _getAllAvailableCameraLens() async {
    for (CameraDescription d in FaceCamera.cameras) {
      final lens = EnumHandler.cameraLensDirectionToCameraLens(d.lensDirection);
      if (lens != null && !_availableCameraLens.contains(lens)) {
        _availableCameraLens.add(lens);
      }
    }

    if (widget.defaultCameraLens != null) {
      try {
        _currentCameraLens = _availableCameraLens.indexOf(widget.defaultCameraLens!);
      } catch (e) {
        logError(e.toString());
      }
    }
  }

  Future<void> _initCamera() async {
    final cameras = FaceCamera.cameras
        .where((c) => c.lensDirection == EnumHandler.cameraLensToCameraLensDirection(_availableCameraLens[_currentCameraLens]))
        .toList();

    if (cameras.isNotEmpty) {
      _controller = CameraController(cameras.first, EnumHandler.imageResolutionToResolutionPreset(widget.imageResolution),
          enableAudio: widget.enableAudio, imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888);

      await _controller!.initialize().then((_) {
        if (!mounted) {
          return;
        }
        setState(() {});
      });

      await _changeFlashMode(_availableFlashMode.indexOf(widget.defaultFlashMode));

      await _controller!.lockCaptureOrientation(EnumHandler.cameraOrientationToDeviceOrientation(widget.orientation)).then((_) {
        if (mounted) {
          setState(() {});
        }
      });
    }
  }

  Future<void> _changeFlashMode(int index) async {
    await _controller!.setFlashMode(EnumHandler.cameraFlashModeToFlashMode(_availableFlashMode[index])).then((_) {
      if (mounted) setState(() => _currentFlashMode = index);
    });
  }

  @override
  void initState() {
    WidgetsBinding.instance.addObserver(this);
    widget.controller.attach(this);
    _getAllAvailableCameraLens().then(
      (value) {
        _initCamera().then((_) {
          _startImageStream();
        });
      },
    );

    super.initState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final CameraController? cameraController = _controller;

    if (cameraController != null && cameraController.value.isInitialized) {
      cameraController.dispose();
    }

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = _controller;

    // App state changed before we got the chance to initialize.
    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      cameraController.stopImageStream();
    } else if (state == AppLifecycleState.resumed) {
      _startImageStream();
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final CameraController? cameraController = _controller;
    return Stack(
      alignment: Alignment.center,
      children: [
        if (cameraController != null && cameraController.value.isInitialized) ...[
          Transform.scale(
            scale: 1.0,
            child: AspectRatio(
              aspectRatio: size.aspectRatio,
              child: OverflowBox(
                alignment: Alignment.center,
                child: FittedBox(
                  fit: BoxFit.fitHeight,
                  child: SizedBox(
                    width: size.width,
                    height: size.width * cameraController.value.aspectRatio,
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        _cameraDisplayWidget(),
                        if (_detectedFace != null) ...[
                          SizedBox(
                            width: _detectedFace?.face?.boundingBox.width,
                            height: _detectedFace?.face?.boundingBox.height,
                            child: CustomPaint(
                              painter: FacePainter(
                                face: _detectedFace!.face,
                                imageSize: Size(
                                  _controller!.value.previewSize!.height,
                                  _controller!.value.previewSize!.width,
                                ),
                                isError: widget.isError,
                                isLoading: widget.isLoading,
                                isFetched: widget.isFetched,
                              ),
                            ),
                          )
                        ]
                      ],
                    ),
                  ),
                ),
              ),
            ),
          )
        ] else ...[
          const Text(
            'Не удалось определить камеру',
            style: TextStyle(
              fontSize: 16,
              color: Colors.white,
              fontWeight: FontWeight.w400,
            ),
          ),
          CustomPaint(
            size: size,
            painter: HolePainter(),
          )
        ],
        if (widget.showControls) ...[
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(15.0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.showFlashControl) ...[_flashControlWidget()],
                  if (widget.showCaptureControl) ...[const SizedBox(width: 15), _captureControlWidget(), const SizedBox(width: 15)],
                  if (widget.showCameraLensControl) ...[_lensControlWidget()],
                ],
              ),
            ),
          )
        ]
      ],
    );
  }

  /// Render camera.
  Widget _cameraDisplayWidget() {
    final CameraController? cameraController = _controller;
    if (cameraController != null && cameraController.value.isInitialized) {
      return CameraPreview(cameraController, child: Builder(builder: (context) {
        if (widget.messageBuilder != null) {
          return widget.messageBuilder!.call(context, _detectedFace);
        }
        if (widget.message != null) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 55, vertical: 15),
            child: Text(widget.message!, textAlign: TextAlign.center, style: widget.messageStyle),
          );
        }
        return const SizedBox.shrink();
      }));
    }
    return const SizedBox.shrink();
  }

  /// Display the control buttons to take pictures.
  Widget _captureControlWidget() {
    final CameraController? cameraController = _controller;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: cameraController != null && cameraController.value.isInitialized ? _onTakePictureButtonPressed : null,
        child: Ink(
          width: 70,
          height: 70,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            color: const Color(0xFF3C4A7C),
          ),
          child: const Icon(
            Icons.camera_alt_rounded,
            size: 35,
          ),
        ),
      ),
    );
  }

  /// Display the control buttons to switch between flash modes.
  Widget _flashControlWidget() {
    final CameraController? cameraController = _controller;

    final icon = _availableFlashMode[_currentFlashMode] == CameraFlashMode.always
        ? Icons.flash_on
        : _availableFlashMode[_currentFlashMode] == CameraFlashMode.off
            ? Icons.flash_off
            : Icons.flash_auto;

    return IconButton(
      iconSize: 38,
      icon: widget.flashControlBuilder?.call(context, _availableFlashMode[_currentFlashMode]) ??
          CircleAvatar(
              radius: 38,
              child: Padding(
                padding: const EdgeInsets.all(2.0),
                child: Icon(icon, size: 25),
              )),
      onPressed: cameraController != null && cameraController.value.isInitialized
          ? () => _changeFlashMode((_currentFlashMode + 1) % _availableFlashMode.length)
          : null,
    );
  }

  /// Display the control buttons to switch between camera lens.
  Widget _lensControlWidget() {
    final CameraController? cameraController = _controller;

    return IconButton(
        iconSize: 38,
        icon: widget.lensControlIcon ??
            const CircleAvatar(
                radius: 38,
                child: Padding(
                  padding: EdgeInsets.all(2.0),
                  child: Icon(Icons.switch_camera_sharp, size: 25),
                )),
        onPressed: cameraController != null && cameraController.value.isInitialized
            ? () {
                _currentCameraLens = (_currentCameraLens + 1) % _availableCameraLens.length;
                _initCamera();
              }
            : null);
  }

  String timestamp() => DateTime.now().millisecondsSinceEpoch.toString();

  void showInSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void onViewFinderTap(TapDownDetails details, BoxConstraints constraints) {
    if (_controller == null) {
      return;
    }

    final CameraController cameraController = _controller!;

    final offset = Offset(
      details.localPosition.dx / constraints.maxWidth,
      details.localPosition.dy / constraints.maxHeight,
    );
    cameraController.setExposurePoint(offset);
    cameraController.setFocusPoint(offset);
  }

  Future<void> _onTakePictureButtonPressed() async {
    try {
      if (_controller == null) {
        return;
      }
      if (_controller!.value.isStreamingImages) {
        await _controller?.stopImageStream().whenComplete(() {
          takePicture().then((XFile? file) {
            if (file != null) {
              widget.onCapture(File(file.path));
            }

            ///Resume image stream after a delay
            Future.delayed(const Duration(seconds: 2)).whenComplete(() {
              if (mounted && _controller!.value.isInitialized) {
                try {
                  _startImageStream();
                } catch (e) {
                  logError(e.toString());
                }
              }
            });
          });
        });

        // // Add some delay before capturing the picture
        // await Future.delayed(const Duration(milliseconds: 1000));
      } else {
        // Handle the case when the camera is not streaming images
        logError("Camera is not streaming images");
      }
    } catch (e) {
      logError(e.toString());
    }
  }

  Future<XFile?> takePicture() async {
    final CameraController? cameraController = _controller;
    if (cameraController == null || !cameraController.value.isInitialized) {
      showInSnackBar('Error: select a camera first.');
      return null;
    }

    if (cameraController.value.isTakingPicture) {
      // A capture is already pending, do nothing.
      return null;
    }

    try {
      XFile file = await cameraController.takePicture();

      return file;
    } on CameraException catch (e) {
      _showCameraException(e);
      return null;
    }
  }

  void _showCameraException(CameraException e) {
    logError(e.code, e.description);
    // showInSnackBar('Error: ${e.code}\n${e.description}');
  }

  void _startImageStream() {
    final CameraController? cameraController = _controller;
    if (cameraController != null) {
      cameraController.startImageStream(_processImage);
    }
  }

  void _processImage(CameraImage cameraImage) async {
    final CameraController? cameraController = _controller;
    if (!_alreadyCheckingImage && mounted) {
      _alreadyCheckingImage = true;
      try {
        await FaceIdentifier.scanImage(cameraImage: cameraImage, camera: cameraController!.description).then((result) async {
          setState(() => _detectedFace = result);

          if (result != null) {
            try {
              if (result.wellPositioned) {
                if (widget.onFaceDetected != null) {
                  widget.onFaceDetected!.call(result.face);
                }
                if (widget.autoCapture) {
                  _onTakePictureButtonPressed();
                }
              }
            } catch (e) {
              logError(e.toString());
            }
          }
        });
        _alreadyCheckingImage = false;
      } catch (ex, stack) {
        logError('$ex, $stack');
      }
    }
  }
}
