# Phase 3 交付清单 · C 语言真编译真运行

目标：把「点运行 → 控制台输出」从**模拟**换成**真的编译执行**。

---

## 一、核心难点与最终方案

Android 上跑自带编译器的最大障碍不是「有没有编译器」，而是三条系统限制。下面每一行都是对应方案：

| 限制 | 表现 | Phase 3 的处理 |
|------|------|----------------|
| targetSdk ≥ 29 的应用**不能 `execve` 应用数据目录里的文件** | 把 tcc 解压到 `filesDir` 再执行 → `EACCES` | 编译器放进 `jniLibs/arm64-v8a/libtcc.so`，安装后位于 `nativeLibraryDir`，**该目录可执行**，与 targetSdk 无关 |
| 编译产物同样落在应用数据目录，同样不能执行 | 编译成功也跑不起来 | 用 `tcc -run`：把 C 代码**即时编译到内存**并在 tcc 进程内执行，**不产出可执行文件**，绕开 `execve` |
| Android 不自带 libc 头文件与编译期库 | `#include <stdio.h>` 找不到 | 把 Termux `ndk-sysroot` 的 bionic 头文件打包进 assets，首次启动解压到 `filesDir/toolchain/`，用 `-I` 指给 tcc |

顺带的好处：`tcc <文件> -run` 的 stdin / stdout 就是 tcc 进程自己的，所以 `scanf` 能真的读到输入 —— 控制台因此加了 stdin 输入行。

> 为什么不用 NDK clang 交叉编译？NDK 的 Windows 包只带 `windows-x86_64` 的编译器，**没有能在 arm64 平板本机跑的 clang 可执行文件**，无法直接搬进 APK。Termux 的 clang 包可以，但依赖 llvm / lld / libc++ 合计约 65 MB，且 clang 不能像 tcc 那样「内存编译直接执行」，仍需 `execve` 产物 → 留给 Phase 3.5（用 NDK 交叉编译一个 `dlopen` 加载器来解决执行问题）。

---

## 二、随 APK 分发的工具链

| 内容 | 来源 | 体积 | 落位 |
|------|------|------|------|
| `tcc` 0.9.27-p20230415（aarch64 PIE） | Termux `tcc_1:0.9.27-p20230415-2_aarch64.deb` | 370 KB | `jniLibs/arm64-v8a/libtcc.so` → `nativeLibraryDir` |
| `libtcc1.a` + Android `crt*.o` + tcc 自带内部头 | 同上 `lib/tcc/` | 0.3 MB | `assets/toolchain/tcc/` → `filesDir/toolchain/tcc/` |
| bionic 头文件（含 `stdio.h` / `stdlib.h` / `sys/` / `linux/`，已裁掉 C++ 与 camera/drm/media） | Termux `ndk-sysroot_30_aarch64.deb` | 4.7 MB | `assets/toolchain/include/` → `filesDir/toolchain/include/` |

合计给 APK 增加约 **5.3 MB**（压缩后更小）。授权：tcc 为 LGPL-2.1，bionic 头文件为 Apache-2.0，均为「随包分发需要保留声明」的类型。

首次运行 C 时解压一次（1416 个头文件 + libtcc1.a + crt，共 1435 个文件），之后靠 `filesDir/toolchain/VERSION` 标记跳过。

**可重复构建**：这两步不靠手工记录，`scripts/fetch-toolchain.ps1` 一条命令重抓并组装，自带 ELF 架构校验与文件完整性自检：

```powershell
.\scripts\fetch-toolchain.ps1
# ✔ 工具链就绪
#   libtcc.so       …\jniLibs\arm64-v8a\libtcc.so
#   assets/toolchain 4.9 MB（1416 个头文件）
```

---

## 三、代码改动

新增：

- `android/app/src/main/kotlin/com/codepad/codepad/NativeCompiler.kt`
  MethodChannel `codepad/compiler` 的实现：`probe` / `run` / `writeStdin` / `cancel`；
  资产解压、`ProcessBuilder(tcc, "-B", "-I", "-run", source)`、stdout/stderr 双线程逐行回调 `onOutput`。
- `lib/runtime/native_toolchain.dart`
  `ToolchainGateway` 抽口（便于注入假实现）+ `NativeToolchain`（MethodChannel 实现）+ `ToolchainStatus` / `RunProcessResult`。
- `lib/runtime/native_runtime_engine.dart`
  真实 C 引擎：把工程内所有文件写到缓存目录 `run/<file>/`，调 `tcc -run`，流式回传，映射退出码。
- `lib/runtime/unavailable_runtime_engine.dart`
  缺少运行时时**明确报错**，绝不伪造成功（用于 C++ / Python / 工具链缺失）。
- `test/native_engine_test.dart` 10 个测试：成功、编译错误、启动失败、多文件落盘、stdin、取消、工厂四条分支。

修改：

- `MainActivity.kt`：注册 MethodChannel。
- `android/app/build.gradle.kts`：`packaging { jniLibs { useLegacyPackaging = true } }`（关键，否则不会解压到 nativeLibraryDir）。
- `AndroidManifest.xml`：`android:extractNativeLibs="true"`。
- `lib/runtime/runtime_engine.dart`：`run()` 增加 `projectFiles`、新增 `writeInput()`。
- `lib/runtime/runtime_factory.dart`：`preferNative` / `workRoot` / `toolchain` / `toolchainStatus` 四个注入点。
- `lib/features/editor/editor_controller.dart`：运行传工程内全部文件；新增 `sendInput()`。
- `lib/features/editor/widgets/output_console.dart`：stdin 输入行（`.input` 级别回显为绿色）。
- `lib/data/models/console_message.dart`：`ConsoleLevel.input`。
- `lib/main.dart`：启动时 `probe()` 一次，**探测失败也不崩**，退回模拟/明确报错；准备 `getTemporaryDirectory()/run`。
- `lib/app.dart` / `home_page.dart` / `editor_page.dart` / `settings_page.dart`：把工厂与工具链状态一路传到设置页展示。
- `lib/core/constants/app_constants.dart`：版本 `0.3.0`、`Phase 3 · C 真编译`、控制台高度 190 → 226（容纳输入行）。

---

## 四、本机验证

```
$ flutter analyze
No issues found! (ran in 6.2s)

$ flutter test
00:02 +43: All tests passed!
  原 33 个（模型 / 界面 / 高亮 / 文件仓库 / 文件操作 / 设置持久化 / 文件操作 UI）
+ 新 10 个（真实 C 引擎 6 + 运行引擎工厂 4）
```

**未验证**：真机上的 `execve`、`tcc -run`、`scanf` 行为——本机没有 arm64 设备/模拟器，只能静态保证 + 用清晰的错误信息兜底。这是本次交付最主要的风险点，见下节自检。

---

## 五、装到平板后请按这 5 步自检（0.3.1）

1. **设置 → 编译器**：应显示「本地 C 编译器（内置 tcc）· 已就绪：tcc version 0.9.27 ...」。
   - 若显示「不可用：…」，把冒号后的原因发我（会直接指出是没找到 `libtcc.so`、还是工具链解压失败）。
2. **点「运行编译器自检」**（同一张卡片上）：应 5 项全绿 —— hello / 格式化输出 / **math.h（sqrt、exp）** / 循环 / **多文件编译**。
   这一条同时回答了两个我在本机无法确认的问题：数学库能不能链接、多个 `.c` 能不能一起编译。哪一项红，把它的输出发我。
3. 打开「C 语言入门」→ 运行 `main.c`，控制台应出现：
   ```
   $ tcc main.c util.c -run
   梯形法 n = 1000
   积分值 = 0.33333333
   精确值 = 0.33333333
   误差   = -1.85e-09
   ```
   状态**运行成功**。真实输出与模拟输出的区别：模拟版一定会多打一行「（模拟输出：…）」。
4. **故意写错一行**（例如把 `printf` 改成 `printff`），再运行 → 应是 tcc 的真实报错，并且：
   - 报错行尾部出现「第 N 行」小标签，**点它光标会跳到源码对应行**；
   - 报错下方多一行橙色的中文提示（例如「函数没有先声明：…printf/scanf 需要 <stdio.h>」）。
5. **测 stdin**：切到 `input.c` 运行，在控制台底部 `stdin` 行输入 `21` 回车 → 输出 `21 的平方是 441`；
   再点 `stdin` 右边的 ⏹（结束输入 / EOF）按钮，`while (scanf(...) != EOF)` 这类循环会正常收尾。

