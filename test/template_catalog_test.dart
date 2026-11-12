import 'package:codepad/data/models/program_language.dart';
import 'package:codepad/data/models/project.dart';
import 'package:codepad/data/models/source_file.dart';
import 'package:codepad/features/templates/template_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('高数示例工程', () {
    test('提供两个可直接运行的 C 工程', () {
      final List<Project> samples = TemplateCatalog.calculusProjects();

      expect(samples, hasLength(2));
      expect(
        samples.map((Project p) => p.id).toSet(),
        <String>{'demo-c-quadrature', 'demo-c-taylor'},
      );
      for (final Project project in samples) {
        expect(project.language, ProgramLanguage.c);
        expect(project.files, isNotEmpty);
      }
    });

    test('每个示例都只有一个带 main 的 .c 文件', () {
      for (final Project project in TemplateCatalog.calculusProjects()) {
        final Iterable<SourceFile> withMain = project.files.where(
          (SourceFile file) =>
              file.path.endsWith('.c') && file.content.contains('int main('),
        );
        expect(withMain, hasLength(1), reason: '${project.name} 应当只有一个入口');
      }
    });

    test('数值积分示例用到了 math.h，并打印误差', () {
      final Project project = TemplateCatalog.calculusProjects().first;
      final String source = project.files.single.content;

      expect(source, contains('#include <math.h>'));
      expect(source, contains('simpson'));
      expect(source, contains('fabs('));
    });

    test('示例 id 与首次启动的示例工程不冲突', () {
      final Set<String> seeded = <String>{
        for (final Project project in TemplateCatalog.demoProjects()) project.id,
      };
      for (final Project project in TemplateCatalog.calculusProjects()) {
        expect(seeded.contains(project.id), isFalse);
      }
    });
  });
}
