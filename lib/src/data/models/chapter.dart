class EpubViewChapter {
  EpubViewChapter(this.title, this.startIndex, {this.subChaptersCount = 0});

  final String? title;
  final int startIndex;
  final int? subChaptersCount;

  String get type => this is EpubViewSubChapter ? 'subchapter' : 'chapter';

  @override
  String toString() => '$type: {title: $title, startIndex: $startIndex}, subs: $subChaptersCount';
}

class EpubViewSubChapter extends EpubViewChapter {
  EpubViewSubChapter(String? title, int startIndex) : super(title, startIndex);
}
