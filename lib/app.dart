import 'package:flutter/material.dart';

import 'core/constants/app_constants.dart';
import 'core/settings/settings_controller.dart';
import 'core/theme/app_theme.dart';
import 'data/repositories/project_repository.dart';
import 'features/home/home_page.dart';
import 'runtime/native_toolchain.dart';
import 'runtime/runtime_factory.dart';

/// 应用根组件：注入主题与依赖。
class CodePadApp extends StatelessWidget {
  const CodePadApp({
    super.key,
    required this.settings,
    required this.projectRepository,
    this.runtimeFactory = const RuntimeFactory(),
    this.toolchainStatus,
  });

  final SettingsController settings;
  final ProjectRepository projectRepository;

  /// 运行引擎工厂：默认模拟引擎，真机由 main.dart 注入真实引擎。
  final RuntimeFactory runtimeFactory;

  /// 启动时探测到的内置编译器状态（用于设置页展示）。
  final ToolchainStatus? toolchainStatus;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (BuildContext context, Widget? child) {
        return MaterialApp(
          title: AppConstants.appName,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: settings.themeMode,
          home: HomePage(
            projectRepository: projectRepository,
            settings: settings,
            runtimeFactory: runtimeFactory,
            toolchainStatus: toolchainStatus,
          ),
        );
      },
    );
  }
}
