/// 行号 ↔ 字符偏移的换算。
///
/// 编辑器把「编译错误的第 N 行」变成光标位置时要用到：
/// Flutter 的 [TextSelection] 用的是字符偏移，不是行列。
library;

/// 返回第 [line] 行（1 起）第一个字符在 [text] 中的偏移。
///
/// 越界时返回文本长度（即把光标放到末尾），保证调用方不用做边界判断。
int offsetForLine(String text, int line) {
  if (line <= 1) {
    return 0;
  }
  int offset = 0;
  int current = 1;
  while (current < line) {
    final int index = text.indexOf('\n', offset);
    if (index < 0) {
      return text.length;
    }
    offset = index + 1;
    current++;
  }
  return offset > text.length ? text.length : offset;
}

/// 返回 [offset] 所在的行号（1 起）。
int lineForOffset(String text, int offset) {
  final int clamped = offset.clamp(0, text.length);
  int line = 1;
  for (int i = 0; i < clamped; i++) {
    if (text.codeUnitAt(i) == 0x0A) {
      line++;
    }
  }
  return line;
}
