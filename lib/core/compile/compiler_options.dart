/// 编译选项：C 标准、优化级别、警告开关。
///
/// 单独建模的原因：这些值既要持久化、又要拼成 tcc 命令行、还要在界面上回显。
/// 拼装逻辑做成纯函数，方便测试（`-Wall` 到底带没带，一眼能验）。
library;

/// C 语言标准。
enum CStandard {
  c99('c99', '-std=c99', 'C99（老教材常用）'),
  c11('c11', '-std=c11', 'C11（推荐，默认）'),
  gnu11('gnu11', '-std=gnu11', 'GNU C11（带 GNU 扩展）');

  const CStandard(this.id, this.flag, this.label);

  final String id;
  final String flag;
  final String label;

  static CStandard fromId(Object? value) {
    for (final CStandard item in CStandard.values) {
      if (item.id == value) {
        return item;
      }
    }
    return CStandard.c11;
  }
}

/// 优化级别。
enum OptimizationLevel {
  o0('0', '-O0', '不优化（调试最直观）'),
  o1('1', '-O1', '轻度优化'),
  o2('2', '-O2', '较快（默认）');

  const OptimizationLevel(this.id, this.flag, this.label);

  final String id;
  final String flag;
  final String label;

  static OptimizationLevel fromId(Object? value) {
    for (final OptimizationLevel item in OptimizationLevel.values) {
      if (item.id == value) {
        return item;
      }
    }
    return OptimizationLevel.o2;
  }
}

/// 一组编译选项。
class CompilerOptions {
  const CompilerOptions({
    this.standard = CStandard.c11,
    this.optimization = OptimizationLevel.o2,
    this.warnings = true,
  });

  final CStandard standard;
  final OptimizationLevel optimization;

  /// 是否带上 `-Wall`（把常见错误当警告显示出来）。
  final bool warnings;

  CompilerOptions copyWith({
    CStandard? standard,
    OptimizationLevel? optimization,
    bool? warnings,
  }) {
    return CompilerOptions(
      standard: standard ?? this.standard,
      optimization: optimization ?? this.optimization,
      warnings: warnings ?? this.warnings,
    );
  }

  /// 拼成 tcc 命令行参数（顺序固定，便于日志比对）。
  List<String> toFlags() {
    return <String>[
      standard.flag,
      optimization.flag,
      if (warnings) '-Wall',
    ];
  }

  /// 给界面看的一句话摘要。
  String get summary {
    final List<String> parts = <String>[
      standard.id,
      'O${optimization.id}',
      if (warnings) 'Wall',
    ];
    return parts.join(' · ');
  }
}
