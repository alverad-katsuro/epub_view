import 'package:flutter/material.dart';

class FullScreenImageViewer extends StatefulWidget {
  final Image image;

  const FullScreenImageViewer({super.key, required this.image});

  @override
  State<FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<FullScreenImageViewer> {
  final TransformationController _transformationController =
      TransformationController();

  /// Handles the double-tap gesture to zoom in and out.
  void _handleDoubleTapDown(TapDownDetails details) {
    // If the image is already zoomed in, reset it to the original scale.
    if (_transformationController.value != Matrix4.identity()) {
      _transformationController.value = Matrix4.identity();
    } else {
      // If the image is at the original scale, zoom in to the tap location.
      final position = details.localPosition;
      const double scale = 2.5; // The zoom factor

      // Translate the image to center the tap position and then apply the scale.
      _transformationController.value = Matrix4.identity()
        ..translateByDouble(
            -position.dx * (scale - 1), -position.dy * (scale - 1), 0.0, 1.0)
        ..scaleByDouble(scale, scale, scale, 1.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Visualizar Imagem"),
        backgroundColor: Colors.black,
        leading: IconButton(
          // Adiciona um botão de fechar
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      backgroundColor: Colors.black,
      body: Center(
        child: GestureDetector(
          onDoubleTapDown: _handleDoubleTapDown,
          child: InteractiveViewer(
            transformationController: _transformationController,
            boundaryMargin: const EdgeInsets.all(20.0),
            minScale: 1.0,
            maxScale: 4.0,
            child: widget.image,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }
}
