import 'package:flutter/material.dart';

import '../../../core/text/project_search.dart';
import '../../../core/text/text_search.dart';
import '../../../core/theme/app_theme.dart';

/// 编辑器顶部的「查找 / 替换」条。
///
/// 行为对齐桌面编辑器：`Enter` 找下一处、`Shift+Enter` 找上一处，
/// 命中数显示成 `3/12`，替换只动当前这一处，另有「全部替换」。
class FindBar extends StatefulWidget {
  const FindBar({
    super.key,
    required this.controller,
    required this.onClose,
    this.projectFiles = const <String, String>{},
    this.onOpenProjectMatch,
    this.autofocus = true,
  });

  /// 代码内容控制器（直接改它，编辑区立刻同步）。
  final TextEditingController controller;
  final VoidCallback onClose;
  final bool autofocus;

  /// 工程内所有文件（路径 → 内容），用于「全工程」搜索。
  final Map<String, String> projectFiles;

  /// 点工程搜索结果时回调：切到该文件并选中。
  final void Function(ProjectMatch match)? onOpenProjectMatch;

  @override
  State<FindBar> createState() => _FindBarState();
}

class _FindBarState extends State<FindBar> {
  final TextEditingController _query = TextEditingController();
  final TextEditingController _replacement = TextEditingController();