---

## 六、已知限制（都是有意的取舍）

1. **C++ 还不能真编译**：tcc 只支持 C。当前 C++ 工程运行会明确提示「计划 Phase 3.5 接入」，不伪造输出。
2. **多文件的规则**：**一个 `.c` 文件 = 一个可运行目标**。只有「不含 `main()`」的 `.c`（如 `util.c`）会作为辅助单元一起编译；
   其它带 `main()` 的文件不参与（切换过去点运行即可单独跑）。所以像示例工程 `main.c / util.c / hello.c / input.c` 这样多个 `main()` 共存是合法的。
   当前文件没有 `main()` 时自动改用工程里唯一的那个作入口；tcc 不做增量编译，文件多了会慢一点。
   若某设备上多文件编译异常，设置里可关闭「多文件编译」退回只编当前文件。
3. **输出是块缓冲的**：程序输出通过管道读取，C 标准库对管道默认按块缓冲，所以 `printf` 不换行/未刷新时才可能延迟到程序结束才出现；加 `fflush(stdout)` 或输出换行即可。
4. **tcc 不优化**：它是「编译快、代码慢」的编译器（无 `-O2` 级别优化），跑算法题没问题，跑大循环会比 gcc 慢。
5. **只有「跳到行」，没有调试器**：编译错误能点击跳到对应行，但没有断点、单步、gdb、变量监视（留到 Phase 5）。
6. **取消是 kill 进程**：`tcc <文件> -run` 的编译与运行在同一进程内，点「停止」会连同编译一起杀掉，无法只停运行。
7. **中文提示是关键字匹配**：17 条常见报错的中文解释靠关键字命中，遇到没收录的报错只会显示原文，不会猜错内容。

---

## 七、下一阶段（Phase 3.5 / Phase 4）

- **Phase 3.5 · C++**：内置 Termux clang（裁剪 llvm，约 30–65 MB）或用 NDK 交叉编译出 arm64 的 `clang`；
  执行侧用 `jniLibs` 放一个自写的 `codeloader`（`dlopen` 编译产物 `.so` + 调用 `main`），这样即使 targetSdk 36 也能跑。
- **Phase 4 · Python**：嵌入式 CPython（交叉编译 arm64 wheel）或 Chaquopy，独立 isolate，stdin/REPL 复用本阶段的控制台输入行。

---

## 八、0.3.1：C 语言打磨（本轮）

0.3.0 让 C「能跑」，0.3.1 让它「好用」。四件事：

| 改动 | 解决的问题 | 落点 |
|------|-----------|------|
| **编译错误可点击跳行** | 平板上看报错要手动翻几百行找位置 | `runtime/compile_diagnostic.dart` 解析 `file:line: error:`；控制台每行带「第 N 行」标签，点击切标签页并把光标放到该行 |
| **常见报错中文注解** | `stray '\357'`、`implicit declaration` 这类信息学生看不懂 | 17 条关键字规则 → 橙色提示行；另加运行前全角标点体检（中文输入法最容易踩的坑） |
| **多 .c 文件一起编译** | 原来只编当前文件，`util.c` 里的函数用不了 | 入口 + 其余不含 `main()` 的 `.c` 一并交给 `tcc -run`；多 `main` 提前提示；每次运行前清空工作目录 |
| **结束输入（EOF）** | `while (scanf(...) != EOF)` 会一直卡住 | 控制台新增 ⏹ 按钮 → 原生 `stdin.close()` |

额外加了**一键编译器自检**（设置 → 编译器）：跑 5 个小程序（hello / 格式化 / math.h / 循环 / 多文件），逐项显示真实输出。
这不是装饰——`math.h` 能不能链接、多文件能不能编，我在 Windows 上无法验证，只能让它在真机上自己回答。

新增/修改文件：

```
新增 lib/runtime/compile_diagnostic.dart   诊断模型 + 解析 + 17 条中文提示 + 全角标点体检
新增 lib/runtime/toolchain_self_check.dart  5 项自检（可注入网关，纯 Dart 可测）
新增 lib/core/text/line_offsets.dart       行号 ↔ 字符偏移
新增 test/diagnostic_test.dart             14 个：解析 / 提示 / 体检 / 行偏移
新增 test/editor_jump_test.dart            4 个：跳转、basename 兜底、缺失文件、无位置
新增 test/self_check_test.dart             4 个：全通过 / 单项失败 / 启动失败 / 覆盖旧文件
改  lib/runtime/native_runtime_engine.dart 多文件选择、目录清理、路径缩短
改  lib/runtime/native_toolchain.dart      sources 列表 + closeStdin
改  lib/features/editor/editor_controller.dart  诊断分流、jumpToDiagnostic、endInput、运行前体检
改  lib/features/editor/widgets/output_console.dart  可点击诊断行、EOF 按钮、hint 配色
改  android/…/NativeCompiler.kt            sources 列表、closeStdin
改  lib/features/templates/template_catalog.dart  C 示例改成多文件（main.c + util.h + util.c）
```

验证：

```
$ flutter analyze
No issues found! (ran in 5.2s)

$ flutter test
00:03 +68: All tests passed!
  43 个（0.3.0 已有）+ 25 个（诊断 14 · 跳转 4 · 自检 4 · 多文件 3）
```

---

## 九、0.3.2：修掉 0.3.1 的「什么都跑不起来」

### 现象与根因

0.3.1 装到平板后，工程里**任何文件点运行都失败**。

根因是我 0.3.1 同时改了两处，二者组合成了死局：

1. 示例工程从 3 个文件扩成 5 个：`main.c` / `util.h` / `util.c` / `hello.c` / `input.c`——后两个各自也有 `main()`；
2. 多文件规则写成了「其它 `.c` 全部参与编译」，只排除了 `.h`。

于是运行 `main.c` 时命令变成 `tcc main.c util.c -run hello.c input.c`，链接期立刻
`duplicate symbol 'main'`。工程里每个文件都带进别人的 `main()`，所以谁都跑不起来。
（0.3.0 只编当前文件，所以同样的工程是好的——这是纯粹的回归。）

### 修复

| 改动 | 落点 |
|------|------|
| **一个 `.c` = 一个目标**：只有不含 `main()` 的 `.c` 作为辅助单元参与编译，其它带 `main()` 的不参与，并在控制台列出「哪些文件因此没参与、切过去可单独运行」 | `native_runtime_engine.dart` `_selectUnits()` |
| **自动兜底**：多文件编译若报「编译器诊断」（`file:line: error:` / `tcc: error:`），自动退回只编入口文件重试一次，并说明「改为只编译 X 重试」；程序自身运行失败（无编译器诊断）不会重跑 | `run()` |
| **可关闭的开关**：设置 → 编译器 → 「多文件编译」（默认开，持久化）。关掉即 0.3.0 的语义，最保险 | `settings_controller.dart` / `settings_page.dart` / `runtime_factory.dart` |
| **控制台一键复制**：控制台标题栏新增复制按钮，失败时点一下就能把整段输出发出来 | `output_console.dart` |

回归测试（`test/native_engine_test.dart`，共 15 个）：

```
✓ 其它含 main() 的文件不参与编译，并给出提示   ← 直接盯住这次的 bug
✓ 多文件编译失败时自动退回单文件重试一次
✓ 程序自身运行失败（没有编译器诊断）不会触发重试
✓ 关闭多文件编译后只编当前文件
✓ 多文件开关由设置实时提供
```

```
$ flutter analyze
No issues found! (ran in 5.3s)

$ flutter test
00:03 +72: All tests passed!
```

---

## 十、0.3.3：bionic 头文件被裁过头（真正的「跑不了」）

### 现象

0.3.2 装上后命令、多文件规则都对了，但每个 C 程序都停在同一处：

```
In file included from main.c:1:
In file included from …/files/toolchain/include/stdio.h:41:
…/files/toolchain/include/sys/cdefs.h:360: error: include file 'android/versioning.h' not found
```

### 根因：打包脚本裁掉了 `include/android/`

`fetch-toolchain.ps1` 第 3 步当年为了压体积，把 `c++`、**`android`**、`camera`、`drm`、`media` 五个目录一起删了。
但 bionic 的头文件是**互相引用**的：

| 被保留的头文件 | 会 include |
|---|---|
| `sys/cdefs.h`（每个头文件都引它） | `<android/versioning.h>`、`<android/api-level.h>`、`<android/ndk-version.h>` |
| `termios.h` / `unistd.h` / `threads.h` | `<android/legacy_termios_inlines.h>` 等 |
| `AMidi.h` | `<media/NdkMediaError.h>` |
| `kfd_ioctl.h` | `<drm/drm.h>` |

