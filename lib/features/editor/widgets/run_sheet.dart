import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/console_message.dart';
import '../../../data/models/run_result.dart';
import '../../editor/editor_controller.dart';
import 'console_input_row.dart';
import 'console_output_view.dart';

/// 弹出式「运行窗口」。
///
/// 设计参照常见在线编译器 / 移动 IDE 的做法：
/// · 点「运行」→ 立刻弹出面板，输出**流式**出现（不是等程序跑完才显示）；
/// · 面板高度可拖拽（从底部拉起，可拉到接近全屏看长输出）；
/// · 标准输入独立成一行，程序在跑的时候就能往里送；
/// · 编译错误那一行点一下 → 关掉面板并跳到源码对应行。
Future<void> showRunSheet({
  required BuildContext context,
  required EditorController controller,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext context) => RunSheet(controller: controller),
  );
}

class RunSheet extends StatelessWidget {
  const RunSheet({super.key, required this.controller});

  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      minChildSize: 0.28,
      maxChildSize: 0.95,
      builder: (BuildContext context, ScrollController scrollController) {
        return DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            border: Border(
              top: BorderSide(color: scheme.outlineVariant),
            ),
          ),
          child: ListenableBuilder(
            listenable: controller,
            builder: (BuildContext context, Widget? _) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _handle(scheme),
                  _header(context, scheme, AppPalette.of(context)),
                  Divider(height: 1, color: scheme.outlineVariant),
                  Expanded(
                    child: ConsoleOutputView(
                      messages: controller.consoleMessages,
                      scrollController: scrollController,
                      emptyHint: '正在准备运行环境…',
                      onTapDiagnostic: (diagnostic) {
                        Navigator.of(context).pop();
                        controller.jumpToDiagnostic(diagnostic);
                      },
                    ),
                  ),
                  Divider(height: 1, color: scheme.outlineVariant),
                  ConsoleInputRow(
                    enabled: controller.canSendInput,
                    onSendInput: controller.sendInput,
                    onEndInput: controller.endInput,
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _handle(ColorScheme scheme) {
    return SizedBox(
      height: 22,
      child: Center(
        child: Container(
          width: 38,
          height: 4,
          decoration: BoxDecoration(
            color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, ColorScheme scheme, AppPalette palette) {
    final RunStatus status = controller.status;
    final Color statusColor = _statusColor(scheme, status);

    return SizedBox(
      height: 48,
      child: Row(
        children: <Widget>[
          const SizedBox(width: 14),
          // 状态胶囊：颜色 + 文案成对出现，扫一眼就知道跑完了没有
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: statusColor.withValues(alpha: 0.32)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (status == RunStatus.running)
                  SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.8,
                      color: statusColor,
                    ),
                  )
                else
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                const SizedBox(width: 6),
                Text(
                  status.label,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '运行结果',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: palette.text,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              controller.activeFile.fileName,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
            ),
          ),
          const Spacer(),
          if (status == RunStatus.running)
            IconButton(
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              tooltip: '停止运行',
              onPressed: controller.cancelRun,
              icon: const Icon(Icons.stop_circle_outlined),
            ),
          IconButton(
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            tooltip: '复制全部输出',
            onPressed: controller.consoleMessages.isEmpty
                ? null
                : () => _copyAll(context),
            icon: const Icon(Icons.copy_all_outlined),
          ),
          IconButton(
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            tooltip: '清空输出',
            onPressed: controller.clearConsole,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
          IconButton(
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            tooltip: '收起',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.keyboard_arrow_down),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Color _statusColor(ColorScheme scheme, RunStatus status) {
    switch (status) {
      case RunStatus.idle:
        return scheme.onSurfaceVariant;
      case RunStatus.running:
        return scheme.primary;
      case RunStatus.success:
        return const Color(0xFF57C77D);
      case RunStatus.failed:
        return const Color(0xFFFF6B6B);
      case RunStatus.cancelled:
        return const Color(0xFFFFB454);
    }
  }

  Future<void> _copyAll(BuildContext context) async {
    final String text =
        controller.consoleMessages.map((ConsoleMessage m) => m.text).join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已复制 ${controller.consoleMessages.length} 行输出'),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
