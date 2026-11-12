import 'dart:io';

import 'package:path/path.dart' as p;

import '../data/models/program_language.dart';
import '../data/models/run_result.dart';
import '../data/models/source_file.dart';
import 'compile_diagnostic.dart';
import 'native_toolchain.dart';
import 'runtime_engine.dart';

/// Phase 3：真实的 C 编译执行。
///
/// 工作方式：把源码写到临时目录，然后调用内置的 tcc 执行 `tcc a.c b.c -run`。
/// tcc 在**自己的进程内**把 C 代码编译成内存中的机器码再执行，
/// 因此不需要先产出可执行文件、也不需要再次 `execve`（绕开 Android 对应用数据目录的限制）。
///
/// 多文件规则（0.3.2 修正）：**一个 `.c` 文件 = 一个可运行的目标**。
/// 只有「不含 `main()`」的 `.c` 才会作为辅助单元参与编译；
/// 其它带 `main()` 的文件不参与（它们各自点运行即可单独跑），否则必然重复定义 `main`。
class NativeRuntimeEngine implements RuntimeEngine {
  NativeRuntimeEngine({
    required this.language,
    required this.workDir,
    ToolchainGateway? toolchain,
    this.extraArgs = const <String>[],
    this.multiFile = true,
  }) : _toolchain = toolchain ?? NativeToolchain();

  @override
  final ProgramLanguage language;

  /// 源文件落地目录（应用缓存目录下的 run/）。
  final Directory workDir;

  /// 追加给编译器的参数（例如 -lm、-DSOME_FLAG）。
  final List<String> extraArgs;

  /// 是否把不含 `main()` 的其它 `.c` 一起编译（设置页可关，关掉即「只编当前文件」）。
  final bool multiFile;

  final ToolchainGateway _toolchain;

  bool _running = false;
  bool _cancelled = false;

  @override
  bool get isRunning => _running;

  @override
  bool get supportsInput => true;

  @override
  String buildCommand(SourceFile file) => 'tcc ${file.fileName} -run';

