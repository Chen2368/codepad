import 'dart:io';

import 'package:codepad/data/models/program_language.dart';
import 'package:codepad/data/models/run_result.dart';
import 'package:codepad/data/models/source_file.dart';
import 'package:codepad/runtime/native_runtime_engine.dart';
import 'package:codepad/runtime/native_toolchain.dart';
import 'package:codepad/runtime/runtime_engine.dart';
import 'package:codepad/runtime/runtime_factory.dart';
import 'package:codepad/runtime/unavailable_runtime_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// 一次「原生执行」的预设回复。
class _Reply {
  const _Reply({
    this.exitCode = 0,
    this.stdout = const <String>[],
    this.stderr = const <String>[],
    this.error,
  });

  final int exitCode;
  final List<String> stdout;
  final List<String> stderr;
  final String? error;
}

/// 假的原生工具链：不碰 MethodChannel，按预设回放输出并记录调用。
class _FakeToolchain implements ToolchainGateway {
  _FakeToolchain({List<_Reply>? replies})
      : _replies = replies ?? const <_Reply>[_Reply()];

  final List<_Reply> _replies;

  int runCount = 0;
  final List<List<String>> receivedSources = <List<String>>[];
  List<String> lastArgs = const <String>[];
  final List<String> stdin = <String>[];
  bool stdinClosed = false;
  bool cancelled = false;

  List<String> get lastSources => receivedSources.last;

  @override
  Future<ToolchainStatus> probe({bool force = false}) async =>
      const ToolchainStatus(available: true, version: 'tcc version 0.9.27');

  @override
  Future<RunProcessResult> run({
    required List<String> sources,
    List<String> args = const <String>[],
    List<String> flags = const <String>[],
    void Function(String stream, String text)? onLine,
  }) async {
    final _Reply reply = _replies[runCount.clamp(0, _replies.length - 1)];
    runCount++;
    receivedSources.add(sources);
    lastArgs = args;
    for (final String line in reply.stdout) {
      onLine?.call('stdout', line);
    }
    for (final String line in reply.stderr) {
      onLine?.call('stderr', line);
    }
    return RunProcessResult(
      exitCode: reply.exitCode,
      durationMs: 12,
      error: reply.error,
    );
  }

  @override
  Future<bool> writeStdin(String text) async {
    stdin.add(text);
    return true;
  }

  @override
  Future<bool> closeStdin() async {
    stdinClosed = true;
    return true;
  }

  @override
  Future<void> cancel() async {
    cancelled = true;
  }
}

