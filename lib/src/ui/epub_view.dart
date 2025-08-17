import 'dart:async';
import 'dart:typed_data';

import 'package:collection/collection.dart' show IterableExtension;
import 'package:epub_view/src/data/epub_cfi_reader.dart';
import 'package:epub_view/src/data/epub_parser.dart';
import 'package:epub_view/src/data/models/chapter.dart';
import 'package:epub_view/src/data/models/chapter_view_value.dart';
import 'package:epub_view/src/data/models/paragraph.dart';
import 'package:epub_view/src/ui/zoom_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_html_table/flutter_html_table.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

export 'package:epub_enchanted/epub_enchanted.dart' hide Image;

part '../epub_controller.dart';
part '../helpers/epub_view_builders.dart';

const _minTrailingEdge = 0.55;
const _minLeadingEdge = -0.05;

typedef ExternalLinkPressed = void Function(String href);

class EpubView extends StatefulWidget {
  const EpubView({
    required this.controller,
    this.onExternalLinkPressed,
    this.onChapterChanged,
    this.onDocumentLoaded,
    this.onDocumentError,
    this.builders = const EpubViewBuilders<DefaultBuilderOptions>(
      options: DefaultBuilderOptions(),
    ),
    this.shrinkWrap = false,
    Key? key,
  }) : super(key: key);

  final EpubController controller;
  final ExternalLinkPressed? onExternalLinkPressed;
  final bool shrinkWrap;
  final void Function(EpubChapterViewValue? value)? onChapterChanged;

  /// Called when a document is loaded
  final void Function(EpubBook document)? onDocumentLoaded;

  /// Called when a document loading error
  final void Function(Exception? error)? onDocumentError;

  /// Builders
  final EpubViewBuilders builders;

  @override
  State<EpubView> createState() => _EpubViewState();
}

