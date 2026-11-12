import 'package:codepad/data/models/program_language.dart';
import 'package:codepad/data/models/project.dart';
import 'package:codepad/data/models/source_file.dart';
import 'package:codepad/features/editor/editor_controller.dart';
import 'package:flutter_test/flutter_test.dart';

Project _project(String content) {
  return Project(
    id: 'p1',
    name: '测试',
    language: ProgramLanguage.c,
    files: <SourceFile>[SourceFile(path: 'main.c', content: content)],
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );
}

void main() {
  test('撤销能回到上一次内容', () {
    final EditorController controller =
        EditorController(project: _project('int a = 1;\n'));
    addTearDown(controller.dispose);

    controller.updateContent('main.c', 'int a = 2;\n');
    expect(controller.activeFile.content, 'int a = 2;\n');
    expect(controller.canUndo, isTrue);

    controller.undo();
    expect(controller.activeFile.content, 'int a = 1;\n');
    expect(controller.canRedo, isTrue);
  });

  test('重做能回到撤销前的内容', () {
    final EditorController controller =
        EditorController(project: _project('A\n'));
    addTearDown(controller.dispose);

    controller.updateContent('main.c', 'B\n');
    controller.undo();
    controller.redo();
    expect(controller.activeFile.content, 'B\n');
  });

  test('没有历史时撤销是安全的空操作', () {
    final EditorController controller =
        EditorController(project: _project('X\n'));
    addTearDown(controller.dispose);

    controller.undo();
    expect(controller.activeFile.content, 'X\n');
    expect(controller.canUndo, isFalse);
  });

  test('撤销后重新输入会清空重做', () {
    final EditorController controller =
        EditorController(project: _project('1\n'));
    addTearDown(controller.dispose);

    controller.updateContent('main.c', '2\n');
    controller.undo();
    expect(controller.canRedo, isTrue);

    controller.updateContent('main.c', '3\n');
    expect(controller.canRedo, isFalse);
  });
}
