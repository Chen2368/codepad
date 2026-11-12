/// 编译诊断：把 tcc（gcc 风格）的报错行解析成结构化信息，并给出中文提示。
///
/// tcc 的报错形如：
/// ```
/// main.c:3: error: 'x' undeclared
/// main.c:7: warning: assignment makes integer from pointer without a cast
/// In file included from main.c:2:
/// tcc: error: file 'util.h' not found
/// ```
library;

/// 诊断级别。
enum DiagnosticSeverity {
  error,
  warning,
  note,
}

/// 一条编译诊断。
class CompileDiagnostic {
  const CompileDiagnostic({
    required this.severity,
    required this.message,
    this.file,
    this.line,
    this.column,
    this.hint,
  });

  final DiagnosticSeverity severity;

  /// 编译器原始信息（不含 `file:line: error:` 前缀）。
  final String message;

  /// 出问题的文件（相对工程根，例如 `main.c` 或 `lib/util.c`）。
  final String? file;

  /// 行号（1 起）。
  final int? line;

  /// 列号（tcc 通常不给）。
  final int? column;

  /// 中文提示：这条报错的常见成因与改法。
  final String? hint;

  /// 是否能定位到具体位置（决定控制台里该行是否可以点击跳转）。
  bool get hasLocation => file != null && line != null;

  String get severityLabel {
    switch (severity) {
      case DiagnosticSeverity.error:
        return '错误';
      case DiagnosticSeverity.warning:
        return '警告';
      case DiagnosticSeverity.note:
        return '说明';
    }
  }

  @override
  String toString() =>
      'CompileDiagnostic($severityLabel${hasLocation ? ' $file:$line' : ''}: $message)';
}

/// 诊断解析器（纯函数，方便单测）。
class CompileDiagnosticParser {
  const CompileDiagnosticParser._();

  /// `file:line[:col]: error: message`
  ///
  /// 文件名用 `.+?` 而非 `[^:]+`，这样 `lib/util.c` 这类带子目录的路径也能匹配；
  /// 结尾强制要求 `:\d+:` 出现，避免把 `Note: something` 误判成诊断。
  static final RegExp _withLocation = RegExp(
    r'^(?<file>.+?):(?<line>\d+):(?:(?<col>\d+):)?\s*'
    r'(?<severity>fatal error|error|warning|note):\s*(?<message>.*)$',
  );

  /// 没有位置的诊断：`tcc: error: ...`
  static final RegExp _withoutLocation = RegExp(
    r'^(?:tcc|clang|gcc|cc):\s*(?<severity>fatal error|error|warning|note):\s*(?<message>.*)$',
  );

  static CompileDiagnostic? parseLine(String raw) {
    final String line = raw.trimRight();
    if (line.isEmpty) {
      return null;
    }

    final RegExpMatch? withLocation = _withLocation.firstMatch(line);
    if (withLocation != null) {
      final String message = withLocation.namedGroup('message') ?? '';
      return CompileDiagnostic(
        severity: _severityOf(withLocation.namedGroup('severity')),
        message: message,
        file: withLocation.namedGroup('file'),
        line: int.tryParse(withLocation.namedGroup('line') ?? ''),
        column: int.tryParse(withLocation.namedGroup('col') ?? ''),
        hint: hintFor(message),
      );
    }

    final RegExpMatch? withoutLocation = _withoutLocation.firstMatch(line);
    if (withoutLocation != null) {
      final String message = withoutLocation.namedGroup('message') ?? '';
      return CompileDiagnostic(
        severity: _severityOf(withoutLocation.namedGroup('severity')),
        message: message,
        hint: hintFor(message),
      );
    }

    return null;
  }

  /// 解析整段编译输出（保留原有顺序，跳过非诊断行）。
  static List<CompileDiagnostic> parse(String text) {
    final List<CompileDiagnostic> result = <CompileDiagnostic>[];
    for (final String line in text.split('\n')) {
      final CompileDiagnostic? diagnostic = parseLine(line);
      if (diagnostic != null) {
        result.add(diagnostic);
      }
    }
    return result;
  }

