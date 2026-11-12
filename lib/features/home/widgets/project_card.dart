import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/project.dart';
import '../../editor/widgets/file_tab_bar.dart';

/// 首页的工程卡片：左侧语言色条 + 语言徽标 + 名称/元信息。
class ProjectCard extends StatelessWidget {
  const ProjectCard({
    super.key,
    required this.project,
    required this.onTap,
    required this.onDelete,
  });

  final Project project;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color accent = languageColor(project.language);

    return Material(
      color: palette.panel,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: palette.border),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // 左侧语言色条：一眼分辨语言，比纯文字徽标更快
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(AppRadius.card),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 13, 6, 13),
                    child: Row(
                      children: <Widget>[
                        Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(
                              color: accent.withValues(alpha: 0.28),
                            ),
                          ),
                          child: Text(
                            project.language.label,
                            style: TextStyle(
                              fontSize:
                                  project.language.label.length > 2 ? 10.5 : 13,
                              fontWeight: FontWeight.w700,
                              color: accent,
                            ),
                          ),
                        ),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              Text(
                                project.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w600,
                                  color: palette.text,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Row(
                                children: <Widget>[
                                  _meta(
                                    palette,
                                    Icons.description_outlined,
                                    '${project.fileCount} 个文件',
                                  ),
                                  const SizedBox(width: 12),
                                  _meta(
                                    palette,
                                    Icons.schedule,
                                    formatRelativeTime(project.updatedAt),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: '删除工程',
                          onPressed: onDelete,
                          iconSize: 18,
                          color: scheme.onSurfaceVariant,
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _meta(AppPalette palette, IconData icon, String text) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 12, color: palette.textMuted.withValues(alpha: 0.9)),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(fontSize: 11.5, color: palette.textMuted),
        ),
      ],
    );
  }
}

/// 相对时间格式化：刚刚 / N 分钟前 / N 小时前 / N 天前 / 具体日期。
String formatRelativeTime(DateTime time) {
  final Duration diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) {
    return '刚刚';
  }
  if (diff.inMinutes < 60) {
    return '${diff.inMinutes} 分钟前';
  }
  if (diff.inHours < 24) {
    return '${diff.inHours} 小时前';
  }
  if (diff.inDays < 30) {
    return '${diff.inDays} 天前';
  }
  final String month = time.month.toString().padLeft(2, '0');
  final String day = time.day.toString().padLeft(2, '0');
  return '${time.year}-$month-$day';
}
