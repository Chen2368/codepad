import 'dart:io';

import 'native_toolchain.dart';

/// 一条自检项的结果。
class SelfCheckResult {
  const SelfCheckResult({
    required this.name,
    required this.description,
    required this.passed,
    this.output = '',
    this.note,
  });

  final String name;

  /// 这一项检查什么（给用户看）。
  final String description;

  final bool passed;

  /// 程序的真实输出（stdout + stderr，已截断）。
  final String output;

  /// 失败时的补充说明。
  final String? note;
}

/// 自检项（内部实现；对外只暴露 [ToolchainSelfCheck]）。
class SelfCheckProbe {
  const SelfCheckProbe({
    required this.name,
    required this.description,
    required this.files,
    required this.expect,
  });

  final String name;
  final String description;

  /// 文件名 → 内容；第一个文件是入口。
  final Map<String, String> files;

  /// 期望在输出里出现的片段。
  final String expect;
}

/// 内置 C 工具链自检：在真机上跑 5 个小程序，逐项报告「能不能用」。
///
/// 存在的意义：`tcc -run`、bionic 头文件、数学库链接这些事情在开发机上无法验证，
/// 与其让用户撞到「莫名报错」，不如给出一个一键自检，把真正的失败点直接指出来。
class ToolchainSelfCheck {
  ToolchainSelfCheck({
    required this.workRoot,
    ToolchainGateway? toolchain,
  }) : _toolchain = toolchain ?? NativeToolchain();

  final Directory workRoot;
  final ToolchainGateway _toolchain;

  /// 自检项。每项：名称、说明、若干源文件、期望输出片段。
  static final List<SelfCheckProbe> probes = <SelfCheckProbe>[
    // 第一项专门用来确认「兼容垫片有没有真的被用上」：
    // bionic 的 sys/cdefs.h 是 clang 写的，tcc 编不动，所以 compat/sys/cdefs.h 必须生效。
    const SelfCheckProbe(
      name: 'shim',
      description: '头文件兼容垫片是否生效（compat/sys/cdefs.h）',
      files: <String, String>{
        'shim.c': '#include <stdio.h>\n'
            'int main(void) {\n'
            '#ifdef CODEPAD_COMPAT_SYS_CDEFS_H\n'
            '    printf("shim=on\\n");\n'
            '#else\n'
            '    printf("shim=off\\n");\n'
            '#endif\n'
            '    return 0;\n'
            '}\n',
      },
      expect: 'shim=on',
    ),
    const SelfCheckProbe(
      name: 'hello',
      description: 'printf 基本输出（stdio.h）',
      files: <String, String>{
        'hello.c': '#include <stdio.h>\n'
            'int main(void) { printf("OK-HELLO\\n"); return 0; }\n',
      },
      expect: 'OK-HELLO',
    ),
    const SelfCheckProbe(
      name: 'format',
      description: '格式化输出 %d / %.2f / %s',
      files: <String, String>{
        'format.c': '#include <stdio.h>\n'
            'int main(void) {\n'
            '    printf("%d %.2f %s\\n", 42, 3.14, "abc");\n'
            '    return 0;\n'
            '}\n',
      },
      expect: '42 3.14 abc',
    ),
    const SelfCheckProbe(
      name: 'math',
      description: '数学库 sqrt / exp（math.h）',
      files: <String, String>{
        'math.c': '#include <stdio.h>\n'
            '#include <math.h>\n'
            'int main(void) {\n'
            '    printf("sqrt2=%.5f exp0=%.1f\\n", sqrt(2.0), exp(0.0));\n'
            '    return 0;\n'
            '}\n',
      },
      expect: 'sqrt2=1.41421',
    ),
    const SelfCheckProbe(
      name: 'loop',
      description: '循环与数组（求和 1..100）',
      files: <String, String>{
        'loop.c': '#include <stdio.h>\n'
            'int main(void) {\n'
            '    int sum = 0;\n'
            '    for (int i = 1; i <= 100; i++) { sum += i; }\n'
            '    printf("sum=%d\\n", sum);\n'
            '    return 0;\n'
            '}\n',
      },
      expect: 'sum=5050',
    ),
    const SelfCheckProbe(
      name: 'multi',
      description: '多文件编译（util.c 里的函数被 main.c 调用）',
      files: <String, String>{
        'multi_main.c': '#include <stdio.h>\n'
            'int add(int a, int b);\n'
            'int main(void) { printf("add=%d\\n", add(3, 4)); return 0; }\n',
        'multi_util.c': 'int add(int a, int b) { return a + b; }\n',
      },
      expect: 'add=7',
    ),
    const SelfCheckProbe(
      name: 'headers',
      description: '标准头齐全（iso646 / uchar / stdatomic / inttypes）',
      files: <String, String>{
        'headers.c': '#include <stdio.h>\n'
            '#include <iso646.h>\n'
            '#include <uchar.h>\n'
            '#include <stdatomic.h>\n'
            '#include <inttypes.h>\n'
            '#include <stdint.h>\n'
            'int main(void) {\n'
            "    char16_t c = (char16_t)65;  /* tcc 不支持 u'A' 字面量，用强转验证类型即可 */\n"
            '    atomic_int n = 0;\n'
            '    atomic_store(&n, 2);\n'
            '    atomic_fetch_add(&n, 3);\n'
            '    int64_t big = 7;\n'
            '    int ok = (1 and 1) ? 1 : 0;\n'
            '    printf("headers=%d,%d,%" PRId64 "\\n",\n'
            '           (int)c, (int)atomic_load(&n) + ok, big);\n'
            '    return 0;\n'
            '}\n',
      },
      expect: 'headers=65,6,7',
    ),
  ];

