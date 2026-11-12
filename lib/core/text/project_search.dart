/// 工程内（跨文件）搜索：纯逻辑，便于测试。
library;

import 'text_search.dart';

/// 一处跨文件命中。
class ProjectMatch {
  const ProjectMatch({
    required this.path,
    required this.line,
    required this.column,
    required this.start,
    required this.length,
    required this.preview,
  });

  /// 文件路径（工程内相对路径，例如 `main.c`）。
  final String path;

  /// 行号（1 起）。
  final int line;

  /// 列号（1 起）。
  final int column;

  /// 在**该文件全文**里的起始偏移，用于选中。
  final int start;
  final int length;

  /// 该行原文（裁剪前后空白），用于结果列表预览。
  final String preview;
}

/// 在一个文件里收集命中。
List<ProjectMatch> matchInFile(
  String path,
  String content,
  String query, {
  bool caseSensitive = true,
}) {
  if (query.isEmpty || content.isEmpty) {
    return const <ProjectMatch>[];
  }
  final List<TextMatch> matches =
      findMatches(content, query, caseSensitive: caseSensitive);
  if (matches.isEmpty) {
    return const <ProjectMatch>[];
  }

  // 预先算好每行的起始偏移，避免每个命中都从头数换行
  final List<int> lineStarts = <int>[0];
  for (int i = 0; i < content.length; i++) {
    if (content.codeUnitAt(i) == 10) {
      lineStarts.add(i + 1);
    }
  }

  final List<ProjectMatch> results = <ProjectMatch>[];
  for (final TextMatch match in matches) {
    int lineIndex = 0;
    for (int i = 0; i < lineStarts.length; i++) {
      if (lineStarts[i] <= match.start) {
        lineIndex = i;
      } else {
        break;
      }
    }
    final int lineStart = lineStarts[lineIndex];
    int lineEnd = content.indexOf('\n', lineStart);
    if (lineEnd < 0) {
      lineEnd = content.length;
    }
    final String raw = content.substring(lineStart, lineEnd).trimRight();
    results.add(
      ProjectMatch(
        path: path,
        line: lineIndex + 1,
        column: match.start - lineStart + 1,
        start: match.start,
        length: match.length,
        preview: _clip(raw, 120),
      ),
    );
  }
  return results;
}

/// 在整个工程里搜索。[files] 是「路径 → 内容」。
List<ProjectMatch> searchProject(
  Map<String, String> files,
  String query, {
  bool caseSensitive = true,
  int maxResults = 200,
}) {
  if (query.isEmpty) {
    return const <ProjectMatch>[];
  }
  final List<ProjectMatch> results = <ProjectMatch>[];
  final List<String> paths = files.keys.toList()..sort();
  for (final String path in paths) {
    results.addAll(
      matchInFile(path, files[path] ?? '', query, caseSensitive: caseSensitive),
    );
    if (results.length >= maxResults) {
      break;
    }
  }
  return results.length > maxResults
      ? results.sublist(0, maxResults)
      : results;
}

String _clip(String text, int max) {
  final String trimmed = text.trimLeft();
  return trimmed.length <= max ? trimmed : '${trimmed.substring(0, max)}…';
}
