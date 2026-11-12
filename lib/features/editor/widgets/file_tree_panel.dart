import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

import '../../../data/models/source_file.dart';
import 'file_tab_bar.dart';

/// 左侧文件树：按目录分组显示工程内全部文件。
///
/// Phase 2 起支持新建 / 重命名 / 删除（通过 [onCreate] / [onRename] / [onDelete]）。
class FileTreePanel extends StatelessWidget {
  const FileTreePanel({
    super.key,
    required this.files,
    required this.activePath,
    required this.onSelect,
    this.onCreate,
    this.onRename,
    this.onDelete,
  });

  final List<SourceFile> files;
  final String activePath;
  final ValueChanged<String> onSelect;
  final VoidCallback? onCreate;
  final ValueChanged<String>? onRename;
  final ValueChanged<String>? onDelete;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    final Map<String, List<SourceFile>> groups = <String, List<SourceFile>>{};
    for (final SourceFile file in files) {
      groups.putIfAbsent(file.folder, () => <SourceFile>[]).add(file);
    }
    final List<String> folders = groups.keys.toList()..sort();

    final AppPalette palette = AppPalette.of(context);

    return Container(
      color: palette.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 6, 6),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.folder_open_outlined,
                  size: 15,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '资源管理器',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 0.6,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (onCreate != null)
                  IconButton(
                    tooltip: '新建文件',
                    iconSize: 17,
                    visualDensity: VisualDensity.compact,
                    onPressed: onCreate,
                    icon: const Icon(Icons.note_add_outlined),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 16),
              children: <Widget>[
                for (final String folder in folders)
                  ..._buildFolder(
                    context,
                    folder,
                    groups[folder] ?? const <SourceFile>[],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildFolder(
    BuildContext context,
    String folder,
    List<SourceFile> folderFiles,
  ) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return <Widget>[
      if (folder.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 14, 4),
          child: Row(
            children: <Widget>[
              Icon(Icons.folder_outlined, size: 14, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  folder,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      for (final SourceFile file in folderFiles)
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => onSelect(file.path),
            onLongPress: onRename == null ? null : () => onRename!(file.path),
            child: Container(
              height: 36,
              padding: EdgeInsets.only(left: folder.isEmpty ? 18 : 32, right: 4),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    width: 2,
                    color: file.path == activePath
                        ? scheme.primary
                        : Colors.transparent,
                  ),
                ),
                color: file.path == activePath
                    ? scheme.primary.withValues(alpha: 0.08)
                    : Colors.transparent,
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.description_outlined,
                    size: 14,
                    color: languageColor(file.language),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      file.fileName,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: file.path == activePath
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                  if (onRename != null)
                    PopupMenuButton<String>(
                      tooltip: '文件操作',
                      iconSize: 16,
                      padding: EdgeInsets.zero,
                      icon: Icon(Icons.more_vert, color: scheme.onSurfaceVariant),
                      onSelected: (String action) {
                        if (action == 'rename') {
                          onRename!(file.path);
                        } else if (action == 'delete') {
                          onDelete?.call(file.path);
                        }
                      },
                      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                        const PopupMenuItem<String>(
                          value: 'rename',
                          child: Text('重命名 / 移动'),
                        ),
                        const PopupMenuItem<String>(
                          value: 'delete',
                          child: Text('删除文件'),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
    ];
  }
}
