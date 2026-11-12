import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/console_message.dart';
import '../../../runtime/compile_diagnostic.dart';

/// 编译问题面板：把控制台里「带位置」的诊断单独列出来，一条一行、点哪跳哪。
///
/// 和控制台的区别：控制台是"时间轴"（含运行输出、提示），这里是"清单"，
/// 修错时只需要看它。
class ProblemsPanel extends StatelessWidget {
  const ProblemsPanel({
    super.key,
    required this.messages,
    required this.onTapDiagnostic,
    required this.onClose,
  });

  final List<ConsoleMessage> messages;
  final ValueChanged<CompileDiagnostic> onTapDiagnostic;
  final VoidCallback onClose;

  List<ConsoleMessage> get _problems =>
      messages.where((ConsoleMessage m) => m.isJumpable).toList();

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final List<ConsoleMessage> problems = _problems;
    final int errors = problems
        .where((ConsoleMessage m) => m.level == ConsoleLevel.error)
        .length;
    final int warnings = problems.length - errors;

    return Container(
      decoration: BoxDecoration(
        color: palette.panel,
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
                Icon(Icons.error_outline, size: 15, color: palette.danger),
                const SizedBox(width: 6),
                Text(
                  '问题 ${problems.length}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: palette.text,
                  ),
                ),
                const SizedBox(width: 10),
                if (errors > 0) _chip(palette, '$errors 错误', palette.danger),
                if (warnings > 0) ...<Widget>[
                  const SizedBox(width: 6),
                  _chip(palette, '$warnings 提示', palette.warning),
                ],
                const Spacer(),
                IconButton(
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  tooltip: '收起问题面板',
                  onPressed: onClose,
                  icon: const Icon(Icons.keyboard_arrow_down),
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
          Divider(height: 1, color: palette.border),
          Expanded(
            child: problems.isEmpty
                ? Center(
                    child: Text(
                      '没有编译问题',
                      style: TextStyle(fontSize: 12, color: palette.textMuted),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: problems.length,
                    itemBuilder: (BuildContext context, int index) {
                      final ConsoleMessage message = problems[index];
                      final CompileDiagnostic diagnostic = message.diagnostic!;
                      final Color color = message.level == ConsoleLevel.error
                          ? palette.danger
                          : palette.warning;
                      return InkWell(
                        onTap: () => onTapDiagnostic(diagnostic),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 7, 12, 7),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Icon(
                                message.level == ConsoleLevel.error
                                    ? Icons.cancel_outlined
                                    : Icons.warning_amber_rounded,
                                size: 14,
                                color: color,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  message.text,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: palette.text,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${diagnostic.file}:${diagnostic.line}',
                                style: AppTheme.mono(
                                  fontSize: 10.5,
                                  color: palette.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _chip(AppPalette palette, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
