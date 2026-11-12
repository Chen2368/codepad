import '../data/models/program_language.dart';
import '../data/models/run_result.dart';
import '../data/models/source_file.dart';
import 'runtime_engine.dart';

/// 当前阶段还没有真实实现的引擎：不伪造输出，直接把原因告诉用户。
///
/// 用在「已切换到真实运行模式，但该语言缺少运行时」的情况，
/// 例如 C++（需要 clang，尚未内置）与 Python（Phase 4）。
class UnavailableRuntimeEngine implements RuntimeEngine {
  UnavailableRuntimeEngine({required this.language, required this.reason});

  @override
  final ProgramLanguage language;

  final String reason;

  bool _running = false;

  @override
  bool get isRunning => _running;

  @override
  bool get supportsInput => false;

  @override
  String buildCommand(SourceFile file) {
    switch (language) {
      case ProgramLanguage.c:
        return 'tcc ${file.path}';
      case ProgramLanguage.cpp:
        return 'clang++ ${file.path}';
      case ProgramLanguage.python:
        return 'python3 ${file.path}';
    }
  }

  @override
  Future<RunResult> run(
    SourceFile file, {
    void Function(String chunk)? onOutput,
    List<SourceFile> projectFiles = const <SourceFile>[],
    List<String> compilerFlags = const <String>[],
  }) async {
    final String message = '⚠️ $reason\n';
    onOutput?.call(message);
    return RunResult(
      status: RunStatus.failed,
      command: buildCommand(file),
      stderrText: reason,
      exitCode: -1,
    );
  }

  @override
  Future<bool> writeInput(String text) async => false;

  @override
  Future<bool> closeInput() async => false;

  @override
  Future<void> cancel() async {}

  @override
  void dispose() {
    _running = false;
  }
}
