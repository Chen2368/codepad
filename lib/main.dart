import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/settings/settings_controller.dart';
import 'data/models/project.dart';
import 'data/repositories/file_project_repository.dart';
import 'data/repositories/prefs_settings_store.dart';
import 'data/repositories/project_repository.dart';
import 'data/repositories/settings_store.dart';
import 'features/templates/template_catalog.dart';
import 'runtime/native_toolchain.dart';
import 'runtime/runtime_factory.dart';

/// 启动流程：
/// 1. 读取持久化设置（shared_preferences），失败则退回内存存储；
/// 2. 打开应用私有目录下的工程仓库（真实文件读写），失败则退回内存仓库；
/// 3. Phase 3：探测内置 tcc 工具链，决定 C 语言走真实编译还是模拟运行；
/// 4. 首次启动写入两个示例工程，避免空白首页。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final SettingsStore store = await _createSettingsStore();
  final SettingsController settings = SettingsController(store: store);
  await settings.load();

  final ProjectRepository repository = await _createProjectRepository();
  final RuntimeFactory runtimeFactory = await _createRuntimeFactory(settings);

  runApp(
    CodePadApp(
      settings: settings,
      projectRepository: repository,
      runtimeFactory: runtimeFactory,
      toolchainStatus: runtimeFactory.toolchainStatus,
    ),
  );
}

Future<SettingsStore> _createSettingsStore() async {
  try {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return PrefsSettingsStore(prefs);
  } catch (error) {
    debugPrint('设置持久化不可用，回退到内存存储：$error');
    return InMemorySettingsStore();
  }
}

Future<ProjectRepository> _createProjectRepository() async {
  try {
    final Directory documents = await getApplicationDocumentsDirectory();
    final FileProjectRepository repository = FileProjectRepository(
      root: Directory(p.join(documents.path, 'CodePad', 'projects')),
    );
    if ((await repository.loadAll()).isEmpty) {
      for (final Project project in TemplateCatalog.demoProjects()) {
        await repository.save(project);
      }
    }
    return repository;
  } catch (error) {
    debugPrint('文件系统仓库不可用，回退到内存仓库：$error');
    return InMemoryProjectRepository(seed: TemplateCatalog.demoProjects());
  }
}

/// 探测内置编译器并组装运行引擎工厂。
Future<RuntimeFactory> _createRuntimeFactory(SettingsController settings) async {
  final NativeToolchain toolchain = NativeToolchain();
  final ToolchainStatus status = await toolchain.probe();
  debugPrint('内置编译器状态：${status.summary}');

  Directory? runRoot;
  try {
    final Directory temp = await getTemporaryDirectory();
    runRoot = Directory(p.join(temp.path, 'run'));
    await runRoot.create(recursive: true);
  } catch (error) {
    debugPrint('无法准备运行目录，C 运行时将不可用：$error');
  }

  return RuntimeFactory(
    preferNative: true,
    workRoot: runRoot,
    toolchain: toolchain,
    toolchainStatus: status,
    multiFileCompile: () => settings.multiFileCompile,
  );
}
