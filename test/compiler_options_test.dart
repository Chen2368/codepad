import 'package:codepad/core/compile/compiler_options.dart';
import 'package:codepad/core/settings/settings_controller.dart';
import 'package:codepad/data/models/console_message.dart';
import 'package:codepad/features/editor/widgets/problems_panel.dart';
import 'package:codepad/runtime/compile_diagnostic.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('编译选项', () {
    test('默认是 c11 + O2 + -Wall', () {
      const CompilerOptions options = CompilerOptions();
      expect(options.toFlags(), <String>['-std=c11', '-O2', '-Wall']);
      expect(options.summary, 'c11 · O2 · Wall');
    });

    test('可以关掉警告、换优化级别', () {
      const CompilerOptions options = CompilerOptions(
        standard: CStandard.c99,
        optimization: OptimizationLevel.o0,
        warnings: false,
      );
      expect(options.toFlags(), <String>['-std=c99', '-O0']);
    });

    test('id 解析带兜底', () {
      expect(CStandard.fromId('gnu11'), CStandard.gnu11);
      expect(CStandard.fromId('乱写'), CStandard.c11);
      expect(OptimizationLevel.fromId('1'), OptimizationLevel.o1);
      expect(OptimizationLevel.fromId(null), OptimizationLevel.o2);
    });

    test('设置里拼出来的参数能直接喂给 tcc', () {
      final SettingsController settings = SettingsController();
      settings.setCStandard(CStandard.gnu11);
      settings.setCOptimization(OptimizationLevel.o1);
      settings.setCWarnings(false);
      expect(settings.compilerFlags, <String>['-std=gnu11', '-O1']);
    });

    test('运行超时设置范围', () {
      final SettingsController settings = SettingsController();
      expect(settings.runTimeoutSeconds, 10);
      settings.setRunTimeoutSeconds(-5);
      expect(settings.runTimeoutSeconds, 0);
      expect(settings.runTimeout, Duration.zero);
    });
  });

  group('问题面板', () {
    const CompileDiagnostic error = CompileDiagnostic(
      file: 'main.c',
      line: 4,
      message: "expected ';'",
      severity: DiagnosticSeverity.error,
    );
    const CompileDiagnostic warning = CompileDiagnostic(
      file: 'util.c',
      line: 9,
      message: 'unused variable',
      severity: DiagnosticSeverity.warning,
    );

    testWidgets('列出可跳转的诊断，点击回传位置', (WidgetTester tester) async {
      CompileDiagnostic? tapped;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProblemsPanel(
              messages: const <ConsoleMessage>[
                ConsoleMessage(
                  text: "main.c:4: error: expected ';'",
                  level: ConsoleLevel.error,
                  diagnostic: error,
                ),
                ConsoleMessage(
                  text: 'util.c:9: warning: unused variable',
                  level: ConsoleLevel.hint,
                  diagnostic: warning,
                ),
                ConsoleMessage(text: 'printf 输出这一行不算诊断'),
              ],
              onTapDiagnostic: (CompileDiagnostic value) => tapped = value,
              onClose: () {},
            ),
          ),
        ),
      );

      expect(find.text('问题 2'), findsOneWidget);
      expect(find.text('1 错误'), findsOneWidget);
      expect(find.text('1 提示'), findsOneWidget);

      await tester.tap(find.textContaining("expected ';'"));
      expect(tapped?.line, 4);
    });

    testWidgets('没有问题时给一句明确的话', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProblemsPanel(
              messages: const <ConsoleMessage>[
                ConsoleMessage(text: '普通输出'),
              ],
              onTapDiagnostic: (CompileDiagnostic _) {},
              onClose: () {},
            ),
          ),
        ),
      );
      expect(find.text('没有编译问题'), findsOneWidget);
    });
  });
}
