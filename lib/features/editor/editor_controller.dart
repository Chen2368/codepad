import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../core/text/line_offsets.dart';
import '../../data/models/console_message.dart';
import '../../data/models/program_language.dart';
import '../../data/models/project.dart';
import '../../data/models/run_result.dart';
import '../../data/models/source_file.dart';
import '../../data/repositories/project_repository.dart';
import '../../runtime/compile_diagnostic.dart';
import '../../core/text/undo_stack.dart';
import '../../runtime/runtime_engine.dart';
import 'highlight/code_palette.dart';
import '../../runtime/runtime_factory.dart';
import 'highlight/highlighting_controller.dart';

/// 编辑器页面状态机：打开的文件、控制台输出、运行状态、文件增删改名、自动保存。
///
/// Phase 2 起接入了真实仓库（[ProjectRepository]）：编辑内容会在停止输入
/// [autoSaveDelay] 后自动落盘；传 null 则只在内存中（单元测试 / 兜底模式）。
class EditorController extends ChangeNotifier {
  EditorController({
    required Project project,
    RuntimeFactory runtimeFactory = const RuntimeFactory(),
    ProjectRepository? repository,
    Duration autoSaveDelay = const Duration(milliseconds: 900),
  })  : _project = project,
        _runtimeFactory = runtimeFactory,
        _repository = repository,
        _autoSaveDelay = autoSaveDelay {
    _tabs.addAll(project.files);
    for (final SourceFile file in _tabs) {
      _textControllers[file.path] = _createController(file);
    }
    final SourceFile? entry = project.entryFile;
    if (entry != null) {
      final int index = _tabs.indexWhere((SourceFile f) => f.path == entry.path);
      if (index >= 0) {
        _activeIndex = index;
      }
    }
  }

  final RuntimeFactory _runtimeFactory;
  final ProjectRepository? _repository;
  final Duration _autoSaveDelay;
  final List<SourceFile> _tabs = <SourceFile>[];
  final List<ConsoleMessage> _console = <ConsoleMessage>[];
  final Map<String, HighlightingTextEditingController> _textControllers =
      <String, HighlightingTextEditingController>{};

  Project _project;
  int _activeIndex = 0;
  RunStatus _status = RunStatus.idle;
  RuntimeEngine? _engine;
  bool _dirty = false;
  bool _consoleVisible = true;
  bool _disposed = false;
  Timer? _saveTimer;

  Project get project => _project;

  List<SourceFile> get files => List<SourceFile>.unmodifiable(_tabs);

  int get activeIndex => _activeIndex;

  SourceFile get activeFile => _tabs[_activeIndex];

  List<ConsoleMessage> get consoleMessages => List<ConsoleMessage>.unmodifiable(_console);

  RunStatus get status => _status;

  bool get isRunning => _status == RunStatus.running;

  bool get dirty => _dirty;

  bool get consoleVisible => _consoleVisible;

  /// 取某个文件对应的文本控制器（带语法高亮）。
  TextEditingController controllerFor(SourceFile file) {
    return _textControllers.putIfAbsent(file.path, () => _createController(file));
  }

  HighlightingTextEditingController _createController(SourceFile file) {
    return HighlightingTextEditingController(
      text: file.content,
      language: file.language,
      codeTheme: _codeTheme,
    );
  }

  void select(int index) {
    if (index < 0 || index >= _tabs.length || index == _activeIndex) {
      return;
    }
    _activeIndex = index;
    notifyListeners();
  }

  void selectPath(String path) {
    final int index = _tabs.indexWhere((SourceFile f) => f.path == path);
    if (index >= 0) {
      select(index);
    }
  }

  /// 文本变化时调用。刻意不 notify：输入过程重建整页会打断输入法。
  void updateContent(String path, String value) {
    final int index = _tabs.indexWhere((SourceFile f) => f.path == path);
    if (index < 0 || _tabs[index].content == value) {
      return;
    }
    // 撤销栈记录的是「改动前」的内容；连续输入会被合并成一两步
    _undoFor(path).record(
      _tabs[index].content,
      controllerFor(_tabs[index]).selection.baseOffset,
    );
    _tabs[index] = _tabs[index].copyWith(content: value);
    _project = _project.copyWith(
      files: List<SourceFile>.unmodifiable(_tabs),
      updatedAt: DateTime.now(),
    );
    if (!_dirty) {
      _dirty = true;
      notifyListeners();
    } else {
      _notifyUndoState();
    }
    _persistSoon();
  }

