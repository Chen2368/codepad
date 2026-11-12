import 'dart:io';

import 'package:codepad/runtime/native_toolchain.dart';
import 'package:codepad/runtime/toolchain_self_check.dart';
import 'package:flutter_test/flutter_test.dart';

/// 按脚本依次返回输出的假网关。
class _ScriptedToolchain implements ToolchainGateway {
  _ScriptedToolchain(this.script);

  final List<_Reply> script;
  int _index = 0;
  final List<List<String>> receivedSources = <List<String>>[];

  @override
  Future<ToolchainStatus> probe({bool force = false}) async =>
      const ToolchainStatus(available: true);

  @override
  Future<RunProcessResult> run({
    required List<String> sources,
    List<String> args = const <String>[],
    List<String> flags = const <String>[],
    void Function(String stream, String text)? onLine,
  }) async {
    receivedSources.add(sources);
    final _Reply reply = script[_index.clamp(0, script.length - 1)];
    _index++;
    for (final String line in reply.lines) {
      onLine?.call(reply.stream, line);
    }
    return RunProcessResult(exitCode: reply.exitCode, durationMs: 3, error: reply.error);
  }

  @override
  Future<bool> writeStdin(String text) async => true;

  @override
  Future<bool> closeStdin() async => true;

  @override
  Future<void> cancel() async {}
}

class _Reply {
  const _Reply(this.lines, {this.exitCode = 0, this.stream = 'stdout', this.error});

  final List<String> lines;
  final int exitCode;
  final String stream;
  final String? error;
}

void main() {
  late Directory workDir;

  setUp(() async {
    workDir = await Directory.systemTemp.createTemp('codepad_selfcheck_');
  });

  tearDown(() async {
    if (await workDir.exists()) {
      await workDir.delete(recursive: true);
    }
  });

  test('六项全通过：自检报告全部 passed', () async {
    final _ScriptedToolchain toolchain = _ScriptedToolchain(<_Reply>[
      const _Reply(<String>['shim=on']),
      const _Reply(<String>['OK-HELLO']),
      const _Reply(<String>['42 3.14 abc']),
      const _Reply(<String>['sqrt2=1.41421 exp0=1.0']),
      const _Reply(<String>['sum=5050']),
      const _Reply(<String>['add=7']),
      const _Reply(<String>['headers=65,6,7']),
    ]);

    final List<SelfCheckResult> results =
        await ToolchainSelfCheck(workRoot: workDir, toolchain: toolchain).run();

      expect(results.length, 7);
    expect(results.every((SelfCheckResult r) => r.passed), isTrue);
    expect(results.map((SelfCheckResult r) => r.name), <String>[
      'shim',
      'hello',
      'format',
      'math',
      'loop',
      'multi',
      'headers',
    ]);

    // 多文件那一项真的把两个 .c 都交给了原生侧
    final List<String> multiSources = toolchain.receivedSources.firstWhere(
      (List<String> sources) => sources.any((String s) => s.endsWith('multi_main.c')),
    );
    expect(multiSources.length, 2);
    expect(multiSources.first, endsWith('multi_main.c'));
  });

  test('数学库不可用：只有 math 一项失败，并说明原因', () async {
    final _ScriptedToolchain toolchain = _ScriptedToolchain(<_Reply>[
      const _Reply(<String>['shim=on']),
      const _Reply(<String>['OK-HELLO']),
      const _Reply(<String>['42 3.14 abc']),
      const _Reply(
        <String>["tcc: error: undefined symbol 'sqrt'"],
        exitCode: 1,
        stream: 'stderr',
      ),
      const _Reply(<String>['sum=5050']),
      const _Reply(<String>['add=7']),
      const _Reply(<String>['headers=65,6,7']),
    ]);

    final List<SelfCheckResult> results =
        await ToolchainSelfCheck(workRoot: workDir, toolchain: toolchain).run();

    final SelfCheckResult math =
        results.firstWhere((SelfCheckResult r) => r.name == 'math');
    expect(math.passed, isFalse);
    expect(math.note, contains('sqrt2=1.41421'));
    expect(math.output, contains('undefined symbol'));
    expect(results.where((SelfCheckResult r) => r.passed).length, 6);
  });

  test('原生侧启动失败：标记失败并带上错误信息', () async {
    final _ScriptedToolchain toolchain = _ScriptedToolchain(<_Reply>[
      const _Reply(<String>[], exitCode: -1, error: '启动编译器失败：Permission denied'),
    ]);

    final List<SelfCheckResult> results =
        await ToolchainSelfCheck(workRoot: workDir, toolchain: toolchain).run();

    expect(results.first.passed, isFalse);
    expect(results.first.note, contains('Permission denied'));
  });

  test('自检会覆盖上一次的文件，不会读到旧内容', () async {
    final Directory stale = Directory('${workDir.path}/selfcheck/hello');
    stale.createSync(recursive: true);
    File('${stale.path}/old.c').writeAsStringSync('int main(void){return 0;}\n');

    final _ScriptedToolchain toolchain = _ScriptedToolchain(<_Reply>[
      const _Reply(<String>['OK-HELLO']),
    ]);

    await ToolchainSelfCheck(workRoot: workDir, toolchain: toolchain).run();

    expect(File('${stale.path}/old.c').existsSync(), isFalse);
    expect(
      toolchain.receivedSources.any(
        (List<String> s) => s.single.endsWith('hello.c'),
      ),
      isTrue,
    );
  });
}
