import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/program_language.dart';
import '../models/project.dart';
import '../models/source_file.dart';
import 'project_repository.dart';

/// 基于真实文件系统的工程仓库（Phase 2）。
///
/// 目录结构：
/// ```
/// <root>/<projectId>/meta.json          工程元数据
/// <root>/<projectId>/files/<相对路径>    源文件（保留子目录结构）
/// ```
///
/// 构造函数直接接收 [root]，不依赖 path_provider：
/// 真机由 `main.dart` 传入应用私有目录，单元测试传入临时目录。
class FileProjectRepository implements ProjectRepository {
  FileProjectRepository({required this.root});

  final Directory root;

  static const String metaFileName = 'meta.json';
  static const String filesDirName = 'files';

  /// loadAll 时会作为“源文件”读取的后缀。
  static const Set<String> sourceExtensions = <String>{
    '.c',
    '.h',
    '.cpp',
    '.cc',
    '.cxx',
    '.hpp',
    '.hh',
    '.py',
    '.md',
    '.txt',
  };

  @override
  Future<List<Project>> loadAll() async {
    if (!await root.exists()) {
      return <Project>[];
    }
    final List<Project> projects = <Project>[];
    await for (final FileSystemEntity entity in root.list()) {
      if (entity is! Directory) {
        continue;
      }
      final Project? project = await _readProject(entity);
      if (project != null) {
        projects.add(project);
      }
    }
    projects.sort((Project a, Project b) => b.updatedAt.compareTo(a.updatedAt));
    return projects;
  }

  @override
  Future<Project> save(Project project) async {
    final Directory projectDir = Directory(p.join(root.path, _safeId(project.id)));
    final Directory filesDir = Directory(p.join(projectDir.path, filesDirName));
    await filesDir.create(recursive: true);

    // 1) 写入 / 更新源文件，同时记录磁盘上应保留的路径
    final Set<String> keep = <String>{};
    for (final SourceFile file in project.files) {
      final File target = File(p.join(filesDir.path, _platformPath(file.path)));
      await target.parent.create(recursive: true);
      keep.add(_key(target));
      final bool unchanged = await target.exists() &&
          await target.readAsString() == file.content;
      if (!unchanged) {
        await target.writeAsString(file.content);
      }
    }

    // 2) 删除磁盘上已不存在的文件（覆盖重命名 / 删除文件）
    final List<File> stale = <File>[];
    await for (final FileSystemEntity entity in filesDir.list(recursive: true)) {
      if (entity is File && !keep.contains(_key(entity))) {
        stale.add(entity);
      }
    }
    for (final File file in stale) {
      await file.delete();
    }

    // 3) 写元数据
    final Map<String, Object?> meta = <String, Object?>{
      'id': project.id,
      'name': project.name,
      'language': project.language.name,
      'createdAt': project.createdAt.toIso8601String(),
      'updatedAt': project.updatedAt.toIso8601String(),
    };
    await File(p.join(projectDir.path, metaFileName))
        .writeAsString(const JsonEncoder.withIndent('  ').convert(meta));

    return project;
  }

  @override
  Future<void> delete(String id) async {
    final Directory projectDir = Directory(p.join(root.path, _safeId(id)));
    if (await projectDir.exists()) {
      await projectDir.delete(recursive: true);
    }
  }

  Future<Project?> _readProject(Directory projectDir) async {
    final File meta = File(p.join(projectDir.path, metaFileName));
    if (!await meta.exists()) {
      return null;
    }
    try {
      final Object? decoded = jsonDecode(await meta.readAsString());
      if (decoded is! Map<String, Object?>) {
        return null;
      }
      final String id = decoded['id'] as String? ?? p.basename(projectDir.path);
      final String name = decoded['name'] as String? ?? id;
      final String? languageName = decoded['language'] as String?;
      final ProgramLanguage language = ProgramLanguage.values.firstWhere(
        (ProgramLanguage item) => item.name == languageName,
        orElse: () => ProgramLanguage.cpp,
      );
      final DateTime createdAt =
          DateTime.tryParse(decoded['createdAt'] as String? ?? '') ?? DateTime.now();
      final DateTime updatedAt =
          DateTime.tryParse(decoded['updatedAt'] as String? ?? '') ?? createdAt;

      List<SourceFile> files = await _readFiles(Directory(
        p.join(projectDir.path, filesDirName),
      ));
      if (files.isEmpty) {
        files = <SourceFile>[SourceFile(path: language.defaultFileName)];
      }
      return Project(
        id: id,
        name: name,
        language: language,
        files: files,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
    } on FormatException {
      return null;
    }
  }

  Future<List<SourceFile>> _readFiles(Directory filesDir) async {
    if (!await filesDir.exists()) {
      return <SourceFile>[];
    }
    final List<SourceFile> files = <SourceFile>[];
    await for (final FileSystemEntity entity in filesDir.list(recursive: true)) {
      if (entity is! File) {
        continue;
      }
      final String relative =
          p.relative(entity.path, from: filesDir.path).replaceAll(r'\', '/');
      if (!sourceExtensions.contains(p.extension(relative).toLowerCase())) {
        continue;
      }
      files.add(SourceFile(path: relative, content: await entity.readAsString()));
    }
    files.sort((SourceFile a, SourceFile b) => a.path.compareTo(b.path));
    return files;
  }

  String _platformPath(String relativePath) {
    return relativePath.split('/').where((String s) => s.isNotEmpty).join(p.separator);
  }

  String _key(FileSystemEntity entity) =>
      p.normalize(entity.absolute.path).toLowerCase();

  String _safeId(String id) => id.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');
}
