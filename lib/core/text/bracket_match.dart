/// 括号匹配：找出光标旁边的括号与它的配对位置（纯逻辑，可测）。
///
/// 只处理三种括号：`()`、`[]`、`{}`。字符串与注释里的括号**不参与**匹配
/// （否则 `printf("(")` 会让匹配乱跳），实现上用一次简单扫描跳过字符串/注释。
library;

/// 一对匹配的括号下标（都指向括号字符本身）。
class BracketPair {
  const BracketPair({required this.open, required this.close});

  final int open;
  final int close;

  @override
  String toString() => 'BracketPair($open, $close)';
}

const Map<String, String> _openers = <String, String>{
  '(': ')',
  '[': ']',
  '{': '}',
};

/// 扫描文本，收集所有括号位置；跳过字符串与 `//`、`/* */` 注释中的括号。
///
/// 返回（下标 → 是否为左括号）的有序列表，供配对使用。
List<MapEntry<int, bool>> _scanBrackets(String text) {
  final List<MapEntry<int, bool>> brackets = <MapEntry<int, bool>>[];
  bool inString = false;
  bool inChar = false;
  bool inLineComment = false;
  bool inBlockComment = false;
  String quote = '';

  for (int i = 0; i < text.length; i++) {
    final String ch = text[i];
    final String next = i + 1 < text.length ? text[i + 1] : '';

    if (inLineComment) {
      if (ch == '\n') {
        inLineComment = false;
      }
      continue;
    }
    if (inBlockComment) {
      if (ch == '*' && next == '/') {
        inBlockComment = false;
        i++;
      }
      continue;
    }
    if (inString || inChar) {
      if (ch == '\\') {
        i++; // 跳过转义字符
        continue;
      }
      if (ch == quote) {
        inString = false;
        inChar = false;
        quote = '';
      }
      continue;
    }

    if (ch == '/' && next == '/') {
      inLineComment = true;
      i++;
      continue;
    }
    if (ch == '/' && next == '*') {
      inBlockComment = true;
      i++;
      continue;
    }
    if (ch == '"' || ch == '\'') {
      inString = ch == '"';
      inChar = ch == '\'';
      quote = ch;
      continue;
    }
    if (_openers.containsKey(ch)) {
      brackets.add(MapEntry<int, bool>(i, true));
      continue;
    }
    if (ch == ')' || ch == ']' || ch == '}') {
      brackets.add(MapEntry<int, bool>(i, false));
    }
  }
  return brackets;
}

/// 找出光标所在/紧邻的括号，并返回它与配对括号的下标。
///
/// 判断顺序：光标左侧字符 → 光标右侧字符。找不到或括号不配对时返回 null。
BracketPair? findBracketPair(String text, int caret) {
  if (text.isEmpty) {
    return null;
  }
  final int index = caret.clamp(0, text.length);
  // 光标贴着左括号（右侧）或右括号（左侧）都算「在括号上」
  final List<int> candidates = <int>[
    if (index - 1 >= 0) index - 1,
    if (index < text.length) index,
  ];

  final List<MapEntry<int, bool>> brackets = _scanBrackets(text);
  for (final int candidate in candidates) {
    if (candidate < 0 || candidate >= text.length) {
      continue;
    }
    final String ch = text[candidate];
    final bool isOpenBracket = _openers.containsKey(ch) || ch == ')' ||
        ch == ']' || ch == '}';
    if (!isOpenBracket) {
      continue;
    }
    final BracketPair? pair = _pairFor(text, brackets, candidate);
    if (pair != null) {
      return pair;
    }
  }
  return null;
}

BracketPair? _pairFor(
  String text,
  List<MapEntry<int, bool>> brackets,
  int position,
) {
  final int bracketIndex =
      brackets.indexWhere((MapEntry<int, bool> e) => e.key == position);
  if (bracketIndex < 0) {
    return null;
  }
  final bool forward = brackets[bracketIndex].value;
  final String target = text[position];
  final String? other = forward ? _openers[target] : _reverse(target);
  if (other == null) {
    return null;
  }

  int depth = 0;
  if (forward) {
    for (int i = bracketIndex; i < brackets.length; i++) {
      final MapEntry<int, bool> entry = brackets[i];
      if (entry.value) {
        depth++;
      } else {
        depth--;
        if (depth == 0) {
          return text[entry.key] == other
              ? BracketPair(open: position, close: entry.key)
              : null;
        }
      }
    }
    return null;
  }

  for (int i = bracketIndex; i >= 0; i--) {
    final MapEntry<int, bool> entry = brackets[i];
    if (entry.value) {
      depth++;
      if (depth == 0) {
        return text[entry.key] == other
            ? BracketPair(open: entry.key, close: position)
            : null;
      }
    } else {
      depth--;
    }
  }
  return null;
}

String? _reverse(String closer) {
  for (final MapEntry<String, String> entry in _openers.entries) {
    if (entry.value == closer) {
      return entry.key;
    }
  }
  return null;
}
