import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// 编辑器顶部工具栏：主操作（运行/保存）与辅助操作（查找/控制台）分组。
class EditorToolbar extends StatelessWidget {
  const EditorToolbar({
    super.key,
    required this.isRunning,
    required this.onRun,
    required this.onStop,
    required this.onSave,
    required this.consoleVisible,
    required this.onToggleConsole,
    this.onFind,
    this.findVisible = false,
    this.onUndo,
    this.onRedo,
    this.canUndo = false,
    this.canRedo = false,
    this.onToggleProblems,
    this.problemsVisible = false,
    this.problemCount = 0,
    this.onOpenFileTree,
  });

  final bool isRunning;
  final VoidCallback onRun;
  final VoidCallback onStop;
  final VoidCallback onSave;
  final bool consoleVisible;
  final VoidCallback onToggleConsole;

  /// 打开/关闭「查找替换」条。
  final VoidCallback? onFind;
  final bool findVisible;

  /// 撤销 / 重做。
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final bool canUndo;
  final bool canRedo;

  /// 打开/关闭「问题面板」。
  final VoidCallback? onToggleProblems;
  final bool problemsVisible;
  final int problemCount;

  /// 窄屏时显示“文件树”按钮（打开抽屉）；宽屏下常驻文件树，传 null 即可隐藏。
  final VoidCallback? onOpenFileTree;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);

    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: palette.panelAlt,
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: <Widget>[
            if (onOpenFileTree != null)
              IconButton(
                tooltip: '文件列表',
                onPressed: onOpenFileTree,
                icon: const Icon(Icons.account_tree_outlined, size: 19),
              ),
            if (onOpenFileTree != null) const SizedBox(width: 2),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: isRunning
                  ? FilledButton.tonalIcon(
                      key: const ValueKey<String>('stop'),
                      onPressed: onStop,
                      style: FilledButton.styleFrom(
                        backgroundColor: palette.danger.withValues(alpha: 0.16),
                        foregroundColor: palette.danger,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      icon: const Icon(Icons.stop_rounded, size: 18),
                      label: const Text('停止'),
                    )
                  : FilledButton.icon(
                      key: const ValueKey<String>('run'),
                      onPressed: onRun,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                      ),
                      icon: const Icon(Icons.play_arrow_rounded, size: 20),
                      label: const Text('运行'),
                    ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: onSave,
              icon: const Icon(Icons.save_outlined, size: 16),
              label: const Text('保存'),
            ),
            const SizedBox(width: 10),
            _divider(palette),
            IconButton(
              tooltip: '撤销（Ctrl+Z）',
              onPressed: canUndo ? onUndo : null,
              icon: const Icon(Icons.undo, size: 19),
            ),
            IconButton(
              tooltip: '重做（Ctrl+Y）',
              onPressed: canRedo ? onRedo : null,
              icon: const Icon(Icons.redo, size: 19),
            ),
            _divider(palette),
            if (onFind != null)
              IconButton(
                tooltip: findVisible ? '关闭查找' : '查找 / 替换',
                onPressed: onFind,
                icon: Icon(
                  findVisible ? Icons.search_off : Icons.search,
                  size: 19,
                  color: findVisible ? palette.accent : palette.textMuted,
                ),
              ),
            if (onToggleProblems != null)
              // 有问题时用角标把数量亮出来，否则平时不占注意力
              Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  IconButton(
                    tooltip: problemsVisible ? '收起问题面板' : '编译问题',
                    onPressed: onToggleProblems,
                    icon: Icon(
                      Icons.bug_report_outlined,
                      size: 19,
                      color: problemsVisible
                          ? palette.accent
                          : (problemCount > 0 ? palette.danger : palette.textMuted),
                    ),
                  ),
                  if (problemCount > 0)
                    Positioned(
                      right: 4,
                      top: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: palette.danger,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '$problemCount',
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            IconButton(
              tooltip: consoleVisible ? '收起控制台' : '展开控制台',
              onPressed: onToggleConsole,
              icon: Icon(
                consoleVisible
                    ? Icons.terminal
                    : Icons.terminal_outlined,
                size: 19,
                color: consoleVisible ? palette.accent : palette.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider(AppPalette palette) {
    return Container(
      width: 1,
      height: 22,
      margin: const EdgeInsets.only(right: 6),
      color: palette.border,
    );
  }
}