所以 `#include <stdio.h>` 必然失败 —— 与用户代码无关，**任何 C 程序都编不过**。
（0.3.0 的 APK 用的是同一套头文件，理论上也是坏的，只是那时还没被测出来。）

### 修复（五处）

| # | 改动 | 说明 |
|---|------|------|
| 1 | **只裁 `c++` 与 `camera`** | `android` / `media` / `drm` 全部保留。`assets/toolchain` 4.9 MB → 6.6 MB（1527 个头文件） |
| 2 | **脚本加一致性检查** | 扫所有保留头文件里的 `#include <dir/…>`，凡是被引用却不存在的目录就 **直接失败**（`asm`/`cutils`/`log` 是 Termux sysroot 本身没有的，列在白名单）。这类 bug 以后不会再悄悄溜进 APK |
| 3 | **补上两个必需宏** | `sys/cdefs.h` 在 `__has_include(<android/ndk-version.h>)` 为真时会 `#error "Unversioned target triples are not supported"`，而 `versioning.h` 用到 `__ANDROID_MIN_SDK_VERSION__`。tcc 不是 clang 驱动、不会自动注入，所以命令行显式加 `-D__ANDROID_MIN_SDK_VERSION__=24 -D__ANDROID_API__=24`（与 minSdk 一致） |
| 4 | **升级 `TOOLCHAIN_VERSION`** | 手机上 `filesDir/toolchain` 是解压缓存，标记不变就不会重新解压。改成 `…-android-2`，老用户首次运行会自动重新解压出新头文件 |
| 5 | 顺手修两个体验问题 | ① 全角标点检查改成「先涂空注释与字符串再扫」，块注释里的中文标点不再误报（日志里那 3 条 ⚠ 就是假的）；② 多文件失败只在「符号未定义 / 重复定义」这类真与文件数量相关的错误上才重试，缺头文件不再打两遍 |

新增测试（共 77 个）：

```
✓ 跨行块注释里的中文标点也不会误报        ← 对应日志里的假警告
✓ 注释之外的代码里仍然会抓到全角标点
✓ char 字面量与转义不会让扫描错位
✓ 涂空注释后行号保持不变
✓ 缺头文件的错误不会触发单文件重试        ← 对应日志里的重复报错
✓ 其它含 main() 的文件不参与编译（0.3.2）
```

验证：

```
$ flutter analyze
No issues found! (ran in 4.9s)

$ flutter test
00:03 +77: All tests passed!
```

### 装 0.3.3 后先做这一步

**设置 → 编译器 → 「运行编译器自检」**。之前它必然 5 项全红（同一个缺头文件错误），现在应该是 5 项全绿；
如果还有红项，把那一项的输出发我，那是「真机才有的问题」，我按输出继续修。

---

## 十一、0.3.4：`_Nonnull` —— bionic 头文件是给 clang 写的

### 现象

0.3.3 补回 `include/android/` 后，自检仍然全红。原因不难推断：**补回版本标注只是第一道关卡**。
Termux 的 ndk-sysroot 打的是 NDK r30 的 bionic 头文件，整套头文件是为 clang 写的：

| clang 专有词汇 | 出现规模 | tcc 的反应 |
|---|---|---|
| `_Nonnull` / `_Nullable` 类型限定符 | **2104 处 / 136 个文件** | 不认识，声明直接语法错 |
| `__RENAME(x)` = `__asm__(#x)` 汇编符号别名 | cdefs.h + 多个头文件 | aarch64 上不支持 asm 标签 |
| `__attribute__((__availability__(android,strict,introduced=30)))` | versioning.h 的宏 | 属性不认识 |
| `__has_include(<…>)` | 6 处 | 可能直接语法错 |
| `__pass_object_size` / `__builtin_available` / `__overloadable` | fortify 与重载区 | 不支持 |

也就是说：只要 `#include <stdio.h>`，tcc 必然在某个 clang 词汇上翻车 —— 换哪个字符都只是把错误往后挪一行。

### 做法：一层「tcc 兼容垫片」

bionic 的每个头文件第一句几乎都是 `#include <sys/cdefs.h>`。所以只要**用自己的 `sys/cdefs.h` 顶掉它**，
把上面这些词汇全部定义成「无副作用」形式，其余 1500 多个真实声明（`printf`、`malloc`…）保持原样：

```
android/compat-headers/
  sys/cdefs.h   ← 顶掉 bionic 的那份：
                  _Nonnull/_Nullable → 空
                  __RENAME → 空     __INTRODUCED_IN/__availability__ → 空
                  __has_include → 0  __BIONIC_FORTIFY → 0
                  __BIONIC_CAST / __bos / __printflike … 全套词汇补齐
                  BIONIC_IOCTL_NO_SIGNEDNESS_OVERLOAD → 1（关掉 clang 的重载技巧）
  limits.h      ← bionic 的 limits.h 靠 `#include_next` 找编译器的 limits.h 才能拿到
                  INT_MAX；tcc 没有那份，所以给一份自足的（aarch64 LP64）
```

命令行里把 `-I<toolchain>/compat` 排在**第一位**，`-Iinclude` 之后：

```
tcc -B…/tcc -I…/compat -I…/include -I…/include/aarch64-linux-android -run main.c
```

### 这次终于能离线验证了

之前每一轮都只能「改完打包、等真机结果」。这次找到办法：**用 NDK 自带的 clang 做纯头文件语法检查**，
把搜索路径限制成和 tcc 完全一样的四个目录，就能在开发机上验证垫片本身对不对：

```powershell
$clang = '…\ndk\28.2.13676358\toolchains\llvm\prebuilt\windows-x86_64\bin\clang.exe'
& $clang --target=aarch64-linux-android24 -nostdinc -fsyntax-only -w `
  "-I$assets\compat" "-I$assets\include" "-I$assets\include\aarch64-linux-android" "-I$assets\tcc\include" `
  many.c
```

这一跑立刻抓出垫片里两个真错误（`__always_inline` 展开成双重 `inline`、`__BIONIC_CAST` 参数个数写成 2 个），
接着又抓出 `__strftimelike` 参数个数、`ioctl` 声明冲突、`INT_MAX` 缺失。修完后：

```
24 个头文件的宽集测试（stdio/stdlib/string/math/ctype/time/stdint/limits/
sys-stat/sys-time/unistd/wchar/…）        → 0 error
学生风格样例（scanf + qsort + struct + malloc + snprintf + sqrt） → 0 error
```

### 自检里新增两项「给自己看」的信息

1. **`shim` 探针**（第 1 项）：编译一段 `#ifdef CODEPAD_COMPAT_SYS_CDEFS_H` 的代码，输出 `shim=on`。
   它直接回答「垫片到底有没有被用上」——如果不是 `on`，说明 `-I` 顺序或解压缓存有问题。
2. **自检报告带完整命令行**：每一项的输出里现在第一行就是 `> tcc -B… -I… -run …` 原件，
   失败时这一行就是诊断的关键；弹窗右上角还有「复制全部」一键拷走整份报告。

```
$ flutter analyze
No issues found! (ran in 4.6s)

$ flutter test
00:03 +77: All tests passed!
```

---

## 十二、0.3.5：把 tcc 真身请到开发机上 —— 又抓出四个真 bug

0.3.4 的自检如果还是红的，本来只能继续靠你来回传日志。这次换了办法：
**下载 Windows 版 tcc 0.9.27**（和 Termux 的 aarch64 版同版本、同源码），
在开发机上直接跑「App 会发给它的那条命令」。第一次跑就暴露出下面四个问题，
**每一个都会让真机上的 C 编译失败**，而且前两个是 0.3.0 以来一直存在的。

### bug 1（最致命）：`-run` 的位置错了 → 多文件从来没编进去过

tcc 的规则是：**`-run` 之后的一切都当作被运行程序的参数**。所以

```
tcc -run main.c util.c      ← 错：util.c 只是变成 argv[1]，根本没参与编译
tcc main.c util.c -run      ← 对
```

之前的写法是前者。于是「运行示例工程」时 `main.c` 里的 `f()`（定义在 `util.c`）永远是
`undefined symbol 'f'`——多文件编译这个功能从头到尾没真正工作过。
改成「源文件在前、`-run` 在后」后，示例工程立刻输出正确结果：