  @override
  Future<RunResult> run(
    SourceFile file, {
    void Function(String chunk)? onOutput,
    List<SourceFile> projectFiles = const <SourceFile>[],
    List<String> compilerFlags = const <String>[],
  }) async {
    _running = true;
    _cancelled = false;
    final Stopwatch watch = Stopwatch()..start();

    void emit(String chunk) => onOutput?.call(chunk);

    try {
      final Directory projectDir = Directory(p.join(workDir.path, _workspaceName(file)));
      // 每次运行都用干净目录，避免上一次残留的源文件/头文件影响本次编译
      if (await projectDir.exists()) {
        await projectDir.delete(recursive: true);
      }
      await projectDir.create(recursive: true);

      List<SourceFile> units = _selectUnits(file, projectFiles, emit);
      // 工程里的所有文件都落盘（.h 不参与编译，但需要被 #include 找到），
      // 只有 units 里的 .c 会交给 tcc。
      final Map<String, String> written = await _materialize(
        projectDir,
        _allFiles(file, projectFiles),
      );
      List<String> sourcePaths = <String>[
        for (final SourceFile unit in units)
          if (written[unit.path] != null) written[unit.path]!,
      ];

      if (sourcePaths.isEmpty) {
        const String message = '没有可编译的 .c 文件（当前文件可能已被重命名或内容为空）\n';
        emit(message);
        return RunResult(
          status: RunStatus.failed,
          command: buildCommand(file),
          stderrText: message,
          exitCode: -1,
          duration: watch.elapsed,
        );
      }

      String command = _commandFor(units);

      Future<RunProcessResult> execute(
        List<String> paths,
        StringBuffer outBuffer,
        StringBuffer errBuffer,
      ) {
        return _toolchain.run(
          sources: paths,
          args: extraArgs,
          flags: compilerFlags,
          onLine: (String stream, String text) {
            if (stream == 'info') {
              // 原生侧回显的完整命令行，属于日志，不混进程序输出
              return;
            }
            // 把 /data/.../run/main/main.c 这类绝对路径缩成 main.c，控制台才看得清
            final String short = _shorten(text, projectDir);
            final String chunk = '$short\n';
            if (stream == 'stderr') {
              errBuffer.write(chunk);
            } else {
              outBuffer.write(chunk);
            }
            emit(chunk);
          },
        );
      }

      emit('\$ $command\n');

      if (_cancelled) {
        return RunResult(
          status: RunStatus.cancelled,
          command: command,
          duration: watch.elapsed,
        );
      }

      StringBuffer stdoutBuffer = StringBuffer();
      StringBuffer stderrBuffer = StringBuffer();
      RunProcessResult result = await execute(sourcePaths, stdoutBuffer, stderrBuffer);

      // 兜底：多文件编译在报「链接类」错误时，自动退回只编当前文件重试一次。
      // 只认「符号/重复定义」这类真正可能由多文件引起的诊断；缺头文件、语法错误等
      // 与文件数量无关，重试只会多打一遍同样的报错（0.3.2 日志里就刷了两遍）。
      if (sourcePaths.length > 1 &&
          !result.succeeded &&
          result.error == null &&
          !_cancelled &&
          _looksLikeMultiFileProblem(stderrBuffer.toString())) {
        emit('… 多文件编译失败，改为只编译 ${units.first.fileName} 重试一次'
            '（设置里可以关闭「多文件编译」）\n');
        command = _commandFor(<SourceFile>[units.first]);
        stdoutBuffer = StringBuffer();
        stderrBuffer = StringBuffer();
        result = await execute(<String>[sourcePaths.first], stdoutBuffer, stderrBuffer);
      }

      if (_cancelled) {
        return RunResult(
          status: RunStatus.cancelled,
          command: command,
          stdoutText: stdoutBuffer.toString(),
          stderrText: stderrBuffer.toString(),
          duration: watch.elapsed,
        );
      }

      if (result.error != null) {
        final String message = '${result.error}\n';
        stderrBuffer.write(message);
        emit(message);
        return RunResult(
          status: RunStatus.failed,
          command: command,
          stdoutText: stdoutBuffer.toString(),
          stderrText: stderrBuffer.toString(),
          exitCode: result.exitCode,
          duration: watch.elapsed,
        );
      }

      // 链接期「找不到符号」是最常见、也最容易被误判的失败。
      // 先尝试**自动补救**：若缺失的符号定义在工程里某个没参与编译的 .c 中，
      // 就把它们一起编进去重试一次（即使用户关掉了「多文件编译」——
      // 这种情况下不开这个开关程序就真的跑不起来，替他打开比让他去翻设置好）。
      if (!result.succeeded) {
        final List<SourceFile> rescued = _rescueUnits(
          stderrBuffer.toString(),
          units,
          _allFiles(file, projectFiles),
        );
        if (rescued.isNotEmpty && !_cancelled) {
          final String names = rescued.map((SourceFile f) => f.path).join('、');
          final String note = multiFile
              ? '… 缺少的实现定义在 $names，连带编译再试一次\n'
              : '… 设置里关闭了「多文件编译」，但缺少的实现定义在 $names，'
                  '本次自动带上重试（可到设置里打开「多文件编译」）\n';
          emit(note);
          units = <SourceFile>[...units, ...rescued];
          final List<String> mergedPaths = <String>[
            ...sourcePaths,
            for (final SourceFile unit in rescued)
              if (written[unit.path] != null) written[unit.path]!,
          ];
          command = _commandFor(units);
          stdoutBuffer = StringBuffer();
          stderrBuffer = StringBuffer();
          result = await execute(mergedPaths, stdoutBuffer, stderrBuffer);
          sourcePaths = mergedPaths;
        }
      }

      // 补救后仍失败：给一条能直接照做的说明
      if (!result.succeeded) {
        final String? hint = _explainUndefinedSymbol(
          stderrBuffer.toString(),
          units,
          _allFiles(file, projectFiles),
        );
        if (hint != null) {
          emit(hint);
          stderrBuffer.write(hint);
        }
      }

      return RunResult(
        status: result.succeeded ? RunStatus.success : RunStatus.failed,
        command: command,
        stdoutText: stdoutBuffer.toString(),
        stderrText: stderrBuffer.toString(),
        exitCode: result.exitCode,
        duration: result.durationMs > 0
            ? Duration(milliseconds: result.durationMs)
            : watch.elapsed,
      );
    } catch (error) {
      final String message = '运行失败：$error\n';
      emit(message);
      return RunResult(
        status: RunStatus.failed,
        command: buildCommand(file),
        stderrText: message,
        exitCode: -1,
        duration: watch.elapsed,
      );
    } finally {
      _running = false;
    }
  }

  @override
  Future<bool> writeInput(String text) => _toolchain.writeStdin(text);

  @override
  Future<bool> closeInput() => _toolchain.closeStdin();

  @override
  Future<void> cancel() async {
    _cancelled = true;
    await _toolchain.cancel();
  }

  @override
  void dispose() {
    _cancelled = true;
    _running = false;
  }

