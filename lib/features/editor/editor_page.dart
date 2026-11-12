import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants/app_constants.dart';
import '../../core/text/project_search.dart';
import '../../core/settings/settings_controller.dart';
import '../../data/models/console_message.dart';
import '../../data/models/project.dart';
import '../../data/models/source_file.dart';
import '../../data/repositories/project_repository.dart';
import '../../runtime/compile_diagnostic.dart';
import '../../runtime/native_toolchain.dart';
import '../../runtime/runtime_factory.dart';
import '../settings/settings_page.dart';
import 'editor_controller.dart';
import 'widgets/code_editor_view.dart';
import 'widgets/editor_toolbar.dart';
import 'widgets/file_name_dialog.dart';
import 'widgets/file_tab_bar.dart';
import 'widgets/file_tree_panel.dart';
import 'widgets/find_bar.dart';
import 'widgets/output_console.dart';
import 'widgets/problems_panel.dart';
import 'widgets/run_sheet.dart';

/// 编辑器页面：工具栏 + 文件标签 + 代码区 + 控制台。
///
/// 宽屏（平板横屏）左侧常驻文件树；窄屏收进抽屉。
/// Phase 2：文件树可新建 / 重命名 / 删除文件，编辑内容自动落盘。
class EditorPage extends StatefulWidget {
  const EditorPage({
    super.key,
    required this.project,
    required this.projectRepository,
    required this.settings,
    this.runtimeFactory = const RuntimeFactory(),
    this.toolchainStatus,
  });

  final Project project;
  final ProjectRepository projectRepository;
  final SettingsController settings;
  final RuntimeFactory runtimeFactory;
  final ToolchainStatus? toolchainStatus;

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  late final EditorController _controller = EditorController(
    project: widget.project,
    runtimeFactory: widget.runtimeFactory,
    repository: widget.projectRepository,
  );
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  bool _showTree = true;
  bool _problemsOpen = false;

  @override
  void initState() {
    super.initState();
    _syncSettings();
    widget.settings.addListener(_syncSettings);
  }

  /// 设置变化（字号 / 编译选项 / 配色 / 超时）后同步给编辑器控制器。
  void _syncSettings() {
    _controller.setRunTimeout(widget.settings.runTimeout);
    _controller.setCodeTheme(widget.settings.codeTheme);
  }

  @override
  void dispose() {
    widget.settings.removeListener(_syncSettings);
    _controller.dispose();
    super.dispose();
  }

  /// 查找/替换条是否展开（只在当前文件里查）。
  bool _findOpen = false;

  Future<void> _save() async {
    await _controller.saveNow();
    if (!mounted) {
      return;
    }
    _snack('已保存到本地存储');
  }