  static DiagnosticSeverity _severityOf(String? raw) {
    switch (raw) {
      case 'warning':
        return DiagnosticSeverity.warning;
      case 'note':
        return DiagnosticSeverity.note;
      default:
        return DiagnosticSeverity.error;
    }
  }

  /// 常见报错 → 中文提示。匹配用「包含关键字」，越具体的规则放越前面。
  static String? hintFor(String message) {
    final String text = message.toLowerCase();

    for (final _HintRule rule in _rules) {
      for (final String keyword in rule.keywords) {
        if (text.contains(keyword)) {
          return rule.hint;
        }
      }
    }
    return null;
  }

  static const List<_HintRule> _rules = <_HintRule>[
    _HintRule(
      <String>['implicit declaration of function'],
      '函数没有先声明：检查名字是否拼错，以及是否漏了对应的 #include'
      '（printf/scanf 需要 <stdio.h>，sqrt/pow 需要 <math.h>）。',
    ),
    _HintRule(
      <String>["' undeclared", 'undeclared identifier', 'undeclared (first use'],
      '变量或函数没定义就用了：检查拼写、大小写，以及是不是忘了先写类型（例如忘了 int）。',
    ),
    _HintRule(
      <String>['undefined symbol', 'undefined reference', 'unresolved symbol'],
      '找不到函数或变量的实现：多半是漏了 #include，或用了需要 -l 的库。',
    ),
    _HintRule(
      <String>['multiple definition', 'redefinition of', 'duplicate symbol'],
      '重复定义：常见原因是工程里有多个 main()、同一个变量被定义了两次，'
      '或者头文件里直接写了变量/函数定义（应该只放声明，定义写进 .c）。',
    ),
    _HintRule(
      <String>["expected ';'", "expected ')' ", 'expected expression'],
      '大概率是上一行少了分号，或者括号没配对。C 语言每条语句都要以 ; 结尾。',
    ),
    _HintRule(
      <String>['stray', 'invalid character', 'illegal character'],
      '代码里混进了非法字符：最常见的是中文/全角标点（；，（）“”），请改成英文半角。',
    ),
    _HintRule(
      <String>['unterminated', 'missing terminating', 'eof in string', 'eof in comment'],
      '字符串或注释没有闭合：检查双引号是否成对，/* 是否配上了 */。',
    ),
    _HintRule(
      <String>['no such file or directory', 'not found', 'file not found'],
      '找不到这个头文件：检查文件名拼写；只有 C 标准库与 bionic 提供的头文件可用，'
      '第三方库的头文件需要自己放进工程。',
    ),
    _HintRule(
      <String>['#include expects'],
      '#include 后面要写成 "文件名" 或 <文件名>，两种引号不能少、也不能用中文引号。',
    ),
    _HintRule(
      <String>['conflicting types', 'conflicting type'],
      '函数/变量的声明和定义类型不一致：检查原型里的返回类型、参数类型是否与定义相同。',
    ),
    _HintRule(
      <String>['assignment makes pointer from integer', 'makes integer from pointer'],
      '类型不匹配（指针与整数互转）：检查是不是把 int 赋给了指针，或者忘了对函数做声明。',
    ),
    _HintRule(
      <String>['too many arguments', 'too few arguments'],
      '函数调用时参数个数与声明不符：数一下实参个数，别漏逗号或参数。',
    ),
    _HintRule(
      <String>['array subscript', 'subscripted value'],
      '对非数组/非指针用了 []：确认这个变量是不是数组，或指针是否已经指向有效内存。',
    ),
    _HintRule(
      <String>['division by zero'],
      '除数为常量 0：检查公式里的分母。',
    ),
    _HintRule(
      <String>['control reaches end of non-void'],
      '有返回值的函数走到末尾却没 return：补一个 return，或把返回类型改成 void。',
    ),
    _HintRule(
      <String>['unused variable', 'set but not used'],
      '变量定义了但没用到：不影响运行，可以删掉让代码更干净。',
    ),
  ];
}