```
梯形法 n = 1000
积分值 = 0.33333350
精确值 = 0.33333333
误差   = 1.67e-007
```

### bug 2：tcc 的 `#pragma once` 对 `<...>` 完全不生效

实测（同一份头文件，include 两次）：

| 写法 | 结果 |
|---|---|
| `#include "x.h"` ×2 | ✅ 第二次被跳过 |
| `#include <x.h>` ×2 | ❌ 重新解析一遍 → `incompatible redefinition of 'X'` |

bionic 的头文件**清一色用尖括号**，等于在 tcc 下整套头文件都没有去重。
只要某个头文件在一条 include 链上被走到两次就炸，而这类链非常多：
`<signal.h>`（`signal.h ↔ sys/ucontext.h`、`sys/types.h ↔ bits/pthread_types.h`）、
`<pthread.h>`、`<threads.h>`、`<wchar.h>`…

修法：打包脚本给**每个**头文件套一层传统 include guard（1527 个，按字节改，不碰编码）：

```
#ifndef CODEPAD_GUARD_SYS_TYPES_H
#define CODEPAD_GUARD_SYS_TYPES_H 1
…原内容…
#endif /* CODEPAD_GUARD_SYS_TYPES_H */
```

之后 `<signal.h>`、`<pthread.h>`、`<threads.h>`、`<wchar.h>` 全部通过。

### bug 3：tcc 自带的 `stddef.h` 和 bionic 的 `stdint.h` 抢着定义 `intptr_t`

```
tcc/include/stddef.h:  typedef __PTRDIFF_TYPE__ intptr_t;   ← 按标准这不该在这里
bionic/stdint.h:       typedef __intptr_t intptr_t;
```

bionic 的头文件是照 clang 的 `stddef.h`（不含 `intptr_t`）写的，所以垫片补了一份同形的
`compat/stddef.h`（只放 `size_t` / `ptrdiff_t` / `wchar_t` / `max_align_t` / `offsetof` / `NULL`）。

### bug 4：bionic 的 `limits.h` 拿不到 `INT_MAX`

bionic 的 `limits.h` 第一句就是 `#if __has_include_next(<limits.h>)` —— 它指望**编译器自带**那份
limits.h 提供 `INT_MAX` 等标准宏，自己只补 POSIX 部分。tcc 没有那份，所以 `<limits.h>` 里
`INT_MAX` 根本不存在。垫片给一份自足的 `compat/limits.h`（aarch64 = LP64）。

### 顺手修的：C23 枚举与 128 位整数

| 问题 | 位置 | 处理 |
|---|---|---|
| `enum : size_t { … }`（C23 带底层类型的枚举） | `bits/bionic_multibyte_result.h` | 垫片改成等价的 3 个宏，否则 `<wchar.h>`/`<uchar.h>` 编不过 |
| `__uint128_t` 作为 16 字节字段类型 | `asm/sigcontext.h`、`asm/ptrace.h` | 垫片给一个 16 字节结构体顶上，布局一致，`<signal.h>` 因此能过 |
| `ioctl` 的「有符号/无符号重载」 | `bits/ioctl.h` | 定义 `BIONIC_IOCTL_NO_SIGNEDNESS_OVERLOAD` 关掉 clang 的重载技巧 |

### 明确不支持（会给出清楚的报错，不会假装成功）

| 头文件 | 原因 |
|---|---|
| `<stdatomic.h>` | tcc 没有 `_Atomic` 类型说明符，也没有 `__ATOMIC_*`；C11 原子操作在 tcc 下无解 |
| `<uchar.h>` | 依赖编译器的 `__CHAR16_TYPE__` / `__CHAR32_TYPE__`，tcc 未提供 |
| `linux/*.h` 等内核头 | `typedef unsigned __int128 __u128;` 是关键字用法，补不了 |

### 验收脚本：`scripts/acceptance-test.ps1`

把「App 会发给 tcc 的那条命令」原样跑一遍，6 项全绿才算完：

```
1) 单文件 hello                    [PASS] Hello, CodePad!
2) 多文件 main.c + util.c          [PASS] integral=0.33333350
3) 标准输入 scanf 21 → 441         [PASS] square 441
4) math.h + 浮点格式化              [PASS] sqrt2=1.41421 / 42 3.14 abc
5) 常用头文件全家桶（30 个）        [PASS] qsort/struct/malloc/stat/localtime 全可用
6) 编译错误格式（点击跳行依赖它）    [PASS] bad.c:4: error: identifier expected
全部通过（6/6）
```

两条已知平台差异（都只会让真机更宽松）：

1. Windows 版 tcc 没定义 `__builtin_va_list`（aarch64 版在 `tccdefs.h` 里定义了），
   所以脚本多传 `-D__builtin_va_list=char*`；真机不需要。
2. Windows CRT 不导出 `stdout` 这个数据符号（bionic 有），所以脚本里用 `fflush(NULL)` 替代。

**仍然只能在真机上确认的**：arm64 上的 `execve` 限制、tcc 的 aarch64 后端、
`math.h` 在 bionic 里的符号解析。这三项各自都有兜底报错，不会静默输出假结果。

```
$ flutter analyze
No issues found! (ran in 4.3s)

$ flutter test
00:03 +77: All tests passed!

$ scripts\acceptance-test.ps1
全部通过（6/6）
```

---

## 十三、0.3.6：真机日志终于说话了 —— 是「我把 tcc 已经提供的类型又定义了一遍」

0.3.5 装到真机上，自检 6 项仍然全红，但这次日志给到两个精确行号：

```
compat/sys/cdefs.h:145: warning: BIONIC_IOCTL_NO_SIGNEDNESS_OVERLOAD redefined
compat/sys/cdefs.h:155: error: too many basic types
```

（顺便说：这两行能直接定位，全靠 0.3.5 加的两件事 —— 自检报告里带**完整命令行**、每一项带**原始报错原文**。）

### 145 行：Termux 的 tcc 已经替我重载 ioctl 了

打开 `assets/toolchain/tcc/include/tccdefs.h`（tcc 的预置头，每次编译自动先处理），第 134 行起：

```c
#elif defined __ANDROID__
    #define  BIONIC_IOCTL_NO_SIGNEDNESS_OVERLOAD
    #define  __PRETTY_FUNCTION__ __FUNCTION__
    #define __has_builtin(x) 0
    #define __has_feature(x) 0
    #define _Nonnull
    #define _Nullable
    #define _Null_unspecified
```

**Termux 的 aarch64 tcc 早就替 Android 打好了补丁**，我垫片里又定义成 `1`（预置头是空值），
于是 `redefined`。顺带一个反推：`_Nonnull` / `_Nullable` / `_Null_unspecified` 也是预置头提供的，
且取值与我相同，所以没有告警 —— 0.3.4 里我「发现 `_Nonnull` 2104 处」的判断方向是对的，
但真机上它其实已经被 tcc 自己解决了，真正要垫的是 `__RENAME`、`__availability__`、`__has_include` 这一类。

### 155 行：`__uint128_t` 在 aarch64 tcc 里是**基本类型**

```c
typedef struct { unsigned long long __h[2]; } __uint128_t;   ← 我写的
```

`__uint128_t` 已经是 tcc 的 32/128 位基本类型关键字，所以在「声明名字」的位置上放了第二个类型 →
`too many basic types`。这一条只影响真机（aarch64 支持 `__int128`），Windows 版 tcc 没有这个类型，
所以开发机上的验收反而是全绿的 —— 这也解释了为什么本地 6/6 通过、真机却挂。

### 修法：垫片全面改成「先判存在」

| 宏 / 类型 | 处理 |
|---|---|
| `BIONIC_IOCTL_NO_SIGNEDNESS_OVERLOAD` | `#ifndef` 保护，且保持**空值**（与预置头一致） |
| `_Nonnull` / `_Nullable` / `_Null_unspecified` / `_Nullable_result` | `#ifndef` 保护 |
| `__RENAME(x)` | `#ifndef` 保护（有的 tcc 把它定义成 `__asm__("_"X)`） |
| `__uint128_t` / `__int128_t` | **只在非 `__ANDROID__` 目标上补**，真机直接用 tcc 的基本类型 |

### 怎么在开发机上验证这一条

Windows 版 tcc 加 `-D__ANDROID__`，就走进了和真机**同一条**预置分支（`_Nonnull`、ioctl 重载那些都由预置头提供）：

