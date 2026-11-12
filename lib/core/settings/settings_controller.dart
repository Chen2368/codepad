import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/repositories/settings_store.dart';
import '../compile/compiler_options.dart';
import '../../features/editor/highlight/code_palette.dart';
import '../constants/app_constants.dart';

/// 全局设置（主题 / 字号 / 行号），Phase 2 起持久化到 [SettingsStore]。
///
/// 默认使用内存存储，`main.dart` 会注入基于 shared_preferences 的实现；
/// 单元测试直接构造即可，不依赖平台插件。
class SettingsController extends ChangeNotifier {
  SettingsController({SettingsStore? store})
      : _store = store ?? InMemorySettingsStore();

  static const String keyThemeMode = 'themeMode';
  static const String keyFontSize = 'fontSize';
  static const String keyLineNumbers = 'lineNumbers';
  static const String keyMultiFileCompile = 'multiFileCompile';
  static const String keyUpdateUrl = 'updateUrl';
  static const String keyAutoCheckUpdate = 'autoCheckUpdate';
  static const String keyCStandard = 'cStandard';
  static const String keyCOptimization = 'cOptimization';
  static const String keyCWarnings = 'cWarnings';
  static const String keyRunTimeout = 'runTimeoutSeconds';
  static const String keyCodeTheme = 'codeTheme';

  final SettingsStore _store;

  ThemeMode _themeMode = ThemeMode.dark;
  double _editorFontSize = 14;
  bool _showLineNumbers = true;
  bool _multiFileCompile = true;
  String _updateUrl = '';
  bool _autoCheckUpdate = false;
  CStandard _cStandard = CStandard.c11;
  OptimizationLevel _cOptimization = OptimizationLevel.o2;
  bool _cWarnings = true;
  int _runTimeoutSeconds = 10;
  CodeThemeId _codeTheme = CodeThemeId.auto;

  ThemeMode get themeMode => _themeMode;

  double get editorFontSize => _editorFontSize;

  bool get showLineNumbers => _showLineNumbers;

  /// 编译 C 时是否把工程内其它不含 `main()` 的 `.c` 一起编译。
  ///
  /// 默认开启；万一在某个设备上多文件编译有问题，关掉即回到「只编当前文件」。
  bool get multiFileCompile => _multiFileCompile;

  /// 更新清单地址（为空表示未配置，可用「从文件安装」）。
  String get updateUrl => _updateUrl;

  /// 启动时是否自动检查更新（默认关，绝不打扰）。
  bool get autoCheckUpdate => _autoCheckUpdate;

  /// 编译选项（C 标准 / 优化 / 警告）。
  CompilerOptions get compilerOptions => CompilerOptions(
        standard: _cStandard,
        optimization: _cOptimization,
        warnings: _cWarnings,
      );

  /// 直接拼好的 tcc 参数。
  List<String> get compilerFlags => compilerOptions.toFlags();

  /// 代码高亮配色方案。
  CodeThemeId get codeTheme => _codeTheme;

  /// 运行超时（秒）；0 表示不限制。
  int get runTimeoutSeconds => _runTimeoutSeconds;

  Duration get runTimeout => Duration(seconds: _runTimeoutSeconds);

