import 'dart:io';

import '../data/models/program_language.dart';
import 'native_runtime_engine.dart';
import 'native_toolchain.dart';
import 'runtime_engine.dart';
import 'stub_runtime_engine.dart';
import 'unavailable_runtime_engine.dart';

/// 运行引擎工厂：语言 → 引擎实现。
///
/// 两种模式：
/// - 默认（`preferNative: false`）：全部返回模拟引擎，供单元测试与无设备环境使用；
/// - 真机（`preferNative: true`）：C 走内置 tcc 真实编译运行；
///   C++ / Python 缺少运行时时明确报错，而不是伪造成功。
class RuntimeFactory {
  const RuntimeFactory({
    this.preferNative = false,
    this.workRoot,
    this.toolchain,
    this.toolchainStatus,
    this.multiFileCompile,
  });

  /// 是否优先使用真实运行引擎。
  final bool preferNative;

  /// 真实运行时的临时工作目录（一般取 getTemporaryDirectory()/run）。
  final Directory? workRoot;

  /// 原生工具链网关（便于注入假实现）。
  final ToolchainGateway? toolchain;

  /// 启动时探测到的工具链状态。
  final ToolchainStatus? toolchainStatus;

  /// 读取「多文件编译」开关（每次运行时现取，用户改了设置立刻生效）。
  final bool Function()? multiFileCompile;

  RuntimeEngine create(ProgramLanguage language) {
    if (!preferNative) {
      return StubRuntimeEngine(language: language);
    }

    switch (language) {
      case ProgramLanguage.c:
        final Directory? root = workRoot;
        if (root != null && (toolchainStatus?.available ?? false)) {
          return NativeRuntimeEngine(
            language: language,
            workDir: root,
            toolchain: toolchain,
            multiFile: multiFileCompile?.call() ?? true,
          );
        }
        return UnavailableRuntimeEngine(
          language: language,
          reason: toolchainStatus?.error ?? '未检测到内置的 C 编译器',
        );

      case ProgramLanguage.cpp:
        return UnavailableRuntimeEngine(
          language: language,
          reason: 'C++ 需要 clang（尚未内置，计划在 Phase 3.5 接入）；'
              '现在可以先用 C 练手，或把代码写成 .c 文件。',
        );

      case ProgramLanguage.python:
        return UnavailableRuntimeEngine(
          language: language,
          reason: 'Python 运行时（嵌入式 CPython）计划在 Phase 4 接入。',
        );
    }
  }
}
