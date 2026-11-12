import 'package:codepad/core/text/bracket_match.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('括号配对', () {
    test('光标在左括号右侧时匹配到右括号', () {
      const String text = 'f(a + b)';
      final BracketPair? pair = findBracketPair(text, 2); // f( | a...
      expect(pair, isNotNull);
      expect(pair!.open, 1);
      expect(pair.close, 7);
    });

    test('光标在右括号左侧时反向匹配', () {
      const String text = 'f(a + b)';
      final BracketPair? pair = findBracketPair(text, 7); // 光标在 ')' 前
      expect(pair!.open, 1);
      expect(pair.close, 7);
    });

    test('嵌套时匹配到正确的那一层', () {
      const String text = 'if (a) { g(b); }';
      final int inner = text.indexOf('g(') + 1;
      final BracketPair? pair = findBracketPair(text, inner + 1);
      expect(pair!.open, inner);
      expect(pair.close, text.indexOf(')', inner));
    });

    test('字符串里的括号不参与匹配', () {
      const String text = 'printf("(");';
      final BracketPair? pair = findBracketPair(text, 8); // 在字符串的 ( 之后
      expect(pair, isNull);
    });

    test('注释里的括号不参与匹配', () {
      const String text = 'int a; // ( \nint b;';
      expect(findBracketPair(text, text.indexOf('(') + 1), isNull);
    });

    test('光标不在任何括号旁边时返回 null', () {
      const String text = 'int a = 1;';
      expect(findBracketPair(text, 5), isNull);
    });

    test('括号不配对时返回 null', () {
      const String text = 'f(a';
      expect(findBracketPair(text, 2), isNull);
    });

    test('空文本安全返回', () {
      expect(findBracketPair('', 0), isNull);
    });
  });
}
