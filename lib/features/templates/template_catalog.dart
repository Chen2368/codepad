import '../../data/models/program_language.dart';
import '../../data/models/project.dart';
import '../../data/models/source_file.dart';

/// 内置代码模板。
///
/// 注意：模板内容使用原始字符串（r'''...'''），保证 `\n` 等转义按源码原样写入文件。
class TemplateCatalog {
  TemplateCatalog._();

  /// 某语言的 Hello World 模板。
  static String helloWorld(ProgramLanguage language) {
    switch (language) {
      case ProgramLanguage.c:
        return cHelloWorld;
      case ProgramLanguage.cpp:
        return cppHelloWorld;
      case ProgramLanguage.python:
        return pythonHelloWorld;
    }
  }

  /// 示例工程列表：首次启动时展示，方便直接点开体验。
  ///
  /// 「C 语言入门」排在最前：Phase 3 起 C 是唯一能真编译真运行的语言，
  /// 装好应用第一次点「运行」就应该看到真实结果。
  static List<Project> demoProjects() {
    final DateTime now = DateTime.now();
    return <Project>[
      Project(
        id: 'demo-c',
        name: 'C 语言入门',
        language: ProgramLanguage.c,
        files: <SourceFile>[
          const SourceFile(path: 'main.c', content: cIntegralDemo),
          const SourceFile(path: 'util.h', content: cUtilHeader),
          const SourceFile(path: 'util.c', content: cUtilSource),
          const SourceFile(path: 'hello.c', content: cHelloWorld),
          const SourceFile(path: 'input.c', content: cStdinDemo),
        ],
        createdAt: now.subtract(const Duration(days: 5)),
        updatedAt: now,
      ),
      Project(
        id: 'demo-cpp',
        name: 'C++ 算法练习',
        language: ProgramLanguage.cpp,
        files: <SourceFile>[
          const SourceFile(path: 'main.cpp', content: cppSortDemo),
          const SourceFile(path: 'hello.cpp', content: cppHelloWorld),
        ],
        createdAt: now.subtract(const Duration(days: 3)),
        updatedAt: now.subtract(const Duration(hours: 5)),
      ),
      Project(
        id: 'demo-python',
        name: 'Python 入门',
        language: ProgramLanguage.python,
        files: <SourceFile>[
          const SourceFile(path: 'main.py', content: pythonFibDemo),
          const SourceFile(path: 'hello.py', content: pythonHelloWorld),
        ],
        createdAt: now.subtract(const Duration(days: 1)),
        updatedAt: now.subtract(const Duration(hours: 2)),
      ),
    ];
  }

  static const String cHelloWorld = r'''#include <stdio.h>

int main(void) {
    printf("Hello, CodePad!\n");
    return 0;
}
''';

  /// 真编译示例：梯形法求定积分，被积函数在 util.c 里（演示多文件编译）。
  static const String cIntegralDemo = r'''#include <stdio.h>

#include "util.h"

/* 梯形法计算 f(x) 在 [0, 1] 上的定积分，f(x)=x^2，精确值为 1/3。
   f 定义在同工程的 util.c 里：点「运行」会同时编译 main.c 与 util.c。 */

int main(void) {
    const int n = 1000;
    const double a = 0.0;
    const double b = 1.0;
    const double h = (b - a) / n;

    double sum = (f(a) + f(b)) / 2.0;
    for (int i = 1; i < n; i++) {
        sum += f(a + i * h);
    }

    double integral = sum * h;
    printf("梯形法 n = %d\n", n);
    printf("积分值 = %.8f\n", integral);
    printf("精确值 = %.8f\n", 1.0 / 3.0);
    printf("误差   = %.2e\n", integral - 1.0 / 3.0);
    return 0;
}
''';

  static const String cUtilHeader = r'''#ifndef CODEPAD_UTIL_H
#define CODEPAD_UTIL_H

/* 被积函数：f(x) = x * x。
   头文件里只放声明，实现放在 util.c —— 否则多个 .c 一起编译会重复定义。 */
double f(double x);

#endif
''';

  static const String cUtilSource = r'''#include "util.h"

double f(double x) {
    return x * x;
}
''';

  /// 标准输入示例：运行后在控制台底部 stdin 输入行填数字再回车。
  static const String cStdinDemo = r'''#include <stdio.h>

int main(void) {
    int n;
    printf("请输入一个整数: ");
    fflush(stdout);   /* 管道默认块缓冲，不刷新可能看不到提示 */

    if (scanf("%d", &n) != 1) {
        printf("\n没有读到输入：请在控制台底部的 stdin 输入行填一个整数再回车\n");
        return 1;
    }

    printf("%d 的平方是 %d\n", n, n * n);
    return 0;
}
''';

