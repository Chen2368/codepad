import '../../../data/models/program_language.dart';
import 'code_token.dart';

/// 语法高亮用的轻量 tokenizer。
///
/// 不做完整语法分析，只识别「关键字 / 类型 / 字符串 / 注释 / 数字 / 函数名 /
/// 预处理指令」这几类，够用于着色，且对不完整代码（边写边变色）不会崩。
abstract class CodeTokenizer {
  const CodeTokenizer();

  List<CodeToken> tokenize(String source);

  static CodeTokenizer forLanguage(ProgramLanguage? language) {
    switch (language) {
      case ProgramLanguage.c:
        return CLikeTokenizer.c;
      case ProgramLanguage.cpp:
        return CLikeTokenizer.cpp;
      case ProgramLanguage.python:
        return const PythonTokenizer();
      case null:
        return const PlainTokenizer();
    }
  }
}

/// 无法识别语言时的空实现。
class PlainTokenizer extends CodeTokenizer {
  const PlainTokenizer();

  @override
  List<CodeToken> tokenize(String source) => const <CodeToken>[];
}

/// C / C++ 共用的 tokenizer（差异只在关键字集合）。
class CLikeTokenizer extends CodeTokenizer {
  const CLikeTokenizer({required this.keywords, required this.types});

  static const CLikeTokenizer c = CLikeTokenizer(
    keywords: _cKeywords,
    types: _cTypes,
  );

  static const CLikeTokenizer cpp = CLikeTokenizer(
    keywords: _cppKeywords,
    types: _cppTypes,
  );

  final Set<String> keywords;
  final Set<String> types;

  @override
  List<CodeToken> tokenize(String source) {
    final List<CodeToken> tokens = <CodeToken>[];
    final int n = source.length;
    int i = 0;
    bool lineStart = true;

    while (i < n) {
      final String ch = source[i];

      // 行首的 # 预处理指令，一直染到行尾
      if (ch == '#' && lineStart) {
        int j = i;
        while (j < n && source[j] != '\n') {
          j++;
        }
        tokens.add(CodeToken(start: i, end: j, kind: TokenKind.preprocessor));
        i = j;
        continue;
      }

      if (ch == '/' && i + 1 < n && source[i + 1] == '/') {
        int j = i;
        while (j < n && source[j] != '\n') {
          j++;
        }
        tokens.add(CodeToken(start: i, end: j, kind: TokenKind.comment));
        i = j;
        continue;
      }

      if (ch == '/' && i + 1 < n && source[i + 1] == '*') {
        final int close = source.indexOf('*/', i + 2);
        final int j = close < 0 ? n : close + 2;
        tokens.add(CodeToken(start: i, end: j, kind: TokenKind.comment));
        i = j;
        continue;
      }

      if (ch == '"' || ch == '\'') {
        final int j = _scanQuoted(source, i, ch);
        tokens.add(CodeToken(start: i, end: j, kind: TokenKind.string));
        i = j;
        lineStart = false;
        continue;
      }

      if (_isDigit(ch)) {
        final int j = _scanNumber(source, i);
        tokens.add(CodeToken(start: i, end: j, kind: TokenKind.number));
        i = j;
        lineStart = false;
        continue;
      }

      if (_isIdentStart(ch)) {
        int j = i + 1;
        while (j < n && _isIdentPart(source[j])) {
          j++;
        }
        final String word = source.substring(i, j);
        TokenKind kind = TokenKind.plain;
        if (keywords.contains(word)) {
          kind = TokenKind.keyword;
        } else if (types.contains(word)) {
          kind = TokenKind.type;
        } else if (_nextNonSpace(source, j) == '(') {
          kind = TokenKind.function;
        }
        if (kind != TokenKind.plain) {
          tokens.add(CodeToken(start: i, end: j, kind: kind));
        }
        i = j;
        lineStart = false;
        continue;
      }

      if (ch == '\n') {
        lineStart = true;
      } else if (ch != ' ' && ch != '\t' && ch != '\r') {
        lineStart = false;
      }
      i++;
    }
    return tokens;
  }
}

