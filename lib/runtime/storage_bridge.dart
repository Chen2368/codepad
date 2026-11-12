import 'package:flutter/services.dart';

/// 「存储与更新」的原生能力封装（channel `codepad/storage`）。
///
/// 桌面上跑测试时通道不可用，所有方法都会安全降级（返回 null / false），
/// 这样界面逻辑仍可被组件测试驱动。
class StorageBridge {
  StorageBridge({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('codepad/storage');

  final MethodChannel _channel;

  /// 把工程目录打包导出到系统「下载/CodePad」。
  Future<ExportResult?> exportProjectsZip({
    required String sourceDir,
    String name = 'CodePad-projects',
  }) async {
    try {
      final Map<Object?, Object?>? map =
          await _channel.invokeMapMethod<Object?, Object?>('exportZip', <String, Object?>{
        'sourceDir': sourceDir,
        'name': name,
      });
      if (map == null) {
        return null;
      }
      return ExportResult(
        path: map['path'] as String? ?? '',
        fileCount: (map['fileCount'] as int?) ?? 0,
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// 打开系统的「下载」界面。
  Future<bool> openDownloads() async {
    try {
      await _channel.invokeMethod<bool>('openDownloads');
      return true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// 用系统浏览器打开一个链接（下载新版本用）。
  Future<bool> openUrl(String url) async {
    try {
      await _channel.invokeMethod<bool>('openUrl', <String, Object?>{'url': url});
      return true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// 让用户挑一个本地 APK 并交给系统安装器。
  Future<InstallResult?> pickAndInstallApk() async {
    try {
      final Map<Object?, Object?>? map = await _channel
          .invokeMapMethod<Object?, Object?>('pickApk');
      if (map == null) {
        return null;
      }
      return InstallResult(cancelled: map['cancelled'] != false);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}

/// 导出结果。
class ExportResult {
  const ExportResult({required this.path, required this.fileCount});

  /// 展示给用户的路径（`Download/CodePad/xxx.zip` 或老系统的绝对路径）。
  final String path;
  final int fileCount;
}

/// 安装请求结果。
class InstallResult {
  const InstallResult({required this.cancelled});

  final bool cancelled;
}
