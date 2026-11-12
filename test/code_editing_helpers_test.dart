import 'package:codepad/core/text/code_indent_formatter.dart';
import 'package:codepad/features/editor/widgets/symbol_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('回车自动缩进', () {
    const CodeIndentFormatter formatter = CodeIndentFormatter();

    String? indentAt(String text, int caret) => caret == 0
        ? ''
        : (caret > 0 && caret <= text.length && text[caret - 1] == '\n')
            ? formatter.indentationFor(text, caret)
            : null;

    test('沿用上一行的缩进', () {
      const String text = 'int main(void) {\n    int a = 1;\n';
      expect(indentAt(text, text.length), '    ');
    });

    test('上一行以 { 结尾时再缩进一级', () {
      const String text = 'int main(void) {\n';
      expect(indentAt(text, text.length), '    ');
      const String nested = 'int main(void) {\n    for (int i = 0; i < 3; i++) {\n';
      expect(indentAt(nested, nested.length), '        ');
    });

    test('上一行是空行时不缩进', () {
      const String text = 'a\n\n';
      expect(indentAt(text, text.length), '');
    });

    test('没有上一行（文件开头）时不缩进', () {
      const String text = '\n';
      expect(indentAt(text, text.length), '');
    });

    test('插入换行时自动补缩进，并把光标放到缩进之后', () {
      const TextEditingValue oldValue = TextEditingValue(
        text: 'int main(void) {',
        selection: TextSelection.collapsed(offset: 16),
      );
      const TextEditingValue newValue = TextEditingValue(
        text: 'int main(void) {\n',
        selection: TextSelection.collapsed(offset: 17),
      );

      final TextEditingValue result = formatter.formatEditUpdate(oldValue, newValue);

      expect(result.text, 'int main(void) {\n    ');
      expect(result.selection.baseOffset, 21);
    });

    test('普通输入不受影响（不会误插缩进）', () {
      const TextEditingValue oldValue = TextEditingValue(
        text: 'ab',
        selection: TextSelection.collapsed(offset: 2),
      );
      const TextEditingValue newValue = TextEditingValue(
        text: 'abc',
        selection: TextSelection.collapsed(offset: 3),
      );
      expect(formatter.formatEditUpdate(oldValue, newValue), newValue);
    });
  });

  group('符号快捷条', () {
    test('成对符号补全，光标落在中间', () {
      final TextEditingController controller =
          TextEditingController(text: 'printf');
      addTearDown(controller.dispose);
      controller.selection = const TextSelection.collapsed(offset: 6);

      _barFor(controller).insert('(');

      expect(controller.text, 'printf()');
      expect(controller.selection.baseOffset, 7);
    });

    test('选中内容时用成对符号包裹', () {
      final TextEditingController controller =
          TextEditingController(text: 'int a = 1;');
      addTearDown(controller.dispose);
      controller.selection = const TextSelection(baseOffset: 0, extentOffset: 3);

      _barFor(controller).insert('{');

      expect(controller.text, '{int} a = 1;');
      expect(controller.selection.baseOffset, 5);
    });

    test('普通符号直接插入光标处', () {
      final TextEditingController controller =
          TextEditingController(text: 'int a = 1');
      addTearDown(controller.dispose);
      controller.selection = const TextSelection.collapsed(offset: 9);

      _barFor(controller).insert(';');

      expect(controller.text, 'int a = 1;');
      expect(controller.selection.baseOffset, 10);
    });

    test('Tab 按钮插入四个空格', () {
      final TextEditingController controller = TextEditingController(text: '');
      addTearDown(controller.dispose);

      _barFor(controller).insert('    ');

      expect(controller.text, '    ');
      expect(controller.selection.baseOffset, 4);
    });

    testWidgets('快捷条能渲染出来', (WidgetTester tester) async {
      final TextEditingController controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: _barFor(controller)),
        ),
      );
      expect(find.text(';'), findsOneWidget);
      expect(find.text('{'), findsOneWidget);
      expect(find.text('Tab'), findsOneWidget);
    });
  });
}

/// 直接构造控件实例来测插入逻辑，避免依赖整页布局。
CodeSymbolBar _barFor(TextEditingController controller) =>
    CodeSymbolBar(controller: controller);

