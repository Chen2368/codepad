import '../models/project.dart';

/// 工程仓库接口。
///
/// Phase 1 使用内存实现（[InMemoryProjectRepository]）；
/// Phase 2 换成 `FileProjectRepository`，把文件真正写入应用私有目录。
abstract class ProjectRepository {
  Future<List<Project>> loadAll();

  Future<Project> save(Project project);

  Future<void> delete(String id);
}

/// 内存版仓库：进程结束数据即丢失，仅用于骨架阶段与单元测试。
///
/// 注意这里不依赖 `features/` 里的模板代码：示例工程由调用方注入，
/// 保证依赖方向始终是 features → data。
class InMemoryProjectRepository implements ProjectRepository {
  InMemoryProjectRepository({List<Project> seed = const <Project>[]}) {
    for (final Project project in seed) {
      _projects[project.id] = project;
    }
  }

  final Map<String, Project> _projects = <String, Project>{};

  @override
  Future<List<Project>> loadAll() async {
    final List<Project> list = _projects.values.toList();
    list.sort((Project a, Project b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  @override
  Future<Project> save(Project project) async {
    _projects[project.id] = project;
    return project;
  }

  @override
  Future<void> delete(String id) async {
    _projects.remove(id);
  }
}
