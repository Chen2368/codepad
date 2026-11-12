import 'package:codepad/app.dart';
import 'package:codepad/core/settings/settings_controller.dart';
import 'package:codepad/data/models/program_language.dart';
import 'package:codepad/data/models/project.dart';
import 'package:codepad/data/models/source_file.dart';
import 'package:codepad/data/repositories/project_repository.dart';
import 'package:codepad/features/templates/template_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('模型层', () {
    test('按文件名后缀识别语言', () {
      expect(ProgramLanguage.fromFileName('main.cpp'), ProgramLanguage.cpp);
      expect(ProgramLanguage.fromFileName('main.cc'), ProgramLanguage.cpp);
      expect(ProgramLanguage.fromFileName('main.c'), ProgramLanguage.c);
      expect(ProgramLanguage.fromFileName('util.h'), ProgramLanguage.c);
      expect(ProgramLanguage.fromFileName('main.py'), ProgramLanguage.python);
      expect(ProgramLanguage.fromFileName('README.md'), isNull);
    });

    test('SourceFile 能拆出目录与文件名', () {
      const SourceFile file = SourceFile(path: 'src/util.cpp', content: 'int main(){}');
      expect(file.fileName, 'util.cpp');
      expect(file.folder, 'src');
      expect(file.extension, '.cpp');
      expect(file.language, ProgramLanguage.cpp);
    });

    test('内存仓库按更新时间倒序返回工程', () async {
      final InMemoryProjectRepository repo = InMemoryProjectRepository(
        seed: TemplateCatalog.demoProjects(),
      );
      final List<Project> projects = await repo.loadAll();
      expect(projects.length, 3);
      expect(projects.first.name, 'C 语言入门');
    });
  });

  group('界面骨架', () {
    testWidgets('首页渲染示例工程列表', (WidgetTester tester) async {
      final SettingsController settings = SettingsController();
      await tester.pumpWidget(
        CodePadApp(
          settings: settings,
          projectRepository: InMemoryProjectRepository(
            seed: TemplateCatalog.demoProjects(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('CodePad'), findsWidgets);
      expect(find.text('C 语言入门'), findsOneWidget);
      expect(find.text('C++ 算法练习'), findsOneWidget);
      expect(find.text('Python 入门'), findsOneWidget);
      expect(find.text('新建工程'), findsWidgets);
    });

    testWidgets('进入编辑器并点运行，控制台给出模拟结果', (WidgetTester tester) async {
      final SettingsController settings = SettingsController();
      await tester.pumpWidget(
        CodePadApp(
          settings: settings,
          projectRepository: InMemoryProjectRepository(
            seed: TemplateCatalog.demoProjects(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('C++ 算法练习'));
      await tester.pumpAndSettle();

      expect(find.text('运行'), findsOneWidget);

      await tester.tap(find.text('运行'));
      await tester.pump();
      // 模拟引擎：编译 420ms + 若干行输出，推进 2 秒足够跑完
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      // 状态机落到「成功」，控制台出现收尾消息
      expect(find.textContaining('控制台 · 运行成功'), findsOneWidget);
      // 运行窗口（弹出面板）同时出现：标题 + 状态胶囊
      expect(find.text('运行结果'), findsOneWidget);
      expect(find.textContaining('运行成功'), findsWidgets);
      expect(find.textContaining('运行结束'), findsWidgets);
    });

    testWidgets('平板横屏宽度下左侧文件树常驻', (WidgetTester tester) async {
      // 模拟 12.6 寸平板横屏：1280x800 逻辑像素
      tester.view.physicalSize = const Size(2560, 1600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final SettingsController settings = SettingsController();
      await tester.pumpWidget(
        CodePadApp(
          settings: settings,
          projectRepository: InMemoryProjectRepository(
            seed: TemplateCatalog.demoProjects(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('C++ 算法练习'));
      await tester.pumpAndSettle();

      // 宽屏：文件树直接可见，且不需要抽屉按钮
      expect(find.text('资源管理器'), findsOneWidget);
      expect(find.text('main.cpp'), findsWidgets);
    });
  });
}