/// Python tokenizer：支持 `#` 注释、三引号字符串、装饰器、def / class 名称。
class PythonTokenizer extends CodeTokenizer {
  const PythonTokenizer();

  @override
  List<CodeToken> tokenize(String source) {
    final List<CodeToken> tokens = <CodeToken>[];
    final int n = source.length;
    int i = 0;
    String? previousWord;

    while (i < n) {
      final String ch = source[i];

      if (ch == '#') {
        int j = i;
        while (j < n && source[j] != '\n') {
          j++;
        }
        tokens.add(CodeToken(start: i, end: j, kind: TokenKind.comment));
        i = j;
        continue;
      }

      if (ch == '"' || ch == '\'') {
        final bool triple = source.startsWith(ch * 3, i);
        int j;
        if (triple) {
          final int close = source.indexOf(ch * 3, i + 3);
          j = close < 0 ? n : close + 3;
        } else {
          j = _scanQuoted(source, i, ch);
        }
        tokens.add(CodeToken(start: i, end: j, kind: TokenKind.string));
        i = j;
        previousWord = null;
        continue;
      }

      if (ch == '@' && i + 1 < n && _isIdentStart(source[i + 1])) {
        int j = i + 1;
        while (j < n && _isIdentPart(source[j])) {
          j++;
        }
        tokens.add(CodeToken(start: i, end: j, kind: TokenKind.function));
        i = j;
        continue;
      }

      if (_isDigit(ch)) {
        final int j = _scanNumber(source, i);
        tokens.add(CodeToken(start: i, end: j, kind: TokenKind.number));
        i = j;
        continue;
      }

      if (_isIdentStart(ch)) {
        int j = i + 1;
        while (j < n && _isIdentPart(source[j])) {
          j++;
        }
        final String word = source.substring(i, j);
        TokenKind kind = TokenKind.plain;
        if (_pythonKeywords.contains(word)) {
          kind = TokenKind.keyword;
        } else if (_pythonBuiltins.contains(word)) {
          kind = TokenKind.type;
        } else if (previousWord == 'def') {
          kind = TokenKind.function;
        } else if (previousWord == 'class') {
          kind = TokenKind.type;
        } else if (_nextNonSpace(source, j) == '(') {
          kind = TokenKind.function;
        }
        if (kind != TokenKind.plain) {
          tokens.add(CodeToken(start: i, end: j, kind: kind));
        }
        previousWord = word;
        i = j;
        continue;
      }

      i++;
    }
    return tokens;
  }
}

const Set<String> _cKeywords = <String>{
  'auto', 'break', 'case', 'const', 'continue', 'default', 'do', 'else', 'enum',
  'extern', 'for', 'goto', 'if', 'inline', 'register', 'restrict', 'return',
  'sizeof', 'static', 'struct', 'switch', 'typedef', 'union', 'volatile', 'while',
};

const Set<String> _cTypes = <String>{
  'char', 'double', 'float', 'int', 'long', 'short', 'signed', 'unsigned', 'void',
  '_Bool', 'size_t', 'ssize_t', 'FILE', 'bool', 'int8_t', 'int16_t', 'int32_t',
  'int64_t', 'uint8_t', 'uint16_t', 'uint32_t', 'uint64_t', 'NULL',
};

const Set<String> _cppKeywords = <String>{
  'alignas', 'alignof', 'and', 'and_eq', 'asm', 'auto', 'bitand', 'bitor', 'break',
  'case', 'catch', 'class', 'compl', 'concept', 'const', 'consteval', 'constexpr',
  'constinit', 'const_cast', 'continue', 'co_await', 'co_return', 'co_yield',
  'decltype', 'default', 'delete', 'do', 'dynamic_cast', 'else', 'enum', 'explicit',
  'export', 'extern', 'false', 'for', 'friend', 'goto', 'if', 'inline', 'mutable',
  'namespace', 'new', 'noexcept', 'not', 'not_eq', 'nullptr', 'operator', 'or',
  'or_eq', 'private', 'protected', 'public', 'register', 'reinterpret_cast',
  'requires', 'return', 'sizeof', 'static', 'static_assert', 'static_cast', 'struct',
  'switch', 'template', 'this', 'thread_local', 'throw', 'true', 'try', 'typedef',
  'typeid', 'typename', 'union', 'using', 'virtual', 'volatile', 'while', 'xor',
  'xor_eq',
};

