import 'package:codepad/core/text/project_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('单文件命中定位', () {
    test('给出正确的行号、列号与行内容', () {
      const String content = 'int main(void) {\n    int a = 1;\n    int b = 2;\n}\n';
      final List<ProjectMatch> matches = matchInFile('main.c', content, 'int');

      expect(matches, hasLength(3));
      expect(matches[0].line, 1);
      expect(matches[0].column, 1);
      expect(matches[1].line, 2);
      expect(matches[1].column, 5);
      expect(matches[1].preview, 'int a = 1;');
    });

    test('命中的偏移能直接用于选中', () {
      const String content = 'abc abc';
      final ProjectMatch match = matchInFile('a.c', content, 'abc')[0];
      expect(content.substring(match.start, match.start + match.length), 'abc');
    });

    test('区分大小写', () {
      const String content = 'Printf printf';
      expect(matchInFile('a.c', content, 'printf'), hasLength(1));
      expect(
        matchInFile('a.c', content, 'printf', caseSensitive: false),
        hasLength(2),
      );
    });

    test('空查询返回空结果', () {
      expect(matchInFile('a.c', 'abc', ''), isEmpty);
    });
  });

  group('工程搜索', () {
    test('跨文件收集并按路径排序', () {
      final Map<String, String> files = <String, String>{
        'util.c': 'int f(void) { return 1; }',
        'main.c': 'int main(void) { return 0; }',
      };
      final List<ProjectMatch> results = searchProject(files, 'int');
      expect(results.map((ProjectMatch m) => m.path).toSet(),
          <String>{'main.c', 'util.c'});
      // main.c 排在 util.c 前面（按路径排序）
      expect(results.first.path, 'main.c');
    });

    test('结果数量受上限约束', () {
      final Map<String, String> files = <String, String>{
        'a.c': 'x\n' * 50,
      };
      expect(searchProject(files, 'x', maxResults: 5), hasLength(5));
    });

    test('预览过长会截断', () {
      // 一行很长、只含一个命中，避免命中数影响断言
      final String longLine = 'y${'z' * 300}';
      final List<ProjectMatch> results =
          searchProject(<String, String>{'a.c': longLine}, 'y');
      expect(results, hasLength(1));
      expect(results.single.preview.endsWith('…'), isTrue);
      expect(results.single.preview.length, lessThanOrEqualTo(121));
    });
  });
}
