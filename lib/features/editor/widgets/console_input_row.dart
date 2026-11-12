import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// 运行窗口底部的那一行标准输入（scanf / input 用）。
///
/// 内嵌控制台和弹出运行窗口共用，保证两头行为一致。
class ConsoleInputRow extends StatefulWidget {
  const ConsoleInputRow({
    super.key,
    this.onSendInput,
    this.onEndInput,
    this.enabled = false,
    this.autofocus = false,
  });

  final ValueChanged<String>? onSendInput;
  final VoidCallback? onEndInput;
  final bool enabled;
  final bool autofocus;

  @override
  State<ConsoleInputRow> createState() => _ConsoleInputRowState();
}

class _ConsoleInputRowState extends State<ConsoleInputRow> {
  final TextEditingController _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _submit() {
    final String text = _input.text;
    final ValueChanged<String>? handler = widget.onSendInput;
    if (handler == null || text.isEmpty) {
      return;
    }
    handler(text);
    _input.clear();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Container(
      height: 40,
      padding: const EdgeInsets.fromLTRB(12, 0, 6, 0),
      child: Row(
        children: <Widget>[
          Text(
            'stdin',
            style: AppTheme.mono(
              fontSize: 11,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _input,
              enabled: widget.enabled,
              autofocus: widget.autofocus,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _submit(),
              style: AppTheme.mono(fontSize: 12),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: widget.enabled
                    ? '程序正在运行，可在此输入一行并回车'
                    : '程序运行时可在此输入',
                hintStyle: TextStyle(
                  fontSize: 11.5,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                ),
              ),
            ),
          ),
          IconButton(
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            tooltip: '发送这一行（回车）',
            onPressed: widget.enabled ? _submit : null,
            icon: const Icon(Icons.send),
          ),
          if (widget.onEndInput != null)
            IconButton(
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              tooltip: '结束输入（EOF）',
              onPressed: widget.enabled ? widget.onEndInput : null,
              icon: const Icon(Icons.done_all),
            ),
        ],
      ),
    );
  }
}
