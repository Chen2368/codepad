/// 编辑器里的「查找 / 替换」核心逻辑：纯函数，便于单元测试。
///
/// 单独抽出来的原因：查找的可疑行为（大小写、重叠、替换后游标位置）都在这里，
/// 放进 Widget 里就只能靠点界面去猜。
library;

/// 一处匹配。
class TextMatch {
  const TextMatch({required this.start, required this.length});

  final int start;
  final int length;

  int get end => start + length;

  String apply(String text, String replacement) =>
      text.replaceRange(start, end, replacement);
}

/// 在 [text] 里找出所有 [query]。
///
/// · [query] 为空 → 空列表；
/// · 默认区分大小写（写代码时 `Printf` 和 `printf` 不是一回事）；
/// · 匹配之间不重叠（搜索 `aa` 于 `aaaa` 得到 2 处，而不是 3 处）。
List<TextMatch> findMatches(
  String text,
  String query, {
  bool caseSensitive = true,
}) {
  if (query.isEmpty || text.isEmpty) {
    return const <TextMatch>[];
  }
  final String haystack = caseSensitive ? text : text.toLowerCase();
  final String needle = caseSensitive ? query : query.toLowerCase();
  final List<TextMatch> matches = <TextMatch>[];
  int index = haystack.indexOf(needle);
  while (index >= 0) {
    matches.add(TextMatch(start: index, length: query.length));
    index = haystack.indexOf(needle, index + needle.length);
  }
  return matches;
}

/// 从 [current] 走到下一处（[forward] 为 false 时上一处），到头会绕回去。
///
/// [current] 为 -1 表示还没有选中任何东西：向前找时落在第 0 处，
/// 向后找时落在最后一处。
int stepIndex(int current, int count, {required bool forward}) {
  if (count <= 0) {
    return -1;
  }
  if (current < 0 || current >= count) {
    return forward ? 0 : count - 1;
  }
  final int next = forward ? current + 1 : current - 1;
  if (next < 0) {
    return count - 1;
  }
  if (next >= count) {
    return 0;
  }
  return next;
}

/// 全部替换。替换结果里**不会**再次匹配新生成的文本（避免 `a` → `aa` 无限膨胀）。
(String, int) replaceAllMatches(
  String text,
  String query,
  String replacement, {
  bool caseSensitive = true,
}) {
  final List<TextMatch> matches =
      findMatches(text, query, caseSensitive: caseSensitive);
  if (matches.isEmpty) {
    return (text, 0);
  }
  final StringBuffer buffer = StringBuffer();
  int cursor = 0;
  for (final TextMatch match in matches) {
    buffer.write(text.substring(cursor, match.start));
    buffer.write(replacement);
    cursor = match.end;
  }
  buffer.write(text.substring(cursor));
  return (buffer.toString(), matches.length);
}

/// 只替换当前这一处，返回新的全文（找不到就原样返回）。
String replaceOne(String text, TextMatch match, String replacement) =>
    match.apply(text, replacement);
