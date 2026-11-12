import 'package:codepad/core/text/line_offsets.dart';
import 'package:codepad/data/models/program_language.dart';
import 'package:codepad/data/models/project.dart';
import 'package:codepad/data/models/source_file.dart';
import 'package:codepad/features/editor/editor_controller.dart';
import 'package:codepad/runtime/compile_diagnostic.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Project project() {
    final DateTime now = DateTime(2026, 1, 1);
    return Project(
      id: 'p1',
      name: '测试工程',
      language: ProgramLanguage.c,
      files: <SourceFile>[
        const SourceFile(path: 'main.c', content: 'int main(void) {\n  return 0;\n}\n'),
        const SourceFile(
          path: 'lib/util.c',
          content: 'int add(int a, int b) {\n  return a + b;\n}\nint sub(void){\n  return 0;\n}\n',
        ),
      ],
      createdAt: now,
      updatedAt: now,
    );
  }

  group('点编译错误跳转', () {
    test('跳到另一个文件并定位到对应行', () {
      final EditorController controller = EditorController(project: project());
      addTearDown(controller.dispose);

      expect(controller.activeFile.path, 'main.c');

      controller.jumpToDiagnostic(const CompileDiagnostic(
        severity: DiagnosticSeverity.error,
        message: 'missing return',
        file: 'lib/util.c',
        line: 4,
      ));

      expect(controller.activeFile.path, 'lib/util.c');
      final TextEditingController text = controller.controllerFor(controller.activeFile);
      expect(text.selection.baseOffset, offsetForLine(text.text, 4));
      expect(text.selection.baseOffset, greaterThan(0));
      expect(text.selection.isCollapsed, isTrue);
    });

    test('编译器只给文件名时也能匹配到子目录里的文件', () {
      final EditorController controller = EditorController(project: project());
      addTearDown(controller.dispose);

      controller.jumpToDiagnostic(const CompileDiagnostic(
        severity: DiagnosticSeverity.error,
        message: 'oops',
        file: 'util.c',
        line: 2,
      ));

      expect(controller.activeFile.path, 'lib/util.c');
    });

    test('文件不存在时保持原状并给出提示', () {
      final EditorController controller = EditorController(project: project());
      addTearDown(controller.dispose);

      controller.jumpToDiagnostic(const CompileDiagnostic(
        severity: DiagnosticSeverity.error,
        message: 'oops',
        file: 'gone.c',
        line: 1,
      ));

      expect(controller.activeFile.path, 'main.c');
      expect(controller.consoleMessages.last.text, contains('找不到文件'));
    });

    test('没有位置的诊断不做跳转', () {
      final EditorController controller = EditorController(project: project());
      addTearDown(controller.dispose);

      controller.jumpToDiagnostic(const CompileDiagnostic(
        severity: DiagnosticSeverity.error,
        message: 'file not found',
      ));

      expect(controller.activeFile.path, 'main.c');
    });
  });
}
