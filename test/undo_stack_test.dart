import 'package:codepad/core/text/undo_stack.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('记录后可以撤销回上一步', () {
    final UndoStack stack = UndoStack();
    stack.record('a', 1, now: DateTime(2026, 1, 1, 0, 0, 0));
    expect(stack.canUndo, isTrue);

    final UndoEntry? previous =
        stack.undo('ab', 2);
    expect(previous?.text, 'a');
    expect(stack.canUndo, isFalse);
    expect(stack.canRedo, isTrue);
  });

  test('撤销后可以重做', () {
    final UndoStack stack = UndoStack();
    stack.record('a', 1, now: DateTime(2026, 1, 1, 0, 0, 0));
    stack.undo('ab', 2);
    final UndoEntry? next = stack.redo('a', 1);
    expect(next?.text, 'ab');
  });

  test('连续输入在合并窗口内只算一步', () {
    final UndoStack stack = UndoStack(mergeWindow: const Duration(seconds: 2));
    final DateTime t0 = DateTime(2026, 1, 1, 0, 0, 0);
    stack.record('a', 1, now: t0);
    stack.record('ab', 2, now: t0.add(const Duration(milliseconds: 200)));
    stack.record('abc', 3, now: t0.add(const Duration(milliseconds: 400)));
    expect(stack.undoDepth, 1);
  });

  test('超过合并窗口后另起一步', () {
    final UndoStack stack = UndoStack(mergeWindow: const Duration(seconds: 1));
    final DateTime t0 = DateTime(2026, 1, 1, 0, 0, 0);
    stack.record('a', 1, now: t0);
    stack.record('ab', 2, now: t0.add(const Duration(seconds: 3)));
    expect(stack.undoDepth, 2);
  });

  test('新输入会清空重做栈', () {
    final UndoStack stack = UndoStack();
    stack.record('a', 1, now: DateTime(2026, 1, 1));
    stack.undo('ab', 2);
    expect(stack.canRedo, isTrue);
    stack.record('x', 1, now: DateTime(2026, 1, 1, 0, 0, 5));
    expect(stack.canRedo, isFalse);
  });

  test('栈深超过上限时丢掉最早的', () {
    final UndoStack stack = UndoStack(maxDepth: 3);
    for (int i = 0; i < 6; i++) {
      stack.record('t$i', i, now: DateTime(2026, 1, 1, 0, 0, i * 5));
    }
    expect(stack.undoDepth, 3);
  });

  test('空栈撤销返回 null', () {
    expect(UndoStack().undo('a', 1), isNull);
    expect(UndoStack().redo('a', 1), isNull);
  });
}