  /// 蓝牙键盘快捷键：Ctrl+S 保存 / Ctrl+F 查找 / Ctrl+Enter 运行 / Ctrl+B 控制台。
  ///
  /// 用 [CallbackShortcuts] 而不是全局 KeyboardListener：作用域限定在编辑器页，
  /// 回到首页就不会误触发。
  Widget _withShortcuts(Widget child) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () {
          setState(() {
            _findOpen = !_findOpen;
          });
        },
        const SingleActivator(LogicalKeyboardKey.enter, control: true):
            _runAndShowSheet,
        const SingleActivator(LogicalKeyboardKey.keyB, control: true):
            _controller.toggleConsole,
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true):
            _controller.undo,
        const SingleActivator(LogicalKeyboardKey.keyY, control: true):
            _controller.redo,
      },
      child: Focus(autofocus: true, child: child),
    );
  }

  /// 运行 = 立刻弹出运行窗口 + 开始跑（输出流式进入窗口）。
  ///
  /// 先弹窗再运行：不必等程序跑完就能看到编译进度；长程序 / 等待输入时
  /// 也不会出现「点了没反应」的空档。
  void _runAndShowSheet() {
    // 编译选项来自设置页：-std=… / -O… / -Wall
    unawaited(_controller.run(compilerFlags: widget.settings.compilerFlags));
    unawaited(showRunSheet(context: context, controller: _controller));
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => SettingsPage(
          settings: widget.settings,
          toolchainStatus: widget.toolchainStatus,
          runtimeFactory: widget.runtimeFactory,
        ),
      ),
    );
  }

  Future<void> _createFile() async {
    final String initial = _defaultFileName();
    final String? input = await showFileNameDialog(
      context,
      title: '新建文件',
      initial: initial,
      hint: '例如 lib/utils.cpp 或 solution.py',
    );
    if (input == null || !mounted) {
      return;
    }
    final String? error = _controller.createFile(input);
    if (error != null) {
      _snack(error);
    }
  }

  String _defaultFileName() {
    final String extension = _controller.project.language.extensions.first;
    int index = 1;
    while (_controller.files.any(
      (SourceFile file) => file.path == 'file$index$extension',
    )) {
      index++;
    }
    return 'file$index$extension';
  }

  Future<void> _renameFile(String path) async {
    final String? input = await showFileNameDialog(
      context,
      title: '重命名 / 移动文件',
      initial: path,
      hint: '可以带上目录：lib/main.cpp',
      confirmLabel: '重命名',
    );
    if (input == null || !mounted) {
      return;
    }
    final String? error = _controller.renameFile(path, input);
    if (error != null) {
      _snack(error);
    }
  }

  Future<void> _deleteFile(String path) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('删除文件'),
        content: Text('确定删除 $path 吗？该操作会同步到本地存储。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final String? error = _controller.deleteFile(path);
    if (error != null) {
      _snack(error);
    }
  }

  Future<void> _renameProject() async {
    final String? input = await showFileNameDialog(
      context,
      title: '重命名工程',
      initial: _controller.project.name,
      confirmLabel: '保存',
    );
    if (input == null || !mounted) {
      return;
    }
    _controller.renameProject(input);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[_controller, widget.settings]),
      builder: (BuildContext context, Widget? child) {
        final bool wide =
            MediaQuery.sizeOf(context).width >= AppConstants.wideLayoutBreakpoint;

        if (_controller.files.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: Text(_controller.project.name)),
            body: const Center(child: Text('该工程中还没有文件')),
          );
        }

        return Scaffold(
          key: _scaffoldKey,
          appBar: AppBar(
            leading: wide
                ? IconButton(
                    tooltip: '显示 / 隐藏文件树',
                    onPressed: () => setState(() => _showTree = !_showTree),
                    icon: Icon(
                      _showTree ? Icons.view_sidebar : Icons.view_sidebar_outlined,
                      size: 20,
                    ),
                  )
                : null,
            title: GestureDetector(
              onTap: _renameProject,
              child: _buildTitle(context),
            ),
            actions: <Widget>[
              IconButton(
                tooltip: '设置',
                onPressed: _openSettings,
                icon: const Icon(Icons.settings_outlined, size: 20),
              ),
            ],
          ),
          drawer: wide
              ? null
              : Drawer(
                  child: SafeArea(
                    child: FileTreePanel(
                      files: _controller.files,
                      activePath: _controller.activeFile.path,
                      onSelect: (String path) {
                        _controller.selectPath(path);
                        Navigator.of(context).pop();
                      },
                      onCreate: () {
                        Navigator.of(context).pop();
                        _createFile();
                      },
                      onRename: (String path) {
                        Navigator.of(context).pop();
                        _renameFile(path);
                      },
                      onDelete: (String path) {
                        Navigator.of(context).pop();
                        _deleteFile(path);
                      },
                    ),
                  ),
                ),
          body: _withShortcuts(
            wide
                ? _buildWideBody(context)
                : _buildEditorArea(context, narrow: true),
          ),
        );
      },
    );
  }

  Widget _buildTitle(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Row(
          children: <Widget>[
            Flexible(
              child: Text(
                _controller.project.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600),
              ),
            ),
            if (_controller.dirty) ...<Widget>[
              const SizedBox(width: 5),
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
        Text(
          '${_controller.project.language.label} · ${_controller.files.length} 个文件',
          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _buildWideBody(BuildContext context) {
    final Widget editorArea = _buildEditorArea(context, narrow: false);
    if (!_showTree) {
      return editorArea;
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(
          width: AppConstants.fileTreeWidth,
          child: FileTreePanel(
            files: _controller.files,
            activePath: _controller.activeFile.path,
            onSelect: _controller.selectPath,
            onCreate: _createFile,
            onRename: _renameFile,
            onDelete: _deleteFile,
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(child: editorArea),
      ],
    );
  }

  Widget _buildEditorArea(BuildContext context, {required bool narrow}) {
    final SourceFile active = _controller.activeFile;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        EditorToolbar(
          isRunning: _controller.isRunning,
          onRun: _runAndShowSheet,
          onStop: _controller.cancelRun,
          onSave: _save,
          consoleVisible: _controller.consoleVisible,
          onToggleConsole: _controller.toggleConsole,
          onFind: () => setState(() {
            _findOpen = !_findOpen;
          }),
          findVisible: _findOpen,
          onUndo: () => setState(_controller.undo),
          onRedo: () => setState(_controller.redo),
          canUndo: _controller.canUndo,
          canRedo: _controller.canRedo,
          onToggleProblems: () => setState(() {
            _problemsOpen = !_problemsOpen;
          }),
          problemsVisible: _problemsOpen,
          problemCount: _controller.consoleMessages
              .where((ConsoleMessage m) => m.isJumpable)
              .length,
          onOpenFileTree: narrow
              ? () => _scaffoldKey.currentState?.openDrawer()
              : null,
        ),
        FileTabBar(
          files: _controller.files,
          activeIndex: _controller.activeIndex,
          onSelect: _controller.select,
        ),
        const Divider(height: 1),
        if (_findOpen)
          FindBar(
            // 打开时用当前文件内容作初值；工程搜索读到的是各文件的最新文本
            controller: _controller.controllerFor(active),
            projectFiles: <String, String>{
              for (final SourceFile file in _controller.files)
                file.path: _controller.controllerFor(file).text,
            },
            onOpenProjectMatch: (ProjectMatch match) {
              _controller.openProjectMatch(
                match.path,
                match.start,
                match.length,
              );
              setState(() {
                _findOpen = false;
              });
            },
            onClose: () => setState(() {
              _findOpen = false;
            }),
          ),
        Expanded(
          child: CodeEditorView(
            key: ValueKey<String>(active.path),
            controller: _controller.controllerFor(active),
            fontSize: widget.settings.editorFontSize,
            showLineNumbers: widget.settings.showLineNumbers,
            onChanged: (String value) => _controller.updateContent(active.path, value),
            onZoom: widget.settings.setEditorFontSize,
          ),
        ),
        if (_problemsOpen)
          SizedBox(
            height: 168,
            child: ProblemsPanel(
              messages: _controller.consoleMessages,
              onTapDiagnostic: (CompileDiagnostic diagnostic) {
                setState(() {
                  _problemsOpen = false;
                });
                _controller.jumpToDiagnostic(diagnostic);
              },
              onClose: () => setState(() {
                _problemsOpen = false;
              }),
            ),
          ),
        if (_controller.consoleVisible)
          SizedBox(
            height: AppConstants.consoleHeight,
            child: OutputConsole(
              messages: _controller.consoleMessages,
              status: _controller.status,
              onClear: _controller.clearConsole,
              onClose: _controller.toggleConsole,
              onSendInput: _controller.sendInput,
              onEndInput: _controller.endInput,
              onTapDiagnostic: _controller.jumpToDiagnostic,
              canSendInput: _controller.canSendInput,
            ),
          ),
      ],
    );
  }
}
