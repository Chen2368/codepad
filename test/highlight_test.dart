import 'package:codepad/data/models/program_language.dart';
import 'package:codepad/features/editor/highlight/code_tokenizer.dart';
import 'package:codepad/features/editor/highlight/code_token.dart';
import 'package:flutter_test/flutter_test.dart';

/// 把 token 列表转成 `kind:text` 便于断言。
List<String> tokensOf(CodeTokenizer tokenizer, String source) {
  return tokenizer
      .tokenize(source)
      .map((CodeToken token) => '${token.kind.name}:${source.substring(token.start, token.end)}')
      .toList();
}

void main() {
  group('C/C++ 高亮', () {
    final CodeTokenizer cpp = CodeTokenizer.forLanguage(ProgramLanguage.cpp);

    test('关键字、类型、函数名、数字', () {
      final List<String> tokens = tokensOf(cpp, 'int main() { return 0; }');
      // int 属于类型集合，用类型色显示
      expect(tokens, contains('type:int'));
      expect(tokens, contains('function:main'));
      expect(tokens, contains('keyword:return'));
      expect(tokens, contains('number:0'));
    });

    test('注释、字符串、预处理指令', () {
      const String source = '#include <iostream>\n'
          '// 行注释\n'
          'std::string s = "hi";\n';
      final List<String> tokens = tokensOf(cpp, source);
      expect(tokens, contains('#include <iostream>'.replaceFirst('#', 'preprocessor:#')));
      expect(tokens, contains('comment:// 行注释'));
      expect(tokens, contains('string:"hi"'));
    });

    test('块注释跨行也能识别', () {
      final List<String> tokens = tokensOf(cpp, 'a /* 多行\n注释 */ b');
      expect(tokens.any((String t) => t.startsWith('comment:')), isTrue);
    });

    test('C 与 C++ 关键字集合不同', () {
      final CodeTokenizer c = CodeTokenizer.forLanguage(ProgramLanguage.c);
      // class 在 C++ 是关键字，在 C 里不是
      expect(tokensOf(cpp, 'class A {};'), contains('keyword:class'));
      expect(tokensOf(c, 'class A {};').where((String t) => t == 'keyword:class'), isEmpty);
    });

    test('未闭合的代码不抛异常', () {
      expect(
        () => cpp.tokenize('#include <iostream>\nint main() { /* 没闭合'),
        returnsNormally,
      );
    });
  });

  group('Python 高亮', () {
    final CodeTokenizer python = CodeTokenizer.forLanguage(ProgramLanguage.python);

    test('def 名称着色为函数，内置函数为类型色', () {
      final List<String> tokens = tokensOf(python, 'def fib(n):\n    return print(n)');
      expect(tokens, contains('keyword:def'));
      expect(tokens, contains('function:fib'));
      expect(tokens, contains('type:print'));
    });

    test('# 注释与三引号字符串', () {
      const String source = '"""文档字符串\n第二行"""\n# 注释\nx = 1\n';
      final List<String> tokens = tokensOf(python, source);
      expect(tokens, contains('comment:# 注释'));
      expect(tokens.any((String t) => t.startsWith('string:"""')), isTrue);
      expect(tokens, contains('number:1'));
    });

    test('装饰器识别为函数记号', () {
      expect(tokensOf(python, '@staticmethod'), contains('function:@staticmethod'));
    });
  });

  test('未知语言返回空 token 列表', () {
    final CodeTokenizer plain = CodeTokenizer.forLanguage(null);
    expect(plain.tokenize('anything'), isEmpty);
  });
}
