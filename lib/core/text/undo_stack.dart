/// 简易撤销/重做栈（纯逻辑，可测）。
///
/// 为什么自己管：`TextField` 自带的撤销依赖平台输入法的按键事件，
/// 蓝牙键盘 / 软键盘的行为不一致，而且看不出「还能撤几步」。
/// 这里用「文本快照 + 合并窗口」的方式：同一秒内的连续输入合并成一步，
/// 避免每个字符都占一格。
library;

class UndoEntry {
  const UndoEntry({required this.text, required this.selectionStart});

  final String text;
  final int selectionStart;
}

class UndoStack {
  UndoStack({this.maxDepth = 100, this.mergeWindow = const Duration(milliseconds: 900)});

  final int maxDepth;

  /// 两次编辑间隔小于该值时合并为一步（连续打字不逐字入栈）。
  final Duration mergeWindow;

  final List<UndoEntry> _undo = <UndoEntry>[];
  final List<UndoEntry> _redo = <UndoEntry>[];

  DateTime? _lastPushAt;

  bool get canUndo => _undo.isNotEmpty;

  bool get canRedo => _redo.isNotEmpty;

  int get undoDepth => _undo.length;

  int get redoDepth => _redo.length;

  /// 记录「编辑前的状态」。
  ///
  /// [now] 便于测试注入时间；距上次入栈超过 [mergeWindow] 才真正新增一步，
  /// 否则只是把当前这步的「起点」保留下来（连续输入算一步）。
  void record(
    String text,
    int selectionStart, {
    DateTime? now,
  }) {
    final DateTime stamp = now ?? DateTime.now();
    final bool shouldMerge = _lastPushAt != null &&
        stamp.difference(_lastPushAt!) < mergeWindow &&
        _undo.isNotEmpty;
    _lastPushAt = stamp;
    if (shouldMerge) {
      return;
    }
    _undo.add(UndoEntry(text: text, selectionStart: selectionStart));
    if (_undo.length > maxDepth) {
      _undo.removeAt(0);
    }
    _redo.clear();
  }

  /// 撤销：传入当前文本，返回上一步状态；没有可撤销时返回 null。
  UndoEntry? undo(String currentText, int currentSelection) {
    if (_undo.isEmpty) {
      return null;
    }
    final UndoEntry previous = _undo.removeLast();
    _redo.add(
      UndoEntry(text: currentText, selectionStart: currentSelection),
    );
    _lastPushAt = null; // 撤销后不再与后续输入合并
    return previous;
  }

  /// 重做：传入当前文本，返回下一步状态；没有可重做时返回 null。
  UndoEntry? redo(String currentText, int currentSelection) {
    if (_redo.isEmpty) {
      return null;
    }
    final UndoEntry next = _redo.removeLast();
    _undo.add(UndoEntry(text: currentText, selectionStart: currentSelection));
    _lastPushAt = null;
    return next;
  }

  void clear() {
    _undo.clear();
    _redo.clear();
    _lastPushAt = null;
  }
}
