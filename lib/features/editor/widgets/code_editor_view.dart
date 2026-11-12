import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/text/code_indent_formatter.dart';
import '../../../core/text/completion.dart';
import '../../../core/theme/app_theme.dart';
import 'completion_strip.dart';
import 'symbol_bar.dart';

/// 代码编辑区：左侧行号栏 + 右侧多行文本输入。
///
/// 骨架阶段刻意使用原生 [TextField]：没有第三方依赖，保证 `flutter pub get`
/// 一定能通过。Phase 2 会替换为带语法高亮的 `CodeField` / `flutter_highlight`。
class CodeEditorView extends StatefulWidget {
  const CodeEditorView({
    super.key,
    required this.controller,
    required this.fontSize,
    this.showLineNumbers = true,
    this.onChanged,
    this.onZoom,
    this.showCompletions = true,
  });

  final TextEditingController controller;
  final double fontSize;
  final bool showLineNumbers;
  final ValueChanged<String>? onChanged;

  /// 双指缩放时回调新的字号（由页面写回设置）。
  final ValueChanged<double>? onZoom;

  /// 是否显示补全候选条。
  final bool showCompletions;

  @override
  State<CodeEditorView> createState() => _CodeEditorViewState();
}

class _CodeEditorViewState extends State<CodeEditorView> {
  final ScrollController _codeScroll = ScrollController();
  final ScrollController _gutterScroll = ScrollController();

  double _zoomBase = 0;

  @override
  void initState() {
    super.initState();
    _codeScroll.addListener(_syncGutter);
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(CodeEditorView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTextChanged);
      widget.controller.addListener(_onTextChanged);
      setState(() {});
    }
  }

  void _onTextChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  /// 行号栏跟随代码区滚动（行号栏自身禁止滚动）。
  void _syncGutter() {
    if (!_gutterScroll.hasClients || !_codeScroll.hasClients) {
      return;
    }
    final double max = _gutterScroll.position.maxScrollExtent;
    final double offset = _codeScroll.offset;
    final double target = offset < 0 ? 0 : (offset > max ? max : offset);
    _gutterScroll.jumpTo(target);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _codeScroll.removeListener(_syncGutter);
    _codeScroll.dispose();
    _gutterScroll.dispose();
    super.dispose();
  }

  /// 光标当前所在行（1 起）。行号栏据此高亮，方便定位。
  int get _caretLine {
    final int offset = widget.controller.selection.baseOffset;
    if (offset < 0) {
      return 1;
    }
    final String text = widget.controller.text;
    final int end = offset > text.length ? text.length : offset;
    int line = 1;
    for (int i = 0; i < end; i++) {
      if (text.codeUnitAt(i) == 10) {
        line++;
      }
    }
    return line;
  }

  List<CompletionItem> _suggestions() {
    if (!widget.showCompletions || !widget.controller.selection.isValid) {
      return const <CompletionItem>[];
    }
    if (!widget.controller.selection.isCollapsed) {
      return const <CompletionItem>[];
    }
    return suggestCompletions(
      widget.controller.text,
      widget.controller.selection.baseOffset,
    );
  }

  void _applyCompletion(CompletionItem item) {
    final TextEditingValue value = widget.controller.value;
    final ({String text, int caret}) updated = applyCompletion(
      value.text,
      value.selection.baseOffset,
      item,
    );
    widget.controller.value = TextEditingValue(
      text: updated.text,
      selection: TextSelection.collapsed(offset: updated.caret),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String text = widget.controller.text;
    final int lineCount = text.isEmpty ? 1 : '\n'.allMatches(text).length + 1;
    final int activeLine = _caretLine;
    final TextStyle monoStyle = AppTheme.mono(
      fontSize: widget.fontSize,
      color: palette.text,
    );
    final int digits = lineCount.toString().length;

    return Column(
      children: <Widget>[
        Expanded(
          child: GestureDetector(
            // 双指缩放调字号；单指仍由 TextField 处理选择与光标（子级手势优先）
            onScaleStart: (ScaleStartDetails details) {
              _zoomBase = widget.fontSize;
            },
            onScaleUpdate: (ScaleUpdateDetails details) {
              if (details.pointerCount < 2 || widget.onZoom == null) {
                return;
              }
              final double next = _zoomBase * details.scale;
              widget.onZoom!(next.clamp(AppConstants.minFontSize, AppConstants.maxFontSize));
            },
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (widget.showLineNumbers)
                Container(
                  width: digits * widget.fontSize * 0.68 + 22,
                  decoration: BoxDecoration(
                    color: palette.gutter,
                    border: Border(right: BorderSide(color: palette.border)),
                  ),
                  child: SingleChildScrollView(
                    controller: _gutterScroll,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: <Widget>[
                        for (int i = 1; i <= lineCount; i++)
                          Container(
                            padding: const EdgeInsets.only(right: 10),
                            decoration: BoxDecoration(
                              border: Border(
                                right: BorderSide(
                                  color: i == activeLine
                                      ? palette.accent
                                      : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                            ),
                            child: Text(
                              '$i',
                              style: monoStyle.copyWith(
                                fontSize: widget.fontSize * 0.92,
                                color: i == activeLine
                                    ? palette.accent
                                    : palette.textMuted.withValues(alpha: 0.7),
                                fontWeight:
                                    i == activeLine ? FontWeight.w600 : null,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
        Expanded(
          child: Container(
            color: palette.code,
            padding: const EdgeInsets.fromLTRB(10, 12, 12, 12),
            child: TextField(
              controller: widget.controller,
              scrollController: _codeScroll,
              onChanged: widget.onChanged,
              expands: true,
              maxLines: null,
              minLines: null,
              textAlignVertical: TextAlignVertical.top,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.none,
              autocorrect: false,
              enableSuggestions: false,
              style: monoStyle,
              cursorColor: scheme.primary,
              inputFormatters: const <TextInputFormatter>[
                CodeIndentFormatter(),
              ],
              decoration: const InputDecoration(
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: '在这里输入代码 ...',
              ),
            ),
          ),
        ),
            ],
          ),
        ),
        ),
        // 补全候选（有匹配才出现）
        CompletionStrip(items: _suggestions(), onPick: _applyCompletion),
        // 软键盘打不出符号，给它一排按钮
        CodeSymbolBar(
          controller: widget.controller,
          fontSize: widget.fontSize * 0.86,
        ),
      ],
    );
  }
}
