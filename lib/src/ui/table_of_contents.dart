import 'package:epub_view/src/data/models/chapter.dart';
import 'package:epub_view/src/ui/epub_view.dart';
import 'package:flutter/material.dart';

class EpubViewTableOfContents extends StatelessWidget {
  const EpubViewTableOfContents({
    required this.controller,
    this.padding,
    this.loader,
    Key? key,
  }) : super(key: key);

  final EdgeInsetsGeometry? padding;
  final EpubController controller;
  final Widget? loader;

  /// Transforma a lista de capítulos em uma lista de widgets (ListTile/ExpansionTile).
  List<Widget> _buildTocList(List<EpubViewChapter> chapters) {
    final List<Widget> widgets = [];
    int i = 0;

    while (i < chapters.length) {
      final chapter = chapters[i];
      final subChaptersCount = chapter.subChaptersCount ?? 0;

      // Se o capítulo tem subcapítulos, cria um ExpansionTile.
      if (subChaptersCount > 0) {
        final subChapterStartIndex = i + 1;
        // Garante que não vamos exceder o tamanho da lista.
        final subChapterEndIndex =
            (subChapterStartIndex + subChaptersCount < chapters.length)
                ? subChapterStartIndex + subChaptersCount
                : chapters.length;

        final subChapters =
            chapters.sublist(subChapterStartIndex, subChapterEndIndex);

        widgets.add(
          ExpansionTile(
            title: Text(
              chapter.title?.trim() ?? '',
            ),
            shape: const Border(
              top: BorderSide.none,
              bottom: BorderSide.none,
            ),
            // Mapeia cada subcapítulo para um ListTile.
            children: subChapters.map((subChapter) {
              return ListTile(
                // Adiciona um recuo para diferenciar visualmente.
                contentPadding: const EdgeInsets.only(left: 32.0, right: 16.0),
                title: Text(subChapter.title?.trim() ?? ''),
                onTap: () => controller.scrollTo(index: subChapter.startIndex),
              );
            }).toList(),
          ),
        );

        // Pula o índice para depois do capítulo principal e seus subcapítulos.
        i += 1 + subChaptersCount;
      }
      // Caso contrário, cria um ListTile simples.
      else {
        widgets.add(
          ListTile(
            title: Text(chapter.title?.trim() ?? ''),
            onTap: () => controller.scrollTo(index: chapter.startIndex),
          ),
        );
        i++;
      }
    }
    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<EpubViewChapter>>(
      valueListenable: controller.tableOfContentsListenable,
      builder: (_, data, child) {
        Widget content;

        if (data.isNotEmpty) {
          // Usa a nova função para construir a lista de widgets.
          final tocWidgets = _buildTocList(data);
          content = ListView(
            padding: padding,
            key: Key('$runtimeType.content'),
            children: tocWidgets,
          );
        } else {
          content = KeyedSubtree(
            key: Key('$runtimeType.loader'),
            child: loader ?? const Center(child: CircularProgressIndicator()),
          );
        }

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          transitionBuilder: (Widget child, Animation<double> animation) =>
              FadeTransition(opacity: animation, child: child),
          child: content,
        );
      },
    );
  }
}
