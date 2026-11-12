import 'dart:io';

import 'package:codepad/data/models/program_language.dart';
import 'package:codepad/data/models/project.dart';
import 'package:codepad/data/models/source_file.dart';
import 'package:codepad/data/repositories/file_project_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempRoot;
  late FileProjectRepository repository;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('codepad_repo_');
    repository = FileProjectRepository(root: tempRoot);
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  Project sampleProject({List<SourceFile>? files}) {
    final DateTime now = DateTime.now();
    return Project(
      id: 'p-1',
      name: '测试工程',
      language: ProgramLanguage.cpp,
      files: files ??
          <SourceFile>[
            const SourceFile(path: 'main.cpp', content: 'int main() { return 0; }'),
            const SourceFile(path: 'lib/util.h', content: '#pragma once\n'),
          ],
      createdAt: now,
      updatedAt: now,
    );
  }

  test('保存后能完整读回（含子目录与中文内容）', () async {
    final Project project = sampleProject(
      files: <SourceFile>[
        const SourceFile(path: 'main.cpp', content: 'int main() { return 0; }'),
        const SourceFile(path: 'src/工具.py', content: 'print("你好")\n'),
      ],
    );
    await repository.save(project);

    final List<Project> loaded = await repository.loadAll();
    expect(loaded, hasLength(1));
    expect(loaded.single.name, '测试工程');
    expect(loaded.single.language, ProgramLanguage.cpp);
    expect(loaded.single.fileByPath('main.cpp')?.content, 'int main() { return 0; }');
    expect(loaded.single.fileByPath('src/工具.py')?.content, 'print("你好")\n');
  });

  test('重命名文件后磁盘上旧文件被删除', () async {
    await repository.save(sampleProject());
    expect(File(p.join(tempRoot.path, 'p-1', 'files', 'main.cpp')).existsSync(), isTrue);

    final Project renamed = sampleProject(
      files: <SourceFile>[
        const SourceFile(path: 'app.cpp', content: 'int main() { return 1; }'),
        const SourceFile(path: 'lib/util.h', content: '#pragma once\n'),
      ],
    );
    await repository.save(renamed);

    expect(File(p.join(tempRoot.path, 'p-1', 'files', 'main.cpp')).existsSync(), isFalse);
    expect(File(p.join(tempRoot.path, 'p-1', 'files', 'app.cpp')).existsSync(), isTrue);

    final List<Project> loaded = await repository.loadAll();
    expect(loaded.single.files.map((SourceFile f) => f.path),
        unorderedEquals(<String>['app.cpp', 'lib/util.h']));
  });

  test('删除工程会移除整个目录', () async {
    await repository.save(sampleProject());
    await repository.delete('p-1');
    expect(Directory(p.join(tempRoot.path, 'p-1')).existsSync(), isFalse);
    expect(await repository.loadAll(), isEmpty);
  });

  test('忽略非源文件后缀', () async {
    await repository.save(sampleProject());
    final File noise = File(p.join(tempRoot.path, 'p-1', 'files', 'build.log'));
    await noise.writeAsString('log');

    final List<Project> loaded = await repository.loadAll();
    expect(loaded.single.files.any((SourceFile f) => f.path == 'build.log'), isFalse);
  });

  test('没有 meta.json 的目录被跳过', () async {
    await Directory(p.join(tempRoot.path, 'stray')).create(recursive: true);
    expect(await repository.loadAll(), isEmpty);
  });
}