class _EpubViewState extends State<EpubView> {
  Exception? _loadingError;
  ItemScrollController? _itemScrollController;
  ItemPositionsListener? _itemPositionListener;
  List<EpubChapter> _chapters = [];
  late final List<EpubChapter> _flatChapters = chapterFlat(_chapters);
  List<Paragraph> _paragraphs = [];
  EpubCfiReader? _epubCfiReader;
  EpubChapterViewValue? _currentValue;
  final _chapterIndexes = <int>[];
  Timer? _debounce;
  EpubController get _controller => widget.controller;
  bool _isTapEligible = false;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _itemScrollController = ItemScrollController();
    _itemPositionListener = ItemPositionsListener.create();
    _controller._attach(this);
    _controller.loadingState.addListener(() {
      switch (_controller.loadingState.value) {
        case EpubViewLoadingState.loading:
          break;
        case EpubViewLoadingState.success:
          widget.onDocumentLoaded?.call(_controller._document!);
          break;
        case EpubViewLoadingState.error:
          widget.onDocumentError?.call(_loadingError);
          break;
      }

      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _itemPositionListener!.itemPositions.removeListener(_changeListener);
    _controller._detach();
    _debounce?.cancel();
    super.dispose();
  }

  List<EpubChapter> chapterFlat(List<EpubChapter> chaps) {
    List<EpubChapter> chapters = [];

    for (var chapter in chaps) {
      if (chapter.subChapters.isNotEmpty) {
        chapters.addAll(chapterFlat(chapter.subChapters));
      } else {
        chapters.add(chapter);
      }
    }
    return chapters;
  }

  Future<bool> _init() async {
    if (_controller.isBookLoaded.value) {
      return true;
    }
    _chapters = parseChapters(_controller._document!);
    final parseParagraphsResult =
        parseParagraphs(_chapters, _controller._document!.content);
    _paragraphs = parseParagraphsResult.flatParagraphs;
    _chapterIndexes.addAll(parseParagraphsResult.chapterIndexes);

    _epubCfiReader = EpubCfiReader.parser(
      cfiInput: _controller.epubCfi,
      chapters: _chapters,
      paragraphs: _paragraphs,
    );
    _itemPositionListener!.itemPositions.addListener(_changeListener);
    _controller.isBookLoaded.value = true;

    return true;
  }

  void _changeListener() {
    if (_paragraphs.isEmpty ||
        _itemPositionListener!.itemPositions.value.isEmpty) {
      return;
    }
    final position = _itemPositionListener!.itemPositions.value.first;
    final chapterIndex = _getChapterIndexBy(
      positionIndex: position.index,
      trailingEdge: position.itemTrailingEdge,
      leadingEdge: position.itemLeadingEdge,
    );
    final paragraphIndex = _getParagraphIndexBy(
      positionIndex: position.index,
      trailingEdge: position.itemTrailingEdge,
      leadingEdge: position.itemLeadingEdge,
    );
    _currentValue = EpubChapterViewValue(
      chapter: chapterIndex >= 0 ? _flatChapters[chapterIndex] : null,
      chapterNumber: chapterIndex + 1,
      paragraphNumber: paragraphIndex + 1,
      position: position,
    );
    _controller.currentValueListenable.value = _currentValue;
    widget.onChapterChanged?.call(_currentValue);
  }

  void _gotoEpubCfi(
    String? epubCfi, {
    double alignment = 0,
    Duration duration = const Duration(milliseconds: 250),
    Curve curve = Curves.linear,
  }) {
    _epubCfiReader?.epubCfi = epubCfi;
    final index = _epubCfiReader?.paragraphIndexByCfiFragment;

    if (index == null) {
      return;
    }

    _itemScrollController?.scrollTo(
      index: index,
      duration: duration,
      alignment: alignment,
      curve: curve,
    );
  }

  void _onLinkPressed(String href) {
    if (href.contains('://')) {
      widget.onExternalLinkPressed?.call(href);
      return;
    }

    // Chapter01.xhtml#ph1_1 -> [ph1_1, Chapter01.xhtml] || [ph1_1]
    String? hrefIdRef;
    String? hrefFileName;

    if (href.contains('#')) {
      final dividedHref = href.split('#');
      if (dividedHref.length == 1) {
        hrefIdRef = href;
      } else {
        hrefFileName = dividedHref[0];
        hrefIdRef = dividedHref[1];
      }
    } else {
      hrefFileName = href;
    }

    if (hrefIdRef == null) {
      final chapter = _chapterByFileName(hrefFileName);
      if (chapter != null) {
        final cfi = _epubCfiReader?.generateCfiChapter(
          book: _controller._document,
          chapter: chapter,
          additional: ['/4/2'],
        );

        _gotoEpubCfi(cfi);
      }
      return;
    } else {
      final paragraph = _paragraphByIdRef(hrefIdRef);
      final chapter =
          paragraph != null ? _chapters[paragraph.chapterIndex] : null;

      if (chapter != null && paragraph != null) {
        final paragraphIndex =
            _epubCfiReader?.getParagraphIndexByElement(paragraph.element);
        final cfi = _epubCfiReader?.generateCfi(
          book: _controller._document,
          chapter: chapter,
          paragraphIndex: paragraphIndex,
        );

        _gotoEpubCfi(cfi);
      }

      return;
    }
  }

  Paragraph? _paragraphByIdRef(String idRef) =>
      _paragraphs.firstWhereOrNull((paragraph) {
        if (paragraph.element.id == idRef) {
          return true;
        }

        return paragraph.element.children.isNotEmpty &&
            paragraph.element.children[0].id == idRef;
      });

  EpubChapter? _chapterByFileName(String? fileName) =>
      _chapters.firstWhereOrNull((chapter) {
        if (fileName != null) {
          if (chapter.contentFileName!.contains(fileName)) {
            return true;
          } else {
            return false;
          }
        }
        return false;
      });

  int _getChapterIndexBy({
    required int positionIndex,
    double? trailingEdge,
    double? leadingEdge,
  }) {
    final posIndex = _getAbsParagraphIndexBy(
      positionIndex: positionIndex,
      trailingEdge: trailingEdge,
      leadingEdge: leadingEdge,
    );
    final index = posIndex >= _chapterIndexes.last
        ? _chapterIndexes.length
        : _chapterIndexes.indexWhere((chapterIndex) {
            if (posIndex < chapterIndex) {
              return true;
            }
            return false;
          });

    return index - 1;
  }

  int _getParagraphIndexBy({
    required int positionIndex,
    double? trailingEdge,
    double? leadingEdge,
  }) {
    final posIndex = _getAbsParagraphIndexBy(
      positionIndex: positionIndex,
      trailingEdge: trailingEdge,
      leadingEdge: leadingEdge,
    );

    final index = _getChapterIndexBy(positionIndex: posIndex);

    if (index == -1) {
      return posIndex;
    }

    return posIndex - _chapterIndexes[index];
  }

  int _getAbsParagraphIndexBy({
    required int positionIndex,
    double? trailingEdge,
    double? leadingEdge,
  }) {
    int posIndex = positionIndex;
    if (trailingEdge != null &&
        leadingEdge != null &&
        trailingEdge < _minTrailingEdge &&
        leadingEdge < _minLeadingEdge) {
      posIndex += 1;
    }

    return posIndex;
  }

  static Widget _chapterDividerBuilder(EpubChapter chapter) => Container(
        height: 56,
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: Color(0x24000000),
        ),
        alignment: Alignment.centerLeft,
        child: Text(
          chapter.title ?? '',
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
          ),
        ),
      );

  static Widget _chapterBuilder(
    BuildContext context,
    EpubViewBuilders builders,
    EpubBook document,
    List<EpubChapter> chapters,
    List<EpubChapter> flatChapters,
    List<Paragraph> paragraphs,
    int index,
    int chapterIndex,
    int paragraphIndex,
    ExternalLinkPressed onExternalLinkPressed,
  ) {
    if (paragraphs.isEmpty) {
      return Container();
    }

    final defaultBuilder = builders as EpubViewBuilders<DefaultBuilderOptions>;
    final options = defaultBuilder.options;

    final css = Style.fromCss(
        document.content?.css.values.toList().first.content ?? '', null);

    return Column(
      children: <Widget>[
        if (index >= 0 && paragraphIndex == 0)
          builders.chapterDividerBuilder(flatChapters[chapterIndex]),
        Html(
          // TODO aqui tem q criar um componente q junta os html e cria uma pagina do livro
          data: paragraphs[index].element.outerHtml,
          onLinkTap: (href, _, __) => onExternalLinkPressed(href!),

          style: {
            ...css,
            'html': Style(
              padding: HtmlPaddings.only(
                top: (options.paragraphPadding as EdgeInsets?)?.top,
                right: (options.paragraphPadding as EdgeInsets?)?.right,
                bottom: (options.paragraphPadding as EdgeInsets?)?.bottom,
                left: (options.paragraphPadding as EdgeInsets?)?.left,
              ),
            ).merge(Style.fromTextStyle(options.textStyle)),
            '*': Style(height: Height.auto(), width: Width.auto()),
            'td': Style(border: Border.all(width: 1))
          },
          extensions: [
            const TableHtmlExtension(),
            TagExtension(
              tagsToExtend: {"img"},
              builder: (imageContext) {
                final url =
                    imageContext.attributes['src']!.replaceAll('../', '');
                final content =
                    Uint8List.fromList(document.content!.images[url]!.content!);
                final image = Image.memory(content);

                return ZoomableImagePreview(image: image);
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLoaded(BuildContext context) {
    final defaultBuilder =
        widget.builders as EpubViewBuilders<DefaultBuilderOptions>;
    final options = defaultBuilder.options;
    return GestureDetector(
        onTapDown: (_) {
          // Marcamos que um toque é potencialmente válido e que ainda não estamos arrastando.
          _isTapEligible = true;
          _isDragging = false;

          // Inicia um "cronômetro". Se o usuário segurar o dedo por mais de 200ms,
          // o toque não é mais elegível. Isso evita que um "long press" acione a navegação.
          Future.delayed(const Duration(milliseconds: 300), () {
            _isTapEligible = false;
          });
        },

        // 2. O sistema detectou o início de um gesto de arrastar.
        onPanStart: (_) {
          // Imediatamente invalida o toque e marca que estamos arrastando.
          _isTapEligible = false;
          _isDragging = true;
        },

        // 3. O sistema cancelou nosso toque (geralmente porque o "arrastar" da lista venceu a disputa).
        onTapCancel: () {
          _isTapEligible = false;
        },
        onTapUp: (TapUpDetails details) {
          if (_isTapEligible &&
              !_isDragging &&
              options.axis == Axis.horizontal) {
            // Pega a largura total da tela
            final screenWidth = MediaQuery.of(context).size.width;
            // Pega a posição X (horizontal) do toque
            final tapPosition = details.localPosition.dx;

            final bool isRightSideTap = tapPosition > screenWidth / 2;

            final bool shouldGoNext = isRightSideTap ^ options.reverse;

            if (shouldGoNext) {
              _goNext();
            } else {
              _goPrevious();
            }
            // Reseta as flags para o próximo toque.
            _isTapEligible = false;
            _isDragging = false;
          }
        },
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is ScrollEndNotification &&
                options.axis == Axis.horizontal) {
              _onScrollEnded();
            }
            return true;
          },
          child: ScrollablePositionedList.builder(
            // TODO tem q pensar numa forma de envolver esse cara já com a qtd e paginas para passar pro itemCount, ou criar um outro EpubView so q para Paginas e n lista
            shrinkWrap: widget.shrinkWrap,
            scrollDirection: options.axis,
            initialScrollIndex:
                _epubCfiReader!.paragraphIndexByCfiFragment ?? 0,
            itemCount: _paragraphs.length,
            itemScrollController: _itemScrollController,
            itemPositionsListener: _itemPositionListener,
            reverse: options.reverse,
            physics: options.axis == Axis.vertical
                ? null
                : const PageScrollPhysics(),
            itemBuilder: (BuildContext context, int index) {
              return widget.builders.chapterBuilder(
                context,
                widget.builders,
                widget.controller._document!,
                _chapters,
                _flatChapters,
                _paragraphs,
                index,
                _getChapterIndexBy(positionIndex: index),
                _getParagraphIndexBy(positionIndex: index),
                _onLinkPressed,
              );
            },
          ),
        ));
  }

  static Widget _builder(
    BuildContext context,
    EpubViewBuilders builders,
    EpubViewLoadingState state,
    WidgetBuilder loadedBuilder,
    Exception? loadingError,
  ) {
    final Widget content = () {
      switch (state) {
        case EpubViewLoadingState.loading:
          return KeyedSubtree(
            key: const Key('epubx.root.loading'),
            child: builders.loaderBuilder?.call(context) ?? const SizedBox(),
          );
        case EpubViewLoadingState.error:
          return KeyedSubtree(
            key: const Key('epubx.root.error'),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: builders.errorBuilder?.call(context, loadingError!) ??
                  Center(child: Text(loadingError.toString())),
            ),
          );
        case EpubViewLoadingState.success:
          return KeyedSubtree(
            key: const Key('epubx.root.success'),
            child: loadedBuilder(context),
          );
      }
    }();

    final defaultBuilder = builders as EpubViewBuilders<DefaultBuilderOptions>;
    final options = defaultBuilder.options;

    return AnimatedSwitcher(
      duration: options.loaderSwitchDuration,
      transitionBuilder: options.transitionBuilder,
      child: content,
    );
  }

  void _onScrollEnded() {
    // Se já houver um debounce ativo, cancele-o
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    // Crie um novo debounce para executar a lógica de snap após um curto período de inatividade
    _debounce = Timer(const Duration(milliseconds: 200), () {
      if (!_itemScrollController!.isAttached) return;

      final positions = _itemPositionListener!.itemPositions.value;
      if (positions.isNotEmpty) {
        // Lógica para encontrar o item mais próximo do topo
        // O itemLeadingEdge é a distância do topo do item ao topo da viewport.
        // Queremos o item com a menor distância (o mais próximo do topo).
        final closestItem = positions.reduce((a, b) {
          return (a.itemLeadingEdge).abs() < (b.itemLeadingEdge).abs() ? a : b;
        });

        // Pega o índice do item mais próximo
        final targetIndex = closestItem.index;

        // Rola programaticamente para o item alvo, garantindo que ele fique
        // perfeitamente alinhado no topo da lista.
        _itemScrollController!.scrollTo(
          index: targetIndex,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  // NOVA FUNÇÃO: Move para o item anterior
  void _goPrevious() {
    final positions = _itemPositionListener?.itemPositions.value ?? [];
    if (positions.isNotEmpty) {
      // Pega o índice do primeiro item visível e subtrai 1
      final firstVisibleIndex = positions.first.index;
      final targetIndex = firstVisibleIndex - 1;
      _scrollToIndex(targetIndex);
    }
  }

  // NOVA FUNÇÃO: Move para o próximo item
  void _goNext() {
    final positions = _itemPositionListener?.itemPositions.value ?? [];
    if (positions.isNotEmpty) {
      // Pega o índice do primeiro item visível e soma 1
      final firstVisibleIndex = positions.first.index;
      final targetIndex = firstVisibleIndex + 1;
      _scrollToIndex(targetIndex);
    }
  }

  // NOVA FUNÇÃO: Centraliza a lógica de rolagem
  void _scrollToIndex(int index) {
    // Garante que o índice esteja dentro dos limites da lista
    final clampedIndex = index.clamp(0, _paragraphs.length - 1);

    _itemScrollController?.scrollTo(
      index: clampedIndex,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return widget.builders.builder(
      context,
      widget.builders,
      _controller.loadingState.value,
      _buildLoaded,
      _loadingError,
    );
  }
}
