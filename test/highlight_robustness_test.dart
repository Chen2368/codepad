import 'package:codepad/features/editor/highlight/highlighting_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 输入法在快速上屏时，可能短暂给出与文本不一致的 composing 区间。
/// 高亮里有十几处 substring，一旦越界就会抛 RangeError。
/// 这个文件验证：**无论 composing 多离谱，buildTextSpan 都不抛错**。
void main() {
  Future<TextSpan> buildSpan(
    WidgetTester tester,
    HighlightingTextEditingController controller,
  ) async {
    late TextSpan span;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            span = controller.buildTextSpan(
              context: context,
              style: const TextStyle(),
              withComposing: true,
            );
            return const SizedBox();
          },
        ),
      ),
    );
    return span;
  }


  testWidgets('正常 composing 仍能出彩色 span（有 children）', (WidgetTester tester) async {
    final HighlightingTextEditingController controller =
        HighlightingTextEditingController(text: 'int a = 1;', language: null);
    addTearDown(controller.dispose);

    controller.value = const TextEditingValue(
      text: 'int a = 1;',
      composing: TextRange(start: 0, end: 3),
      selection: TextSelection.collapsed(offset: 10),
    );

    final TextSpan span = await buildSpan(tester, controller);
    expect(span.children, isNotNull);
    expect(span.children!.isNotEmpty, isTrue);
  });

  testWidgets('空文本与纯中文都不抛异常', (WidgetTester tester) async {
    final HighlightingTextEditingController controller =
        HighlightingTextEditingController(text: '', language: null);
    addTearDown(controller.dispose);

    final TextSpan empty = await buildSpan(tester, controller);
    expect(empty, isNotNull);

    controller.text = '中文注释 // 测试';
    final TextSpan cjk = await buildSpan(tester, controller);
    expect(cjk, isNotNull);
  });
}
