import 'package:codepad/data/models/program_language.dart';
import 'package:codepad/data/models/project.dart';
import 'package:codepad/data/models/source_file.dart';
import 'package:codepad/data/repositories/project_repository.dart';
import 'package:codepad/features/editor/editor_controller.dart';
import 'package:flutter_test/flutter_test.dart';

Project buildProject() {
  final DateTime now = DateTime.now();
  return Project(
    id: 'p-1',
    name: '测试工程',
    language: ProgramLanguage.cpp,
    files: <SourceFile>[
      const SourceFile(path: 'main.cpp', content: 'int main() { return 0; }'),
    ],
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('文件操作', () {
    test('新建文件：追加标签、切换激活、拒绝重名与非法后缀', () {
      final EditorController controller = EditorController(project: buildProject());
      addTearDown(controller.dispose);

      expect(controller.createFile('lib/a.cpp'), isNull);
      expect(controller.files, hasLength(2));
      expect(controller.activeFile.path, 'lib/a.cpp');

      expect(controller.createFile('lib/a.cpp'), contains('已存在'));
      expect(controller.createFile('bad.xyz'), contains('不支持'));
      expect(controller.createFile('   '), contains('不能为空'));
    });

    test('路径规范化：反斜杠与多余分隔符', () {
      final EditorController controller = EditorController(project: buildProject());
      addTearDown(controller.dispose);

      expect(controller.createFile(r'\lib\\a.py'), isNull);
      expect(controller.activeFile.path, 'lib/a.py');
      expect(EditorController.normalizePath('/x//y/./z.c'), 'x/y/z.c');
    });

    test('重命名后语言随之更新，重复目标被拒绝', () {
      final EditorController controller = EditorController(project: buildProject());
      addTearDown(controller.dispose);
      controller.createFile('b.py');
      controller.selectPath('b.py');

      expect(controller.renameFile('b.py', 'tool.py'), isNull);
      expect(controller.activeFile.path, 'tool.py');
      expect(controller.activeFile.language, ProgramLanguage.python);

      expect(controller.renameFile('tool.py', 'main.cpp'), contains('已存在'));
      expect(controller.renameFile('missing.cpp', 'x.cpp'), contains('不存在'));
    });

    test('删除文件：保留最后一个文件', () {
      final EditorController controller = EditorController(project: buildProject());
      addTearDown(controller.dispose);

      expect(controller.deleteFile('main.cpp'), contains('保留一个文件'));

      controller.createFile('extra.cpp');
      expect(controller.deleteFile('extra.cpp'), isNull);
      expect(controller.files, hasLength(1));
      expect(controller.activeFile.path, 'main.cpp');
    });
  });

  group('自动保存', () {
    test('编辑后自动落盘到仓库', () async {
      final InMemoryProjectRepository repository = InMemoryProjectRepository();
      final EditorController controller = EditorController(
        project: buildProject(),
        repository: repository,
        autoSaveDelay: const Duration(milliseconds: 10),
      );
      addTearDown(controller.dispose);

      controller.updateContent('main.cpp', 'int main() { return 42; }');
      expect(controller.dirty, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 80));

      final List<Project> saved = await repository.loadAll();
      expect(saved, hasLength(1));
      expect(
        saved.single.fileByPath('main.cpp')?.content,
        'int main() { return 42; }',
      );
      expect(controller.dirty, isFalse);
    });

    test('新建文件同样会落盘', () async {
      final InMemoryProjectRepository repository = InMemoryProjectRepository();
      final EditorController controller = EditorController(
        project: buildProject(),
        repository: repository,
        autoSaveDelay: const Duration(milliseconds: 10),
      );
      addTearDown(controller.dispose);

      controller.createFile('util.cpp');
      await Future<void>.delayed(const Duration(milliseconds: 80));

      final List<Project> saved = await repository.loadAll();
      expect(saved.single.files.map((SourceFile f) => f.path),
          containsAll(<String>['main.cpp', 'util.cpp']));
    });
  });

  group('编辑内容', () {
    test('updateContent 只在首次变脏时重建界面', () {
      final EditorController controller = EditorController(project: buildProject());
      addTearDown(controller.dispose);

      int notifications = 0;
      controller.addListener(() => notifications++);

      controller.updateContent('main.cpp', 'a');
      expect(notifications, 1);
      controller.updateContent('main.cpp', 'ab');
      // 已经是脏状态，不再通知，避免输入卡顿
      expect(notifications, 1);
      expect(controller.activeFile.content, 'ab');
    });
  });
}
