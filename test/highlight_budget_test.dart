import 'package:codepad/features/editor/highlight/highlight_budget.dart';
import 'package:codepad/features/editor/highlight/highlighting_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('高亮预算', () {
    test('正常大小的文件允许高亮', () {
      expect(defaultHighlightBudget.allows('int main(void) { return 0; }'), isTrue);
      expect(defaultHighlightBudget.reasonFor('int a;'), isNull);
    });

    test('字符数超限则拒绝，并给出原因', () {
      final String big = 'x' * (defaultHighlightBudget.maxChars + 1);
      expect(defaultHighlightBudget.allows(big), isFalse);
      final String? reason = defaultHighlightBudget.reasonFor(big);
      expect(reason, isNotNull);
      expect(reason, contains('字符'));
    });

    test('行数超限则拒绝（即使字符数不多）', () {
      final String manyLines = List<String>.filled(
        defaultHighlightBudget.maxLines + 10,
        ';',
      ).join('\n');
      // 字符数远低于上限，但行数超了
      expect(manyLines.length, lessThan(defaultHighlightBudget.maxChars));
      expect(defaultHighlightBudget.allows(manyLines), isFalse);
      expect(defaultHighlightBudget.reasonFor(manyLines), contains('行'));
    });

    test('可自定义阈值', () {
      const HighlightBudget tight = HighlightBudget(maxChars: 10, maxLines: 2);
      expect(tight.allows('0123456789'), isTrue);
      expect(tight.allows('0123456789A'), isFalse);
    });
  });

  group('控制器降级', () {
    testWidgets('超预算时不生成 token，且 highlightDisabled 为真', (WidgetTester tester) async {
      final HighlightingTextEditingController controller =
          HighlightingTextEditingController(
        text: '',
        language: null,
      )..budget = const HighlightBudget(maxChars: 20, maxLines: 5);
      addTearDown(controller.dispose);

      late TextSpan span;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (BuildContext context) {
              span = controller.buildTextSpan(
                context: context,
                style: const TextStyle(),
                withComposing: false,
              );
              return const SizedBox();
            },
          ),
        ),
      );

      // 小文本：正常（这里没有语言，也会走 tokenize，但至少不是整段纯文本兜底）
      expect(controller.highlightDisabled, isFalse);

      controller.text = 'x' * 40; // 超过 20 字符预算
      expect(controller.highlightDisabled, isTrue);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (BuildContext context) {
              span = controller.buildTextSpan(
                context: context,
                style: const TextStyle(),
                withComposing: false,
              );
              return const SizedBox();
            },
          ),
        ),
      );

      // 降级后应当是「单段纯文本」，没有子 span
      expect(span.children, isNull);
      expect(span.text, 'x' * 40);
    });
  });
}