const Set<String> _cppTypes = <String>{
  'bool', 'char', 'char8_t', 'char16_t', 'char32_t', 'double', 'float', 'int', 'long',
  'short', 'signed', 'unsigned', 'void', 'wchar_t', 'size_t', 'string', 'wstring',
  'vector', 'map', 'set', 'unordered_map', 'unordered_set', 'pair', 'tuple',
  'shared_ptr', 'unique_ptr', 'optional', 'function', 'ostream', 'istream',
  'stringstream', 'int8_t', 'int16_t', 'int32_t', 'int64_t', 'uint8_t', 'uint16_t',
  'uint32_t', 'uint64_t',
};

const Set<String> _pythonKeywords = <String>{
  'False', 'None', 'True', 'and', 'as', 'assert', 'async', 'await', 'break', 'case',
  'class', 'continue', 'def', 'del', 'elif', 'else', 'except', 'finally', 'for',
  'from', 'global', 'if', 'import', 'in', 'is', 'lambda', 'match', 'nonlocal',
  'not', 'or', 'pass', 'raise', 'return', 'try', 'while', 'with', 'yield',
};

const Set<String> _pythonBuiltins = <String>{
  'abs', 'all', 'any', 'bool', 'bytes', 'dict', 'enumerate', 'filter', 'float',
  'format', 'frozenset', 'input', 'int', 'isinstance', 'len', 'list', 'map', 'max',
  'min', 'object', 'open', 'print', 'range', 'repr', 'reversed', 'round', 'set',
  'sorted', 'str', 'sum', 'super', 'tuple', 'type', 'zip',
};

bool _isDigit(String c) {
  final int u = c.codeUnitAt(0);
  return u >= 48 && u <= 57;
}

bool _isIdentStart(String c) {
  final int u = c.codeUnitAt(0);
  return (u >= 65 && u <= 90) || (u >= 97 && u <= 122) || c == '_' || u > 127;
}

bool _isIdentPart(String c) {
  return _isIdentStart(c) || _isDigit(c);
}

/// 取 [index] 之后第一个非空白字符（用于判断是否函数调用）。
String? _nextNonSpace(String source, int index) {
  int i = index;
  while (i < source.length && (source[i] == ' ' || source[i] == '\t' || source[i] == '\r')) {
    i++;
  }
  return i < source.length ? source[i] : null;
}

/// 扫描到匹配的引号为止（含转义），遇到换行则终止（不完整代码也能高亮）。
int _scanQuoted(String source, int start, String quote) {
  int i = start + 1;
  while (i < source.length) {
    final String c = source[i];
    if (c == r'\' && i + 1 < source.length) {
      i += 2;
      continue;
    }
    if (c == quote) {
      return i + 1;
    }
    if (c == '\n') {
      return i;
    }
    i++;
  }
  return source.length;
}

int _scanNumber(String source, int start) {
  int i = start;
  final int n = source.length;
  if (source[i] == '0' && i + 1 < n && (source[i + 1] == 'x' || source[i + 1] == 'X')) {
    i += 2;
    while (i < n && (RegExp(r'[0-9a-fA-F]').hasMatch(source[i]))) {
      i++;
    }
    return i;
  }
  while (i < n && _isDigit(source[i])) {
    i++;
  }
  if (i < n && source[i] == '.') {
    i++;
    while (i < n && _isDigit(source[i])) {
      i++;
    }
  }
  if (i < n && (source[i] == 'e' || source[i] == 'E')) {
    i++;
    if (i < n && (source[i] == '+' || source[i] == '-')) {
      i++;
    }
    while (i < n && _isDigit(source[i])) {
      i++;
    }
  }
  while (i < n && RegExp(r'[uUlLfF]').hasMatch(source[i])) {
    i++;
  }
  return i;
}