```
$ tcc shim.c -run -D__ANDROID__ -I…/compat -I…/include -I…/include/aarch64-linux-android
shim=on                      ← 0.3.5 是真机上报错的那段，现在通过且没有告警
$ tcc multi_a.c multi_b.c -run （同上参数）
add=7
```

真机上现在应该是 6 项全绿；第 1 项 `shim=on` 就是这段探针。

```
$ flutter analyze        → No issues found!
$ flutter test           → 00:03 +77: All tests passed!
$ scripts\acceptance-test.ps1 → 全部通过（7 个用例 / 8 项断言）
```

---

## 十四、0.3.7：`include file 'stdarg.h' not found` —— 编译器自带头找不到自己家

0.3.6 上真机，六个探针的报错全部换成同一句：

```
In file included from shim.c:1:
…/include/stdio.h:46: error: include file 'stdarg.h' not found
```

这是好消息：**垫片已经过关**（145/155 行那两个错误没了），错误推进到了下一环。

### 根因：tcc 只在「自己所在目录」旁边找 include/

`stdarg.h`、`varargs.h`、`stdalign.h`、`stdnoreturn.h`、`float.h` 这些是**编译器自带头**，
bionic 当然不提供（它指望编译器给）。tcc 找它们的规则是：

```
<编译器所在目录>/include/*.h
```

