/// 代码补全与代码片段（纯逻辑，便于单元测试）。
///
/// 规则很简单：光标在一个「标识符前缀」上时，列出匹配的候选；
/// 候选分两类 —— **片段**（insert 里带换行/占位）与**单词**（关键字、标准库函数）。
library;

/// 一个补全候选。
class CompletionItem {
  const CompletionItem({
    required this.label,
    required this.insert,
    this.detail = '',
    this.isSnippet = false,
  });

  /// 列表里显示的名字。
  final String label;

  /// 选中后替换掉前缀的内容。
  final String insert;

  /// 右侧说明（例如 "标准库"）。
  final String detail;

  /// 是否是片段（含多行模板）。
  final bool isSnippet;
}

/// C 常用关键字与标准库函数（前缀匹配用）。
const List<CompletionItem> cCompletions = <CompletionItem>[
  // 关键字
  CompletionItem(label: 'int', insert: 'int ', detail: '关键字'),
  CompletionItem(label: 'double', insert: 'double ', detail: '关键字'),
  CompletionItem(label: 'float', insert: 'float ', detail: '关键字'),
  CompletionItem(label: 'char', insert: 'char ', detail: '关键字'),
  CompletionItem(label: 'void', insert: 'void ', detail: '关键字'),
  CompletionItem(label: 'long', insert: 'long ', detail: '关键字'),
  CompletionItem(label: 'unsigned', insert: 'unsigned ', detail: '关键字'),
  CompletionItem(label: 'const', insert: 'const ', detail: '关键字'),
  CompletionItem(label: 'static', insert: 'static ', detail: '关键字'),
  CompletionItem(label: 'struct', insert: 'struct ', detail: '关键字'),
  CompletionItem(label: 'typedef', insert: 'typedef ', detail: '关键字'),
  CompletionItem(label: 'return', insert: 'return ', detail: '关键字'),
  CompletionItem(label: 'if', insert: 'if () {\n    \n}', detail: '条件', isSnippet: true),
  CompletionItem(label: 'else', insert: 'else {\n    \n}', detail: '分支', isSnippet: true),
  CompletionItem(label: 'for', insert: 'for (int i = 0; i < n; i++) {\n    \n}', detail: '循环', isSnippet: true),
  CompletionItem(label: 'while', insert: 'while () {\n    \n}', detail: '循环', isSnippet: true),
  CompletionItem(label: 'switch', insert: 'switch () {\n    case 0:\n        break;\n}', detail: '分支', isSnippet: true),
  CompletionItem(label: 'sizeof', insert: 'sizeof()', detail: '运算符'),
  // 标准库
  CompletionItem(label: 'printf', insert: 'printf("");', detail: 'stdio'),
  CompletionItem(label: 'scanf', insert: 'scanf("", );', detail: 'stdio'),
  CompletionItem(label: 'puts', insert: 'puts("");', detail: 'stdio'),
  CompletionItem(label: 'fgets', insert: 'fgets(, sizeof(), stdin);', detail: 'stdio'),
  CompletionItem(label: 'malloc', insert: 'malloc(sizeof());', detail: 'stdlib'),
  CompletionItem(label: 'free', insert: 'free();', detail: 'stdlib'),
  CompletionItem(label: 'qsort', insert: 'qsort(, , sizeof(), cmp);', detail: 'stdlib'),
  CompletionItem(label: 'strlen', insert: 'strlen();', detail: 'string'),
  CompletionItem(label: 'strcmp', insert: 'strcmp(, )', detail: 'string'),
  CompletionItem(label: 'strcpy', insert: 'strcpy(, );', detail: 'string'),
  CompletionItem(label: 'memset', insert: 'memset(, 0, sizeof());', detail: 'string'),
  CompletionItem(label: 'sqrt', insert: 'sqrt()', detail: 'math'),
  CompletionItem(label: 'fabs', insert: 'fabs()', detail: 'math'),
  CompletionItem(label: 'pow', insert: 'pow(, )', detail: 'math'),
  CompletionItem(label: 'exp', insert: 'exp()', detail: 'math'),
  CompletionItem(label: 'sin', insert: 'sin()', detail: 'math'),
  CompletionItem(label: 'cos', insert: 'cos()', detail: 'math'),
  // 片段
  CompletionItem(
    label: 'main',
    insert: '#include <stdio.h>\n\nint main(void) {\n    \n    return 0;\n}\n',
    detail: '程序骨架',
    isSnippet: true,
  ),
  CompletionItem(
    label: 'include',
    insert: '#include <stdio.h>\n',
    detail: '预处理',
  ),
  CompletionItem(
    label: 'fori',
    insert: 'for (int i = 0; i < n; i++) {\n    \n}',
    detail: '循环片段',
    isSnippet: true,
  ),
];

