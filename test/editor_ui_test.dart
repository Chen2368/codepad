import 'package:codepad/app.dart';
import 'package:codepad/core/settings/settings_controller.dart';
import 'package:codepad/data/repositories/project_repository.dart';
import 'package:codepad/features/templates/template_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase 2 的文件操作接在界面上，这里从「点按钮」开始验证整条链路。
void main() {
  Future<void> pumpTabletApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(2560, 1600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      CodePadApp(
        settings: SettingsController(),
        projectRepository: InMemoryProjectRepository(
          seed: TemplateCatalog.demoProjects(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('C++ 算法练习'));
    await tester.pumpAndSettle();
  }

  testWidgets('文件树「+」新建文件后出现在标签栏', (WidgetTester tester) async {
    await pumpTabletApp(tester);

    await tester.tap(find.byTooltip('新建文件'));
    await tester.pumpAndSettle();

    final Finder dialogInput = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    expect(dialogInput, findsOneWidget);

    await tester.enterText(dialogInput, 'lib/utils.cpp');
    await tester.tap(find.widgetWithText(FilledButton, '确定'));
    await tester.pumpAndSettle();

    // 新建的文件成为当前标签，并出现在文件树中（同一文本可能出现两次）
    expect(find.text('utils.cpp'), findsWidgets);
  });

  testWidgets('重名文件会给出提示而不是静默失败', (WidgetTester tester) async {
    await pumpTabletApp(tester);

    await tester.tap(find.byTooltip('新建文件'));
    await tester.pumpAndSettle();
    final Finder dialogInput = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(dialogInput, 'main.cpp');
    await tester.tap(find.widgetWithText(FilledButton, '确定'));
    await tester.pumpAndSettle();

    expect(find.textContaining('文件已存在'), findsOneWidget);
  });

  testWidgets('删除文件菜单会弹出确认框', (WidgetTester tester) async {
    await pumpTabletApp(tester);

    final Finder firstMenu = find.byTooltip('文件操作').first;
    await tester.tap(firstMenu);
    await tester.pumpAndSettle();

    await tester.tap(find.text('删除文件'));
    await tester.pumpAndSettle();

    expect(find.text('删除文件'), findsWidgets);
    expect(find.textContaining('确定删除'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(find.textContaining('确定删除'), findsNothing);
  });
}