  // ---------- 撤销 / 重做 ----------

  final Map<String, UndoStack> _undoStacks = <String, UndoStack>{};

  UndoStack _undoFor(String path) =>
      _undoStacks.putIfAbsent(path, () => UndoStack());

  UndoStack get _activeUndo => _undoFor(activeFile.path);

  bool get canUndo => _activeUndo.canUndo;

  bool get canRedo => _activeUndo.canRedo;

  /// 撤销一步：把文本与光标恢复到上一步。
  void undo() {
    final SourceFile file = activeFile;
    final UndoStack stack = _undoFor(file.path);
    final TextEditingController controller = controllerFor(file);
    final UndoEntry? entry = stack.undo(file.content, controller.selection.baseOffset);
    if (entry == null) {
      return;
    }
    _applyHistoricalText(file, entry);
  }

  void redo() {
    final SourceFile file = activeFile;
    final UndoStack stack = _undoFor(file.path);
    final TextEditingController controller = controllerFor(file);
    final UndoEntry? entry = stack.redo(file.content, controller.selection.baseOffset);
    if (entry == null) {
      return;
    }
    _applyHistoricalText(file, entry);
  }

  void _applyHistoricalText(SourceFile file, UndoEntry entry) {
    final int index = _tabs.indexWhere((SourceFile f) => f.path == file.path);
    if (index < 0) {
      return;
    }
    _tabs[index] = _tabs[index].copyWith(content: entry.text);
    _project = _project.copyWith(
      files: List<SourceFile>.unmodifiable(_tabs),
      updatedAt: DateTime.now(),
    );
    final TextEditingController controller = controllerFor(_tabs[index]);
    controller.value = TextEditingValue(
      text: entry.text,
      selection: TextSelection.collapsed(
        offset: entry.selectionStart.clamp(0, entry.text.length),
      ),
    );
    _dirty = true;
    notifyListeners();
    _persistSoon();
  }

  Timer? _uiThrottle;

  /// 只刷新「撤销/重做按钮」这类界面状态：节流 250ms，避免每次按键都重建页面。
  void _notifyUndoState() {
    if (_uiThrottle?.isActive ?? false) {
      return;
    }
    _uiThrottle = Timer(const Duration(milliseconds: 250), () {
      if (!_disposed) {
        notifyListeners();
      }
    });
  }

  /// 新建文件。返回 null 表示成功，否则是给用户看的错误提示。
  String? createFile(String rawPath) {
    final String path = normalizePath(rawPath);
    if (path.isEmpty) {
      return '文件名不能为空';
    }
    if (_tabs.any((SourceFile f) => f.path.toLowerCase() == path.toLowerCase())) {
      return '文件已存在：$path';
    }
    final SourceFile file = SourceFile(path: path);
    if (file.language == null) {
      return '不支持的文件类型，请使用 .c / .cpp / .py / .h 等后缀';
    }
    _tabs.add(file);
    _textControllers[path] = _createController(file);
    _activeIndex = _tabs.length - 1;
    _markProjectChanged();
    return null;
  }

  /// 重命名 / 移动文件。返回 null 表示成功。
  String? renameFile(String oldPath, String rawNewPath) {
    final int index = _tabs.indexWhere((SourceFile f) => f.path == oldPath);
    if (index < 0) {
      return '文件不存在';
    }
    final String newPath = normalizePath(rawNewPath);
    if (newPath.isEmpty) {
      return '文件名不能为空';
    }
    if (newPath == oldPath) {
      return null;
    }
    if (_tabs.any((SourceFile f) => f.path.toLowerCase() == newPath.toLowerCase())) {
      return '文件已存在：$newPath';
    }
    final SourceFile renamed = _tabs[index].copyWith(path: newPath);
    if (renamed.language == null) {
      return '不支持的文件类型，请使用 .c / .cpp / .py / .h 等后缀';
    }
    final HighlightingTextEditingController? oldController =
        _textControllers.remove(oldPath);
    oldController?.language = renamed.language;
    if (oldController != null) {
      _textControllers[newPath] = oldController;
    }
    _tabs[index] = renamed;
    _markProjectChanged();
    return null;
  }