  static const String cppHelloWorld = r'''#include <iostream>

int main() {
    std::cout << "Hello, CodePad!" << std::endl;
    return 0;
}
''';

  static const String cppSortDemo = r'''#include <algorithm>
#include <iostream>
#include <vector>

int main() {
    std::vector<int> nums = {5, 2, 9, 1, 7, 3};
    std::sort(nums.begin(), nums.end());

    std::cout << "排序结果: ";
    for (int value : nums) {
        std::cout << value << ' ';
    }
    std::cout << std::endl;
    return 0;
}
''';

  static const String pythonHelloWorld = r'''print("Hello, CodePad!")
''';

  static const String pythonFibDemo = r'''def fib(n):
    if n < 2:
        return n
    return fib(n - 1) + fib(n - 2)


if __name__ == "__main__":
    print("前 10 项斐波那契数列:", [fib(i) for i in range(10)])
''';

  /// 高数用得上的示例工程（可以在首页一键加入，不必手打代码）。
  static List<Project> calculusProjects() {
    final DateTime now = DateTime.now();
    return <Project>[
      Project(
        id: 'demo-c-quadrature',
        name: '数值积分：梯形 vs 辛普森',
        language: ProgramLanguage.c,
        files: <SourceFile>[
          const SourceFile(path: 'quadrature.c', content: cQuadratureDemo),
        ],
        createdAt: now,
        updatedAt: now,
      ),
      Project(
        id: 'demo-c-taylor',
        name: '泰勒展开与余项',
        language: ProgramLanguage.c,
        files: <SourceFile>[
          const SourceFile(path: 'taylor.c', content: cTaylorDemo),
        ],
        createdAt: now,
        updatedAt: now,
      ),
    ];
  }

  /// 复合梯形 / 复合辛普森算 ∫₀^π sin x dx，并打印误差随 n 的变化。
  static const String cQuadratureDemo = r'''#include <stdio.h>
#include <math.h>

/* 被积函数 f(x) = sin(x)，积分区间 [0, pi] */
static double f(double x) { return sin(x); }

/* 复合梯形公式 */
static double trapezoid(double a, double b, int n) {
    double h = (b - a) / n;
    double sum = (f(a) + f(b)) / 2.0;
    for (int i = 1; i < n; i++) {
        sum += f(a + i * h);
    }
    return sum * h;
}

/* 复合辛普森公式（n 必须为偶数） */
static double simpson(double a, double b, int n) {
    double h = (b - a) / n;
    double sum = f(a) + f(b);
    for (int i = 1; i < n; i++) {
        sum += (i % 2 == 1 ? 4.0 : 2.0) * f(a + i * h);
    }
    return sum * h / 3.0;
}

int main(void) {
    const double pi = 3.14159265358979323846;
    const double exact = 2.0; /* ∫₀^π sin x dx = 2 */

    printf("%4s %14s %12s %14s %12s\n", "n", "trapezoid", "err", "simpson", "err");
    for (int n = 10; n <= 320; n *= 2) {
        double t = trapezoid(0.0, pi, n);
        double s = simpson(0.0, pi, n);
        printf("%4d %14.8f %12.2e %14.8f %12.2e\n",
               n, t, fabs(t - exact), s, fabs(s - exact));
    }
    return 0;
}
''';

  /// e^x 的麦克劳林展开：实际误差 vs 拉格朗日余项上界。
  static const String cTaylorDemo = r'''#include <stdio.h>
#include <math.h>

/* e^x 的麦克劳林展开：1 + x + x^2/2! + ... + x^n/n! */
static double taylor_exp(double x, int n) {
    double term = 1.0;
    double sum = 1.0;
    for (int k = 1; k <= n; k++) {
        term *= x / k;
        sum += term;
    }
    return sum;
}

static double fact(int n) {
    double r = 1.0;
    for (int i = 2; i <= n; i++) {
        r *= i;
    }
    return r;
}

int main(void) {
    const double x = 1.0;
    const double exact = exp(x);

    printf("e^%.1f = %.10f\n\n", x, exact);
    printf("%3s %18s %12s %12s\n", "n", "taylor", "err", "bound");

    for (int n = 1; n <= 12; n++) {
        double t = taylor_exp(x, n);
        /* 拉格朗日余项：R_n = e^xi * x^(n+1) / (n+1)!，0 < xi < 1，故 e^xi < 3 */
        double bound = 3.0 / fact(n + 1);
        printf("%3d %18.10f %12.3e %12.3e\n", n, t, fabs(t - exact), bound);
    }
    return 0;
}
''';
}
