/// 支持的编程语言。
enum ProgramLanguage {
  c(
    label: 'C',
    defaultFileName: 'main.c',
    extensions: <String>['.c', '.h'],
    compilerHint: 'gcc',
  ),
  cpp(
    label: 'C++',
    defaultFileName: 'main.cpp',
    extensions: <String>['.cpp', '.cc', '.cxx', '.hpp'],
    compilerHint: 'g++',
  ),
  python(
    label: 'Python',
    defaultFileName: 'main.py',
    extensions: <String>['.py'],
    compilerHint: 'python3',
  );

  const ProgramLanguage({
    required this.label,
    required this.defaultFileName,
    required this.extensions,
    required this.compilerHint,
  });

  /// 界面展示名，如 `C++`。
  final String label;

  /// 新建工程时的默认文件名。
  final String defaultFileName;

  /// 归属该语言的文件后缀（小写，含点）。
  final List<String> extensions;

  /// 运行时使用的工具链名称，用于控制台提示与后续真实执行。
  final String compilerHint;

  /// 依据文件名推断语言，无法识别时返回 null。
  static ProgramLanguage? fromFileName(String fileName) {
    final String lower = fileName.toLowerCase();
    for (final ProgramLanguage language in ProgramLanguage.values) {
      for (final String extension in language.extensions) {
        if (lower.endsWith(extension)) {
          return language;
        }
      }
    }
    return null;
  }
}