  /// 展示给用户看的命令行。注意 `-run` 在源文件之后：tcc 把 `-run` 之后的内容
  /// 全部当作被运行程序的参数，写在前面会让后面的源文件根本不参与编译。
  String _commandFor(List<SourceFile> units) =>
      'tcc ${units.map((SourceFile f) => f.fileName).join(' ')} -run';

  /// 决定这次编译哪些 .c 文件（第一项是入口）。
  ///
  /// 规则：
  /// 1. 当前文件有 `main()` → 它就是入口；
  /// 2. 当前文件没有 `main()`，而工程里恰好另一个 .c 有 → 用那个作入口（并提示）；
  /// 3. 辅助单元 = 其它**不含 `main()`** 的 `.c`（这样 `util.c` 里的函数能直接用）；
  /// 4. 其它带 `main()` 的文件一律不参与（它们各自是独立目标，否则必然重复定义 main）。
  List<SourceFile> _selectUnits(
    SourceFile current,
    List<SourceFile> projectFiles,
    void Function(String chunk) emit,
  ) {
    final List<SourceFile> others = projectFiles
        .where((SourceFile f) => f.path != current.path && _isCTranslationUnit(f))
        .toList();

    SourceFile entry = current;
    if (!_definesMain(current.content)) {
      final List<SourceFile> candidates =
          others.where((SourceFile f) => _definesMain(f.content)).toList();
      if (candidates.length == 1) {
        entry = candidates.first;
        emit('… ${current.path} 没有 main()，本次以 ${entry.path} 作为入口\n');
      }
    }

    if (!multiFile) {
      return <SourceFile>[entry];
    }

    final List<SourceFile> helpers = others
        .where((SourceFile f) => f.path != entry.path && !_definesMain(f.content))
        .toList();
    final List<SourceFile> skippedMains = others
        .where((SourceFile f) => f.path != entry.path && _definesMain(f.content))
        .toList();

    if (skippedMains.isNotEmpty) {
      final String names =
          skippedMains.map((SourceFile f) => f.path).join('、');
      emit('… $names 也定义了 main()，本次不参与编译；'
          '想看它们运行，切到对应文件再点「运行」\n');
    }

    return <SourceFile>[entry, ...helpers];
  }

  /// 找出「缺失符号的定义所在、且这次没参与编译」的 `.c`（按出现顺序去重）。
  ///
  /// 只认「.c 且没有 main()」的文件：有 main 的文件加进来会撞车，
  /// 头文件不产生目标码，加了也没用。
  List<SourceFile> _rescueUnits(
    String stderr,
    List<SourceFile> units,
    List<SourceFile> allFiles,
  ) {
    final Set<String> compiledPaths = <String>{
      for (final SourceFile unit in units) unit.path,
    };
    final Set<String> symbols = <String>{
      for (final RegExpMatch m
          in RegExp(r"undefined symbol '([A-Za-z_]\w*)'").allMatches(stderr))
        m.group(1)!,
    };
    if (symbols.isEmpty) {
      return const <SourceFile>[];
    }

    final List<SourceFile> rescued = <SourceFile>[];
    for (final String symbol in symbols) {
      for (final SourceFile candidate in allFiles) {
        if (compiledPaths.contains(candidate.path)) {
          continue;
        }
        if (!candidate.path.endsWith('.c')) {
          continue;
        }
        if (_definesMain(candidate.content)) {
          continue;
        }
        if (!_definesSymbol(candidate.content, symbol)) {
          continue;
        }
        if (rescued.any((SourceFile f) => f.path == candidate.path)) {
          break;
        }
        rescued.add(candidate);
        compiledPaths.add(candidate.path);
        break;
      }
    }
    return rescued;
  }

