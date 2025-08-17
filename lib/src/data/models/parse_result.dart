import 'package:epub_view/epub_view.dart';
import 'package:epub_view/src/data/epub_parser.dart';


class ParseResult {
  const ParseResult(this.epubBook, this.chapters, this.parseResult);

  final EpubBook epubBook;
  final List<EpubChapter> chapters;
  final ParseParagraphsResult parseResult;
}
