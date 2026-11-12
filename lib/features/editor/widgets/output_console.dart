import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/console_message.dart';
import '../../../data/models/run_result.dart';
import '../../../runtime/compile_diagnostic.dart';
import 'console_input_row.dart';
import 'console_output_view.dart';

/// 底部输出控制台（内嵌版）：与弹出式运行窗口共用同一份渲染与输入行。
class OutputConsole extends StatefulWidget {
  const OutputConsole({
    super.key,
    required this.messages,
    required this.status,
    required this.onClear,
    required this.onClose,
    this.onSendInput,
    this.onEndInput,
    this.onTapDiagnostic,
    this.canSendInput = false,
  });

  final List<ConsoleMessage> messages;
  final RunStatus status;
  final VoidCallback onClear;
  final VoidCallback onClose;

  /// 把一行文本送进正在运行的程序（scanf / input 用）。
  final ValueChanged<String>? onSendInput;

  /// 结束标准输入（EOF）。
  final VoidCallback? onEndInput;

  /// 点击带位置的编译诊断 → 跳到源码对应行。
  final ValueChanged<CompileDiagnostic>? onTapDiagnostic;

  /// 程序正在运行且支持标准输入时为 true。
  final bool canSendInput;

  @override
  State<OutputConsole> createState() => _OutputConsoleState();
}

class _OutputConsoleState extends State<OutputConsole> {
  Color _statusColor(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    switch (widget.status) {
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
        widget.messages.map((ConsoleMessage m) => m.text).join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已复制 ${widget.messages.length} 行控制台内容'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color statusColor = _statusColor(context);

    final AppPalette palette = AppPalette.of(context);

    return Container(
      decoration: BoxDecoration(
        color: palette.panelAlt,
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            height: 38,
            child: Row(
              children: <Widget>[
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '控制台 · ${widget.status.label}',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.messages.any((ConsoleMessage m) => m.isJumpable)) ...<Widget>[
                  const SizedBox(width: 10),
                  Text(
                    '（点错误可跳到对应行）',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
                    ),
                  ),
                ],
                const Spacer(),
                IconButton(
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  tooltip: '复制全部输出',
                  onPressed:
                      widget.messages.isEmpty ? null : () => _copyAll(context),
                  icon: const Icon(Icons.copy_all_outlined),
                ),
                IconButton(
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  tooltip: '清空控制台',
                  onPressed: widget.onClear,
                  icon: const Icon(Icons.delete_sweep_outlined),
                ),
                IconButton(
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  tooltip: '收起控制台',
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.keyboard_arrow_down),
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
          Expanded(
            child: ConsoleOutputView(
              messages: widget.messages,
              onTapDiagnostic: widget.onTapDiagnostic,
            ),
          ),
          if (widget.onSendInput != null)
            ConsoleInputRow(
              enabled: widget.canSendInput,
              onSendInput: widget.onSendInput,
              onEndInput: widget.onEndInput,
            ),
        ],
      ),
    );
  }
}
