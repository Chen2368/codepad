import 'package:flutter/material.dart';

import 'code_token.dart';

/// 语法高亮配色方案。
///
/// 深浅两套默认方案之外，另提供两套「编辑器风格」的经典配色：
/// `One Dark`（偏冷、对比高）与 `纸白`（浅色、印刷感）。用户可在设置里切换。
enum CodeThemeId {
  auto('auto', '跟随系统'),
  oneDark('one_dark', 'One Dark'),
  paper('paper', '纸白');

  const CodeThemeId(this.id, this.label);

  final String id;
  final String label;

  static CodeThemeId fromId(Object? value) {
    for (final CodeThemeId item in CodeThemeId.values) {
      if (item.id == value) {
        return item;
      }
    }
    return CodeThemeId.auto;
  }
}

/// 语法高亮配色。
class CodePalette {
  const CodePalette({
    required this.keyword,
    required this.type,
    required this.string,
    required this.comment,
    required this.number,
    required this.functionName,
    required this.preprocessor,
  });

  final Color keyword;
  final Color type;
  final Color string;
  final Color comment;
  final Color number;
  final Color functionName;
  final Color preprocessor;

  static const CodePalette dark = CodePalette(
    keyword: Color(0xFFC792EA),
    type: Color(0xFF82AAFF),
    string: Color(0xFFC3E88D),
    comment: Color(0xFF6B7A8F),
    number: Color(0xFFF78C6C),
    functionName: Color(0xFFFFCB6B),
    preprocessor: Color(0xFFFF9CAC),
  );

  static const CodePalette light = CodePalette(
    keyword: Color(0xFF7C4DFF),
    type: Color(0xFF1565C0),
    string: Color(0xFF2E7D32),
    comment: Color(0xFF8A9BA8),
    number: Color(0xFFEF6C00),
    functionName: Color(0xFFB26A00),
    preprocessor: Color(0xFFAD1457),
  );

  /// 经典 One Dark 配色（Atom / VS Code 同款色值）。
  static const CodePalette oneDark = CodePalette(
    keyword: Color(0xFFC678DD),
    type: Color(0xFFE5C07B),
    string: Color(0xFF98C379),
    comment: Color(0xFF7F848E),
    number: Color(0xFFD19A66),
    functionName: Color(0xFF61AFEF),
    preprocessor: Color(0xFF56B6C2),
  );

  /// 纸白：低饱和、印刷感，白天看清爽。
  static const CodePalette paper = CodePalette(
    keyword: Color(0xFF9C27B0),
    type: Color(0xFF00695C),
    string: Color(0xFF2E7D32),
    comment: Color(0xFF9E9E9E),
    number: Color(0xFFD84315),
    functionName: Color(0xFF1565C0),
    preprocessor: Color(0xFF8E24AA),
  );

  /// 按设置与亮度挑一套。
  static CodePalette resolve(CodeThemeId id, Brightness brightness) {
    switch (id) {
      case CodeThemeId.auto:
        return brightness == Brightness.dark ? dark : light;
      case CodeThemeId.oneDark:
        return oneDark;
      case CodeThemeId.paper:
        return paper;
    }
  }

  static CodePalette fromScheme(ColorScheme scheme) {
    return scheme.brightness == Brightness.dark ? dark : light;
  }

  TextStyle styleFor(TokenKind kind) {
    switch (kind) {
      case TokenKind.plain:
        return const TextStyle();
      case TokenKind.keyword:
        return TextStyle(color: keyword);
      case TokenKind.type:
        return TextStyle(color: type);
      case TokenKind.string:
        return TextStyle(color: string);
      case TokenKind.comment:
        return TextStyle(color: comment, fontStyle: FontStyle.italic);
      case TokenKind.number:
        return TextStyle(color: number);
      case TokenKind.function:
        return TextStyle(color: functionName);
      case TokenKind.preprocessor:
        return TextStyle(color: preprocessor);
    }
  }
}