class _HintRule {
  const _HintRule(this.keywords, this.hint);

  final List<String> keywords;
  final String hint;
}

/// 运行前源码检查：抓那些「编译器报错很难懂、但其实是输入法问题」的错误。
class SourceLint {
  const SourceLint._();

  /// 全角标点 → 对应半角
  static const Map<String, String> _fullWidth = <String, String>{
    '；': ';',
    '，': ',',
    '（': '(',
    '）': ')',
    '｛': '{',
    '｝': '}',
    '“': '"',
    '”': '"',
    '‘': "'",
    '’': "'",
    '：': ':',
    '＝': '=',
    '＜': '<',
    '＞': '>',
    '！': '!',
    '＋': '+',
    '－': '-',
    '＊': '*',
    '／': '/',
    '％': '%',
    '［': '[',
    '］': ']',
    '　': ' ',
  };

  /// 扫描源码，返回最多 [limit] 条问题（行号 1 起）。
  ///
  /// 先把注释与字符串字面量「涂空」（保持行数不变），再在剩下的代码里找全角标点。
  /// 这一步很关键：中文注释、`printf("你好，世界")` 里的全角标点完全合法，
  /// 0.3.2 就是在整行里直接找，导致示例工程的块注释被误报成 3 条「全角字符」警告。
  static List<SourceLintFinding> check(String source, {int limit = 3}) {
    final List<SourceLintFinding> findings = <SourceLintFinding>[];
    final List<String> lines = stripNonCode(source).split('\n');

    for (int i = 0; i < lines.length; i++) {
      if (findings.length >= limit) {
        break;
      }
      final String code = lines[i];
      for (final MapEntry<String, String> entry in _fullWidth.entries) {
        if (code.contains(entry.key)) {
          findings.add(SourceLintFinding(
            line: i + 1,
            message: '第 ${i + 1} 行出现了全角字符「${entry.key}」，'
                '应改成半角「${entry.value}」（中文输入法忘了切换）。',
          ));
          break;
        }
      }
    }
    return findings;
  }

  /// 把注释（`//` 与跨行 `/* */`）和字符串/字符字面量替换成空白，保留换行。
  ///
  /// 只涂空、不删除，所以返回值的行号与原文一一对应，可以直接用来报行。
  static String stripNonCode(String source) {
    final StringBuffer out = StringBuffer();
    int i = 0;
    while (i < source.length) {
      final String char = source[i];
      final String? next = i + 1 < source.length ? source[i + 1] : null;

      // 行注释：吃到行尾
      if (char == '/' && next == '/') {
        while (i < source.length && source[i] != '\n') {
          out.write(' ');
          i++;
        }
        continue;
      }

      // 块注释：可以跨行
      if (char == '/' && next == '*') {
        out.write('  ');
        i += 2;
        while (i < source.length) {
          if (source[i] == '*' &&
              i + 1 < source.length &&
              source[i + 1] == '/') {
            out.write('  ');
            i += 2;
            break;
          }
          out.write(source[i] == '\n' ? '\n' : ' ');
          i++;
        }
        continue;
      }

      // 字符串 / 字符字面量：处理 \" 与 \\
      if (char == '"' || char == "'") {
        final String quote = char;
        out.write(' ');
        i++;
        while (i < source.length) {
          if (source[i] == '\\' && i + 1 < source.length) {
            out.write('  ');
            i += 2;
            continue;
          }
          final String inner = source[i];
          out.write(inner == '\n' ? '\n' : ' ');
          i++;
          if (inner == quote) {
            break;
          }
        }
        continue;
      }

      out.write(char);
      i++;
    }
    return out.toString();
  }
}

/// 运行前检查发现的一条问题。
class SourceLintFinding {
  const SourceLintFinding({required this.line, required this.message});

  final int line;
  final String message;
}
