import 'package:epub_view/epub_view.dart';
import 'package:epub_view/src/data/epub_cfi_reader.dart';
import 'package:html/dom.dart' as dom;

import 'models/paragraph.dart';

List<EpubChapter> parseChapters(EpubBook epubBook) =>
    epubBook.chapters.fold<List<EpubChapter>>(
      [],
      (acc, next) {
        acc.add(next);
        //next.subChapters.forEach(acc.add);
        return acc;
      },
    );

List<dom.Element> convertDocumentToElements(dom.Document document) =>
    document.getElementsByTagName('body').first.children;

List<dom.Element> _removeAllDiv(List<dom.Element> elements) {
  final List<dom.Element> result = [];

  for (final node in elements) {
    if (node.localName == 'div' && node.children.length > 1) {
      result.addAll(_removeAllDiv(node.children));
    } else {
      result.add(node);
    }
  }

  return result;
}

ParseParagraphsResult parseParagraphs(
    List<EpubChapter> chapters, EpubContent? content,
    {List<int>? chapterIndexesInit, List<Paragraph>? accInit}) {
  String? filename = '';
  List<int> chapterIndexes = chapterIndexesInit ?? [];
  final paragraphs = chapters.fold<List<Paragraph>>(
    accInit ?? [],
    (acc, next) {
      if (next.contentFileName == null) {
        if (next.subChapters.isNotEmpty) {
          parseParagraphs(next.subChapters, content,
              chapterIndexesInit: chapterIndexes,
              accInit: acc); // adicionar chapterIndexes como parametro
          return acc;
        }
        // TODO pode ter paragrafos e não ser so um index
      }
      List<dom.Element> elmList = [];
      if (filename != next.contentFileName) {
        filename = next.contentFileName;
        final document = EpubCfiReader().chapterDocument(next);
        if (document != null) {
          final result = convertDocumentToElements(document);
          elmList = _removeAllDiv(result);
        }
      }

      if (next.anchor == null) {
        // last element from document index as chapter index
        chapterIndexes.add(acc.length);
        acc.addAll(elmList
            .map((element) => Paragraph(element, chapterIndexes.length - 1)));
        return acc;
      } else {
        final index = elmList.indexWhere(
          (elm) => elm.outerHtml.contains(
            'id="${next.anchor}"',
          ),
        );
        if (index == -1) {
          chapterIndexes.add(acc.length);
          acc.addAll(elmList
              .map((element) => Paragraph(element, chapterIndexes.length - 1)));
          return acc;
        }

        chapterIndexes.add(index);
        acc.addAll(elmList
            .map((element) => Paragraph(element, chapterIndexes.length - 1)));
        return acc;
      }
    },
  );

  return ParseParagraphsResult(paragraphs, chapterIndexes);
}

class ParseParagraphsResult {
  ParseParagraphsResult(this.flatParagraphs, this.chapterIndexes);

  final List<Paragraph> flatParagraphs;
  final List<int> chapterIndexes;
}