真机上编译器是 **APK 里的 `/data/app/…/lib/arm64/libtcc.so`** —— 那个目录里只有 `.so`，
没有 `include/`，所以 `stdio.h` 里那句 `#include <stdarg.h>` 必然失败。
而 `-B<toolchain>/tcc` 只管 **lib/**（`libtcc1.a`、`crt/*`），**不影响 include 搜索路径**。

### 为什么本地验收看不到

开发机上的 tcc 是 `…\tcc-win\tcc\tcc.exe`，**它旁边正好就有一份 `include/`**（tcc 发行包自带的），
所以同样的命令在本地永远能找到 `stdarg.h`。这类「靠自身路径推断资源」的 bug 在本机天然隐身。

### 修法：把编译器自带头目录显式写进命令行

```
tcc -B…/tcc -I…/compat -I…/include -I…/include/aarch64-linux-android -I…/tcc/include main.c -run
                └ 垫片      └ bionic   └ bionic aarch64                     └ 补缺：编译器自带头
```

顺序很关键：`compat` 仍然第一（保证 `stddef.h` 用我们那份），`tcc/include` 放最后**只补缺**
（`stdarg.h`、`float.h` 等 bionic 没有的）。副作用是 `<stdatomic.h>` 现在会落到 tcc 自带那份上，
不再直接报错。

### 验收脚本新增第 7 个用例（这条 bug 的回归测试）

把编译器整体搬进一个**没有 `include/` 的目录**（复刻 `lib/arm64/libtcc.so` 的处境），跑两遍：

```
7) 隔离编译器：模拟真机 libtcc.so 旁边没有 include/
  [PASS] 不传 -I<tcc>/include 时复现真机报错（用例有效）
         → include file 'stdarg.h' not found
  [PASS] 传了 -I<tcc>/include 后正常编译运行
         → Hello, CodePad!
```

第一项是**反证**：如果哪天有人把这行 `-I` 删了，用例会先复现真机报错，第二条立刻红 ——
这类「本地看不见」的问题以后不会再悄悄回来。

---

## 十五、0.3.8：真正的老问题 —— 报告没有「身份」

### 先承认一件事

0.3.7 装完后收到的报告，和 0.3.6 的**逐字相同**：命令里没有 `-I…/tcc/include`，
连 `lib/arm64` 的安装哈希都一样。也就是说那份报告**根本不可能来自 0.3.7 的代码**。

而那几轮里，我一直在用同一句「6 项全红 + 同一段命令行」在判断不同版本的运行结果 ——
**报告里没有任何东西能告诉我它是哪个构建、手机上的工具链解压成了什么形状**。
这才是「那么多次都这样」背后真正的系统性原因：不是某个头文件，而是**观测手段本身没有身份**。

### 三条修复

| # | 修法 | 作用 |
|---|------|------|
| 1 | 自检报告首行加 **`CodePad 0.3.8 · 工具链 tcc-…-android-6`** | 一眼分清「老 APK」还是「新 APK」 |
| 2 | 报告加 **环境摘要**：编译器路径、工具链目录，以及 6 个关键文件的 ✓/✗（`compat/sys/cdefs.h`、`include/stdio.h`、`include/aarch64-linux-android`、`tcc/include/stdarg.h`、`tcc/include/float.h`、`tcc/libtcc1.a`） | 直接暴露「解压不全 / 目录缺失」 |
| 3 | `ensureToolchain()` 的缓存校验从 3 项扩到 6 项，并把 `TOOLCHAIN_VERSION` 提到 `android-6` | 手机上强制重新解压一遍，历史残留一律清掉 |

### 构建自证：以后不再靠猜

打包后用字符串核对，确认「我改的代码确实进了这个 APK」：

```
$ classes.dex        含 toolchainVersion ✓  tcc/include/stdarg.h ✓  tcc/include/float.h ✓
$ lib/arm64/libapp.so 含 0.3.8 ✓   含 0.3.7 ✗（旧版本串已不在）
```

这一层核对是 0.3.8 起的新规矩：**每次交付前先证明「源码 → APK」这一步没断**，
再谈真机行为。0.3.7 那次如果早做这一步，就会立刻发现手机上跑的不是新包。

### 下次报告的样子（首行就是结论）

```
CodePad 编译器自检（x/6 通过）
CodePad 0.3.8 · 工具链 tcc-0.9.27-p20230415-android-6
编译器 /data/app/…/lib/arm64/libtcc.so
目录   /data/user/0/com.codepad.codepad/files/toolchain
✓ compat/sys/cdefs.h   ✓ include/stdio.h   ✓ include/aarch64-linux-android
✓ tcc/include/stdarg.h   ✓ tcc/include/float.h   ✓ tcc/libtcc1.a
[OK  ] / [FAIL] …
```

---

## 十六、0.3.9：`libtcc1.a not found` —— `-B` 根本不是库搜索路径

### 现象

0.3.8 的报告证明了三件事：版本对了、6 个关键文件全 ✓、`stdarg.h` 那一环过了。
剩下唯一一句错误，六个探针一模一样：

```
tcc: error: libtcc1.a not found        退出码 255
```

`libtcc1.a` 明明就在 `files/toolchain/tcc/libtcc1.a`，而命令行里也给了 `-B<toolchain>/tcc`。

### 根因：`-B` 与 `-L` 是两回事

| 参数 | 作用 | 管不管 libtcc1.a |
|---|---|---|
| `-Bdir` | 设置 tcc 的**私有目录**（默认的 crt / 头文件位置） | **不管** |
| `-Ldir` | 往**库搜索路径**里加一个目录 | **管，就是它** |

tcc 的 `libtcc1.a` 是作为「运行库」在**库搜索路径**里查的；`-B` 只影响它自己的私有目录。
所以「文件存在 + 给了 `-B`」仍然会报 not found —— 报错信息本身没说错，只是我一厢情愿地把它当成了路径问题。

### 开发机上怎么复现的（这次把两个目录都藏起来）

把 tcc.exe 复制到一个干净目录，并把它的 `include/`、`lib/` 分别改名（模拟真机 `lib/arm64/libtcc.so` 旁边什么都没有）：

```
A) 只给 -B      → tcc: error: library 'libtcc1-64.a' not found
                  tcc: error: undefined symbol '_runmain'          ← 与真机同一环（措辞是 Termux 版差异）
B) 再补 -L      → Hello, CodePad!
                  integral=0.33333350（多文件也通过）
```

顺带解释了一直以来的「本地全绿」：开发机上的 tcc.exe **旁边自带 `lib\`**，默认搜索路径就命中，
`-B` / `-L` 都不需要 —— 于是这条 bug 在本地永远隐身。

### 修法

```
tcc -B…/tcc -L…/tcc -I…/compat -I…/include -I…/include/aarch64-linux-android -I…/tcc/include  main.c -run
             └ 库搜索路径（0.3.9 新增，libtcc1.a 靠它）
```

同时给自检报告加了一行 **构建标记**（`构建 0.3.9-bL-iL`），命令行形状再有变化时会跟着变，
一眼就能确认手机上跑的是哪一套参数。

### 验收脚本第 7 个用例改成「两个目录都没有」

```
7) 隔离编译器：模拟真机 libtcc.so 旁边既没有 include/ 也没有 lib/
  [PASS] 只给 -B 时复现真机 libtcc1.a 报错（用例有效）
  [PASS] 补上 -L 后正常编译运行
全部通过（7 个用例 / 8 项断言，含 2 条反证）
```

### 真机结果（2026-11-11）

华为平板上 **6/6 全绿**：

| 探针 | 输出 | 说明 |
|---|---|---|
| shim | `shim=on` | 兼容垫片确实生效 |
| hello | `OK-HELLO` | bionic `stdio.h` 可用 |
| format | `42 3.14 abc` | 格式化输出正常 |
| math | `sqrt2=1.41421` | `math.h` 符号在运行时解析成功 |
| loop | `sum=5050` | 代码生成与执行正常 |
| multi | `add=7` | 多文件（`-run` 在源文件之后）正常 |

至此 C 语言在平板上「写 → 编译 → 运行 → 看输出」的完整链路打通。
真机上踩过的五处坑（按发现顺序）：`-run` 位置 → `#pragma once` 失效 → compat 垫片重复定义
→ 编译器自带头路径 → `libtcc1.a` 的库搜索路径（`-L`）。
---

## 十七、0.6.0：运行窗口 —— 参考别人的做法，再决定我们的形态

### 别人是怎么做的（三类）

| 类型 | 代表 | 形态 | 优点 / 代价 |
|---|---|---|---|
| 在线编译器 | [JDoodle 移动端](https://www.jdoodle.com/docs/mobile-app/introduction-to-jdoodle-mobile-app/)、OnlineGDB、Replit | 底部**结果面板**，输出/输入分区，Run / Stop 并列 | 输入区独立、状态清楚；面板高度通常固定 |
| 桌面 IDE | VS Code、CLion、[AndroidIDE](https://docs.androidide.com/user/editor/index.html) | 可拖拽分隔的终端面板 | 高度自由，但需要空格子 |
| 纯移动端 | 各类手机 C 编译器 | 全屏结果页 | 输出好看，但每次都要退出再回来改代码 |

### 移动端的特殊约束

平板横屏时软键盘仍会吃掉约 40% 高度。固定分割的面板会让「代码 + 输出」同时挤压成几行，
所以这里选**可拖拽的底部弹层**：不跑程序时它不存在（编辑器占满），跑起来从底部拉起，
可以拖到接近全屏看长输出，收起就回到代码。

### 实现（`RunSheet`）

- **先弹窗、再运行**：点「运行」立刻出现面板，编译进度与程序输出**流式**进入，
  不会出现「点了没反应」的空档；
- 高度 `DraggableScrollableSheet`：初始 55%，可拖 28%–95%；
- 头部：状态（运行中转圈 / 成功绿 / 失败红 / 已停止橙）+ 文件名 + 停止 / 复制 / 清空 / 收起；
- 底部：`stdin` 一行，运行中即可输入回车送达，另有 EOF 按钮；
- **点编译错误那一行 → 关掉面板并跳到源码对应行**（复用原有诊断跳转）。

### 顺手做的一次去重

把输出渲染（`ConsoleOutputView`）和标准输入行（`ConsoleInputRow`）从原控制台里抽出来，
内嵌控制台与弹层共用一份实现 —— 否则「面板里能自动滚动、控制台里不能」这类走样迟早出现。

测试：新增 5 个（输出区空态/逐行/诊断跳行、输入行进制/禁用），合计 **97 个**。
---

## 十八、0.7.0：查找 / 替换

### 为什么先做这个

写超过 100 行的程序时，「找一个变量在哪出现」「把 `int` 全换成 `long`」是最高频的操作。
没有它，平板上就只能靠肉眼翻页 —— 这比缺语法高亮更影响效率。

### 形态

工具栏多一个 🔍（`search_off` 图标表示已打开），点开后在标签栏下方出现两条：

```
🔍 int                          1/2   Aa  ↑  ↓  ⇄  ✕
   long                                 替换   全部替换
```

- `Aa`：区分大小写（**默认开**——写代码时 `Printf` 和 `printf` 不是一回事）
- `↑ ↓`：上一处 / 下一处，到头**绕回**
- 计数：`1/2` 表示共 2 处、回车会到第 1 处；没命中显示「无匹配」
- `⇄`：展开/收起替换行；「替换」只动当前一处，「全部替换」按计数报告结果

### 两个容易写错的地方（都在纯函数里守住）

1. **匹配不重叠**：`aa` 在 `aaaa` 里是 2 处，不是 3 处。
2. **替换结果不参与再匹配**：把 `a` 全换成 `aa` 只会得到 `aa`，不会无限膨胀。
   如果直接在 `while` 里反复 `replaceAll`，这一条就会炸成死循环。

查找逻辑放在 `lib/core/text/text_search.dart`（`findMatches` / `stepIndex` / `replaceAllMatches`），
界面只负责显示计数和搬运选区 —— 这样「大小写、绕回、替换」都能用单元测试钉死。

测试：新增 12 个（匹配 4 + 跳转 3 + 替换 4 + 界面 1），合计 **109 个**。
---

## 十九、0.8.0：视觉统一（把散装颜色收成一套设计系统）

### 先解决根问题：界面不该直接写十六进制

0.7.0 之前，各个组件拿的都是 `Theme.of(context).colorScheme` 里 Material 生成的色，
再各自叠 `withValues(alpha: 0.03)` 之类的半透明 —— 结果是：深色模式下某些面板发灰、
某些发蓝，控制台和编辑器底色对不上。这类问题逐个调是不可能收敛的。

所以先立一层**语义色板** `AppPalette`：

| 名字 | 用途 |
|---|---|
| `scaffold` / `panel` / `panelAlt` | 页面底 / 卡片 / 工具栏与标签栏 |
| `border` / `borderStrong` | 分割线 / 控件描边 |
| `text` / `textMuted` | 主文字 / 次要文字 |
| `accent` / `accentSoft` | 主色 / 主色淡底 |
| `success` / `warning` / `danger` | 运行状态、提示、错误 |
| `gutter` / `code` | 行号栏 / 代码纸面 |

深浅两套各一份，所有组件只认这些名字。同时统一了圆角（卡片 14 / 面板 16 / 控件 10 / 小标签 8）。

### 组件级打磨

| 组件 | 改动 |
|---|---|
| 主题 | 覆盖 AppBar / Card / Dialog / BottomSheet / 按钮 / 输入框 / SnackBar / Tooltip / PopupMenu / Switch / Slider / Scrollbar 的默认观感；字号与层级统一进 `TextTheme` |
| 首页 | 标题旁加渐变品牌块；「我的工程 · N」分区行；工程卡片左侧加语言色条 + 图标徽标 + 「N 个文件 / 更新时间」元信息行 |
| 编辑器工具栏 | 主操作（运行/保存）与辅助操作（查找/控制台）用竖线分组；运行↔停止用 `AnimatedSwitcher` 过渡，停止态显示危险色 |
| 标签栏 | 从「描边盒子」改成「底色 + 底部 2px 主色条」，活动标签更清 |
| 行号栏 | 独立底色；**当前行行号**变主色加粗、右侧 2px 主色标记（配合光标，平板看代码更容易定位） |
| 符号条 | 每个按键变成带描边的小胶囊；`Tab` 主色强调；每 8 个一组加细分隔线 |
| 运行窗口 | 状态改成**胶囊标签**（颜色 + 文案 + 转圈），标题独立；面板改圆角上沿 |
| 控制台 | 头部同样用状态胶囊，底色改 `panelAlt`，与运行窗口一致 |
| 空状态 | 双层圆底图标（外圈光晕 + 内圈描边），比单个大图标更像成品 |
| 设置页 | 分区标题加主色竖条；卡片 `clipBehavior` + 统一内边距 |

### 一致性怎么保证

新增的视觉值全部来自 `AppPalette` / `AppRadius`，页面里不再出现 `0xFF...` 常量；
`flutter analyze` 零告警，109 个测试全绿（其中 1 个因为运行窗口标题拆分而更新断言）。
---

## 二十、0.9.0：程序存在哪、怎么拿出来、怎么少折腾地更新

### 1. 程序存在哪

工程目录来自 Dart 侧 `getApplicationDocumentsDirectory()`，拼上 `CodePad/projects`
（Android 上通常在 `/data/user/0/com.codepad.codepad/app_flutter/CodePad/projects`）。

设置页 →「存储与更新」→ **程序保存位置** 会显示**运行时真实路径**（不是写死的字符串），
旁边一键复制。这样换设备、换系统版本都不会说谎。

### 2. 怎么把它拿出来（不用连电脑）

- **导出到「下载」**：把整个工程目录打成 zip 写进系统下载目录的 `CodePad/`
  —— Android 10+ 走 `MediaStore.Downloads`，**不需要存储权限**；
  老系统回落到应用自己的外部目录。
- **打开下载**：`ACTION_VIEW_DOWNLOADS` 直接拉起系统的「下载」界面，文件管理器里就能看到。
- 导出后弹提示：`已导出 12 个文件到 Download/CodePad/CodePad-projects-20261111-2240.zip`。

### 3. 更新（重点：别再一次次连电脑传 APK）

三条路，按"省事"排序：

| 方式 | 用法 | 适用 |
|---|---|---|
| **从文件安装** | 把新 APK 拷到平板 → 设置 →「从文件安装」→ 选它 | 已经拿到 APK 时最省事（两步） |
| 检查更新 | 填一个清单地址，点「检查更新」→ 有新版本时提示「去下载」 | 有固定发布地址时 |
| 启动自动检查 | 开关（**默认关**） | 不想错过更新时 |

清单就是一份 JSON：

```json
{"version": "0.9.0", "url": "https://…/codepad.apk", "notes": "修好了编译"}
```

**安装为什么不需要 FileProvider**：用 SAF（`ACTION_OPEN_DOCUMENT`）拿到的是 `content://`，
自带临时读权限，交给系统安装器即可；自己拼 `file://` 在 API 24+ 会抛
`FileUriExposedException`。权限侧只需在清单里声明 `REQUEST_INSTALL_PACKAGES`，
并给 `ACTION_VIEW` + `application/vnd.android.package-archive` 加一条 `queries`
（Android 11+ 包可见性）。

### 设计底线

「检查更新」永远不能把 App 卡住或吓人：没配地址、联网失败、清单格式错，全部化成一句
能看懂的中文提示，并且**顺手给出「从文件安装」按钮**；版本比较与清单解析都是纯函数
（`lib/core/update/update_info.dart`），有单元测试兜着。

测试：新增 9 个（版本比较 2、清单解析 2、检查更新 2、界面 3），合计 **118 个**。
---

## 二十一、0.10.0：编程能力三件套（编译选项 / 问题面板 / 超时保护）

### 1. 编译选项终于能选了

设置 →「编译」：C 标准（`-std=c99/c11/gnu11`）、优化（`-O0/-O1/-O2`）、警告（`-Wall` 开关）、
以及页面上实时回显「当前参数：tcc -std=c11 -O2 -Wall」。

链路是完整打通的：设置 → `SettingsController.compilerFlags` → `EditorController.run(compilerFlags:)`
→ `RuntimeEngine.run(compilerFlags:)` → `ToolchainGateway.run(flags:)` → Kotlin `runProgram(...)`
→ 拼进 tcc 命令行（**放在源文件之前**，因为 `-run` 之后的一切都是程序参数）。

验证：在开发机用同一套 tcc 跑了三组参数，输出一致、退出码 0：

```
tcc -std=c11  -O2 -Wall  → 梯形/辛普森表格正确
tcc -std=c99  -O0 -Wall  → 同上
tcc -std=gnu11 -O1       → 同上
```

### 2. 问题面板：错误从"时间轴"变成"清单"

控制台是时间轴（输出 + 提示 + 报错混在一起），修错时其实只想看错误。
工具栏新增 🐞 按钮，**有问题时带红色角标显示数量**；面板列出所有带位置的诊断：

```
问题 2        1 错误   1 提示                    ⌄
✗ main.c:4: error: expected ';'            main.c:4
⚠ util.c:9: warning: unused variable       util.c:9
```

点任意一条 → 面板收起并跳到源码对应行（复用既有 jump 逻辑）。

### 3. 运行超时保护：死循环不再只能干等

`while (1);` 这类程序以前只能手动点停止；现在默认 **10 秒**自动停（设置里 5/10/30/不限制），
超时会写一行红字说明原因：

```
⏱ 运行超过 10 秒，已自动停止（死循环？可在设置里调整）
```

实现上要注意的一点（踩到了）：定时器必须在 `finally` 里清掉。第一版放进了 `catch`，
结果正常结束的路径上定时器还挂着，组件测试直接报 `Pending timers` 失败 ——
测试替我抓住了这个泄漏。

测试：新增 7 个（编译选项 5、问题面板 2），合计 **125 个**。
---

## 二十二、0.11.0：编辑器手感（快捷键 / 补全 / 配色 / 缩放）

### 1. 蓝牙键盘快捷键

`CallbackShortcuts` 包住编辑器 body（作用域只在编辑器页，回首页不会误触）：

| 快捷键 | 动作 |
|---|---|
| `Ctrl+S` | 立即保存 |
| `Ctrl+F` | 开/关查找替换 |
| `Ctrl+Enter` | 运行 |
| `Ctrl+B` | 开/关控制台 |

### 2. 前缀补全 + 代码片段

编辑区上方多了一行候选条，输入 `pr` 就会出现 `printf`，点一下插入
**并把光标放进引号里**；`mai` → 整个 `main` 骨架；`fori` → 循环模板（光标落在循环体缩进处）。

规则都写在 `lib/core/text/completion.dart`（纯函数）：
- 只在「光标处是一个标识符前缀」时才给建议（`int ` 后面、`3.14` 里的数字都不给）；
- 前缀命中优先、短名字优先（`int` 先于 `unsigned`）；
- 片段用 ⚡ 标记，与普通函数区分。

### 3. 代码配色主题

新增 `One Dark`（深色高对比）与 `纸白`（浅色印刷感），设置 →「代码配色」可切换，
默认仍是「跟随系统深浅色」。配色表集中在 `CodePalette`，编辑器与高亮控制器共用。

### 4. 双指缩放调字号

编辑区支持双指捏合改字号（10–26 px，写回设置持久化）。实现上注意两点：
单指仍由 `TextField` 处理（子级手势优先，选择/光标不受影响）；缩放只在
`pointerCount >= 2` 时生效，避免误触。

### 一个反复踩的坑，记一下

Dart 片段里要换行时，`'\n'` 是正确写法；用 PowerShell 批量改文件时，
**单引号字符串里的 `` `r`n `` 不会被转义**，会原样写进源码 —— 这一轮因此
坏了两处代码（`\n      codeTheme` 被当成字面量）。后来改成「按行插入」才稳。

测试：新增 13 个（补全 8、配色 2、候选条 2、其它 1），合计 **138 个**。
---

## 二十三、0.12.0：把「找工作」这件事做顺（跨文件搜索 / 括号匹配 / 撤销重做）

### 1. 跨文件搜索

查找条多了一个「全工程」开关（`travel_explore` 图标，只有在工程里不止一个文件时才出现）。
打开后：计数变成 `全工程 12 处`，下面列出结果清单：

```
main.c:4:12    double sum = 0.0;
util.c:9:5     return f(x) * 2;
```

点任意一条 → 切到该文件并**选中命中片段**（不是只把光标移过去）。

逻辑在 `lib/core/text/project_search.dart`：先给每个文件算「行首偏移表」，
再逐命中反查行列，避免每个命中都从头数换行；预览超过 120 字符截断加省略号。
命中数默认上限 200，防止在大工程里卡住。

### 2. 括号匹配高亮

把光标放到 `(`、`[`、`{` 旁边（左右都算），它和配对的另一个括号会被加底色 + 加粗。
关键点是**不误判**：`printf("(")` 里的括号、`//` 与 `/* */` 注释里的括号都不参与匹配，
所以 `lib/core/text/bracket_match.dart` 先做一次带状态的扫描（跳过字符串/字符常量/注释），
再在括号序列上做深度配平。8 个用例覆盖：嵌套、反向匹配、字符串、注释、不配对、空文本。

渲染侧在 `HighlightingTextEditingController.buildTextSpan` 里按「括号位置」把文本切成小段，
只给那两个字符套底色（`0x332F6BFF`），其余颜色仍由语法高亮决定。

### 3. 撤销 / 重做

自己接管，而不是依赖输入法的按键事件：

- `UndoStack` 记录「改动前」的快照，**900ms 内的连续输入合并成一步**（不会一个字一步）；
- 栈深上限 100，超出丢最早的；
- 新输入会清空重做栈（符合直觉）；
- 工具栏加了 ↩ / ↪ 按钮，快捷键 `Ctrl+Z` / `Ctrl+Y`。

这里踩了个坑：一开始我让每次编辑都 `notifyListeners()` 去刷新按钮，结果破坏了
「输入过程不重建页面」的既有约束（会打断输入法），组件测试直接抓到了
（`updateContent 只在首次变脏时重建界面` 期望 1 次通知、实际 2 次）。
最终改成**节流 250ms 的通知**：按钮状态照样能跟上，但不会每按一个键就重建。

### 关于「当前行整行高亮」

这项这轮**没有做**，原因写在方案里：`TextField` 默认软换行，一行可能占多行高度，
用固定行高的色带去定位会错位；要做得对，需要在编辑器底下加一层自绘（`CustomPainter`）
按实际布局计算，属于下一版的活。当前版本的替代方案是「行号栏高亮当前行」+ 括号匹配。

测试：新增 19 个（跨文件搜索 7、括号匹配 8、撤销 7 + 集成 4），合计 **164 个**。
---

## 二十四、0.13.0：C 标准库到底齐不齐 —— 用矩阵说话

### 先立规矩：不靠印象，靠编译

写了一个覆盖脚本 `scripts/c-coverage-test.ps1`，用真 tcc（与真机同源码）在开发机上跑两件事：

1. **44 个标准/POSIX 头逐个编译**（C89/99/11 全套 + unistd/fcntl/dirent/sys-*/termios/poll/pthread/getopt/strings/libgen）；
2. **18 组功能实测**：每组是一个真正调用该组函数的 `.c`（stdio 格式化与文件、stdlib 的 malloc/qsort/bsearch/strto*、string 全套、math 全套、ctype、time、stdint/inttypes 的 PRId64、errno/locale、setjmp/signal、assert/stdbool、wchar、threads/pthread、unistd、dirent/socket/poll、变参函数与变参宏、struct/union/enum、float/limits、stdatomic）。

结果（第一次跑）：**头文件 40/44、功能组 14/17**。真实缺口四条，全部有解：

| 缺口 | 原因 | 处理 |
|---|---|---|
| `iso646.h` 不存在 | bionic 不提供（clang 也不需要） | 补 `compat/iso646.h`：标准规定的 11 个宏 |
| `uchar.h` 报 `';' expected (got char16_t)` | 缺 `__CHAR16_TYPE__` / `__CHAR32_TYPE__` | 垫片里补成 `unsigned short` / `unsigned int` |
| `stdatomic.h` 报 `__ATOMIC_RELAXED undeclared` | tcc 无 `_Atomic` 与 `__ATOMIC_*` | 补 `compat/stdatomic.h`：**单线程语义**的实现（普通读写 + 内存序枚举），头里写明「不能用于多线程同步」 |
| 只包含 `math.h` 时 `NULL` 未声明 | bionic 指望编译器带 `stddef.h` | 垫片 `sys/cdefs.h` 补 `NULL`、`__PRETTY_FUNCTION__` |

两处**不是缺陷**的项，单独标注、不算缺口：

- `complex.h`：tcc 没有 `_Complex` 关键字（宏补不出来）。原来的报错是 `';' expected (got "cacos")`，看不懂；现在给 `compat/complex.h`，直接 `#error` 一句人话：「不支持 <complex.h>，需要复数请自己定义 struct { double re, im; }」。**明确不支持 > 假装支持**。
- `variadic_macro`（`va_arg`）：Windows 版 tcc 没有 `__builtin_va_arg`；aarch64 版的 `stdarg.h` 里 `va_arg` 就是映射到它，**真机支持**。开发机上这条永远是红，属平台差异。

