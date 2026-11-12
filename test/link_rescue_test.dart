import 'dart:io';

import 'package:codepad/data/models/program_language.dart';
import 'package:codepad/data/models/run_result.dart';
import 'package:codepad/data/models/source_file.dart';
import 'package:codepad/runtime/native_runtime_engine.dart';
import 'package:codepad/runtime/native_toolchain.dart';
import 'package:flutter_test/flutter_test.dart';

/// 只编 1 个文件时返回「链接失败」，编 2 个文件时成功。
class _RescueToolchain implements ToolchainGateway {
  int runCount = 0;
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
    runCount++;
    if (sources.length == 1) {
      onLine?.call('stderr', "tcc: error: undefined symbol 'f'");
      return const RunProcessResult(exitCode: 255);
    }
    onLine?.call('stdout', 'integral=0.33');
    return const RunProcessResult(exitCode: 0);
  }

  @override
  Future<bool> writeStdin(String text) async => true;

  @override
  Future<bool> closeStdin() async => true;

  @override
  Future<void> cancel() async {}
}

const SourceFile _main = SourceFile(
  path: 'main.c',
  content: '#include <stdio.h>\n'
      'int main(void) { printf("%f\\n", f(1.0)); return 0; }\n',
);

const SourceFile _utilC = SourceFile(
  path: 'util.c',
  content: 'double f(double x) { return x * x; }\n',
);

const SourceFile _utilWithMain = SourceFile(
  path: 'other.c',
  content: 'double f(double x) { return x * x; }\n'
      'int main(void) { return 0; }\n',
);

void main() {
  late Directory workDir;

  setUp(() async {
    workDir = await Directory.systemTemp.createTemp('codepad_rescue_');
  });

  tearDown(() async {
    if (await workDir.exists()) {
      await workDir.delete(recursive: true);
    }
  });

  NativeRuntimeEngine engineFor(
    ToolchainGateway gateway, {
    bool multiFile = true,
  }) {
    return NativeRuntimeEngine(
      language: ProgramLanguage.c,
      workDir: workDir,
      toolchain: gateway,
      multiFile: multiFile,
    );
  }

  group('链接失败自动补救', () {
    test('关闭多文件编译时：自动带上缺失实现所在的 .c 并重试成功', () async {
      final _RescueToolchain gateway = _RescueToolchain();
      final List<String> output = <String>[];

      final RunResult result = await engineFor(gateway, multiFile: false).run(
        _main,
        projectFiles: const <SourceFile>[_utilC],
        onOutput: output.add,
      );

      expect(result.status, RunStatus.success);
      expect(gateway.runCount, 2);
      expect(gateway.receivedSources.last.length, 2);
      expect(
        gateway.receivedSources.last.any((String p) => p.endsWith('util.c')),
        isTrue,
      );
      // 提示里要说明白：这次自动带了 util.c，以及怎么永久修好
      expect(output.join(), contains('util.c'));
      expect(output.join(), contains('多文件编译'));
    });

    test('符号在工程里不存在时：不重试，说明「没有谁定义」', () async {
      final _RescueToolchain gateway = _RescueToolchain();
      final List<String> output = <String>[];

      final RunResult result = await engineFor(gateway, multiFile: false).run(
        _main,
        projectFiles: const <SourceFile>[],
        onOutput: output.add,
      );

      expect(result.status, RunStatus.failed);
      expect(gateway.runCount, 1);
      expect(output.join(), contains('没有谁定义'));
    });

    test('实现所在的 .c 自己也有 main 时：不 rescue，提示切到那个文件', () async {
      final _RescueToolchain gateway = _RescueToolchain();
      final List<String> output = <String>[];

      final RunResult result = await engineFor(gateway, multiFile: false).run(
        _main,
        projectFiles: const <SourceFile>[_utilWithMain],
        onOutput: output.add,
      );

      expect(result.status, RunStatus.failed);
      expect(gateway.runCount, 1);
      expect(output.join(), contains('也写了 main'));
    });
  });
}
