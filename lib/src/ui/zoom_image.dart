import 'dart:async'; // Importe para usar o Timer
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Importe para usar a vibração
import 'full_screen_viewer.dart'; // Importe a tela que criamos

class ZoomableImagePreview extends StatefulWidget {
  final Image image;
  final int seconds;

  // Note que não precisamos mais do BuildContext aqui
  const ZoomableImagePreview(
      {super.key, required this.image, this.seconds = 1});

  @override
  State<ZoomableImagePreview> createState() => _ZoomableImagePreviewState();
}

class _ZoomableImagePreviewState extends State<ZoomableImagePreview> {
  Timer? _timer;

  void _startTimer() {
    // Cancela qualquer timer anterior para evitar múltiplos pop-ups
    _timer?.cancel();
    // Cria um novo timer de 2 segundos
    _timer = Timer(Duration(milliseconds: widget.seconds), () {
      // Vibra para dar um feedback ao usuário que a ação foi concluída
      HapticFeedback.vibrate();

      // Abre a tela de zoom
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => FullScreenImageViewer(image: widget.image),
        ),
      );
    });
  }

  void _cancelTimer() {
    _timer?.cancel();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Quando o usuário começa a pressionar
      onTapDown: (_) => _startTimer(),
      // Quando o usuário solta o dedo
      onTapUp: (_) => _cancelTimer(),
      onTapMove: (_) => _cancelTimer(),
      // Caso o long press seja cancelado por outro gesto (como um scroll)
      onTapCancel: () => _cancelTimer(),
      child: widget.image, // Mostra a imagem estática no corpo do texto
    );
  }
}