/// 光标处的「当前标识符前缀」起始位置；不在标识符里时返回 -1。
int wordPrefixStart(String text, int caret) {
  if (caret < 0 || caret > text.length) {
    return -1;
  }
  int index = caret;
  while (index > 0) {
    final int code = text.codeUnitAt(index - 1);
    final bool isWord = (code >= 97 && code <= 122) || // a-z
        (code >= 65 && code <= 90) || // A-Z
        (code >= 48 && code <= 57) || // 0-9
        code == 95; // _
    if (!isWord) {
      break;
    }
    index--;
  }
  if (index == caret) {
    return -1; // 光标不在任何前缀上
  }
  // 数字开头的不做补全（例如 3.14 里的 14）
  if (index < caret) {
    final int first = text.codeUnitAt(index);
    if (first >= 48 && first <= 57) {
      return -1;
    }
  }
  return index;
}

/// 根据 [text] 与 [caret] 给出补全候选（最多 [limit] 条）。
List<CompletionItem> suggestCompletions(
  String text,
  int caret, {
  int limit = 6,
}) {
  final int start = wordPrefixStart(text, caret);
  if (start < 0) {
    return const <CompletionItem>[];
  }
  final String prefix = text.substring(start, caret);
  if (prefix.isEmpty) {
    return const <CompletionItem>[];
  }

  final String lower = prefix.toLowerCase();
  final List<CompletionItem> exactPrefix = <CompletionItem>[];
  final List<CompletionItem> contains = <CompletionItem>[];
  for (final CompletionItem item in cCompletions) {
    final String label = item.label.toLowerCase();
    if (label.startsWith(lower)) {
      exactPrefix.add(item);
    } else if (label.contains(lower)) {
      contains.add(item);
    }
  }
  // 前缀命中的排前面；同组内短名字优先（int 比 unsigned 更常用）
  exactPrefix.sort((CompletionItem a, CompletionItem b) =>
      a.label.length.compareTo(b.label.length));
  final List<CompletionItem> merged = <CompletionItem>[
    ...exactPrefix,
    ...contains,
  ];
  return merged.take(limit).toList();
}

/// 把光标处的旧前缀替换成 [item].insert，返回新的文本与光标位置。
({String text, int caret}) applyCompletion(
  String text,
  int caret,
  CompletionItem item,
) {
  final int start = wordPrefixStart(text, caret);
  if (start < 0) {
    return (text: text, caret: caret);
  }
  final String updated = text.replaceRange(start, caret, item.insert);
  // 光标落在插入内容的第一对空括号/引号里，符合直觉
  final int caretOffset = _caretInsideInsert(item.insert);
  return (text: updated, caret: start + caretOffset);
}

/// 插入后把光标放到「最可能马上要打字的位置」。
///
/// 优先级：`()` 里 → `""` 里 → 代码块 `{` 后的缩进处 → 末尾。
int _caretInsideInsert(String insert) {
  for (final String pair in <String>['()', '""']) {
    final int index = insert.indexOf(pair);
    if (index >= 0) {
      return index + 1;
    }
  }
  // 片段：写到 `{` 的下一行缩进之后（例如 for/if 的循环体里）
  final int brace = insert.indexOf('{');
  if (brace >= 0) {
    int cursor = brace + 1;
    // 只跳过「一个换行 + 其后缩进」，不要越过空行的第二个换行
    if (cursor < insert.length && insert[cursor] == '\n') {
      cursor++;
    }
    while (cursor < insert.length && insert[cursor] == ' ') {
      cursor++;
    }
    return cursor;
  }
  return insert.length;
}
