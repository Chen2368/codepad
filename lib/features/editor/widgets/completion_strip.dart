import 'package:flutter/material.dart';

import '../../../core/text/completion.dart';
import '../../../core/theme/app_theme.dart';

/// 补全候选条：编辑区上方一行，显示按当前前缀匹配的片段/函数，点一下插入。
///
/// 平板上打字慢，补全比语法高亮更省事；这里只做「前缀匹配 + 点击插入」，
/// 不做自动弹出抢焦点的行为，避免打断输入。
class CompletionStrip extends StatelessWidget {
  const CompletionStrip({
    super.key,
    required this.items,
    required this.onPick,
    this.maxWidth = 640,
  });

  final List<CompletionItem> items;
  final ValueChanged<CompletionItem> onPick;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    final AppPalette palette = AppPalette.of(context);

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: palette.panel,
        border: Border(
          top: BorderSide(color: palette.border),
          bottom: BorderSide(color: palette.border),
        ),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        itemCount: items.length,
        separatorBuilder: (BuildContext context, int index) =>
            const SizedBox(width: 6),
        itemBuilder: (BuildContext context, int index) {
          final CompletionItem item = items[index];
          return InkWell(
            borderRadius: BorderRadius.circular(AppRadius.chip),
            onTap: () => onPick(item),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: item.isSnippet
                    ? palette.accent.withValues(alpha: 0.12)
                    : palette.panelAlt,
                borderRadius: BorderRadius.circular(AppRadius.chip),
                border: Border.all(
                  color: item.isSnippet
                      ? palette.accent.withValues(alpha: 0.4)
                      : palette.border,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (item.isSnippet) ...<Widget>[
                    Icon(Icons.bolt, size: 12, color: palette.accent),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    item.label,
                    style: AppTheme.mono(
                      fontSize: 12,
                      color: item.isSnippet ? palette.accent : palette.text,
                    ),
                  ),
                  if (item.detail.isNotEmpty) ...<Widget>[
                    const SizedBox(width: 6),
                    Text(
                      item.detail,
                      style: TextStyle(
                        fontSize: 9.5,
                        color: palette.textMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
