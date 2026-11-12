import '../data/models/program_language.dart';
import '../data/models/run_result.dart';
import '../data/models/source_file.dart';

/// 运行引擎：把源文件编译（若需要）并执行，返回带输出文本的结果。
///
/// Phase 3 起 C 走 [NativeRuntimeEngine]（内置 tcc，真编译真运行）；
/// 其余语言暂时回落到模拟实现或明确报错。
///
/// [onOutput] 用于流式回传输出片段，界面每收到一段就追加到控制台，
/// 避免出现“必须等程序跑完才能看到任何输出”的体验问题。
abstract class RuntimeEngine {
  /// 该引擎负责的语言。
  ProgramLanguage get language;

  /// 是否正在执行。
  bool get isRunning;

  /// 是否支持向运行中的程序写标准输入。
  bool get supportsInput => false;

  /// 生成将要执行的命令行（用于控制台回显，不负责真正执行）。
  String buildCommand(SourceFile file);

  /// 执行源文件。
  ///
  /// [projectFiles] 是同一工程内的其它文件：真实编译器会把它们一起写到临时目录，
  /// 这样 `#include "util.h"` 才能找到同目录下的头文件；C 引擎还会把其中
  /// 不含 `main()` 的 `.c` 一起编译链接。
  Future<RunResult> run(
    SourceFile file, {
    void Function(String chunk)? onOutput,
    List<SourceFile> projectFiles = const <SourceFile>[],
    List<String> compilerFlags = const <String>[],
  });

  /// 向正在运行的程序投递标准输入（用于 scanf / input）。
  /// 返回 false 表示当前引擎或当前状态不支持。
  Future<bool> writeInput(String text) async => false;

  /// 关闭标准输入（发送 EOF），让 `scanf` / `getchar` 循环正常结束。
  Future<bool> closeInput() async => false;

  /// 请求取消当前执行（例如死循环时用户点“停止”）。
  Future<void> cancel();

  void dispose();
}
