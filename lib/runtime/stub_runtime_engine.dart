import '../data/models/program_language.dart';
import '../data/models/run_result.dart';
import '../data/models/source_file.dart';
import 'runtime_engine.dart';

/// 骨架阶段的“模拟执行”引擎：不真正调用编译器，只按节奏吐出模拟输出。
///
/// 它的意义是先把状态机（空闲 → 运行中 → 成功 / 失败 / 取消）、
/// 流式输出、命令行回显这几条链路跑通，后续替换为真实引擎时界面无需改动。
class StubRuntimeEngine implements RuntimeEngine {
  StubRuntimeEngine({
    required this.language,
    this.compileDelay = const Duration(milliseconds: 420),
    this.lineDelay = const Duration(milliseconds: 80),
  });

  @override
  final ProgramLanguage language;

  /// 模拟编译耗时。
  final Duration compileDelay;

  /// 每行输出之间的间隔。
  final Duration lineDelay;

  bool _running = false;
  bool _cancelled = false;

  @override
  bool get isRunning => _running;

  @override
  bool get supportsInput => false;

  @override
  String buildCommand(SourceFile file) {
    final String binary = _binaryName(file);
    switch (language) {
      case ProgramLanguage.c:
        return 'gcc ${file.path} -o $binary && ./$binary';
      case ProgramLanguage.cpp:
        return 'g++ ${file.path} -std=c++17 -O2 -o $binary && ./$binary';
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
    final Stopwatch watch = Stopwatch()..start();
    _running = true;
    _cancelled = false;

    final String command = buildCommand(file);
    _emit(onOutput, '\$ $command\n');

    await Future<void>.delayed(compileDelay);
    if (_cancelled) {
      return _cancelledResult(command, watch, onOutput);
    }

    final String source = file.content;

    if (source.trim().isEmpty) {
      const String message = 'error: 源文件为空，没有可编译的内容。';
      _emit(onOutput, '$message\n');
      _running = false;
      return RunResult(
        status: RunStatus.failed,
        command: command,
        stderrText: message,
        exitCode: 1,
        duration: watch.elapsed,
      );
    }

    final bool simulatedCompileError =
        source.contains('编译失败') || source.contains('syntax error');
    if (simulatedCompileError) {
      const String message =
          'error: 源文件中出现了「编译失败 / syntax error」标记，这是模拟的编译报错场景。';
      _emit(onOutput, '$message\n');
      _running = false;
      return RunResult(
        status: RunStatus.failed,
        command: command,
        stderrText: message,
        exitCode: 1,
        duration: watch.elapsed,
      );
    }

    if (language == ProgramLanguage.python) {
      _emit(onOutput, '解释器启动，开始执行。\n');
    } else {
      _emit(onOutput, '正在编译 ${file.path} ...\n');
      await Future<void>.delayed(lineDelay * 3);
      if (_cancelled) {
        return _cancelledResult(command, watch, onOutput);
      }
      _emit(onOutput, '编译完成，开始执行。\n');
    }

    final List<String> lines = _simulatedOutput(file);
    final StringBuffer buffer = StringBuffer();
    for (final String line in lines) {
      await Future<void>.delayed(lineDelay);
      if (_cancelled) {
        break;
      }
      buffer.writeln(line);
      _emit(onOutput, '$line\n');
    }

    if (_cancelled) {
      _running = false;
      return RunResult(
        status: RunStatus.cancelled,
        command: command,
        stdoutText: buffer.toString(),
        duration: watch.elapsed,
      );
    }

    _running = false;
    return RunResult(
      status: RunStatus.success,
      command: command,
      stdoutText: buffer.toString(),
      exitCode: 0,
      duration: watch.elapsed,
    );
  }

  @override
  Future<bool> writeInput(String text) async => false;

  @override
  Future<bool> closeInput() async => false;

  @override
  Future<void> cancel() async {
    _cancelled = true;
  }

  @override
  void dispose() {
    _cancelled = true;
    _running = false;
  }

  RunResult _cancelledResult(
    String command,
    Stopwatch watch,
    void Function(String chunk)? onOutput,
  ) {
    _running = false;
    _emit(onOutput, '用户已取消本次运行。\n');
    return RunResult(
      status: RunStatus.cancelled,
      command: command,
      duration: watch.elapsed,
    );
  }

  void _emit(void Function(String chunk)? onOutput, String chunk) {
    onOutput?.call(chunk);
  }

  String _binaryName(SourceFile file) {
    final String name = file.fileName;
    final int index = name.lastIndexOf('.');
    return index <= 0 ? 'a.out' : name.substring(0, index);
  }

  /// 依据源码特征给出一点“看起来像真的”的模拟输出，便于验证控制台链路。
  List<String> _simulatedOutput(SourceFile file) {
    final String source = file.content;
    if (source.contains('std::sort')) {
      return <String>[
        '排序结果: 1 2 3 5 7 9 ',
        '（模拟输出：Phase 3 接入 NDK clang 后即为 g++ 的真实结果）',
      ];
    }
    if (source.contains('fib(')) {
      return <String>[
        '前 10 项斐波那契数列: [0, 1, 1, 2, 3, 5, 8, 13, 21, 34]',
        '（模拟输出：Phase 4 接入嵌入式 Python 解释器后即为真实结果）',
      ];
    }
    return <String>[
      'Hello, CodePad!',
      '（模拟输出：当前没有可用的本地编译器，真实结果需 Phase 3 的内置 tcc）',
    ];
  }
}