  /// 应用启动时读取持久化设置。
  Future<void> load() async {
    final Map<String, Object?> values = await _store.readAll();

    _themeMode = _parseThemeMode(values[keyThemeMode]);

    final double? fontSize = double.tryParse('${values[keyFontSize] ?? ''}');
    if (fontSize != null) {
      _editorFontSize = fontSize
          .clamp(AppConstants.minFontSize, AppConstants.maxFontSize)
          .toDouble();
    }

    final Object? lineNumbers = values[keyLineNumbers];
    if (lineNumbers != null) {
      _showLineNumbers = '$lineNumbers' != 'false';
    }

    final Object? multiFile = values[keyMultiFileCompile];
    if (multiFile != null) {
      _multiFileCompile = '$multiFile' != 'false';
    }

    final Object? updateUrl = values[keyUpdateUrl];
    if (updateUrl is String) {
      _updateUrl = updateUrl;
    }

    final Object? autoCheck = values[keyAutoCheckUpdate];
    if (autoCheck != null) {
      _autoCheckUpdate = '$autoCheck' == 'true';
    }

    _cStandard = CStandard.fromId(values[keyCStandard]);
    _cOptimization = OptimizationLevel.fromId(values[keyCOptimization]);
    final Object? warnings = values[keyCWarnings];
    if (warnings != null) {
      _cWarnings = '$warnings' != 'false';
    }
    _codeTheme = CodeThemeId.fromId(values[keyCodeTheme]);
    final int? timeout = int.tryParse('${values[keyRunTimeout] ?? ''}');
    if (timeout != null) {
      _runTimeoutSeconds = timeout < 0 ? 0 : timeout;
    }

    notifyListeners();
  }

  void setThemeMode(ThemeMode mode) {
    if (mode == _themeMode) {
      return;
    }
    _themeMode = mode;
    notifyListeners();
    unawaited(_store.write(<String, Object?>{keyThemeMode: mode.name}));
  }

  void setEditorFontSize(double size) {
    final double next =
        size.clamp(AppConstants.minFontSize, AppConstants.maxFontSize).toDouble();
    if (next == _editorFontSize) {
      return;
    }
    _editorFontSize = next;
    notifyListeners();
    unawaited(_store.write(<String, Object?>{keyFontSize: next}));
  }

  void setShowLineNumbers(bool value) {
    if (value == _showLineNumbers) {
      return;
    }
    _showLineNumbers = value;
    notifyListeners();
    unawaited(_store.write(<String, Object?>{keyLineNumbers: value}));
  }

  void setMultiFileCompile(bool value) {
    if (value == _multiFileCompile) {
      return;
    }
    _multiFileCompile = value;
    notifyListeners();
    unawaited(_store.write(<String, Object?>{keyMultiFileCompile: value}));
  }

  void setUpdateUrl(String url) {
    final String next = url.trim();
    if (next == _updateUrl) {
      return;
    }
    _updateUrl = next;
    notifyListeners();
    unawaited(_store.write(<String, Object?>{keyUpdateUrl: next}));
  }

  void setAutoCheckUpdate(bool value) {
    if (value == _autoCheckUpdate) {
      return;
    }
    _autoCheckUpdate = value;
    notifyListeners();
    unawaited(_store.write(<String, Object?>{keyAutoCheckUpdate: value}));
  }

  void setCStandard(CStandard value) {
    if (value == _cStandard) {
      return;
    }
    _cStandard = value;
    notifyListeners();
    unawaited(_store.write(<String, Object?>{keyCStandard: value.id}));
  }

  void setCOptimization(OptimizationLevel value) {
    if (value == _cOptimization) {
      return;
    }
    _cOptimization = value;
    notifyListeners();
    unawaited(_store.write(<String, Object?>{keyCOptimization: value.id}));
  }

  void setCWarnings(bool value) {
    if (value == _cWarnings) {
      return;
    }
    _cWarnings = value;
    notifyListeners();
    unawaited(_store.write(<String, Object?>{keyCWarnings: value}));
  }

  void setRunTimeoutSeconds(int value) {
    final int next = value < 0 ? 0 : value;
    if (next == _runTimeoutSeconds) {
      return;
    }
    _runTimeoutSeconds = next;
    notifyListeners();
    unawaited(_store.write(<String, Object?>{keyRunTimeout: next}));
  }

  void setCodeTheme(CodeThemeId value) {
    if (value == _codeTheme) {
      return;
    }
    _codeTheme = value;
    notifyListeners();
    unawaited(_store.write(<String, Object?>{keyCodeTheme: value.id}));
  }

  ThemeMode _parseThemeMode(Object? value) {
    for (final ThemeMode mode in ThemeMode.values) {
      if (mode.name == value) {
        return mode;
      }
    }
    return ThemeMode.dark;
  }
}