  /// 依次跑完所有自检项。
  Future<List<SelfCheckResult>> run() async {
    final List<SelfCheckResult> results = <SelfCheckResult>[];
    for (final SelfCheckProbe probe in probes) {
      results.add(await _runProbe(probe));
    }
    return results;
  }

  Future<SelfCheckResult> _runProbe(SelfCheckProbe probe) async {
    final Directory dir = Directory('${workRoot.path}/selfcheck/${probe.name}');
    try {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
      await dir.create(recursive: true);

      final List<String> paths = <String>[];
      for (final MapEntry<String, String> entry in probe.files.entries) {
        final File file = File('${dir.path}/${entry.key}');
        await file.writeAsString(entry.value);
        paths.add(file.path);
      }

      final StringBuffer buffer = StringBuffer();
      final RunProcessResult result = await _toolchain.run(
        sources: paths,
        onLine: (String stream, String text) {
          if (stream == 'info') {
            // 原生侧回显的完整命令行（含 -I 顺序）：失败时这一行就是诊断的关键
            buffer.writeln('> $text');
            return;
          }
          if (stream == 'stdout' || stream == 'stderr') {
            buffer.writeln(text);
          }
        },
      );

      final String output = _truncate(buffer.toString().trim());
      final bool passed =
          result.error == null && result.exitCode == 0 && output.contains(probe.expect);

      String? note;
      if (!passed) {
        if (result.error != null) {
          note = result.error;
        } else if (output.isEmpty) {
          note = '没有任何输出（退出码 ${result.exitCode}）';
        } else {
          note = '输出里没有找到「${probe.expect}」，退出码 ${result.exitCode}';
        }
      }

      return SelfCheckResult(
        name: probe.name,
        description: probe.description,
        passed: passed,
        output: output,
        note: note,
      );
    } catch (error) {
      return SelfCheckResult(
        name: probe.name,
        description: probe.description,
        passed: false,
        note: '自检执行失败：$error',
      );
    }
  }

  String _truncate(String text, {int maxChars = 1500}) {
    if (text.length <= maxChars) {
      return text;
    }
    return '${text.substring(0, maxChars)}\n…（已截断）';
  }
}
