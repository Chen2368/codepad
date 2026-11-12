import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/update/update_checker.dart';
import '../../core/update/update_info.dart';
import '../../runtime/storage_bridge.dart';

/// 设置页的「存储与更新」分区。
///
/// 回答三件常被问到的事：
/// 1. 我的程序存在哪（显示真实路径 + 一键复制）；
/// 2. 怎么把它拿出来（打包到系统「下载」）；
/// 3. 怎么更新（可配置清单地址检查；不方便时直接选本地 APK 安装）。
class StorageUpdateSection extends StatefulWidget {
  const StorageUpdateSection({
    super.key,
    required this.settings,
    this.bridge,
  });

  final SettingsController settings;

  /// 测试可注入；默认走真实 channel。
  final StorageBridge? bridge;

  @override
  State<StorageUpdateSection> createState() => _StorageUpdateSectionState();
}

class _StorageUpdateSectionState extends State<StorageUpdateSection> {
  late final StorageBridge _bridge = widget.bridge ?? StorageBridge();
  late final TextEditingController _urlController =
      TextEditingController(text: widget.settings.updateUrl);

  String? _projectsPath;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadProjectsPath();
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _loadProjectsPath() async {
    try {
      final Directory docs = await getApplicationDocumentsDirectory();
      final String path = p.join(docs.path, 'CodePad', 'projects');
      if (mounted) {
        setState(() {
          _projectsPath = path;
        });
      }
    } on Object {
      // 桌面/测试环境拿不到应用目录，界面显示「未知」即可
    }
  }

  void _snack(String message, {String? actionLabel, VoidCallback? onAction}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 4),
          action: actionLabel == null
              ? null
              : SnackBarAction(label: actionLabel, onPressed: onAction ?? () {}),
        ),
      );
  }

  Future<void> _copyPath() async {
    final String? path = _projectsPath;
    if (path == null) {
      _snack('暂时拿不到工程目录');
      return;
    }
    await Clipboard.setData(ClipboardData(text: path));
    _snack('已复制工程目录路径');
  }

  Future<void> _export() async {
    final String? path = _projectsPath;
    if (path == null) {
      _snack('暂时拿不到工程目录');
      return;
    }
    setState(() => _busy = true);
    final ExportResult? result =
        await _bridge.exportProjectsZip(sourceDir: path, name: 'CodePad-projects');
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    if (result == null) {
      _snack('导出失败（桌面环境没有这个能力）');
      return;
    }
    _snack(
      '已导出 ${result.fileCount} 个文件到 ${result.path}',
      actionLabel: '打开下载',
      onAction: () => _bridge.openDownloads(),
    );
  }

  Future<void> _installFromFile() async {
    setState(() => _busy = true);
    final InstallResult? result = await _bridge.pickAndInstallApk();
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    if (result == null) {
      _snack('当前环境不支持安装（桌面端仅供预览）');
      return;
    }
    if (result.cancelled) {
      _snack('已取消选择');
      return;
    }
    _snack('已交给系统安装器，按提示完成安装即可');
  }

  Future<void> _checkUpdate() async {
    setState(() => _busy = true);
    final UpdateCheckResult result = await UpdateChecker(
      currentVersion: AppConstants.version,
    ).check(widget.settings.updateUrl);
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);

    if (result.upToDate) {
      _snack('已是最新版本 v${AppConstants.version}');
      return;
    }
    if (result.error != null) {
      await _showError(result.error!);
      return;
    }
    await _showUpdateAvailable(result.update!);
  }

  Future<void> _showError(String message) async {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('检查更新失败'),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              _installFromFile();
            },
            icon: const Icon(Icons.folder_open_outlined, size: 17),
            label: const Text('从文件安装'),
          ),
        ],
      ),
    );
  }

  Future<void> _showUpdateAvailable(UpdateInfo info) async {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('发现新版本 v${info.version}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('当前版本 v${AppConstants.version}'),
            const SizedBox(height: 10),
            if (info.notes.isNotEmpty)
              Text(
                info.notes,
                style: const TextStyle(fontSize: 12.5, height: 1.5),
              ),
            const SizedBox(height: 12),
            Text(
              '下载完成后，用下面的「从文件安装」一步装好，不用再连电脑。',
              style: TextStyle(
                fontSize: 11.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('以后再说'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _installFromFile();
            },
            child: const Text('从文件安装'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              _bridge.openUrl(info.url);
            },
            child: const Text('去下载'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ListTile(
            title: const Text('程序保存位置'),
            subtitle: Text(
              _projectsPath ?? '（读取中…）',
              style: AppTheme.mono(fontSize: 10.5),
            ),
            trailing: IconButton(
              tooltip: '复制路径',
              onPressed: _copyPath,
              icon: const Icon(Icons.copy_all_outlined, size: 18),
            ),
          ),
          Divider(height: 1, color: palette.border),
          ListTile(
            title: const Text('把程序导出到「下载」'),
            subtitle: const Text('打包成 zip，平板的文件管理器里就能看到'),
            trailing: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    tooltip: '导出',
                    onPressed: _export,
                    icon: const Icon(Icons.archive_outlined, size: 18),
                  ),
          ),
          Divider(height: 1, color: palette.border),
          SwitchListTile(
            title: const Text('启动时自动检查更新'),
            subtitle: const Text('默认关闭；开启后只在有更新时提示一次'),
            value: widget.settings.autoCheckUpdate,
            onChanged: widget.settings.setAutoCheckUpdate,
          ),
          Divider(height: 1, color: palette.border),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: TextField(
              controller: _urlController,
              style: const TextStyle(fontSize: 12),
              decoration: const InputDecoration(
                labelText: '更新清单地址（可留空）',
                hintText: 'https://example.com/codepad-update.json',
              ),
              onSubmitted: (String value) =>
                  widget.settings.setUpdateUrl(value),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              '清单格式：{"version":"0.9.0","url":"下载页","notes":"更新说明"}',
              style: TextStyle(fontSize: 10.5, color: palette.textMuted),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: Row(
              children: <Widget>[
                TextButton.icon(
                  onPressed: _busy
                      ? null
                      : () {
                          widget.settings.setUpdateUrl(_urlController.text);
                          _snack('更新地址已保存');
                        },
                  icon: const Icon(Icons.save_outlined, size: 16),
                  label: const Text('保存地址'),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _installFromFile,
                  icon: const Icon(Icons.system_update_alt, size: 16),
                  label: const Text('从文件安装'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _busy ? null : _checkUpdate,
                  icon: const Icon(Icons.refresh, size: 17),
                  label: const Text('检查更新'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
