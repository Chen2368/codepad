import '../../runtime/compile_diagnostic.dart';

/// 控制台消息级别，决定文字颜色。
enum ConsoleLevel {
  /// 系统提示（开始运行、结束等）。
  info,

  /// 程序标准输出。
  output,

  /// 错误 / 非零退出码 / 编译诊断。
  error,

  /// 成功结束。
  success,

  /// 用户通过控制台输入框投递给程序的标准输入回显。
  input,

  /// 编译器的中文提示（由诊断解析出来）。
  hint,
}

/// 控制台中的一行消息。
class ConsoleMessage {
  const ConsoleMessage({
    required this.text,
    this.level = ConsoleLevel.output,
    this.diagnostic,
  });

  final String text;
  final ConsoleLevel level;

  /// 若这一行是编译诊断（`main.c:12: error: ...`），带上解析结果，
  /// 界面据此把它渲染成「可点击跳转」的行。
  final CompileDiagnostic? diagnostic;

  /// 是否可以点击跳到源码位置。
  bool get isJumpable => diagnostic?.hasLocation ?? false;

  @override
  String toString() => '[$level] $text';
}
