import 'package:flutter/material.dart';

import '../constants/app_constants.dart';

/// 语义化配色：界面各处只认这些名字，不直接写十六进制。
///
/// 这样做的好处是「换主题」= 换一张表，而不会出现某个页面忘记改、
/// 在深色模式下刺眼的情况。
class AppPalette {
  const AppPalette({
    required this.brightness,
    required this.scaffold,
    required this.panel,
    required this.panelAlt,
    required this.border,
    required this.borderStrong,
    required this.text,
    required this.textMuted,
    required this.accent,
    required this.accentSoft,
    required this.success,
    required this.warning,
    required this.danger,
    required this.gutter,
    required this.code,
  });

  final Brightness brightness;

  /// 页面底色。
  final Color scaffold;

  /// 卡片 / 面板底色。
  final Color panel;

  /// 次级面板（工具栏、标签栏、符号条）。
  final Color panelAlt;

  final Color border;
  final Color borderStrong;

  final Color text;
  final Color textMuted;

  final Color accent;
  final Color accentSoft;

  final Color success;
  final Color warning;
  final Color danger;

  /// 行号栏底色。
  final Color gutter;

  /// 代码区底色（比面板再深/浅一点，像纸面）。
  final Color code;

  static const AppPalette dark = AppPalette(
    brightness: Brightness.dark,
    scaffold: Color(0xFF0D1117),
    panel: Color(0xFF151B23),
    panelAlt: Color(0xFF1A212B),
    border: Color(0xFF232C38),
    borderStrong: Color(0xFF2E3947),
    text: Color(0xFFE6EDF3),
    textMuted: Color(0xFF8B97A6),
    accent: Color(0xFF6E9BFF),
    accentSoft: Color(0xFF2A3B57),
    success: Color(0xFF4ADE80),
    warning: Color(0xFFF5B454),
    danger: Color(0xFFFF6B6B),
    gutter: Color(0xFF11171F),
    code: Color(0xFF10161E),
  );

  static const AppPalette light = AppPalette(
    brightness: Brightness.light,
    scaffold: Color(0xFFF5F7FB),
    panel: Color(0xFFFFFFFF),
    panelAlt: Color(0xFFF0F3F9),
    border: Color(0xFFE2E8F0),
    borderStrong: Color(0xFFCBD5E1),
    text: Color(0xFF141A21),
    textMuted: Color(0xFF64748B),
    accent: Color(0xFF2F6BFF),
    accentSoft: Color(0xFFE3ECFF),
    success: Color(0xFF14A05A),
    warning: Color(0xFFB4700A),
    danger: Color(0xFFD93A3A),
    gutter: Color(0xFFF0F3F9),
    code: Color(0xFFFFFFFF),
  );

  static AppPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}

/// 统一的圆角与间距，避免各页面各写一套数字。
class AppRadius {
  AppRadius._();

  static const double card = 14;
  static const double panel = 16;
  static const double control = 10;
  static const double chip = 8;
}

/// 应用主题：深色 / 浅色两套，均基于 Material 3。
class AppTheme {
  AppTheme._();

  static ThemeData light() => _build(AppPalette.light);

  static ThemeData dark() => _build(AppPalette.dark);

  /// 代码区域的等宽文字样式。
  static TextStyle mono({required double fontSize, Color? color}) {
    return TextStyle(
      fontFamily: AppConstants.monoFontFamily,
      fontSize: fontSize,
      height: 1.5,
      color: color,
    );
  }

  static ThemeData _build(AppPalette palette) {
    final bool isDark = palette.brightness == Brightness.dark;
    final ColorScheme base = ColorScheme.fromSeed(
      seedColor: AppConstants.seedColor,
      brightness: palette.brightness,
    );

    // 用语义色覆盖 Material 的默认调色，保证所有组件取到的都是同一套颜色。
    final ColorScheme scheme = base.copyWith(
      primary: palette.accent,
      onPrimary: isDark ? const Color(0xFF0B1220) : Colors.white,
      primaryContainer: palette.accentSoft,
      onPrimaryContainer: palette.text,
      secondary: palette.accent,
      surface: palette.panel,
      onSurface: palette.text,
      onSurfaceVariant: palette.textMuted,
      surfaceContainerLowest: palette.scaffold,
      surfaceContainerLow: palette.panel,
      surfaceContainer: palette.panelAlt,
      surfaceContainerHigh: palette.panelAlt,
      surfaceContainerHighest: palette.panelAlt,
      outline: palette.borderStrong,
      outlineVariant: palette.border,
      error: palette.danger,
    );

    final TextTheme text = _textTheme(palette);

    return ThemeData(
      useMaterial3: true,
      brightness: palette.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: palette.scaffold,
      textTheme: text,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      dividerTheme: DividerThemeData(
        thickness: 1,
        space: 1,
        color: palette.border.withValues(alpha: 0.9),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: palette.scaffold,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleMedium,
        iconTheme: IconThemeData(color: palette.textMuted, size: 21),
      ),
      cardTheme: CardThemeData(
        color: palette.panel,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(color: palette.border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.panel,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.panel),
          side: BorderSide(color: palette.border),
        ),
        titleTextStyle: text.titleMedium,
        contentTextStyle: text.bodyMedium,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.panel,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: palette.panel,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.panel)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.text,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          side: BorderSide(color: palette.borderStrong),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: palette.accent,
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.chip),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: palette.textMuted),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: palette.accent,
        foregroundColor: isDark ? const Color(0xFF0B1220) : Colors.white,
        elevation: 2,
        highlightElevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.panelAlt,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        hintStyle: TextStyle(color: palette.textMuted, fontSize: 12.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: BorderSide(color: palette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: BorderSide(color: palette.accent, width: 1.4),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? palette.panelAlt : const Color(0xFF1F2937),
        contentTextStyle: TextStyle(
          fontSize: 12.5,
          color: isDark ? palette.text : Colors.white,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: palette.textMuted,
        textColor: palette.text,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
          return states.contains(WidgetState.selected)
              ? palette.accent
              : palette.textMuted;
        }),
        trackColor: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
          return states.contains(WidgetState.selected)
              ? palette.accentSoft
              : palette.panelAlt;
        }),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: palette.accent,
        thumbColor: palette.accent,
        inactiveTrackColor: palette.border,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? palette.panelAlt : const Color(0xFF1F2937),
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: TextStyle(
          fontSize: 11.5,
          color: isDark ? palette.text : Colors.white,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: palette.panel,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          side: BorderSide(color: palette.border),
        ),
        textStyle: text.bodyMedium,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: WidgetStateProperty.all(6),
        radius: const Radius.circular(3),
        thumbColor: WidgetStateProperty.all(
          palette.textMuted.withValues(alpha: 0.35),
        ),
      ),
    );
  }

  static TextTheme _textTheme(AppPalette palette) {
    return TextTheme(
      titleLarge: TextStyle(
        fontSize: 19,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: palette.text,
      ),
      titleMedium: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: palette.text,
      ),
      titleSmall: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
        color: palette.text,
      ),
      bodyMedium: TextStyle(fontSize: 13, color: palette.text),
      bodySmall: TextStyle(fontSize: 11.5, color: palette.textMuted),
      labelLarge: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: palette.text,
      ),
      labelSmall: TextStyle(
        fontSize: 10.5,
        letterSpacing: 0.4,
        color: palette.textMuted,
      ),
    );
  }
}
