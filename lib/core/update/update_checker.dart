import 'dart:convert';
import 'dart:io';

import 'update_info.dart';

/// 检查更新的结果。
class UpdateCheckResult {
  const UpdateCheckResult({
    this.update,
    this.error,
    this.currentVersion = '',
  });

  /// 有可更新的版本时为非空。
  final UpdateInfo? update;

  /// 出错说明（网络、清单格式等）；成功时为空。
  final String? error;

  final String currentVersion;

  bool get hasUpdate => update != null;

  /// 是否只是「已是最新」（没报错、也没有新版本）。
  bool get upToDate => update == null && error == null;
}

/// 检查更新：拉一份 JSON 清单，与当前版本比较。
///
/// 设计原则：**这个功能永远不能把 App 卡住或吓到用户** ——
/// 网络失败、清单格式错、超时，全部化成一句能看懂的话，且不影响本地编辑。
class UpdateChecker {
  UpdateChecker({
    required this.currentVersion,
    this.timeout = const Duration(seconds: 8),
  });

  final String currentVersion;
  final Duration timeout;

  /// [manifestUrl] 为空表示「还没配置更新源」。
  Future<UpdateCheckResult> check(String manifestUrl) async {
    if (manifestUrl.trim().isEmpty) {
      return UpdateCheckResult(
        currentVersion: currentVersion,
        error: '还没有配置更新地址。可以在设置里填一个清单地址，或直接用「从文件安装」。',
      );
    }

    final HttpClient client = HttpClient()..connectionTimeout = timeout;
    try {
      final HttpClientRequest request =
          await client.getUrl(Uri.parse(manifestUrl)).timeout(timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final HttpClientResponse response = await request.close().timeout(timeout);
      if (response.statusCode != HttpStatus.ok) {
        return UpdateCheckResult(
          currentVersion: currentVersion,
          error: '更新服务器返回 ${response.statusCode}',
        );
      }
      final String body =
          await response.transform(utf8.decoder).join().timeout(timeout);
      final UpdateInfo? info = UpdateInfo.tryParse(jsonDecode(body));
      if (info == null) {
        return UpdateCheckResult(
          currentVersion: currentVersion,
          error: '更新清单格式不对：至少要有 version 和 url 字段',
        );
      }
      if (!isNewerVersion(info.version, currentVersion)) {
        return UpdateCheckResult(currentVersion: currentVersion);
      }
      return UpdateCheckResult(update: info, currentVersion: currentVersion);
    } on SocketException {
      return UpdateCheckResult(
        currentVersion: currentVersion,
        error: '连不上更新服务器（检查网络或地址）',
      );
    } on FormatException {
      return UpdateCheckResult(
        currentVersion: currentVersion,
        error: '更新地址不是一个合法的 URL',
      );
    } on Object catch (error) {
      return UpdateCheckResult(
        currentVersion: currentVersion,
        error: '检查更新失败：$error',
      );
    } finally {
      client.close(force: true);
    }
  }
}