void main() {
  late Directory workDir;

  setUp(() async {
    workDir = await Directory.systemTemp.createTemp('codepad_run_');
  });

  tearDown(() async {
    if (await workDir.exists()) {
      await workDir.delete(recursive: true);
    }
  });

  const SourceFile helloWorld = SourceFile(
    path: 'main.c',
    content: '#include <stdio.h>\nint main(void){ printf("hi\\n"); return 0; }\n',
  );

  NativeRuntimeEngine engineWith(
    _FakeToolchain toolchain, {
    bool multiFile = true,
  }) =>
      NativeRuntimeEngine(
        language: ProgramLanguage.c,
        workDir: workDir,
        toolchain: toolchain,
        multiFile: multiFile,
      );

  group('真实 C 运行引擎', () {
    test('成功运行：逐行回传输出并返回 success', () async {
      final _FakeToolchain toolchain = _FakeToolchain(
        replies: const <_Reply>[
          _Reply(stdout: <String>['hi']),
        ],
      );

      final List<String> chunks = <String>[];
      final RunResult result =
          await engineWith(toolchain).run(helloWorld, onOutput: chunks.add);

      expect(result.status, RunStatus.success);
      expect(result.exitCode, 0);
      expect(result.stdoutText, contains('hi'));
      expect(chunks.join(), contains('hi'));
      expect(chunks.join(), contains('\$ tcc main.c -run'));
      expect(toolchain.lastSources.length, 1);
      expect(File(toolchain.lastSources.first).readAsStringSync(), helloWorld.content);
    });

    test('编译错误：stderr 与退出码原样带回', () async {
      final _FakeToolchain toolchain = _FakeToolchain(
        replies: const <_Reply>[
          _Reply(exitCode: 1, stderr: <String>["main.c:1: error: 'x' undeclared"]),
        ],
      );

      final RunResult result = await engineWith(toolchain).run(helloWorld);

      expect(result.status, RunStatus.failed);
      expect(result.exitCode, 1);
      expect(result.stderrText, contains('undeclared'));
    });

    test('启动失败：把原因写进 stderr 而不是假装成功', () async {
      final _FakeToolchain toolchain = _FakeToolchain(
        replies: const <_Reply>[
          _Reply(exitCode: -1, error: '启动编译器失败：Permission denied'),
        ],
      );

      final RunResult result = await engineWith(toolchain).run(helloWorld);

      expect(result.status, RunStatus.failed);
      expect(result.stderrText, contains('Permission denied'));
    });

    test('头文件也落盘（#include "util.h" 能找到），但不参与编译', () async {
      final _FakeToolchain toolchain = _FakeToolchain();

      await engineWith(toolchain).run(
        helloWorld,
        projectFiles: <SourceFile>[
          helloWorld,
          const SourceFile(path: 'lib/util.h', content: '#define ANSWER 42\n'),
        ],
      );

      final File header =
          File('${File(toolchain.lastSources.first).parent.path}/lib/util.h');
      expect(header.existsSync(), isTrue);
      expect(header.readAsStringSync(), contains('ANSWER'));
      expect(toolchain.lastSources.length, 1);
    });

    test('不含 main 的 util.c 参与编译', () async {
      final _FakeToolchain toolchain = _FakeToolchain();

      await engineWith(toolchain).run(
        helloWorld,
        projectFiles: <SourceFile>[
          helloWorld,
          const SourceFile(path: 'util.c', content: 'int add(int a,int b){return a+b;}\n'),
        ],
      );

      final List<String> names = toolchain.lastSources
          .map((String s) => s.split(Platform.pathSeparator).last)
          .toList();
      expect(names, <String>['main.c', 'util.c']);
    });

    // 0.3.1 的回归点：示例工程里 hello.c / input.c 也各有 main()，
    // 旧规则把它们全丢给编译器 → duplicate symbol main，导致任何文件都跑不起来。
    test('其它含 main() 的文件不参与编译，并给出提示', () async {
      final _FakeToolchain toolchain = _FakeToolchain(
        replies: const <_Reply>[
          _Reply(stdout: <String>['hi']),
        ],
      );
      final List<String> out = <String>[];

      final RunResult result = await engineWith(toolchain).run(
        helloWorld,
        projectFiles: <SourceFile>[
          helloWorld,
          const SourceFile(path: 'hello.c', content: 'int main(void){return 0;}\n'),
          const SourceFile(path: 'input.c', content: 'int main(void){return 1;}\n'),
          const SourceFile(path: 'util.c', content: 'int add(int a,int b){return a+b;}\n'),
        ],
        onOutput: out.add,
      );

      expect(result.status, RunStatus.success);
      expect(toolchain.lastSources.length, 2);
      final List<String> names = toolchain.lastSources
          .map((String s) => s.split(Platform.pathSeparator).last)
          .toList();
      expect(names, <String>['main.c', 'util.c']);
      expect(out.join(), contains('也定义了 main()'));
      expect(out.join(), contains('hello.c'));
      expect(out.join(), contains('input.c'));
    });

    test('多文件编译失败时自动退回单文件重试一次', () async {
      final _FakeToolchain toolchain = _FakeToolchain(
        replies: const <_Reply>[
          _Reply(exitCode: 1, stderr: <String>["util.c:1: error: undefined symbol 'add'"]),
          _Reply(stdout: <String>['hi']),
        ],
      );
      final List<String> out = <String>[];

      final RunResult result = await engineWith(toolchain).run(
        helloWorld,
        projectFiles: <SourceFile>[
          helloWorld,
          const SourceFile(path: 'util.c', content: 'int add(int a,int b){return a+b;}\n'),
        ],
        onOutput: out.add,
      );

      expect(toolchain.runCount, 2);
      expect(toolchain.lastSources.length, 1, reason: '重试时只编入口文件');
      expect(result.status, RunStatus.success);
      expect(out.join(), contains('改为只编译 main.c 重试'));
    });

    test('程序自身运行失败（没有编译器诊断）不会触发重试', () async {
      final _FakeToolchain toolchain = _FakeToolchain(
        replies: const <_Reply>[
          _Reply(exitCode: 2, stdout: <String>['boom']),
        ],
      );

      final RunResult result = await engineWith(toolchain).run(
        helloWorld,
        projectFiles: <SourceFile>[
          helloWorld,
          const SourceFile(path: 'util.c', content: 'int add(int a,int b){return a+b;}\n'),
        ],
      );

      expect(toolchain.runCount, 1);
      expect(result.status, RunStatus.failed);
      expect(result.exitCode, 2);
    });

    // 真机日志里的情况：缺头文件与「文件数量」无关，重试只会多打一遍同样的报错
    test('缺头文件的错误不会触发单文件重试', () async {
      final _FakeToolchain toolchain = _FakeToolchain(
        replies: const <_Reply>[
          _Reply(
            exitCode: 1,
            stderr: <String>[
              'In file included from main.c:1:',
              "sys/cdefs.h:360: error: include file 'android/versioning.h' not found",
            ],
          ),
        ],
      );

      final RunResult result = await engineWith(toolchain).run(
        helloWorld,
        projectFiles: <SourceFile>[
          helloWorld,
          const SourceFile(path: 'util.c', content: 'int add(int a,int b){return a+b;}\n'),
        ],
      );

      expect(toolchain.runCount, 1);
      expect(result.status, RunStatus.failed);
      expect(result.stderrText, contains('not found'));
    });

    test('关闭多文件编译后只编当前文件', () async {
      final _FakeToolchain toolchain = _FakeToolchain();

      await engineWith(toolchain, multiFile: false).run(
        helloWorld,
        projectFiles: <SourceFile>[
          helloWorld,
          const SourceFile(path: 'util.c', content: 'int add(int a,int b){return a+b;}\n'),
        ],
      );

      expect(toolchain.lastSources.length, 1);
    });

    test('当前文件没有 main 时改用工程里唯一的 main 作为入口', () async {
      final _FakeToolchain toolchain = _FakeToolchain();
      const SourceFile helper =
          SourceFile(path: 'helper.c', content: 'int add(int a,int b){return a+b;}\n');
      final List<String> out = <String>[];

      await engineWith(toolchain).run(
        helper,
        projectFiles: <SourceFile>[
          helper,
          const SourceFile(path: 'app.c', content: 'int main(void){return 0;}\n'),
        ],
        onOutput: out.add,
      );

      final List<String> names = toolchain.lastSources
          .map((String s) => s.split(Platform.pathSeparator).last)
          .toList();
      expect(names.first, 'app.c');
      expect(out.join(), contains('作为入口'));
    });

    test('每次运行前清空工作目录，避免上一次的残留文件', () async {
      final _FakeToolchain toolchain = _FakeToolchain();
      final NativeRuntimeEngine engine = engineWith(toolchain);

      await engine.run(helloWorld);
      final String dir = File(toolchain.lastSources.first).parent.path;
      File('$dir/stale.c').writeAsStringSync('garbage');

      await engine.run(helloWorld);
      expect(File('$dir/stale.c').existsSync(), isFalse);
    });

    test('标准输入写进原生进程，也能发送 EOF', () async {
      final _FakeToolchain toolchain = _FakeToolchain();
      final NativeRuntimeEngine engine = engineWith(toolchain);

      expect(engine.supportsInput, isTrue);
      expect(await engine.writeInput('42\n'), isTrue);
      expect(toolchain.stdin, <String>['42\n']);

      expect(await engine.closeInput(), isTrue);
      expect(toolchain.stdinClosed, isTrue);
    });

    test('取消会把请求转给原生侧', () async {
      final _FakeToolchain toolchain = _FakeToolchain();

      await engineWith(toolchain).cancel();
      expect(toolchain.cancelled, isTrue);
    });
  });

  group('运行引擎工厂', () {
    test('工具链可用时 C 走真实引擎', () {
      final RuntimeFactory factory = RuntimeFactory(
        preferNative: true,
        workRoot: workDir,
        toolchain: _FakeToolchain(),
        toolchainStatus: const ToolchainStatus(available: true),
      );
      final RuntimeEngine engine = factory.create(ProgramLanguage.c);
      expect(engine, isA<NativeRuntimeEngine>());
    });

    test('多文件开关由设置实时提供', () {
      bool multiFile = false;
      final RuntimeFactory factory = RuntimeFactory(
        preferNative: true,
        workRoot: workDir,
        toolchain: _FakeToolchain(),
        toolchainStatus: const ToolchainStatus(available: true),
        multiFileCompile: () => multiFile,
      );

      expect((factory.create(ProgramLanguage.c) as NativeRuntimeEngine).multiFile, isFalse);
      multiFile = true;
      expect((factory.create(ProgramLanguage.c) as NativeRuntimeEngine).multiFile, isTrue);
    });

    test('工具链不可用时 C 明确报错，不伪造输出', () async {
      final RuntimeFactory factory = RuntimeFactory(
        preferNative: true,
        workRoot: workDir,
        toolchainStatus: const ToolchainStatus(available: false, error: '缺少 libtcc.so'),
      );
      final RuntimeEngine engine = factory.create(ProgramLanguage.c);
      expect(engine, isA<UnavailableRuntimeEngine>());

      final RunResult result = await engine.run(helloWorld);
      expect(result.status, RunStatus.failed);
      expect(result.stderrText, contains('libtcc.so'));
    });

    test('C++ 与 Python 当前给出未接入说明', () {
      final RuntimeFactory factory = RuntimeFactory(
        preferNative: true,
        workRoot: workDir,
        toolchainStatus: const ToolchainStatus(available: true),
      );
      expect(factory.create(ProgramLanguage.cpp), isA<UnavailableRuntimeEngine>());
      expect(factory.create(ProgramLanguage.python), isA<UnavailableRuntimeEngine>());
    });

    test('模拟模式（默认）仍返回模拟引擎', () {
      const RuntimeFactory factory = RuntimeFactory();
      final RuntimeEngine engine = factory.create(ProgramLanguage.c);
      expect(engine, isNot(isA<NativeRuntimeEngine>()));
      expect(engine.buildCommand(helloWorld), contains('gcc'));
    });
  });
}
