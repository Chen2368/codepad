import 'package:codepad/core/settings/settings_controller.dart';
import 'package:codepad/core/text/completion.dart';
import 'package:codepad/features/editor/highlight/code_palette.dart';
import 'package:codepad/features/editor/widgets/completion_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void _ignore(CompletionItem _) {}

void main() {
  group('补全：前缀识别', () {
    test('光标在标识符里能找到起点', () {
      expect(wordPrefixStart('int pr', 6), 4);
      expect(wordPrefixStart('abc', 3), 0);
    });

    test('不在标识符里时返回 -1', () {
      expect(wordPrefixStart('int  ', 5), -1);
      expect(wordPrefixStart('a + ', 4), -1);
    });

    test('数字开头不做补全', () {
      expect(wordPrefixStart('3.14', 4), -1);
    });
  });

  group('补全：候选', () {
    test('前缀命中排在前面，且短的优先', () {
      final List<CompletionItem> items = suggestCompletions('pr', 2);
      expect(items, isNotEmpty);
      expect(items.first.label, 'printf');
    });

    test('内置片段可被命中（main / fori）', () {
      expect(suggestCompletions('mai', 3).first.label, 'main');
      expect(
        suggestCompletions('fori', 4).map((CompletionItem i) => i.label),
        contains('fori'),
      );
    });

    test('空前缀或未知前缀不给建议', () {
      expect(suggestCompletions('int ', 4), isEmpty);
      expect(suggestCompletions('zzzz', 4), isEmpty);
    });

    test('候选数量受上限约束', () {
      expect(suggestCompletions('s', 1, limit: 3).length, lessThanOrEqualTo(3));
    });
  });

  group('补全：插入', () {
    test('替换前缀并把光标放进括号里', () {
      final ({String text, int caret}) result =
          applyCompletion('int x;\npr', 9, cCompletions.firstWhere(
                (CompletionItem i) => i.label == 'printf',
              ));
      expect(result.text, 'int x;\nprintf("");');
      // 光标落在引号之间
      expect(result.text.substring(result.caret - 1, result.caret + 1), '""');
    });

    test('片段插入后光标落在循环体缩进处', () {
      final CompletionItem fori = cCompletions.firstWhere(
        (CompletionItem i) => i.label == 'fori',
      );
      final ({String text, int caret}) result = applyCompletion('fori', 4, fori);
      expect(result.text, contains('for (int i = 0;'));
      // 光标落在循环体的缩进处，而不是贴在大括号后面
      expect(result.text.substring(result.caret - 4, result.caret), '    ');
      expect(result.text[result.caret], '\n');
    });
  });

  group('代码配色主题', () {
    test('按设置挑配色', () {
      expect(
        CodePalette.resolve(CodeThemeId.auto, Brightness.dark).keyword,
        CodePalette.dark.keyword,
      );
      expect(
        CodePalette.resolve(CodeThemeId.oneDark, Brightness.light).keyword,
        CodePalette.oneDark.keyword,
      );
      expect(
        CodePalette.resolve(CodeThemeId.paper, Brightness.dark).keyword,
        CodePalette.paper.keyword,
      );
    });

    test('设置里能持久化配色编号', () {
      final SettingsController settings = SettingsController();
      expect(settings.codeTheme, CodeThemeId.auto);
      settings.setCodeTheme(CodeThemeId.oneDark);
      expect(settings.codeTheme, CodeThemeId.oneDark);
      expect(CodeThemeId.fromId('one_dark'), CodeThemeId.oneDark);
      expect(CodeThemeId.fromId('乱写'), CodeThemeId.auto);
    });
  });

  group('补全条界面', () {
    testWidgets('没有候选时不占位置', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CompletionStrip(
              items: <CompletionItem>[],
              onPick: _ignore,
            ),
          ),
        ),
      );
      expect(find.byType(InkWell), findsNothing);
    });

    testWidgets('点候选会回传该条目', (WidgetTester tester) async {
      CompletionItem? picked;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CompletionStrip(
              items: const <CompletionItem>[
                CompletionItem(label: 'printf', insert: 'printf("");', detail: 'stdio'),
                CompletionItem(label: 'fori', insert: 'for (;;) {}', isSnippet: true),
              ],
              onPick: (CompletionItem item) => picked = item,
            ),
          ),
        ),
      );
      expect(find.text('printf'), findsOneWidget);
      await tester.tap(find.text('fori'));
      expect(picked?.isSnippet, isTrue);
    });
  });
}
