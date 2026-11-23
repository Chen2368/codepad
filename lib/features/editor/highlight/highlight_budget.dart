/// 语法高亮的"预算"：文件太大时自动降级为纯文本。
///
/// 为什么需要：`HighlightingTextEditingController.buildTextSpan` 每敲一个键都会
/// 把整篇文本重新切成 span（还叠加括号匹配）。几千行时每次按键要重建上万个 span，
/// 在平板上足以把主线程拖到掉帧甚至 ANR —— 而 ANR 弹窗在用户眼里就是"闪退"。
///
/// 策略：超过阈值就只渲染纯文本（编辑、保存、运行完全不受影响，只是没颜色）。
/// 阈值定得比较保守（默认 6 万字符 ≈ 1500 行），因为高亮带来的是"好看"，
/// 卡顿带来的是"不能用"。
library;

/// 高亮预算。
class HighlightBudget {
  const HighlightBudget({
    this.maxChars = 60000,
    this.maxLines = 1500,
  });

  /// 超过这么多字符就降级。
  final int maxChars;

  /// 或者超过这么多行也降级。
  final int maxLines;

  /// 这个长度的文本是否还值得做语法高亮。
  bool allows(String text) {
    if (text.length > maxChars) {
      return false;
    }
    int lines = 1;
    for (int i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) == 10) {
        lines++;
        if (lines > maxLines) {
          return false;
        }
      }
    }
    return true;
  }

  /// 给界面看的原因说明；不需要降级时返回 null。
  String? reasonFor(String text) {
    if (text.length > maxChars) {
      return '文件 ${text.length} 字符，超过 ${_format(maxChars)} 的高亮预算';
    }
    int lines = 1;
    for (int i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) == 10) {
        lines++;
      }
    }
    if (lines > maxLines) {
      return '文件 $lines 行，超过 ${_format(maxLines)} 行的高亮预算';
    }
    return null;
  }

  static String _format(int value) =>
      value >= 1000 ? '${value ~/ 1000}k' : '$value';
}

/// 全局默认预算。
const HighlightBudget defaultHighlightBudget = HighlightBudget();