/// 语法高亮的记号类型。
enum TokenKind {
  plain,
  keyword,
  type,
  string,
  comment,
  number,
  function,
  preprocessor,
}

/// 源码中的一段记号：[start, end) 半开区间。
class CodeToken {
  const CodeToken({
    required this.start,
    required this.end,
    required this.kind,
  });

  final int start;
  final int end;
  final TokenKind kind;

  int get length => end - start;

  @override
  String toString() => 'CodeToken($start..$end, $kind)';
}
