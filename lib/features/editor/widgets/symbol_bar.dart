import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// 代码符号快捷条：平板上软键盘打不出 `{ } ( ) ; " < >` 这些符号，
/// 这里给一排按钮，点一下就插入到光标处。
///
/// 三个细节：
/// 1. **成对补全**：点 `(` 直接得到 `()`，光标落在中间；
/// 2. **选中包裹**：先选中一段再点 `{`，会变成 `{选中内容}`；
/// 3. **Tab**：插入一个缩进单位（4 空格）。
class CodeSymbolBar extends StatelessWidget {
  const CodeSymbolBar({
    super.key,
    required this.controller,
    this.fontSize = 12.5,
    this.indent = '    ',
  });

  final TextEditingController controller;
  final double fontSize;
  final String indent;

  /// 需要成对补全的符号。
  static const Map<String, String> pairs = <String, String>{
    '(': ')',
    '[': ']',
    '{': '}',
    '"': '"',
    "'": "'",
    '<': '>',
  };

  /// 常用符号（按写 C 的出现频率排）。
  static const List<String> symbols = <String>[
    ';',
    '{',
    '}',
    '(',
    ')',
    '[',
    ']',
    '"',
    "'",
    '<',
    '>',
    '=',
    '==',
    '!=',
    '&&',
    '||',
    '+',
    '-',
    '*',
    '/',
    '%',
    '&',
    '|',
    '!',
    '#',
    ',',
    '.',
    '->',
    '++',
    '--',
    '//',
    '0',
    '1.0',
  ];

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);

    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: palette.panelAlt,
        border: Border(top: BorderSide(color: palette.border)),
      ),
      // 不能抢走编辑器的焦点，否则点一下符号软键盘就收了
      child: ExcludeFocus(
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          children: <Widget>[
            _button(
              context,
              palette,
              label: 'Tab',
              tooltip: '插入缩进（4 空格）',
              emphasised: true,
              onTap: () => insert(indent),
            ),
            _separator(palette),
            for (int i = 0; i < symbols.length; i++) ...<Widget>[
              _button(
                context,
                palette,
                label: symbols[i],
                onTap: () => insert(symbols[i]),
              ),
              // 每 8 个插入一条细分隔线，视觉上分出「分组」，长条也不容易看花
              if ((i + 1) % 8 == 0 && i != symbols.length - 1)
                _separator(palette),
            ],
          ],
        ),
      ),
    );
  }

  Widget _separator(AppPalette palette) {
    return Container(
      width: 1,
      height: 18,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      alignment: Alignment.center,
      color: palette.border,
    );
  }

  Widget _button(
    BuildContext context,
    AppPalette palette, {
    required String label,
    required VoidCallback onTap,
    String? tooltip,
    bool emphasised = false,
  }) {
    final Widget button = InkWell(
      borderRadius: BorderRadius.circular(AppRadius.chip),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minWidth: 34),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        margin: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: emphasised
              ? palette.accent.withValues(alpha: 0.14)
              : palette.panel,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          border: Border.all(
            color: emphasised
                ? palette.accent.withValues(alpha: 0.45)
                : palette.border,
          ),
        ),
        child: Text(
          label,
          style: AppTheme.mono(
            fontSize: fontSize,
            color: emphasised ? palette.accent : palette.text,
          ).copyWith(fontWeight: emphasised ? FontWeight.w600 : null),
        ),
      ),
    );
    if (tooltip == null) {
      return button;
    }
    return Tooltip(message: tooltip, child: button);
  }

  /// 把 [token] 插入光标处；成对符号补全右半边，选中内容时包裹选区。
  void insert(String token) {
    final TextEditingValue value = controller.value;
    final String text = value.text;
    TextSelection selection = value.selection;
    if (!selection.isValid) {
      selection = TextSelection.collapsed(offset: text.length);
    }
    final String? closer = pairs[token];

    if (!selection.isCollapsed) {
      final String selected = text.substring(selection.start, selection.end);
      final String replacement =
          closer == null ? token : '$token$selected$closer';
      final String updated =
          text.replaceRange(selection.start, selection.end, replacement);
      controller.value = TextEditingValue(
        text: updated,
        selection: TextSelection.collapsed(
          offset: selection.start + replacement.length,
        ),
      );
      return;
    }

    final String insertion = closer == null ? token : '$token$closer';
    final int caret = selection.start;
    final String updated = text.replaceRange(caret, caret, insertion);
    controller.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(
        offset: caret + (closer == null ? insertion.length : 1),
      ),
    );
  }
}
