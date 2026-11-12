import 'package:flutter/services.dart';

/// 内置工具链的检测结果。
class ToolchainStatus {
  const ToolchainStatus({
    required this.available,
    this.version,
    this.compilerPath,
    this.toolchainDir,
    this.toolchainVersion,
    this.buildTag,
    this.checks = const <String, bool>{},
    this.error,
  });

  factory ToolchainStatus.fromMap(Map<Object?, Object?>? map) {
    if (map == null) {
      return const ToolchainStatus(available: false, error: '原生侧没有返回检测结果');
    }
    final Map<Object?, Object?>? rawChecks = map['checks'] as Map<Object?, Object?>?;
    return ToolchainStatus(
      available: map['available'] == true,
      version: map['version'] as String?,
      compilerPath: map['compilerPath'] as String?,
      toolchainDir: map['toolchainDir'] as String?,
      toolchainVersion: map['toolchainVersion'] as String?,
      buildTag: map['buildTag'] as String?,
      checks: <String, bool>{
        for (final MapEntry<Object?, Object?> entry
            in (rawChecks ?? const <Object?, Object?>{}).entries)
          '${entry.key}': entry.value == true,
      },
      error: map['error'] as String?,
    );
  }

  final bool available;

  /// 编译器版本行（例如 `tcc version 0.9.27`）。
  final String? version;

  /// 编译器可执行文件路径（nativeLibraryDir 下的 libtcc.so）。
  final String? compilerPath;

  /// 头文件 / libtcc1.a 所在目录。
  final String? toolchainDir;

  /// 原生侧的工具链版本标记（解压缓存靠它判断是否需要重新解压）。
  final String? toolchainVersion;

  /// 原生侧的构建标记（命令行形状变了就变，用来区分「跑的是哪个包」）。
  final String? buildTag;

  /// 工具链关键文件是否到位（键是相对路径，值是是否存在）。
  final Map<String, bool> checks;

  /// 不可用时的原因。
  final String? error;

  String get summary {
    if (available) {
      return version ?? '已就绪';
    }
    return error ?? '不可用';
  }
}

/// 一次原生编译执行的结果。
class RunProcessResult {
  const RunProcessResult({
    required this.exitCode,
    this.durationMs = 0,
    this.error,
  });

  factory RunProcessResult.fromMap(Map<Object?, Object?>? map) {
    if (map == null) {
      return const RunProcessResult(exitCode: -1, error: '原生侧没有返回结果');
    }
    return RunProcessResult(
      exitCode: (map['exitCode'] as num?)?.toInt() ?? -1,
      durationMs: (map['durationMs'] as num?)?.toInt() ?? 0,
      error: map['error'] as String?,
    );
  }

  final int exitCode;
  final int durationMs;

  /// 启动失败等错误信息（编译错误走 stderr，不走这里）。
  final String? error;

  bool get succeeded => error == null && exitCode == 0;
}

/// 原生工具链网关：抽成接口，测试里可以注入假实现，不依赖 MethodChannel。
abstract class ToolchainGateway {
  Future<ToolchainStatus> probe({bool force = false});

  /// 编译并执行。[sources] 第一项是入口文件，其余是参与链接的源文件。
  ///
  /// [flags] 是编译选项（`-std=c11` / `-O2` / `-Wall`），由设置页决定。
  Future<RunProcessResult> run({
    required List<String> sources,
    List<String> args = const <String>[],
    List<String> flags = const <String>[],
    void Function(String stream, String text)? onLine,
  });

  Future<bool> writeStdin(String text);

  /// 关闭标准输入（EOF）。
  Future<bool> closeStdin();

  Future<void> cancel();
}

/// 通过 MethodChannel 与 Kotlin 侧 [NativeCompiler] 通信。
class NativeToolchain implements ToolchainGateway {
  NativeToolchain({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(channelName) {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  static const String channelName = 'codepad/compiler';

  final MethodChannel _channel;

  ToolchainStatus? _cached;
  void Function(String stream, String text)? _onLine;

  @override
  Future<ToolchainStatus> probe({bool force = false}) async {
    if (!force && _cached != null) {
      return _cached!;
    }
    try {
      final Map<Object?, Object?>? raw =
          await _channel.invokeMapMethod<Object?, Object?>('probe');
      final ToolchainStatus status = ToolchainStatus.fromMap(raw);
      _cached = status;
      return status;
    } on MissingPluginException {
      return const ToolchainStatus(
        available: false,
        error: '原生通道不可用（测试环境或未打包原生代码）',
      );
    } on PlatformException catch (error) {
      return ToolchainStatus(available: false, error: error.message ?? error.code);
    }
  }

  @override
  Future<RunProcessResult> run({
    required List<String> sources,
    List<String> args = const <String>[],
    List<String> flags = const <String>[],
    void Function(String stream, String text)? onLine,
  }) async {
    _onLine = onLine;
    try {
      final Map<Object?, Object?>? raw =
          await _channel.invokeMapMethod<Object?, Object?>('run', <String, Object?>{
        'sources': sources,
        'args': args,
        'flags': flags,
      });
      return RunProcessResult.fromMap(raw);
    } on MissingPluginException {
      return const RunProcessResult(exitCode: -1, error: '原生通道不可用');
    } on PlatformException catch (error) {
      return RunProcessResult(
        exitCode: -1,
        error: error.message ?? error.code,
      );
    } finally {
      _onLine = null;
    }
  }

  @override
  Future<bool> writeStdin(String text) async {
    try {
      final bool? ok = await _channel.invokeMethod<bool>(
        'writeStdin',
        <String, Object?>{'text': text},
      );
      return ok ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> closeStdin() async {
    try {
      final bool? ok = await _channel.invokeMethod<bool>('closeStdin');
      return ok ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> cancel() async {
    try {
      await _channel.invokeMethod<bool>('cancel');
    } on PlatformException {
      // 忽略：进程可能已经结束
    } on MissingPluginException {
      // 忽略
    }
  }

  Future<Object?> _handleNativeCall(MethodCall call) async {
    if (call.method == 'onOutput') {
      final Object? arguments = call.arguments;
      if (arguments is Map) {
        final String stream = '${arguments['stream'] ?? 'stdout'}';
        final String text = '${arguments['text'] ?? ''}';
        _onLine?.call(stream, text);
      }
    }
    return null;
  }
}
