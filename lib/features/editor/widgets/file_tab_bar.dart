import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/program_language.dart';
import '../../../data/models/source_file.dart';

/// 语言标识色的统一取色，文件树与标签页共用。
Color languageColor(ProgramLanguage? language) {
  switch (language) {
    case ProgramLanguage.c:
      return const Color(0xFF6FA8DC);
    case ProgramLanguage.cpp:
      return const Color(0xFF4F8CFF);
    case ProgramLanguage.python:
      return const Color(0xFFF2C94C);
    case null:
      return const Color(0xFF9AA4B2);
  }
}

/// 顶部文件标签页：活动标签用「底色 + 底部色条」表示，比描边更轻。
class FileTabBar extends StatelessWidget {
  const FileTabBar({
    super.key,
    required this.files,
    required this.activeIndex,
    required this.onSelect,
  });

  final List<SourceFile> files;
  final int activeIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);

    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: palette.panel,
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: files.length,
        separatorBuilder: (BuildContext context, int index) =>
            const SizedBox(width: 2),
        itemBuilder: (BuildContext context, int index) {
          final SourceFile file = files[index];
          final bool active = index == activeIndex;
          final Color dot = languageColor(file.language);

          return InkWell(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppRadius.chip),
            ),
            onTap: () => onSelect(index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: active ? palette.panelAlt : Colors.transparent,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppRadius.chip),
                ),
                border: Border(
                  bottom: BorderSide(
                    color: active ? palette.accent : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: dot.withValues(alpha: active ? 1 : 0.55),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    file.fileName,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                      color: active ? palette.text : palette.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
