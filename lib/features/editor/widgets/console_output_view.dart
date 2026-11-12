import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/console_message.dart';
import '../../../runtime/compile_diagnostic.dart';

/// 控制台/运行窗口共用的输出区：逐行渲染 + 自动滚到底 + 点错误跳行。
///
/// 抽出来是因为「内嵌控制台」和「弹出的运行窗口」要显示同一份输出，
/// 各写一遍必然会走样（0.5.x 之前就是这样）。
class ConsoleOutputView extends StatefulWidget {
  const ConsoleOutputView({
    super.key,
    required this.messages,
    this.onTapDiagnostic,
    this.emptyHint = '点击工具栏的「运行」查看输出',
    this.padding = const EdgeInsets.fromLTRB(12, 0, 12, 8),
    this.scrollController,
  });

  final List<ConsoleMessage> messages;
  final ValueChanged<CompileDiagnostic>? onTapDiagnostic;
  final String emptyHint;
  final EdgeInsets padding;

  /// 外部传入的滚动控制器（运行窗口交给 [DraggableScrollableSheet] 拖拽用）。
  final ScrollController? scrollController;

  @override
  State<ConsoleOutputView> createState() => _ConsoleOutputViewState();
}

class _ConsoleOutputViewState extends State<ConsoleOutputView> {
  final ScrollController _own = ScrollController();

  ScrollController get _scroll => widget.scrollController ?? _own;

  @override
  void initState() {
    super.initState();
    _scrollToBottom();
  }

  @override
  void didUpdateWidget(ConsoleOutputView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.messages.length != widget.messages.length) {
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) {
        return;
      }
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    if (widget.scrollController == null) {
      _own.dispose();
    }
    super.dispose();
  }

  static Color lineColor(BuildContext context, ConsoleLevel level) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    switch (level) {
      case ConsoleLevel.info:
        return scheme.primary;
      case ConsoleLevel.output:
        return scheme.onSurface;
      case ConsoleLevel.error:
        return const Color(0xFFFF6B6B);
      case ConsoleLevel.success:
        return const Color(0xFF57C77D);
      case ConsoleLevel.input:
        return const Color(0xFF57C77D);
      case ConsoleLevel.hint:
        return const Color(0xFFFFB454);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    if (widget.messages.isEmpty) {
      return Center(
        child: Text(
          widget.emptyHint,
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
      );
    }

    return ListView.builder(
      controller: _scroll,
      padding: widget.padding,
      itemCount: widget.messages.length,
      itemBuilder: (BuildContext context, int index) =>
          _buildLine(context, widget.messages[index]),
    );
  }

  Widget _buildLine(BuildContext context, ConsoleMessage message) {
    final CompileDiagnostic? diagnostic = message.diagnostic;
    final bool jumpable = message.isJumpable && widget.onTapDiagnostic != null;

    if (!jumpable) {
      return SelectableText(
        message.text,
        style: AppTheme.mono(
          fontSize: 12,
          color: lineColor(context, message.level),
        ),
      );
    }

    final Color color = lineColor(context, message.level);
    final String location = '${diagnostic!.file}:${diagnostic.line}';

    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () => widget.onTapDiagnostic!(diagnostic),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Text(
                message.text,
                style: AppTheme.mono(fontSize: 12, color: color),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: <Widget>[
                  Icon(Icons.my_location, size: 11, color: color),
                  const SizedBox(width: 3),
                  Text(
                    '第 ${diagnostic.line} 行',
                    style: TextStyle(fontSize: 10.5, color: color),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: location));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(location), duration: const Duration(seconds: 2)),
        );
      },
    );
  }
}
