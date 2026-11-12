import 'program_language.dart';

/// 工程内的一个源文件。
///
/// [path] 是相对工程根目录的路径，例如 `main.cpp` 或 `src/util.cpp`。
class SourceFile {
  const SourceFile({
    required this.path,
    this.content = '',
  });

  final String path;

  /// 文件当前内容（编辑中可能尚未落盘）。
  final String content;

  /// 文件名，如 `main.cpp`。
  String get fileName {
    final int index = path.lastIndexOf('/');
    return index < 0 ? path : path.substring(index + 1);
  }

  /// 所在目录，根目录返回空字符串。
  String get folder {
    final int index = path.lastIndexOf('/');
    return index < 0 ? '' : path.substring(0, index);
  }

  /// 小写后缀，含点；无后缀返回空字符串。
  String get extension {
    final String name = fileName;
    final int index = name.lastIndexOf('.');
    return index < 0 ? '' : name.substring(index).toLowerCase();
  }

  /// 归属语言，无法识别时为 null。
  ProgramLanguage? get language => ProgramLanguage.fromFileName(fileName);

  SourceFile copyWith({String? path, String? content}) {
    return SourceFile(
      path: path ?? this.path,
      content: content ?? this.content,
    );
  }

  @override
  String toString() => 'SourceFile($path, ${content.length} chars)';
}