修完再跑：**头文件 43/44 编译通过、功能组 17/18 通过、真实缺口 0**，脚本退出码 0。

### 顺带把它们纳入 App 自检

自检项从 6 个加到 7 个，新增 `headers` 探针：一个程序里同时 `#include` iso646 / uchar / stdatomic / inttypes / stdint，
用 `char16_t`、`atomic_store`、`PRId64`、`and` 运算符，输出 `headers=65,6,7`。
真机上 7 项全绿，就说明这些兼容层在新解压的工具链里都生效了。

（`TOOLCHAIN_VERSION` 因此升到 `android-7`：手机上必须重新解压，才能拿到新补的头文件。）

测试：164 个（自检脚本的用例同步改成 7 项）。
### 真机反馈：0.13.0 的 `headers` 探针为什么会红

真机（0.13.0）自检 6/7，唯一红项是 `headers`：

```
headers.c:8: error: 'u' undeclared
```

对应代码是 `char16_t c = u'A';`。在开发机上复验后确认：**tcc 根本不支持 `u''` / `u""` / `U''` / `U""`
这类 UTF-16/32 字面量**（两个平台一致，都是 `error: 'u' undeclared`），
而 `char16_t` / `char32_t` 类型本身、`<uchar.h>` 头、以及强转赋值都正常。

