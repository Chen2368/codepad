import 'package:flutter/services.dart';

/// 回车自动缩进：新行沿用上一行的缩进；若上一行以 `{` 结尾，再缩进一级。
///
/// 只处理「插入单个字符且插入的是换行」这一种情况，其余编辑原样放行；
/// 中文输入法组词期间（composing 有效）也直接放行，避免与候选框冲突。
class CodeIndentFormatter extends TextInputFormatter {
  const CodeIndentFormatter({this.indent = '    '});

  /// 缩进单位，默认 4 个空格。
  final String indent;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.composing.isValid) {
      return newValue;
    }
    final String text = newValue.text;
    if (text.length != oldValue.text.length + 1) {
      return newValue;
    }
    final int caret = newValue.selection.baseOffset;
    if (caret <= 0 || caret > text.length || !newValue.selection.isCollapsed) {
      return newValue;
    }
    if (text[caret - 1] != '\n') {
      return newValue;
    }

    final String insertion = indentationFor(text, caret);
    if (insertion.isEmpty) {
      return newValue;
    }
    return TextEditingValue(
      text: text.replaceRange(caret, caret, insertion),
      selection: TextSelection.collapsed(offset: caret + insertion.length),
    );
  }

  /// 在 [text] 的 [caret] 处按下回车时应当补上的缩进（[caret] 之前必须是换行）。
  ///
  /// 单独抽出来是为了能直接写单元测试。
  String indentationFor(String text, int caret) {
    if (caret <= 0 || caret > text.length) {
      return '';
    }
    final int previousLineEnd = caret - 1;
    if (previousLineEnd <= 0) {
      return ''; // 光标在第 1 个换行之后：上面就是文件开头，没有可沿用的缩进
    }
    final int previousLineStart =
        text.lastIndexOf('\n', previousLineEnd - 1) + 1;
    if (previousLineStart >= previousLineEnd) {
      return ''; // 上一行是空的，不需要缩进
    }
    final String previousLine =
        text.substring(previousLineStart, previousLineEnd);
    final String leading = _leadingWhitespace(previousLine);
    final String trimmed = previousLine.trimRight();
    final String extra = trimmed.endsWith('{') ? indent : '';
    return '$leading$extra';
  }

  static String _leadingWhitespace(String line) {
    final int end = line.length - line.trimLeft().length;
    return line.substring(0, end);
  }
}
