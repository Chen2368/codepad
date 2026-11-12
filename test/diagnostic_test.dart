import 'package:codepad/core/text/line_offsets.dart';
import 'package:codepad/runtime/compile_diagnostic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('编译诊断解析', () {
    test('带位置的 error 解析出文件、行号与中文提示', () {
      final CompileDiagnostic? d =
          CompileDiagnosticParser.parseLine("main.c:5: error: 'x' undeclared");

      expect(d, isNotNull);
      expect(d!.severity, DiagnosticSeverity.error);
      expect(d.file, 'main.c');
      expect(d.line, 5);
      expect(d.message, "'x' undeclared");
      expect(d.hasLocation, isTrue);
      expect(d.hint, contains('变量或函数没定义就用了'));
    });

    test('子目录路径与警告级别', () {
      final CompileDiagnostic? d = CompileDiagnosticParser.parseLine(
        'lib/util.c:12: warning: unused variable a',
      );

      expect(d!.file, 'lib/util.c');
      expect(d.line, 12);
      expect(d.severity, DiagnosticSeverity.warning);
      expect(d.hint, contains('变量定义了但没用到'));
    });

    test('tcc 前缀但没有行号的错误也能识别（不可跳转）', () {
      final CompileDiagnostic? d =
          CompileDiagnosticParser.parseLine("tcc: error: file 'util.h' not found");

      expect(d, isNotNull);
      expect(d!.hasLocation, isFalse);
      expect(d.severity, DiagnosticSeverity.error);
      expect(d.hint, contains('找不到这个头文件'));
    });

    test('隐式声明给出 include 提示', () {
      final CompileDiagnostic? d = CompileDiagnosticParser.parseLine(
        'main.c:3: error: implicit declaration of function \'printf\'',
      );
      expect(d!.hint, contains('stdio.h'));
    });

    test('全角标点/非法字符的报错指向输入法问题', () {
      final CompileDiagnostic? d =
          CompileDiagnosticParser.parseLine("main.c:2: error: stray '\\357' in program");
      expect(d!.hint, contains('全角'));
    });

    test('程序正常输出不会被误判为诊断', () {
      expect(CompileDiagnosticParser.parseLine('排序结果: 1 2 3'), isNull);
      expect(CompileDiagnosticParser.parseLine('tcc version 0.9.27'), isNull);
      expect(CompileDiagnosticParser.parseLine(''), isNull);
      expect(CompileDiagnosticParser.parseLine('Done: 3 items'), isNull);
    });

    test('整段输出里只挑出诊断行', () {
      const String text = 'In file included from main.c:2:\n'
          "main.c:3: error: 'x' undeclared\n"
          'main.c:4: warning: unused variable y\n';

      final List<CompileDiagnostic> list = CompileDiagnosticParser.parse(text);
      expect(list.length, 2);
      expect(list.first.line, 3);
      expect(list.last.severity, DiagnosticSeverity.warning);
    });
  });

  group('运行前源码检查', () {
    test('抓到全角分号并给出行号', () {
      const String source = 'int main(void) {\n'
          '    int a = 1；\n'
          '    return 0;\n'
          '}\n';

      final List<SourceLintFinding> findings = SourceLint.check(source);
      expect(findings.length, 1);
      expect(findings.first.line, 2);
      expect(findings.first.message, contains('全角'));
      expect(findings.first.message, contains('；'));
    });

    test('字符串与注释里的中文不算问题', () {
      const String source = 'int main(void) {\n'
          '    printf("你好，世界；\\n");  // 中文注释，没问题\n'
          '    return 0;\n'
          '}\n';

      expect(SourceLint.check(source), isEmpty);
    });

    // 0.3.2 的日志里，示例工程的块注释里的「，」「：」被误报成 3 条全角警告
    test('跨行块注释里的中文标点也不会误报', () {
      const String source = '''
#include <stdio.h>

/* 梯形法计算 f(x) 在 [0, 1] 上的定积分，精确值为 1/3。
   注意：这里全是中文标点，不该报错。 */
int main(void) {
    printf("ok\\n");
    return 0;
}
''';

      expect(SourceLint.check(source), isEmpty);
    });

    test('注释之外的代码里仍然会抓到全角标点', () {
      const String source = '/* 注释里的 ，没问题 */\nint main(void) { int a = 1； return a; }\n';
      final List<SourceLintFinding> findings = SourceLint.check(source);
      expect(findings.length, 1);
      expect(findings.first.line, 2);
    });

    test('char 字面量与转义不会让扫描错位', () {
      const String source = 'int main(void) {\n'
          "    char c = '\\'';\n"
          '    char d = \'"\';\n'
          '    int a = 2;\n'
          '    return 0;\n'
          '}\n';
      expect(SourceLint.check(source), isEmpty);
    });

    test('涂空注释后行号保持不变', () {
      const String source = 'a\n/* 跨\n行注释 */\nb\n';
      final String stripped = SourceLint.stripNonCode(source);
      expect(stripped.split('\n').length, source.split('\n').length);
      expect(stripped, contains('b'));
    });

    test('最多只报 3 条，避免刷屏', () {
      const String source = 'int a；\nint b；\nint c；\nint d；\nint e；\n';
      expect(SourceLint.check(source).length, 3);
    });
  });

  group('行号与偏移', () {
    const String text = 'line1\nline2\nline3';

    test('offsetForLine 从 1 开始计数', () {
      expect(offsetForLine(text, 1), 0);
      expect(offsetForLine(text, 2), 6);
      expect(offsetForLine(text, 3), 12);
    });

    test('越界时收敛到文本末尾', () {
      expect(offsetForLine(text, 99), text.length);
      expect(offsetForLine(text, 0), 0);
    });

    test('lineForOffset 是反向换算', () {
      expect(lineForOffset(text, 0), 1);
      expect(lineForOffset(text, 6), 2);
      expect(lineForOffset(text, 12), 3);
      expect(lineForOffset(text, 999), 3);
    });
  });
}