所以这不是兼容层的问题，是**探针写错了**：用 `char16_t c = (char16_t)65;` 即可验证类型存在，
且不再依赖 tcc 不支持的字面量。修正后在开发机上跑出 `headers=65,6,7`，与预期一致。

| 能用的 | 不能用的 |
|---|---|
| `char16_t` / `char32_t` 类型、`<uchar.h>`、`(char16_t)65` | `u'A'`、`u"hi"`、`U'A'`、`U"hi"` 字面量 |

这条也加进「明确不支持」清单：需要 UTF-16 文本时，用 `char16_t` 数组 + 数值常量，或改用 `char` 的 UTF-8 字节串。
---

## 二十五、1.0.0：`undefined symbol` 的根治 + C 支持边界定稿

### 现场

真机上运行 `main.c` 反复失败：

```
$ tcc main.c -run
tcc: error: undefined symbol 'f'
```

`f()` 就在工程里的 `util.c`。两个可能：设置里「多文件编译」被关了，或者这个工程里根本没有 `util.c`。
问题在于：**报错和界面都没说清楚是哪一种**，用户只能猜。

### 修法：先自动救，再精确解释

**第一步 · 自动补救**（不要求用户去翻设置）：
链接失败后解析 `undefined symbol 'X'`，在工程里找「定义了 X、是 `.c`、自己又没有 `main()`」的文件，
把它们一起编进去**再试一次**。哪怕「多文件编译」是关的也照做，并在控制台说明：

```
… 设置里关闭了「多文件编译」，但缺少的实现定义在 util.c，本次自动带上重试（可到设置里打开「多文件编译」）
```

**第二步 · 仍然失败时给结论**（四种情况，各自给出下一步动作）：

| 情况 | 提示 |
|---|---|
| 定义在某个 `.c`，但该文件也写了 `main()` | 「它也有 main，本次被跳过；请切到那个文件再运行」 |
| 设置里关了多文件编译 | 「打开：设置 → 编译 → 多文件编译」 |
| 定义在已编译的文件里 | 「多半是 static，或定义在没走到的 #if 分支里」 |
| 工程里没有任何文件定义它 | 「漏了 #include，或需要额外链接库」；若工程只有 1 个 `.c`，直接说「没有谁定义，要么写进本文件，要么新建 .c」 |

判定用的是一个克制的正则（`类型 名字(...) {`），只区分「定义」与「声明」，
不试图做真正的 C 语法分析 —— 目的是给出可执行的建议，不是做编译器。

### C 支持边界（1.0.0 定稿）

| 维度 | 结论 |
|---|---|
| 标准/POSIX 头 | **43/44 可编译**（`complex.h` 明确不支持并给出解释） |
| 功能组实测 | **17/18 通过**（`va_arg` 仅 Windows 版 tcc 缺内建，真机支持） |
| 标准版本 | `-std=c99 / c11 / gnu11` 可选，`-O0/-O1/-O2`、`-Wall` |
| 明确不支持 | `<complex.h>`；`u''`/`U''` 与 `u""`/`U""` 字面量；`<linux/*.h>` 内核头 |
| 语义限制 | `stdatomic` 为单线程语义（头文件内已注明）；无 `_Atomic` 真原子性 |

自检 7 项、164+ 个单元测试、`acceptance-test.ps1`（7 用例）与 `c-coverage-test.ps1`（44 头 × 18 组）全部作为门禁。

### 这一版之后

C 语言这条线到此收口：**写 → 编 → 跑 → 看输出 → 报错定位**闭环完整，标准库覆盖有实测数据支撑，
不支持项都有清晰说明而不是静默出错。后续若继续，方向是工程管理（文件夹、快照回滚）与 C++/Python。