/// 崩溃/会话日志的纯逻辑部分：解析与判定。
///
/// 为什么要这个：闪退时 App 来不及提示任何东西 —— 进程被系统直接杀掉。
/// 所以只有「先落盘、下次启动再读」这条路：运行前写一条 `run-begin`，
/// 跑完写 `run-end`；下次启动如果发现最后一条是 `run-begin`，
/// 就说明**上一个进程死在运行 C 程序的过程中**。
///
/// 这里只放能单元测试的函数，真正的落盘由原生侧（codepad/storage 的 mark/readLog）负责。
library;

/// 一条会话记录。
class SessionEntry {
  const SessionEntry({
    required this.timestamp,
    required this.kind,
    required this.detail,
  });

  /// 日志里的时间前缀（原生侧按 `MM-dd HH:mm:ss.SSS` 写）。
  final String timestamp;
  final String kind;
  final String detail;

  @override
  String toString() => '$timestamp  $kind|$detail';
}

/// 解析原生侧写的 session.log。
///
/// 行格式：`11-23 12:15:07.123  kind|detail`；也容忍 detail 里出现 `|`。
List<SessionEntry> parseSessionLog(String raw) {
  final List<SessionEntry> entries = <SessionEntry>[];
  for (final String line in raw.split('\n')) {
    final String trimmed = line.trimRight();
    if (trimmed.isEmpty) {
      continue;
    }
    final int split = trimmed.indexOf('  ');
    if (split <= 0) {
      continue;
    }
    final String stamp = trimmed.substring(0, split);
    final String body = trimmed.substring(split + 2);
    final int bar = body.indexOf('|');
    if (bar < 0) {
      entries.add(SessionEntry(timestamp: stamp, kind: body, detail: ''));
      continue;
    }
    entries.add(
      SessionEntry(
        timestamp: stamp,
        kind: body.substring(0, bar),
        detail: body.substring(bar + 1),
      ),
    );
  }
  return entries;
}

/// 上一次会话里「没配对的运行」的信息。
class UnfinishedRun {
  const UnfinishedRun({required this.fileName, required this.when});

  final String fileName;
  final String when;
}

/// 找出上一次未收尾的运行。
///
/// 规则：从后往前扫，遇到 `run-end` 就说明上次运行正常结束（返回 null）；
/// 遇到 `run-begin` 说明进程在运行期间被杀（返回该条）。
/// 只看最后一段（以 `app-start` 为界），避免把很久以前的记录算进来。
UnfinishedRun? findUnfinishedRun(List<SessionEntry> entries) {
  for (int i = entries.length - 1; i >= 0; i--) {
    final SessionEntry entry = entries[i];
    if (entry.kind == 'app-start') {
      return null; // 本段会话已经重新开始了
    }
    if (entry.kind == 'run-end') {
      return null; // 上次运行正常收尾
    }
    if (entry.kind == 'run-begin') {
      return UnfinishedRun(fileName: entry.detail, when: entry.timestamp);
    }
  }
  return null;
}

/// 把要发给开发者的报告拼好（日志 + 环境信息）。
String buildCrashReport({
  required String appVersion,
  required String buildTag,
  required String deviceInfo,
  required String rawLog,
}) {
  final StringBuffer buffer = StringBuffer()
    ..writeln('CodePad 崩溃诊断报告')
    ..writeln('版本：$appVersion   构建：$buildTag')
    ..writeln('设备：$deviceInfo')
    ..writeln('时间：${DateTime.now().toIso8601String()}')
    ..writeln('')
    ..writeln(rawLog);
  return buffer.toString();
}