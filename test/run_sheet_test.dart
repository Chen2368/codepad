import 'package:codepad/data/models/console_message.dart';
import 'package:codepad/features/editor/widgets/console_input_row.dart';
import 'package:codepad/features/editor/widgets/console_output_view.dart';
import 'package:codepad/runtime/compile_diagnostic.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('运行输出区', () {
    testWidgets('没有输出时显示提示语', (WidgetTester tester) async {
      await tester.pumpWidget(
        _wrap(const ConsoleOutputView(messages: <ConsoleMessage>[])),
      );
      expect(find.textContaining('点击工具栏的「运行」查看输出'), findsOneWidget);
    });

    testWidgets('逐行显示输出', (WidgetTester tester) async {
      await tester.pumpWidget(
        _wrap(
          const ConsoleOutputView(
            messages: <ConsoleMessage>[
              ConsoleMessage(text: '积分值 = 0.33333350', level: ConsoleLevel.output),
              ConsoleMessage(text: '✓ 运行结束', level: ConsoleLevel.success),
            ],
          ),
        ),
      );
      expect(find.textContaining('积分值'), findsOneWidget);
      expect(find.textContaining('运行结束'), findsOneWidget);
    });

    testWidgets('编译诊断可点击跳行', (WidgetTester tester) async {
      CompileDiagnostic? tapped;
      const CompileDiagnostic diagnostic = CompileDiagnostic(
        file: 'main.c',
        line: 12,
        column: 5,
        message: 'expected ;',
        severity: DiagnosticSeverity.error,
      );

      await tester.pumpWidget(
        _wrap(
          ConsoleOutputView(
            messages: const <ConsoleMessage>[
              ConsoleMessage(
                text: 'main.c:12:5: error: expected ;',
                level: ConsoleLevel.error,
                diagnostic: diagnostic,
              ),
            ],
            onTapDiagnostic: (CompileDiagnostic value) => tapped = value,
          ),
        ),
      );

      expect(find.text('第 12 行'), findsOneWidget);
      await tester.tap(find.text('第 12 行'));
      expect(tapped, isNotNull);
      expect(tapped!.line, 12);
    });
  });

  group('标准输入行', () {
    testWidgets('运行时可以输入并回车发送', (WidgetTester tester) async {
      final List<String> sent = <String>[];
      await tester.pumpWidget(
        _wrap(
          ConsoleInputRow(enabled: true, onSendInput: sent.add),
        ),
      );

      await tester.enterText(find.byType(TextField), '21');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();

      expect(sent, <String>['21']);
    });

    testWidgets('未运行时输入框禁用', (WidgetTester tester) async {
      await tester.pumpWidget(
        _wrap(
          ConsoleInputRow(enabled: false, onSendInput: (String _) {}),
        ),
      );
      final TextField field = tester.widget<TextField>(find.byType(TextField));
      expect(field.enabled, isFalse);
    });
  });
}
