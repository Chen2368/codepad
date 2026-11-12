import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/settings/settings_controller.dart';
import '../../data/models/project.dart';
import '../../data/models/source_file.dart';
import '../../data/repositories/project_repository.dart';
import '../editor/editor_page.dart';
import '../settings/settings_page.dart';
import '../templates/template_catalog.dart';
import '../../runtime/native_toolchain.dart';
import '../../runtime/runtime_factory.dart';
import '../../widgets/app_empty_state.dart';
import 'widgets/new_project_dialog.dart';
import 'widgets/project_card.dart';

/// 首页：工程列表 + 新建 / 删除 / 进入编辑器。
class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.projectRepository,
    required this.settings,
    this.runtimeFactory = const RuntimeFactory(),
    this.toolchainStatus,
  });

  final ProjectRepository projectRepository;
  final SettingsController settings;
  final RuntimeFactory runtimeFactory;
  final ToolchainStatus? toolchainStatus;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<List<Project>> _projectsFuture = widget.projectRepository.loadAll();

  void _reload() {
    setState(() {
      _projectsFuture = widget.projectRepository.loadAll();
    });
  }

  Future<void> _openProject(Project project) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => EditorPage(
          project: project,
          projectRepository: widget.projectRepository,
          settings: widget.settings,
          runtimeFactory: widget.runtimeFactory,
          toolchainStatus: widget.toolchainStatus,
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    _reload();
  }

  Future<void> _createProject() async {
    final NewProjectInput? input = await showDialog<NewProjectInput>(
      context: context,
      builder: (BuildContext context) => const NewProjectDialog(),
    );
    if (input == null || !mounted) {
      return;
    }

    final DateTime now = DateTime.now();
    final Project project = Project(
      id: 'p-${now.microsecondsSinceEpoch}',
      name: input.name,
      language: input.language,
      files: <SourceFile>[
        SourceFile(
          path: input.language.defaultFileName,
          content: TemplateCatalog.helloWorld(input.language),
        ),
      ],
      createdAt: now,
      updatedAt: now,
    );

    await widget.projectRepository.save(project);
    if (!mounted) {
      return;
    }
    _reload();
    await _openProject(project);
  }

  Future<void> _confirmDelete(Project project) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('删除「${project.name}」？'),
        content: const Text('该操作会连同本地磁盘上的源文件一起删除，且无法撤销。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }
    await widget.projectRepository.delete(project.id);
    if (!mounted) {
      return;
    }
    _reload();
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => SettingsPage(
          settings: widget.settings,
          toolchainStatus: widget.toolchainStatus,
          runtimeFactory: widget.runtimeFactory,
        ),
      ),
    );
  }

  /// 把「数值积分 / 泰勒展开」两个高数示例加进工程列表（已存在则跳过）。
  Future<void> _addCalculusSamples() async {
    final List<Project> existing = await widget.projectRepository.loadAll();
    final Set<String> ids = <String>{
      for (final Project project in existing) project.id,
    };
    final List<Project> samples = TemplateCatalog.calculusProjects()
        .where((Project project) => !ids.contains(project.id))
        .toList();

    if (samples.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('两个高数示例已经在列表里了')),
      );
      return;
    }

    for (final Project project in samples) {
      await widget.projectRepository.save(project);
    }
    if (!mounted) {
      return;
    }
    _reload();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已加入 ${samples.length} 个示例工程，点开直接运行')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 66,
        titleSpacing: 16,
        title: Row(
          children: <Widget>[
            // 品牌标记：一个带渐变的圆角方块，比纯文字更像「一个应用」
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    scheme.primary,
                    Color.lerp(scheme.primary, const Color(0xFF8B5CF6), 0.55)!,
                  ],
                ),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(
                Icons.data_object,
                size: 18,
                color: scheme.onPrimary,
              ),
            ),
            const SizedBox(width: 11),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const Text(
                  AppConstants.appName,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '${AppConstants.phaseLabel} · 平板 C/C++ · Python',
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ],
        ),
        actions: <Widget>[
          IconButton(
            tooltip: '加入高数示例（数值积分 / 泰勒展开）',
            onPressed: _addCalculusSamples,
            icon: const Icon(Icons.functions),
          ),
          IconButton(
            tooltip: '设置',
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: FutureBuilder<List<Project>>(
        future: _projectsFuture,
        builder: (BuildContext context, AsyncSnapshot<List<Project>> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return AppEmptyState(
              icon: Icons.error_outline,
              title: '工程加载失败',
              message: '${snapshot.error}',
              action: FilledButton(
                onPressed: _reload,
                child: const Text('重试'),
              ),
            );
          }

          final List<Project> projects = snapshot.data ?? const <Project>[];
          if (projects.isEmpty) {
            return AppEmptyState(
              icon: Icons.code,
              title: '还没有工程',
              message: '点击右下角「新建工程」，开始写第一个 C / C++ 或 Python 程序。',
              action: FilledButton.icon(
                onPressed: _createProject,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('新建工程'),
              ),
            );
          }

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                    child: Row(
                      children: <Widget>[
                        Text(
                          '我的工程',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${projects.length}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: scheme.primary,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '点开即可编辑',
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant.withValues(
                              alpha: 0.8,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 2, 16, 100),
                      itemCount: projects.length,
                      separatorBuilder: (BuildContext context, int index) =>
                          const SizedBox(height: 10),
                      itemBuilder: (BuildContext context, int index) {
                        final Project project = projects[index];
                        return ProjectCard(
                          project: project,
                          onTap: () => _openProject(project),
                          onDelete: () => _confirmDelete(project),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createProject,
        icon: const Icon(Icons.add),
        label: const Text('新建工程'),
      ),
    );
  }
}