  /// 解析 `undefined symbol 'X'`，说明这个符号到底在哪、为什么没编进来。
  ///
  /// 三种结论分别给不同的下一步动作，而不是笼统地「检查 #include」：
  /// 1. 定义在工程里的某个 `.c`，但这次没参与编译 → 说清原因（开关关着 / 有 main 被跳过）；
  /// 2. 定义在已编译的文件里 → 多半是 `static` 或条件编译没走到；
  /// 3. 工程里根本没定义 → 才是真的漏了 #include 或需要链接库。
  String? _explainUndefinedSymbol(
    String stderr,
    List<SourceFile> units,
    List<SourceFile> allFiles,
  ) {
    final RegExpMatch? match =
        RegExp(r"undefined symbol '([A-Za-z_]\w*)'").firstMatch(stderr);
    if (match == null) {
      return null;
    }
    final String symbol = match.group(1)!;
    final Set<String> compiledPaths = <String>{
      for (final SourceFile unit in units) unit.path,
    };

    SourceFile? definingFile;
    for (final SourceFile candidate in allFiles) {
      if (candidate.path.endsWith('.h')) {
        continue; // 头文件只声明，不算定义
      }
      if (_definesSymbol(candidate.content, symbol)) {
        definingFile = candidate;
        break;
      }
    }

    if (definingFile == null) {
      final int cFiles =
          allFiles.where((SourceFile f) => f.path.endsWith('.c')).length;
      if (cFiles <= 1) {
        return '↳ 工程里只有 1 个 .c 文件，没有谁定义 `$symbol`：'
            '要么把函数写进本文件，要么新建一个 .c 放实现。\n';
      }
      return '↳ 工程里没有任何文件定义 `$symbol`：'
          '检查是不是漏了 #include，或用了需要额外链接的库。\n';
    }

    if (compiledPaths.contains(definingFile.path)) {
      return '↳ `$symbol` 定义在 ${definingFile.path}（已参与编译），'
          '多半被声明成了 static，或定义在没走到的 #if 分支里。\n';
    }

    if (_definesMain(definingFile.content)) {
      return '↳ `$symbol` 定义在 ${definingFile.path}，但它也写了 main()，'
          '本次被跳过（一个程序只能有一个 main）。请切到 ${definingFile.path} 再运行。\n';
    }

    if (!multiFile) {
      return '↳ `$symbol` 定义在 ${definingFile.path}，但设置里关闭了「多文件编译」，'
          '所以这次只编了 ${units.first.path}。\n'
          '　 打开：设置 → 编译 → 多文件编译。\n';
    }

    return '↳ `$symbol` 定义在 ${definingFile.path}，但该文件不是 .c（或已被重命名），'
        '所以没有参与编译。\n';
  }

  /// 极简「是否定义了该函数」判断：形如 `类型 名字(...)  {`，且不是声明（以 `;` 结束）。
  bool _definesSymbol(String content, String symbol) {
    final RegExp definition = RegExp(
      r'^[ \t]*(?:static[ \t]+)?[A-Za-z_][A-Za-z0-9_ \t\*]*\b' +
          RegExp.escape(symbol) +
          r'[ \t]*\([^;{}]*\)[ \t\r\n]*\{',
      multiLine: true,
    );
    return definition.hasMatch(content);
  }

  /// 把工程内文件写到临时目录，返回「相对路径 → 绝对路径」。
  Future<Map<String, String>> _materialize(
    Directory projectDir,
    List<SourceFile> files,
  ) async {
    final Map<String, String> paths = <String, String>{};
    for (final SourceFile source in files) {
      final File target = File(
        p.join(projectDir.path, source.path.replaceAll('/', Platform.pathSeparator)),
      );
      await target.parent.create(recursive: true);
      await target.writeAsString(source.content);
      paths[source.path] = target.path;
    }
    return paths;
  }

  /// 入口文件在前，其余去重。
  List<SourceFile> _allFiles(SourceFile entry, List<SourceFile> projectFiles) {
    final Map<String, SourceFile> unique = <String, SourceFile>{entry.path: entry};
    for (final SourceFile file in projectFiles) {
      unique.putIfAbsent(file.path, () => file);
    }
    return unique.values.toList();
  }

  String _shorten(String line, Directory projectDir) {
    return line.replaceAll('${projectDir.path}/', '').replaceAll(projectDir.path, '');
  }

  String _workspaceName(SourceFile file) {
    return file.path.replaceAll('/', '_').replaceAll('\\', '_');
  }

  static final RegExp _mainPattern = RegExp(
    r'^[ \t]*(?:int|void|signed|unsigned)?[ \t]*main[ \t]*\(',
    multiLine: true,
  );

  static bool _definesMain(String source) => _mainPattern.hasMatch(source);

  /// 这条 stderr 是否像「多文件才出的问题」：符号未定义 / 重复定义。
  static bool _looksLikeMultiFileProblem(String stderr) {
    final List<CompileDiagnostic> diagnostics =
        CompileDiagnosticParser.parse(stderr);
    if (diagnostics.isEmpty) {
      return false;
    }
    final RegExp pattern = RegExp(
      r'undefined symbol|undefined reference|multiple definition|duplicate symbol|redefinition',
      caseSensitive: false,
    );
    return diagnostics.any(
      (CompileDiagnostic d) => pattern.hasMatch(d.message),
    );
  }

  /// 只有 `.c` 参与编译；`.h` 只是被 #include 的声明，不能单独编译。
  static bool _isCTranslationUnit(SourceFile file) =>
      file.path.toLowerCase().endsWith('.c');
}
