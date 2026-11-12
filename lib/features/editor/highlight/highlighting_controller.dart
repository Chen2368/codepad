import 'package:flutter/material.dart';

import '../../../data/models/program_language.dart';
import '../../../core/text/bracket_match.dart';
import 'code_palette.dart';
import 'code_token.dart';
import 'code_tokenizer.dart';

/// 带语法高亮的文本控制器。
///
/// 通过重写 [buildTextSpan] 让原生 TextField 直接渲染彩色文本：
/// 不需要第三方高亮库，也不改变编辑、选择、输入法（IME）行为。
class HighlightingTextEditingController extends TextEditingController {
  HighlightingTextEditingController({
    super.text,
    required this.language,
    this.codeTheme = CodeThemeId.auto,
  });

  /// 当前语言（重命名文件后由 EditorController 更新）。
  ProgramLanguage? language;

  /// 配色方案（设置里可选：跟随系统 / One Dark / 纸白）。
  CodeThemeId codeTheme = CodeThemeId.auto;

  String? _cacheKey;
  List<CodeToken> _cacheTokens = const <CodeToken>[];

  /// 按 (语言, 全文) 缓存 token，避免无关重建时重复解析。
  List<CodeToken> _tokensFor(String source) {
    final String key = '${language?.name ?? '-'}\u0000$source';
    if (key == _cacheKey) {
      return _cacheTokens;
    }
    _cacheKey = key;
    _cacheTokens = CodeTokenizer.forLanguage(language).tokenize(source);
    return _cacheTokens;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final TextStyle base = style ?? const TextStyle();
    final CodePalette palette = CodePalette.resolve(
      codeTheme,
      Theme.of(context).colorScheme.brightness,
    );
    final String source = text;
    final List<CodeToken> tokens = _tokensFor(source);

    final List<InlineSpan> spans = <InlineSpan>[];
    // 光标旁边的括号：给它和配对的那个字符加底色，扫代码时更容易看出层次
    final BracketPair? bracketPair =
        _bracketPairFor(source, selection.baseOffset, context);
    int cursor = 0;
    for (final CodeToken token in tokens) {
      if (token.start > cursor) {
        spans.addAll(_plainSpans(source, cursor, token.start, base, bracketPair));
      }
      final TextStyle tokenStyle = base.merge(palette.styleFor(token.kind));
      if (bracketPair == null ||
          !_tokenHasBracket(token, bracketPair)) {
        spans.add(TextSpan(
          text: source.substring(token.start, token.end),
          style: tokenStyle,
        ));
      } else {
        // token 里正好含匹配括号：拆成小段，只给括号上色
        spans.addAll(
          _plainSpans(source, token.start, token.end, tokenStyle, bracketPair),
        );
      }
      cursor = token.end;
    }
    if (cursor < source.length) {
      spans.addAll(_plainSpans(source, cursor, source.length, base, bracketPair));
    }

    final TextSpan root = TextSpan(style: base, children: spans);
    return withComposing ? _withComposing(root, base) : root;
  }

  /// 缓存括号匹配结果：同一文本 + 同一光标只算一次。
  String? _bracketCacheKey;
  BracketPair? _bracketCacheValue;

  BracketPair? _bracketPairFor(String source, int caret, BuildContext context) {
    if (caret < 0) {
      return null;
    }
    final String key = '$caret\u0000$source';
    if (key == _bracketCacheKey) {
      return _bracketCacheValue;
    }
    _bracketCacheKey = key;
    _bracketCacheValue = findBracketPair(source, caret);
    return _bracketCacheValue;
  }

  bool _tokenHasBracket(CodeToken token, BracketPair pair) {
    return (pair.open >= token.start && pair.open < token.end) ||
        (pair.close >= token.start && pair.close < token.end);
  }

  /// 把 [start, end) 这段按「是否括号」切成若干 TextSpan。
  List<InlineSpan> _plainSpans(
    String source,
    int start,
    int end,
    TextStyle base,
    BracketPair? pair,
  ) {
    if (pair == null) {
      return <InlineSpan>[
        TextSpan(text: source.substring(start, end), style: base),
      ];
    }
    final List<InlineSpan> result = <InlineSpan>[];
    int cursor = start;
    while (cursor < end) {
      final bool atOpen = cursor == pair.open;
      final bool atClose = cursor == pair.close;
      if (atOpen || atClose) {
        result.add(TextSpan(
          text: source[cursor],
          style: base.copyWith(
            backgroundColor: _bracketColor,
            fontWeight: FontWeight.w700,
          ),
        ));
        cursor++;
        continue;
      }
      int next = end;
      if (pair.open > cursor && pair.open < next) {
        next = pair.open;
      }
      if (pair.close > cursor && pair.close < next) {
        next = pair.close;
      }
      result.add(
        TextSpan(text: source.substring(cursor, next), style: base),
      );
      cursor = next;
    }
    return result;
  }

  /// 匹配括号的底色（跟随主题的主色，透明度低一些不刺眼）。
  static const Color _bracketColor = Color(0x332F6BFF);

  /// 给正在输入的组词区间（中文输入法）加下划线，避免破坏 IME 体验。
  TextSpan _withComposing(TextSpan root, TextStyle base) {
    final TextRange composing = value.composing;
    if (!composing.isValid || composing.isCollapsed) {
      return root;
    }
    final List<InlineSpan> decorated = <InlineSpan>[];
    int position = 0;
    for (final InlineSpan child in root.children ?? const <InlineSpan>[]) {
      if (child is! TextSpan || child.text == null) {
        decorated.add(child);
        continue;
      }
      final String content = child.text!;
      final int start = position;
      final int end = position + content.length;
      position = end;

      if (end <= composing.start || start >= composing.end) {
        decorated.add(child);
        continue;
      }
      final int rawStart = composing.start - start;
      final int rawEnd = composing.end - start;
      final int cutStart = rawStart < 0 ? 0 : (rawStart > content.length ? content.length : rawStart);
      final int cutEnd = rawEnd < 0 ? 0 : (rawEnd > content.length ? content.length : rawEnd);

      if (cutStart > 0) {
        decorated.add(TextSpan(text: content.substring(0, cutStart), style: child.style));
      }
      if (cutEnd > cutStart) {
        decorated.add(TextSpan(
          text: content.substring(cutStart, cutEnd),
          style: child.style?.merge(
            base.copyWith(decoration: TextDecoration.underline),
          ),
        ));
      }
      if (cutEnd < content.length) {
        decorated.add(TextSpan(text: content.substring(cutEnd), style: child.style));
      }
    }
    return TextSpan(style: root.style, children: decorated);
  }
}
