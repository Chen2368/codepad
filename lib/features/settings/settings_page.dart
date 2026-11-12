import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants/app_constants.dart';
import '../../core/compile/compiler_options.dart';
import '../../core/theme/app_theme.dart';
import '../editor/highlight/code_palette.dart';
import 'storage_update_section.dart';
import '../../core/settings/settings_controller.dart';
import '../../runtime/native_toolchain.dart';
import '../../runtime/runtime_factory.dart';
import '../../runtime/toolchain_self_check.dart';

/// 设置页：主题、编辑器字号 / 行号、本地编译器状态与自检、关于信息。
class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.settings,
    this.toolchainStatus,
    this.runtimeFactory,
  });

  final SettingsController settings;

  /// Phase 3：启动时探测到的内置编译器状态（null 表示未探测 / 模拟模式）。
  final ToolchainStatus? toolchainStatus;

  /// 用于跑编译器自检（需要其中的 workRoot 与 toolchain）。
  final RuntimeFactory? runtimeFactory;

  String _themeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return '跟随系统';
      case ThemeMode.light:
        return '浅色';
      case ThemeMode.dark:
        return '深色';
    }
  }

  static String _codeThemeLabel(CodeThemeId id) {
    switch (id) {
      case CodeThemeId.auto:
        return '跟随系统深浅色';
      case CodeThemeId.oneDark:
        return 'One Dark（深色高对比）';
      case CodeThemeId.paper:
        return '纸白（浅色印刷感）';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListenableBuilder(
        listenable: settings,
        builder: (BuildContext context, Widget? child) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: <Widget>[
                  const _SectionTitle('外观'),
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: <Widget>[
                        const SizedBox(height: 4),
                        ListTile(
                          title: const Text('主题模式'),
                          subtitle: Text(_themeLabel(settings.themeMode)),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                          child: SegmentedButton<ThemeMode>(
                            showSelectedIcon: false,
                            segments: const <ButtonSegment<ThemeMode>>[
                              ButtonSegment<ThemeMode>(
                                value: ThemeMode.system,
                                label: Text('跟随系统'),
                              ),
                              ButtonSegment<ThemeMode>(
                                value: ThemeMode.light,
                                label: Text('浅色'),
                              ),
                              ButtonSegment<ThemeMode>(
                                value: ThemeMode.dark,
                                label: Text('深色'),
                              ),
                            ],
                            selected: <ThemeMode>{settings.themeMode},
                            onSelectionChanged: (Set<ThemeMode> selection) {
                              settings.setThemeMode(selection.first);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const _SectionTitle('编辑器'),
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: <Widget>[
                        const SizedBox(height: 4),
                        ListTile(
                          title: const Text('代码配色'),
                          subtitle: Text(_codeThemeLabel(settings.codeTheme)),
                          trailing: DropdownButton<CodeThemeId>(
                            value: settings.codeTheme,
                            underline: const SizedBox.shrink(),
                            items: <DropdownMenuItem<CodeThemeId>>[
                              for (final CodeThemeId item in CodeThemeId.values)
                                DropdownMenuItem<CodeThemeId>(
                                  value: item,
                                  child: Text(
                                    item.label,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                            ],
                            onChanged: (CodeThemeId? value) {
                              if (value != null) {
                                settings.setCodeTheme(value);
                              }
                            },
                          ),
                        ),
                        SwitchListTile(
                          title: const Text('显示行号'),
                          value: settings.showLineNumbers,
                          onChanged: settings.setShowLineNumbers,
                        ),
                        ListTile(
                          title: const Text('字号'),
                          subtitle: Text('${settings.editorFontSize.toStringAsFixed(0)} px'),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                          child: Slider(
                            min: AppConstants.minFontSize,
                            max: AppConstants.maxFontSize,
                            divisions:
                                (AppConstants.maxFontSize - AppConstants.minFontSize).round(),
                            value: settings.editorFontSize,
                            label: settings.editorFontSize.toStringAsFixed(0),
                            onChanged: settings.setEditorFontSize,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const _SectionTitle('编译器'),
                  Card(
                    child: SwitchListTile(
                      title: const Text('多文件编译'),
                      subtitle: const Text(
                        '开启：把工程内其它不含 main() 的 .c 一起编译（util.c 里的函数可直接调用）。'
                        '关闭：只编译当前文件，最保险。',
                      ),
                      value: settings.multiFileCompile,
                      onChanged: settings.setMultiFileCompile,
                    ),
                  ),
                  _ToolchainCard(status: toolchainStatus, runtimeFactory: runtimeFactory),
                  const _SectionTitle('编译'),
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: <Widget>[
                        const SizedBox(height: 4),
                        ListTile(
                          title: const Text('C 语言标准'),
                          subtitle: Text(
                            settings.compilerOptions.standard.label,
                          ),
                          trailing: DropdownButton<CStandard>(
                            value: settings.compilerOptions.standard,
                            underline: const SizedBox.shrink(),
                            items: <DropdownMenuItem<CStandard>>[
                              for (final CStandard item in CStandard.values)
                                DropdownMenuItem<CStandard>(
                                  value: item,
                                  child: Text(
                                    item.flag,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                            ],
                            onChanged: (CStandard? value) {
                              if (value != null) {
                                settings.setCStandard(value);
                              }
                            },
                          ),
                        ),
                        ListTile(
                          title: const Text('优化级别'),
                          subtitle: Text(
                            settings.compilerOptions.optimization.label,
                          ),
                          trailing: DropdownButton<OptimizationLevel>(
                            value: settings.compilerOptions.optimization,
                            underline: const SizedBox.shrink(),
                            items: <DropdownMenuItem<OptimizationLevel>>[
                              for (final OptimizationLevel item
                                  in OptimizationLevel.values)
                                DropdownMenuItem<OptimizationLevel>(
                                  value: item,
                                  child: Text(
                                    item.flag,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                            ],
                            onChanged: (OptimizationLevel? value) {
                              if (value != null) {
                                settings.setCOptimization(value);
                              }
                            },
                          ),
                        ),
                        SwitchListTile(
                          title: const Text('打开警告 -Wall'),
                          subtitle: const Text('把常见写法问题以警告形式提示出来'),
                          value: settings.compilerOptions.warnings,
                          onChanged: settings.setCWarnings,
                        ),
                        ListTile(
                          title: const Text('运行超时保护'),
                          subtitle: Text(
                            settings.runTimeoutSeconds == 0
                                ? '不限制（死循环需要手动停止）'
                                : '超过 ${settings.runTimeoutSeconds} 秒自动停止',
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: SegmentedButton<int>(
                            showSelectedIcon: false,
                            segments: const <ButtonSegment<int>>[
                              ButtonSegment<int>(value: 5, label: Text('5 秒')),
                              ButtonSegment<int>(value: 10, label: Text('10 秒')),
                              ButtonSegment<int>(value: 30, label: Text('30 秒')),
                              ButtonSegment<int>(value: 0, label: Text('不限制')),
                            ],
                            selected: <int>{settings.runTimeoutSeconds},
                            onSelectionChanged: (Set<int> selection) {
                              settings.setRunTimeoutSeconds(selection.first);
                            },
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: Text(
                            '当前参数：tcc ${settings.compilerFlags.join(' ')}',
                            style: AppTheme.mono(
                              fontSize: 10.5,
                              color: AppPalette.of(context).textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const _SectionTitle('存储与更新'),
                  StorageUpdateSection(settings: settings),
                  const _SectionTitle('关于'),
                  const Card(
                    child: Column(
                      children: <Widget>[
                        ListTile(
                          title: Text(AppConstants.appName),
                          subtitle: Text(
                            '版本 ${AppConstants.version} · ${AppConstants.phaseLabel}',
                          ),
                        ),
                        ListTile(
                          title: Text('技术栈'),
                          subtitle: Text(
                            'Flutter + Material 3；C 由内置 tcc 真实编译执行（tcc -run 内存编译）',
                          ),
                        ),
                        ListTile(
                          title: Text('当前阶段'),
                          subtitle: Text(
                            'Phase 3：C 语言真编译真运行；C++ / Python 运行时后续接入',
                          ),
                        ),
                      ],
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

class _ToolchainCard extends StatefulWidget {
  const _ToolchainCard({this.status, this.runtimeFactory});

  final ToolchainStatus? status;
  final RuntimeFactory? runtimeFactory;

  @override
  State<_ToolchainCard> createState() => _ToolchainCardState();
}

class _ToolchainCardState extends State<_ToolchainCard> {
  bool _running = false;
  List<SelfCheckResult>? _results;

  Future<void> _runSelfCheck() async {
    final RuntimeFactory? factory = widget.runtimeFactory;
    final Directory? workRoot = factory?.workRoot;
    if (factory == null || workRoot == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前是模拟运行模式，没有可自检的本地编译器')),
      );
      return;
    }

    setState(() {
      _running = true;
    });

    final List<SelfCheckResult> results = await ToolchainSelfCheck(
      workRoot: workRoot,
      toolchain: factory.toolchain,
    ).run();

    // 顺便强制刷新一次环境检测：自检报告里要带上「工具链版本标记 + 关键文件是否存在」，
    // 免得下次排查又要在「是不是老 APK / 是不是解压不全」之间来回猜。
    ToolchainStatus? status;
    try {
      status = await factory.toolchain?.probe(force: true);
    } on Object {
      status = widget.status;
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _running = false;
      _results = results;
    });
    await _showResults(results, status);
  }

  Future<void> _showResults(List<SelfCheckResult> results, ToolchainStatus? status) {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) =>
          _SelfCheckDialog(results: results, status: status),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final ToolchainStatus? info = widget.status;

    if (info == null) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.build_circle_outlined),
          title: Text('本地编译器'),
          subtitle: Text('当前为模拟运行模式（未探测本地工具链）'),
        ),
      );
    }

    final List<SelfCheckResult>? results = _results;
    final int passed = results?.where((SelfCheckResult r) => r.passed).length ?? 0;

    return Card(
      child: Column(
        children: <Widget>[
          ListTile(
            leading: Icon(
              info.available ? Icons.check_circle_outline : Icons.error_outline,
              color: info.available ? const Color(0xFF57C77D) : const Color(0xFFFF6B6B),
            ),
            title: const Text('本地 C 编译器（内置 tcc）'),
            subtitle: Text(
              info.available ? '已就绪：${info.summary}' : '不可用：${info.summary}',
            ),
          ),
          if (info.available)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '编译器：${info.compilerPath ?? '-'}',
                    style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '头文件：${info.toolchainDir ?? '-'}',
                    style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          if (info.available)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Row(
                children: <Widget>[
                  FilledButton.tonalIcon(
                    onPressed: _running ? null : _runSelfCheck,
                    icon: _running
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.play_circle_outline, size: 18),
                    label: Text(_running ? '正在自检…' : '运行编译器自检'),
                  ),
                  const SizedBox(width: 12),
                  if (results != null)
                    Expanded(
                      child: Text(
                        '上次自检：$passed/${results.length} 通过'
                        '${passed == results.length ? '，全部正常' : '，见详情'}',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: passed == results.length
                              ? const Color(0xFF57C77D)
                              : const Color(0xFFFFB454),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SelfCheckDialog extends StatelessWidget {
  const _SelfCheckDialog({required this.results, this.status});

  final List<SelfCheckResult> results;

  /// 原生侧回报的工具链环境（版本标记 + 关键文件是否到位）。
  final ToolchainStatus? status;

  /// 环境摘要：写进界面和复制文本，用来一眼分清「老版本 APK」和「解压不全」。
  List<String> get _environmentLines {
    final ToolchainStatus? info = status;
    final List<String> lines = <String>[
      'CodePad ${AppConstants.version} · 工具链 ${info?.toolchainVersion ?? '未知'}'
          '${info?.buildTag != null ? ' · 构建 ${info!.buildTag}' : ''}',
    ];
    if (info?.compilerPath != null) {
      lines.add('编译器 ${info!.compilerPath}');
    }
    if (info?.toolchainDir != null) {
      lines.add('目录   ${info!.toolchainDir}');
    }
    if (info != null && info.checks.isNotEmpty) {
      final List<String> flags = <String>[
        for (final MapEntry<String, bool> entry in info.checks.entries)
          '${entry.value ? '✓' : '✗'} ${entry.key}',
      ];
      lines.add(flags.join('   '));
    }
    return lines;
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final int passed = results.where((SelfCheckResult r) => r.passed).length;

    return AlertDialog(
      title: Text('编译器自检 · $passed/${results.length} 通过'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: scheme.onSurface.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _environmentLines.join('\n'),
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: AppConstants.monoFontFamily,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              for (final SelfCheckResult result in results)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Icon(
                            result.passed ? Icons.check_circle : Icons.cancel,
                            size: 16,
                            color: result.passed
                                ? const Color(0xFF57C77D)
                                : const Color(0xFFFF6B6B),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              result.description,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                      if (result.output.isNotEmpty)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(top: 4, left: 22),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: scheme.onSurface.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            result.output,
                            style: TextStyle(
                              fontSize: 11,
                              fontFamily: AppConstants.monoFontFamily,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      if (result.note != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4, left: 22),
                          child: Text(
                            result.note!,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFFFF6B6B),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton.icon(
          onPressed: () => _copyReport(context),
          icon: const Icon(Icons.copy_all_outlined, size: 16),
          label: const Text('复制全部'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('知道了'),
        ),
      ],
    );
  }

  /// 把自检报告拼成纯文本复制走 —— 出问题时用户一键就能把完整信息发出来。
  Future<void> _copyReport(BuildContext context) async {
    final StringBuffer buffer = StringBuffer()
      ..writeln('CodePad 编译器自检（${results.where((SelfCheckResult r) => r.passed).length}/${results.length} 通过）');
    for (final String line in _environmentLines) {
      buffer.writeln(line);
    }
    buffer.writeln('');
    for (final SelfCheckResult result in results) {
      buffer.writeln('${result.passed ? '[OK  ]' : '[FAIL]'} ${result.name} — ${result.description}');
      if (result.output.isNotEmpty) {
        for (final String line in result.output.split('\n')) {
          buffer.writeln('        $line');
        }
      }
      if (result.note != null) {
        buffer.writeln('        说明: ${result.note}');
      }
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('自检报告已复制'), duration: Duration(seconds: 2)),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 22, 6, 8),
      child: Row(
        children: <Widget>[
          Container(
            width: 3,
            height: 12,
            decoration: BoxDecoration(
              color: palette.accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 7),
          Text(
            text,
            style: TextStyle(
              fontSize: 11.5,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w700,
              color: palette.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
