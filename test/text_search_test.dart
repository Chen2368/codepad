import 'package:codepad/core/text/text_search.dart';
import 'package:codepad/features/editor/widgets/find_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('查找匹配', () {
    test('不重叠地找出全部命中', () {
      final List<TextMatch> matches = findMatches('aaaa', 'aa');
      expect(matches.map((TextMatch m) => m.start), <int>[0, 2]);
    });

    test('默认区分大小写', () {
      expect(findMatches('Printf printf', 'printf'), hasLength(1));
      expect(
        findMatches('Printf printf', 'printf', caseSensitive: false),
        hasLength(2),
      );
    });

    test('空查询不返回匹配', () {
      expect(findMatches('abc', ''), isEmpty);
      expect(findMatches('', 'abc'), isEmpty);
    });

    test('支持跨行匹配', () {
      const String text = 'int a;\nint b;\n';
      expect(findMatches(text, 'int'), hasLength(2));
    });
  });

  group('前后跳转', () {
    test('从 -1 开始：下一个落在第一处，上一个落在最后一处', () {
      expect(stepIndex(-1, 3, forward: true), 0);
      expect(stepIndex(-1, 3, forward: false), 2);
    });

    test('到头会绕回', () {
      expect(stepIndex(2, 3, forward: true), 0);
      expect(stepIndex(0, 3, forward: false), 2);
    });

    test('没有匹配时返回 -1', () {
      expect(stepIndex(-1, 0, forward: true), -1);
    });
  });

  group('替换', () {
    test('全部替换并返回处数', () {
      final (String text, int count) =
          replaceAllMatches('a+b+a', 'a', 'x');
      expect(text, 'x+b+x');
      expect(count, 2);
    });

    test('替换文本不会被再次匹配（不会无限膨胀）', () {
      final (String text, int count) = replaceAllMatches('a', 'a', 'aa');
      expect(text, 'aa');
      expect(count, 1);
    });

    test('没有匹配时原样返回', () {
      final (String text, int count) = replaceAllMatches('abc', 'z', 'y');
      expect(text, 'abc');
      expect(count, 0);
    });

    test('只替换一处', () {
      const String text = 'int a = 1; int a = 2;';
      final List<TextMatch> matches = findMatches(text, 'int');
      expect(replaceOne(text, matches[1], 'long'), 'int a = 1; long a = 2;');
    });
  });

  group('查找条界面', () {
    testWidgets('输入查询后显示命中计数，能跳转并全部替换', (WidgetTester tester) async {
      final TextEditingController controller =
          TextEditingController(text: 'int a;\nint b;\n');
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: <Widget>[
                FindBar(controller: controller, onClose: () {}),
                Expanded(
                  child: TextField(controller: controller),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.enterText(find.widgetWithText(TextField, '查找'), 'int');
      await tester.pump();

      expect(find.text('1/2'), findsOneWidget);

      // 打开替换行并全部替换
      await tester.tap(find.byTooltip('替换'));
      await tester.pump();
      await tester.enterText(find.widgetWithText(TextField, '替换为'), 'long');
      await tester.pump();
      await tester.tap(find.text('全部替换'));
      await tester.pump();

      expect(controller.text, 'long a;\nlong b;\n');
    });
  });
}
