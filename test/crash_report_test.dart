import 'package:codepad/core/diagnostics/crash_report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('会话日志解析', () {
    test('解析时间戳、kind 与 detail', () {
      const String raw = '11-23 12:15:07.123  app-start|v1.0.0\n'
          '11-23 12:15:20.000  run-begin|main.c\n'
          '11-23 12:15:21.500  run-end|main.c\n';
      final List<SessionEntry> entries = parseSessionLog(raw);
      expect(entries, hasLength(3));
      expect(entries[0].kind, 'app-start');
      expect(entries[0].detail, 'v1.0.0');
      expect(entries[1].detail, 'main.c');
    });

    test('detail 里带换行/竖线也不炸', () {
      const String raw =
          '11-23 12:15:07.123  platform-error|a|b\n第二行不是记录\n';
      final List<SessionEntry> entries = parseSessionLog(raw);
      expect(entries, hasLength(1));
      expect(entries.single.kind, 'platform-error');
      expect(entries.single.detail, 'a|b');
    });

    test('空日志返回空列表', () {
      expect(parseSessionLog(''), isEmpty);
    });
  });

  group('上次运行是否异常结束', () {
    List<SessionEntry> log(List<String> kinds) {
      final StringBuffer buffer = StringBuffer();
      for (int i = 0; i < kinds.length; i++) {
        buffer.writeln('11-23 12:00:0$i.000  ${kinds[i]}|main.c');
      }
      return parseSessionLog(buffer.toString());
    }

    test('run-begin 没有 run-end → 判定为异常结束', () {
      final UnfinishedRun? run =
          findUnfinishedRun(log(<String>['app-start', 'run-begin']));
      expect(run, isNotNull);
      expect(run!.fileName, 'main.c');
    });

    test('run-begin + run-end → 正常', () {
      expect(
        findUnfinishedRun(log(<String>['app-start', 'run-begin', 'run-end'])),
        isNull,
      );
    });

    test('新会话开始后不再追究更早的记录', () {
      expect(
        findUnfinishedRun(log(<String>[
          'run-begin',
          'app-start', // 上次闪退后已重新启动过一次
          'run-end',
        ])),
        isNull,
      );
    });

    test('没有任何运行记录 → 正常', () {
      expect(findUnfinishedRun(log(<String>['app-start'])), isNull);
    });
  });

  group('诊断报告', () {
    test('包含版本、构建、设备与原始日志', () {
      final String report = buildCrashReport(
        appVersion: '1.0.0',
        buildTag: '1.0.0-c',
        deviceInfo: 'android 12 (HarmonyOS 4.2)',
        rawLog: '11-23 12:15:20.000  run-begin|main.c',
      );
      expect(report, contains('CodePad 崩溃诊断报告'));
      expect(report, contains('版本：1.0.0'));
      expect(report, contains('1.0.0-c'));
      expect(report, contains('HarmonyOS 4.2'));
      expect(report, contains('run-begin|main.c'));
    });
  });
}