  /// 删除文件（至少保留一个）。返回 null 表示成功。
  String? deleteFile(String path) {
    if (_tabs.length <= 1) {
      return '至少要保留一个文件';
    }
    final int index = _tabs.indexWhere((SourceFile f) => f.path == path);
    if (index < 0) {
      return '文件不存在';
    }
    _tabs.removeAt(index);
    _textControllers.remove(path)?.dispose();
    if (_activeIndex >= _tabs.length) {
      _activeIndex = _tabs.length - 1;
    }
    _markProjectChanged();
    return null;
  }

  void renameProject(String name) {
    final String trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == _project.name) {
      return;
    }
    _project = _project.copyWith(
      name: trimmed,
      files: List<SourceFile>.unmodifiable(_tabs),
      updatedAt: DateTime.now(),
    );
    _markProjectChanged();
  }

  /// 统一规范路径：去空白、反斜杠转正斜杠、去掉开头的 / 与重复的 /。
  static String normalizePath(String raw) {
    final String unified = raw.trim().replaceAll('\\', '/');
    final List<String> parts = unified
        .split('/')
        .where((String s) => s.isNotEmpty && s != '.')
        .toList();
    return parts.join('/');
  }

  void _markProjectChanged() {
    _project = _project.copyWith(
      files: List<SourceFile>.unmodifiable(_tabs),
      updatedAt: DateTime.now(),
    );
    _dirty = true;
    notifyListeners();
    _persistSoon();
  }

  /// 立即落盘（工具栏「保存」按钮 / 退出前调用）。
  Future<void> saveNow() async {
    _saveTimer?.cancel();    _uiThrottle?.cancel();
    await _persist();
  }

  void _persistSoon() {
    if (_repository == null) {
      return;
    }
    _saveTimer?.cancel();    _uiThrottle?.cancel();
    _saveTimer = Timer(_autoSaveDelay, () {
      unawaited(_persist());
    });
  }

  Future<void> _persist() async {
    final ProjectRepository? repository = _repository;
    if (repository == null) {
      return;
    }
    try {
      await repository.save(_project);
      if (!_disposed && _dirty) {
        _dirty = false;
        notifyListeners();
      }
    } catch (_) {
      // 落盘失败时保留脏标记，等待下一次触发，不打断用户编辑
    }
  }

  /// 运行当前文件。
  ///
  /// [compilerFlags] 来自设置页（`-std=` / `-O` / `-Wall`）。
  Future<void> run({List<String> compilerFlags = const <String>[]}) async {
    if (_disposed || _status == RunStatus.running) {
      return;
    }
    final SourceFile file = activeFile;
    final ProgramLanguage language = file.language ?? _project.language;

    _status = RunStatus.running;
    _appendInfo('▶ 运行 ${file.fileName}（${language.label}）');
    _lintBeforeRun(file);
    notifyListeners();

    final RuntimeEngine engine = _runtimeFactory.create(language);
    _engine = engine;
    final Stopwatch watch = Stopwatch()..start();
    _armRunTimeout();

    try {
      final RunResult result = await engine.run(
        file,
        onOutput: _handleChunk,
        projectFiles: List<SourceFile>.unmodifiable(_tabs),
        compilerFlags: compilerFlags,
      );
      watch.stop();

      switch (result.status) {
        case RunStatus.success:
          _status = RunStatus.success;
          _appendSuccess(
            '✓ 运行结束，退出码 ${result.exitCode ?? 0}，耗时 ${watch.elapsedMilliseconds} ms',
          );
        case RunStatus.failed:
          _status = RunStatus.failed;
          _appendError(
            '✗ 运行失败，退出码 ${result.exitCode ?? 1}，耗时 ${watch.elapsedMilliseconds} ms',
          );
        case RunStatus.cancelled:
          _status = RunStatus.cancelled;
          _appendInfo('■ 已取消本次运行');
        case RunStatus.idle:
        case RunStatus.running:
          _status = RunStatus.failed;
          _appendError('✗ 运行状态异常，请重试');
      }
    } catch (error) {
      _status = RunStatus.failed;
      _appendError('✗ 运行抛出异常：$error');
    } finally {
      _clearRunTimeout();
      engine.dispose();
      _engine = null;
      notifyListeners();
    }
  }

  Future<void> cancelRun() async {
    final RuntimeEngine? engine = _engine;
    if (engine == null) {
      return;
    }
    _appendInfo('正在请求停止 ...');
    notifyListeners();
    await engine.cancel();
  }

  /// 把一行文本送进正在运行的程序的标准输入（scanf / gets / input 用）。
  Future<void> sendInput(String line) async {
    final RuntimeEngine? engine = _engine;
    if (engine == null || _status != RunStatus.running) {
      return;
    }
    final bool accepted = await engine.writeInput('$line\n');
    _console.add(ConsoleMessage(text: '› $line', level: ConsoleLevel.input));
    if (!accepted) {
      _appendError('当前程序不接受输入（该引擎不支持标准输入）');
    }
    _trimConsole();
    notifyListeners();
  }

  /// 结束标准输入（发送 EOF），让 `while (scanf(...) != EOF)` 之类的循环收尾。
  Future<void> endInput() async {
    final RuntimeEngine? engine = _engine;
    if (engine == null || _status != RunStatus.running) {
      return;
    }
    final bool accepted = await engine.closeInput();
    _console.add(ConsoleMessage(
      text: accepted ? '⏹ 已结束标准输入（EOF）' : '当前程序不支持结束输入',
      level: accepted ? ConsoleLevel.info : ConsoleLevel.error,
    ));
    _trimConsole();
    notifyListeners();
  }

  /// 当前运行中的程序是否接受标准输入（决定控制台输入行是否可用）。
  bool get canSendInput => _status == RunStatus.running && (_engine?.supportsInput ?? false);

  /// 超时保护：默认 10 秒，0 表示不限制（设置里可改）。
  Duration _runTimeout = const Duration(seconds: 10);
  Timer? _runTimer;

  /// 由页面在创建控制器时注入（跟随设置变化）。
  void setRunTimeout(Duration timeout) {
    _runTimeout = timeout;
  }

  /// 应用代码高亮配色（设置变化时调用）。
  void setCodeTheme(CodeThemeId theme) {
    if (_codeTheme == theme) {
      return;
    }
    _codeTheme = theme;
    for (final HighlightingTextEditingController controller
        in _textControllers.values) {
      controller.codeTheme = theme;
    }
    notifyListeners();
  }

  CodeThemeId _codeTheme = CodeThemeId.auto;

  void _armRunTimeout() {
    _runTimer?.cancel();
    if (_runTimeout.inSeconds <= 0) {
      return;
    }
    _runTimer = Timer(_runTimeout, () {
      if (_status != RunStatus.running) {
        return;
      }
      _appendError('⏱ 运行超过 ${_runTimeout.inSeconds} 秒，已自动停止（死循环？可在设置里调整）');
      unawaited(cancelRun());
    });
  }

  void _clearRunTimeout() {
    _runTimer?.cancel();
    _runTimer = null;
  }

  /// 点控制台里的编译错误 → 切到对应文件并把光标放到对应行。
  void jumpToDiagnostic(CompileDiagnostic diagnostic) {
    final String? file = diagnostic.file;
    final int? line = diagnostic.line;
    if (file == null || line == null) {
      return;
    }
    final int index = _matchFileIndex(file);
    if (index < 0) {
      _appendInfo('找不到文件 $file（可能已重命名或已被删除）');
      notifyListeners();
      return;
    }
    _activeIndex = index;
    final TextEditingController controller = controllerFor(_tabs[index]);
    final int offset = offsetForLine(controller.text, line);
    controller.selection = TextSelection.collapsed(offset: offset);
    notifyListeners();
  }

  /// 点工程搜索结果 → 切到对应文件并选中命中片段。
  void openProjectMatch(String path, int start, int length) {
    final int index = _matchFileIndex(path);
    if (index < 0) {
      _appendInfo('找不到文件 $path（可能已重命名或已被删除）');
      notifyListeners();
      return;
    }
    _activeIndex = index;
    final TextEditingController controller = controllerFor(_tabs[index]);
    final int textLength = controller.text.length;
    final int clampedStart = start.clamp(0, textLength);
    final int clampedEnd = (start + length).clamp(clampedStart, textLength);
    controller.selection =
        TextSelection(baseOffset: clampedStart, extentOffset: clampedEnd);
    notifyListeners();
  }

  /// 编译器的文件路径可能是 `lib/util.c` 或 `util.c`，两种都要能对上。
  int _matchFileIndex(String rawPath) {
    final String normalized = normalizePath(rawPath);
    int index = _tabs.indexWhere((SourceFile f) => f.path == normalized);
    if (index >= 0) {
      return index;
    }
    final String baseName = normalized.split('/').last;
    index = _tabs.indexWhere((SourceFile f) => f.path.split('/').last == baseName);
    return index;
  }

  /// 运行前体检：全角标点这类「编译器报错很难懂」的问题，提前说清楚。
  void _lintBeforeRun(SourceFile file) {
    for (final SourceLintFinding finding in SourceLint.check(file.content)) {
      _console.add(ConsoleMessage(
        text: '⚠ ${finding.message}',
        level: ConsoleLevel.hint,
      ));
    }
  }

  void clearConsole() {
    _console.clear();
    notifyListeners();
  }

  void toggleConsole() {
    _consoleVisible = !_consoleVisible;
    notifyListeners();
  }

  void _handleChunk(String chunk) {
    final List<String> lines = chunk.split('\n');
    for (final String line in lines) {
      if (line.trim().isEmpty) {
        continue;
      }

      // 编译诊断：解析成结构化信息（能点、能跳行），并附一条中文提示
      final CompileDiagnostic? diagnostic = CompileDiagnosticParser.parseLine(line);
      if (diagnostic != null) {
        _console.add(ConsoleMessage(
          text: line.trimRight(),
          level: diagnostic.severity == DiagnosticSeverity.warning
              ? ConsoleLevel.output
              : ConsoleLevel.error,
          diagnostic: diagnostic,
        ));
        final String? hint = diagnostic.hint;
        if (hint != null) {
          _console.add(ConsoleMessage(text: '　↳ $hint', level: ConsoleLevel.hint));
        }
        continue;
      }

      final bool looksLikeError =
          line.contains('error') || line.contains('错误') || line.contains('Error');
      _console.add(ConsoleMessage(
        text: line,
        level: looksLikeError ? ConsoleLevel.error : ConsoleLevel.output,
      ));
    }
    _trimConsole();
    notifyListeners();
  }

  void _appendInfo(String text) {
    _console.add(ConsoleMessage(text: text, level: ConsoleLevel.info));
    _trimConsole();
  }

  void _appendSuccess(String text) {
    _console.add(ConsoleMessage(text: text, level: ConsoleLevel.success));
    _trimConsole();
  }

  void _appendError(String text) {
    _console.add(ConsoleMessage(text: text, level: ConsoleLevel.error));
    _trimConsole();
  }

  void _trimConsole() {
    const int maxLines = 800;
    if (_console.length > maxLines) {
      _console.removeRange(0, _console.length - maxLines);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _saveTimer?.cancel();    _uiThrottle?.cancel();
    if (_dirty) {
      unawaited(_persist());
    }
    _engine?.dispose();
    _engine = null;
    for (final HighlightingTextEditingController controller in _textControllers.values) {
      controller.dispose();
    }
    _textControllers.clear();
    super.dispose();
  }
}
