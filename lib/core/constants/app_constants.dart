import 'package:flutter/material.dart';

/// 全局常量：应用名、版本、界面尺寸、断点、配色等。
class AppConstants {
  AppConstants._();

  /// 应用名称（也是 MaterialApp 的标题）。
  static const String appName = 'CodePad';

  /// 当前版本号，与 pubspec.yaml 保持一致。
  static const String version = '1.0.0';

  /// 当前开发阶段说明，显示在首页副标题与设置页「关于」里。
  static const String phaseLabel = 'C 完整支持 · 平板 IDE';

  /// 平板 / 横屏的宽度断点：达到这个逻辑像素宽度时左侧文件树常驻。
  static const double wideLayoutBreakpoint = 840;

  /// 左侧文件树宽度。
  static const double fileTreeWidth = 240;

  /// 底部控制台默认高度（含标准输入行）。
  static const double consoleHeight = 226;

  /// 编辑器字号下限。
  static const double minFontSize = 10;

  /// 编辑器字号上限。
  static const double maxFontSize = 26;

  /// 等宽字体族：代码与控制台统一使用。
  static const String monoFontFamily = 'monospace';

  /// Material 3 种子色。
  static const Color seedColor = Color(0xFF4F8CFF);
}