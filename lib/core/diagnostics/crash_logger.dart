import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/constants/app_constants.dart';
import '../../core/diagnostics/crash_report.dart';

/// 崩溃/会话日志的记录器。
///
/// 两层：
/// 1. **Dart 侧**：捕获 `FlutterError`、`PlatformDispatcher` 未处理异常、`runZonedGuarded`；
/// 2. **原生侧**：`mark` 落盘到 filesDir/diag/session.log，进程被杀也在。
///
/// 「运行 C 前 mark(run-begin)、跑完 mark(run-end)」是判断闪退原因的关键：
/// 下次启动如果发现 run-begin 没有配对的 run-end，就说明进程死在运行期间。
class CrashLogger {
  CrashLogger({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('codepad/storage');

  final MethodChannel _channel;

  String? _diagDir;
  bool _installed = false;

  /// 上一次会话里未收尾的运行（启动时计算，界面据此提示）。
  UnfinishedRun? unfinishedRun;

  /// 挂上全局异常钩子。只调用一次。
  void install() {
    if (_installed) {
      return;
    }
    _installed = true;

    FlutterError.onError = (FlutterErrorDetails details) {
      // 保留默认行为（红屏/日志），同时落盘
      FlutterError.presentError(details);
      unawaited(
        recordError(
          'flutter-error',
          details.exceptionAsString(),
          details.stack?.toString() ?? '',
        ),
      );
    };

    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      unawaited(recordError('platform-error', '$error', stack.toString()));
      return false; // 让默认处理继续（会打日志/退出）
    };
  }

  /// 记一条会话标记（同步落盘，进程被杀也留得住）。
  Future<void> mark(String kind, [String detail = '']) async {
    try {
      await _channel.invokeMethod<bool>('mark', <String, Object?>{
        'kind': kind,
        'detail': detail,
      });
    } on MissingPluginException {
      // 桌面/测试环境没有原生通道，忽略
    } on PlatformException {
      // 诊断日志失败不能影响主流程
    }
  }

  Future<void> recordError(String kind, String message, String stack) {
    final String brief = _clip(message, 400);
    final String briefStack = _clip(stack, 1200);
    return mark(kind, '$brief\n$briefStack');
  }

  /// 读回日志（原生侧已拼好：原生崩溃 + 当前会话 + 上一段会话）。
  Future<String> readLog() async {
    try {
      return await _channel.invokeMethod<String>('readLog') ?? '（没有日志）';
    } on MissingPluginException {
      return '（桌面环境没有原生日志）';
    } on PlatformException catch (error) {
      return '（读取失败：${error.message}）';
    }
  }

  /// 当前内存快照（判断闪退是否因为 OOM）。
  Future<String> memorySummary() async {
    try {
      final Map<Object?, Object?>? map =
          await _channel.invokeMapMethod<Object?, Object?>('memInfo');
      if (map == null) {
        return '（取不到）';
      }
      return 'java=${map['javaUsedMb']}/${map['javaMaxMb']}MB '
          'native=${map['nativeMb']}MB';
    } on MissingPluginException {
      return '（桌面环境）';
    } on PlatformException {
      return '（取不到）';
    }
  }

  /// 诊断目录路径（用于导出）。
  Future<String?> diagDir() async {
    if (_diagDir != null) {
      return _diagDir;
    }
    try {
      _diagDir = await _channel.invokeMethod<String>('diagDir');
      return _diagDir;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// 启动时调用：读日志 → 判断上次是否异常结束 → 写本次启动标记。
  Future<void> beginSession() async {
    final String raw = await readLog();
    final List<SessionEntry> entries = parseSessionLog(raw);
    unfinishedRun = findUnfinishedRun(entries);
    await mark('app-start', 'v${AppConstants.version}');
  }

  /// 组装成可直接发给开发者的报告。
  Future<String> buildReport() async {
    final String raw = await readLog();
    return buildCrashReport(
      appVersion: AppConstants.version,
      buildTag: AppConstants.buildTag,
      deviceInfo: await _deviceInfo(),
      rawLog: raw,
    );
  }

  Future<String> _deviceInfo() async {
    if (kIsWeb) {
      return 'web';
    }
    try {
      return '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
    } on Object {
      return '未知';
    }
  }

  static String _clip(String text, int max) =>
      text.length <= max ? text : '${text.substring(0, max)}…';
}