  bool _caseSensitive = true;
  bool _showReplace = false;
  int _index = -1;
  List<TextMatch> _matches = const <TextMatch>[];
  bool _projectScope = false;
  List<ProjectMatch> _projectMatches = const <ProjectMatch>[];

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onCodeChanged);
    _query.addListener(_recompute);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onCodeChanged);
    _query.dispose();
    _replacement.dispose();
    super.dispose();
  }

  void _onCodeChanged() {
    if (!mounted) {
      return;
    }
    _recompute();
  }

  void _recompute() {
    final List<TextMatch> matches = findMatches(
      widget.controller.text,
      _query.text,
      caseSensitive: _caseSensitive,
    );
    setState(() {
      _matches = matches;
      _projectMatches = _projectScope
          ? searchProject(
              widget.projectFiles,
              _query.text,
              caseSensitive: _caseSensitive,
            )
          : const <ProjectMatch>[];
      if (_index >= matches.length) {
        _index = matches.isEmpty ? -1 : matches.length - 1;
      }
    });
  }

  void _step({required bool forward}) {
    final List<TextMatch> matches = findMatches(
      widget.controller.text,
      _query.text,
      caseSensitive: _caseSensitive,
    );
    if (matches.isEmpty) {
      setState(() {
        _matches = matches;
        _index = -1;
      });
      return;
    }
    final int next = stepIndex(_index, matches.length, forward: forward);
    final TextMatch match = matches[next];
    widget.controller.selection =
        TextSelection(baseOffset: match.start, extentOffset: match.end);
    setState(() {
      _matches = matches;
      _index = next;
    });
  }

  void _replaceCurrent() {
    final List<TextMatch> matches = findMatches(
      widget.controller.text,
      _query.text,
      caseSensitive: _caseSensitive,
    );
    if (matches.isEmpty) {
      return;
    }
    final int target = _index >= 0 && _index < matches.length ? _index : 0;
    final TextMatch match = matches[target];
    final String updated =
        replaceOne(widget.controller.text, match, _replacement.text);
    widget.controller.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(
        offset: match.start + _replacement.text.length,
      ),
    );
    _recompute();
    setState(() {
      _index = target < _matches.length ? target : _matches.length - 1;
    });
  }

  void _replaceAll() {
    final (String updated, int count) = replaceAllMatches(
      widget.controller.text,
      _query.text,
      _replacement.text,
      caseSensitive: _caseSensitive,
    );
    if (count == 0) {
      return;
    }
    widget.controller.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: updated.length),
    );
    _recompute();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已替换 $count 处'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    // 还没跳转时（_index = -1）也显示 1/N：表示「一共有 N 处，回车会到第 1 处」
    final int displayIndex = _index < 0 ? 0 : _index;
    final String counter = _query.text.isEmpty
        ? ''
        : (_matches.isEmpty ? '无匹配' : '${displayIndex + 1}/${_matches.length}');

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      decoration: BoxDecoration(
        color: AppPalette.of(context).panelAlt,
        border: Border(bottom: BorderSide(color: AppPalette.of(context).border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.search, size: 17, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: _field(
                  controller: _query,
                  hint: '查找',
                  autofocus: widget.autofocus,
                  onSubmitted: (_) => _step(forward: true),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                counter,
                style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
              ),
              // 工程里不止一个文件时才给「全工程」开关
              if (widget.projectFiles.isNotEmpty)
                IconButton(
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  tooltip: _projectScope ? '只搜当前文件' : '搜索整个工程',
                  onPressed: () {
                    setState(() {
                      _projectScope = !_projectScope;
                    });
                    _recompute();
                  },
                  icon: Icon(
                    _projectScope
                        ? Icons.travel_explore
                        : Icons.find_in_page_outlined,
                    size: 17,
                    color: _projectScope
                        ? scheme.primary
                        : scheme.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                ),
              IconButton(
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                tooltip: '区分大小写',
                onPressed: () {
                  setState(() {
                    _caseSensitive = !_caseSensitive;
                  });
                  _recompute();
                },
                icon: Icon(
                  Icons.text_fields,
                  size: 17,
                  color: _caseSensitive
                      ? scheme.primary
                      : scheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
              ),
              IconButton(
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                tooltip: '上一处（Shift+Enter）',
                onPressed: () => _step(forward: false),
                icon: const Icon(Icons.keyboard_arrow_up),
              ),
              IconButton(
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                tooltip: '下一处（Enter）',
                onPressed: () => _step(forward: true),
                icon: const Icon(Icons.keyboard_arrow_down),
              ),
              IconButton(
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                tooltip: _showReplace ? '隐藏替换' : '替换',
                onPressed: () => setState(() {
                  _showReplace = !_showReplace;
                }),
                icon: Icon(
                  Icons.find_replace,
                  size: 17,
                  color: _showReplace
                      ? scheme.primary
                      : scheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
              ),
              IconButton(
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                tooltip: '关闭查找',
                onPressed: widget.onClose,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          if (_projectScope && _projectMatches.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 168),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _projectMatches.length,
                itemBuilder: (BuildContext context, int index) {
                  final ProjectMatch match = _projectMatches[index];
                  return InkWell(
                    onTap: () => widget.onOpenProjectMatch?.call(match),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 6, 8, 6),
                      child: Row(
                        children: <Widget>[
                          SizedBox(
                            width: 96,
                            child: Text(
                              match.path,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.mono(
                                fontSize: 11,
                                color: scheme.primary,
                              ),
                            ),
                          ),
                          Text(
                            '${match.line}:${match.column}',
                            style: AppTheme.mono(
                              fontSize: 10.5,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              match.preview,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.mono(
                                fontSize: 11.5,
                                color: scheme.onSurface,
                              ),
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
          if (_showReplace) ...<Widget>[
            const SizedBox(height: 4),
            Row(
              children: <Widget>[
                const SizedBox(width: 23),
                Expanded(
                  child: _field(controller: _replacement, hint: '替换为'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _matches.isEmpty ? null : _replaceCurrent,
                  child: const Text('替换'),
                ),
                TextButton(
                  onPressed: _matches.isEmpty ? null : _replaceAll,
                  child: const Text('全部替换'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String hint,
    bool autofocus = false,
    ValueChanged<String>? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      onSubmitted: onSubmitted,
      autocorrect: false,
      enableSuggestions: false,
      style: AppTheme.mono(fontSize: 12.5),
      decoration: InputDecoration(
        isDense: true,
        filled: false,
        hintText: hint,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(vertical: 4),
      ),
    );
  }
}
