import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// 空状态占位：列表为空、加载失败时使用。
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final TextTheme text = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // 双层圆底：外层淡淡的光晕，内层是图标，比单个大图标更像成品
            Container(
              width: 92,
              height: 92,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: palette.accent.withValues(alpha: 0.06),
              ),
              child: Container(
                width: 62,
                height: 62,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: palette.accent.withValues(alpha: 0.12),
                  border: Border.all(
                    color: palette.accent.withValues(alpha: 0.22),
                  ),
                ),
                child: Icon(icon, size: 28, color: palette.accent),
              ),
            ),
            const SizedBox(height: 20),
            Text(title, style: text.titleMedium),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(
                color: palette.textMuted,
                height: 1.55,
              ),
            ),
            if (action != null) ...<Widget>[
              const SizedBox(height: 22),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
