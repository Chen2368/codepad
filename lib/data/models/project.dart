import 'program_language.dart';
import 'source_file.dart';

/// 一个编程工程：包含若干源文件，以及创建 / 更新时间。
class Project {
  const Project({
    required this.id,
    required this.name,
    required this.language,
    required this.files,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final ProgramLanguage language;
  final List<SourceFile> files;
  final DateTime createdAt;
  final DateTime updatedAt;

  int get fileCount => files.length;

  /// 打开工程时默认选中的文件：优先语言默认文件，其次同语言文件，最后第一个文件。
  SourceFile? get entryFile {
    if (files.isEmpty) {
      return null;
    }
    final String preferred = language.defaultFileName;
    for (final SourceFile file in files) {
      if (file.path == preferred) {
        return file;
      }
    }
    for (final SourceFile file in files) {
      if (file.language == language) {
        return file;
      }
    }
    return files.first;
  }

  SourceFile? fileByPath(String path) {
    for (final SourceFile file in files) {
      if (file.path == path) {
        return file;
      }
    }
    return null;
  }

  Project copyWith({
    String? name,
    ProgramLanguage? language,
    List<SourceFile>? files,
    DateTime? updatedAt,
  }) {
    return Project(
      id: id,
      name: name ?? this.name,
      language: language ?? this.language,
      files: files ?? this.files,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() => 'Project($name, ${language.label}, $fileCount files)';
}
