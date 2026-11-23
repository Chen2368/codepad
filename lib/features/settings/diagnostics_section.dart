import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants/app_constants.dart';
import '../../core/diagnostics/crash_logger.dart';
import '../../core/diagnostics/crash_report.dart';
import '../../core/theme/app_theme.dart';
import '../../runtime/storage_bridge.dart';

/// 设置页的「诊断」分区：闪退排查用。
///
/// 三件事：
/// 1. 上次启动是否异常结束（进程被杀会留下 run-begin 没有 run-end）；
/// 2. 导出日志到「下载」（zip，含原生崩溃 + 会话记录）；
/// 3. 一键复制完整报告，直接贴给开发者。
class DiagnosticsSection extends StatefulWidget {
  const DiagnosticsSection({
    super.key,
    this.crashLogger,
    this.bridge,
  });

  final CrashLogger? crashLogger;

  /// 测试可注入。
  final StorageBridge? bridge;

  @override
  State<DiagnosticsSection> createState() => _DiagnosticsSectionState();
}

class _DiagnosticsSectionState extends State<DiagnosticsSection> {
  late final StorageBridge _bridge = widget.bridge ?? StorageBridge();

  String _log = '';
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final CrashLogger? logger = widget.crashLogger;
    if (logger == null) {
      setState(() {
        _log = '（没有接入日志：仅真机版本提供）';
        _loading = false;
      });
      return;
    }
    final String raw = await logger.readLog();
    if (!mounted) {
      return;
    }
    setState(() {
      _log = raw;
      _loading = false;
    });
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _copyReport() async {
    final CrashLogger? logger = widget.crashLogger;
    if (logger == null) {
      _snack('当前环境没有日志');
      return;
    }
    setState(() => _busy = true);
    final String report = await logger.buildReport();
    await Clipboard.setData(ClipboardData(text: report));
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    _snack('诊断报告已复制（${(report.length / 1024).toStringAsFixed(1)} KB）');
  }

  Future<void> _export() async {
    final CrashLogger? logger = widget.crashLogger;
    if (logger == null) {
      _snack('当前环境没有日志');
      return;
    }
    setState(() => _busy = true);
    final String? dir = await logger.diagDir();
    if (dir == null) {
      if (mounted) {
        setState(() => _busy = false);
        _snack('拿不到日志目录');
      }
      return;
    }
    final ExportResult? result =
        await _bridge.exportProjectsZip(sourceDir: dir, name: 'codepad-diag');
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    if (result == null) {
      _snack('导出失败（桌面环境没有这个能力）');
      return;
    }
    _snackAction(
      '已导出到 ${result.path}',
      '打开下载',
      () => _bridge.openDownloads(),
    );
  }

  void _snackAction(String message, String label, VoidCallback action) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(label: label, onPressed: action),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final UnfinishedRun? unfinished = widget.crashLogger?.unfinishedRun;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (unfinished != null)
            Container(
              color: palette.danger.withValues(alpha: 0.10),
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(Icons.warning_amber_rounded,
                      size: 18, color: palette.danger),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '上次运行 ${unfinished.fileName} 时进程异常结束'
                      '（${unfinished.when}）。'
                      '如果这个程序写到非法内存或递归过深，系统会直接杀掉进程 —— '
                      '先看下面的日志，或把报告发我。',
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.5,
                        color: palette.danger,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            ListTile(
              leading: Icon(Icons.verified_outlined,
                  size: 18, color: palette.success),
              title: const Text('上次会话正常结束'),
              subtitle: const Text('没有记录到未完成的运行'),
            ),
          Divider(height: 1, color: palette.border),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
            child: Row(
              children: <Widget>[
                Text('日志（最近）',
                    style: TextStyle(fontSize: 11.5, color: palette.textMuted)),
                const Spacer(),
                IconButton(
                  iconSize: 17,
                  visualDensity: VisualDensity.compact,
                  tooltip: '刷新',
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 180),
            child: Container(
              margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: palette.panelAlt,
                borderRadius: BorderRadius.circular(AppRadius.chip),
                border: Border.all(color: palette.border),
              ),
              child: SingleChildScrollView(
                child: Text(
                  _loading ? '读取中…' : _log,
                  style: AppTheme.mono(fontSize: 10.5, color: palette.text),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: <Widget>[
                OutlinedButton.icon(
                  onPressed: _busy ? null : _export,
                  icon: const Icon(Icons.archive_outlined, size: 16),
                  label: const Text('导出日志'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _busy ? null : _copyReport,
                  icon: const Icon(Icons.copy_all_outlined, size: 16),
                  label: const Text('复制诊断报告'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Text(
              '版本 ${AppConstants.version} · 构建 ${AppConstants.buildTag}。'
              '闪退时进程会被系统直接杀掉，所以日志是「先落盘、下次启动读回」的。',
              style: TextStyle(fontSize: 10.5, color: palette.textMuted, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}