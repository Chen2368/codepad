# CodePad

面向平板（华为 HarmonyOS 4.x / Android）的**轻量级移动编程工具**：在平板上直接写、编译、运行 **C** 程序（C++ / Python 排后续阶段），替代装不上的 VS Code。

当前状态：**Phase 3 完成并在真机验证通过（**1.0.0**，C 完整支持：标准库 43/44 头、自检 7 项、链接失败自动补救）** —— C 语言真编译真运行，编译错误可点击跳行、带中文提示，支持多 `.c` 文件与标准输入，内置一键编译器自检。
`flutter analyze` 无问题、`flutter test` 167 个测试全绿、release APK 10.8 MB；C 标准库覆盖见 `scripts\c-coverage-test.ps1`（头文件 43/44、功能组 17/18、真实缺口 0）。


```bash
git clone https://github.com/Chen2368/codepad.git
cd codepad
```

**下载 APK（免构建）**：[Releases](https://github.com/Chen2368/codepad/releases/latest) · **从源码构建**：[docs/build-from-source.md](docs/build-from-source.md)
> 版本修复记录：
> - **0.3.2**：示例工程多个文件都有 `main()`，而多文件规则把它们全丢给编译器 → `duplicate symbol main`，任何文件都跑不起来（示例工程文件数不该混进编译单元规则）。
> - **0.3.3**：打包脚本把 bionic 的 `include/android/` 裁掉了，而 `sys/cdefs.h` 无条件 `#include <android/versioning.h>` → 所有 C 程序报 include file not found。
> - **0.3.4**：bionic 头文件是给 clang 写的（`_Nonnull` 2104 处、`__RENAME` 用 `__asm__` 别名、`__availability__` 属性…），tcc 全不认识 → 加了 `compat/sys/cdefs.h` 兼容垫片把 clang 词汇架空。
> - **0.3.5（关键）**：把 Windows 版 tcc 0.9.27 请到开发机上跑真实命令，抓出四个一直存在的 bug ——
>   ① `-run` 写在源文件前面，导致 `tcc -run a.c b.c` 里 `b.c` 只当程序参数、**多文件从来没编进去过**（`undefined symbol`）；
>   ② tcc 的 `#pragma once` 对 `<...>` 引用完全不生效，而 bionic 全用尖括号 → 打包时给 1527 个头文件补传统 include guard（`<signal.h>`/`<pthread.h>`/`<threads.h>`/`<wchar.h>` 因此能过）；
>   ③ tcc 自带 `stddef.h` 定义 `intptr_t` 与 bionic `stdint.h` 冲突 → `compat/stddef.h`；
>   ④ bionic `limits.h` 靠 `#include_next` 找编译器那份才有 `INT_MAX` → `compat/limits.h`。
>   另修 C23 `enum : size_t`（`<wchar.h>` 路径）与 `__uint128_t`（`<signal.h>` 路径）。新增 `scripts/acceptance-test.ps1`，6 项全绿。
> - **0.3.6（真机日志）**：`compat/sys/cdefs.h:145 redefined` / `:155 too many basic types` —— Termux 的 aarch64 tcc 在预置头 `tccdefs.h` 里已有 `__ANDROID__` 分支，替 Android 定义过 `BIONIC_IOCTL_NO_SIGNEDNESS_OVERLOAD`、`_Nonnull` 等，我又定义了一遍；且 `__uint128_t` 在 aarch64 已是**基本类型**，不能再 typedef。修法：垫片全面 `#ifndef` 保护，int128 只在非 `__ANDROID__` 目标补。
> - **0.3.9 真机确认（2026-11-11）**：华为平板上自检 **6/6 全绿** —— `shim=on`、`OK-HELLO`、`42 3.14 abc`、`sqrt2=1.41421`、`sum=5050`、`add=7`。C 语言在平板上真编译、真运行这一环彻底打通（`-run` 位置、include guard、compat 垫片、`-I tcc/include`、`-L` 库路径五处坑全部收口）。
> - **0.4.0**：首页右上角加「函数」按钮，一键把两个高数示例工程加进列表 —— **数值积分（梯形 vs 辛普森）** 与 **泰勒展开与余项**。两个程序都已在真实 tcc 下跑通，输出里直接能看到 O(h²) / O(h⁴) 与拉格朗日余项上界。
> - **0.5.0（平板输入优化）**：编辑器底部加**符号快捷条**（`; { } ( ) [ ] " ' < > == && || -> ++ -- //` 等 34 个，点一下插入光标处；**成对符号自动补全**、**选中内容自动包裹**、`Tab` 插四空格，且不会抢走软键盘焦点）；回车**自动缩进**（沿用上一行缩进，行尾是 `{` 再缩进一级，中文输入法组词期间不干预）。新增 11 个单元/组件测试（共 92 个）。
> - **0.6.0（运行窗口）**：点「运行」立刻弹出可拖拽的运行面板（28%–95% 高度），输出流式进入；头部有状态/文件名/停止/复制/清空，底部是独立 stdin 行（运行中可回车送达、可发 EOF），点编译错误自动关窗并跳到源码行。输出渲染与输入行抽成共享组件，内嵌控制台与弹窗不再各写一套。
> - **0.7.0（查找替换）**：工具栏 🔍 打开查找条 —— 区分大小写（默认开）、`↑/↓` 命中跳转（到头绕回）、`1/2` 计数、单处替换与全部替换。查找/替换逻辑抽成纯函数（`findMatches` / `stepIndex` / `replaceAllMatches`）；
>     `a` → `aa` 不会回跳（替换结果不参与再匹配）；合计 109 个测试。
> - **0.8.0（视觉统一）**：新增语义色板 AppPalette（scaffold/panel/panelAlt/border/text/textMuted/accent/success/warning/danger/gutter/code）与 AppRadius，界面不再直接写十六进制；首页加渐变品牌块与「我的工程·N」分区；工程卡片加语言色条与元信息；工具栏分组 + 运行/停止过渡动画；标签栏改「底色 + 底部主色条」；行号栏独立底色并高亮当前行；符号条改描边胶囊并按 8 个一组分隔；运行窗口与控制台统一用状态胶囊；空状态改双层圆底。
> - **0.9.0（存储与更新）**：设置页新增「存储与更新」——显示工程真实路径并可复制；一键把工程打包到系统「下载/CodePad」；从文件安装 用 SAF 选本地 APK 交给系统安装器（两步完成更新，不必连电脑）；检查更新 支持配置 JSON 清单（version/url/notes），默认不自动检查，失败只给中文提示并顺手提供本地安装。新增 9 个测试（共 118）。
> - **0.10.0（编程能力）**：设置里可选 C 标准 / 优化级别 / -Wall，参数一路传到 tcc 命令行（有开发机三组参数验证）；工具栏加「问题」按钮与红角标，面板把诊断列成可跳转清单；运行超时保护默认 10 秒（5/10/30/不限），超时写红字原因。
> - **0.11.0（编辑器手感）**：Ctrl+S/F/Enter/B 快捷键；前缀补全条（pr→printf、mai→main 骨架、ori→循环，光标自动落位）；代码配色可选 One Dark / 纸白；编辑区双指捏合调字号（10–26px）。新增 13 个测试（共 138）。
> - **0.12.0（找代码更顺）**：查找条新增「全工程」开关与结果清单（点一条即跳到该文件并选中命中片段）；光标旁的括号与其配对括号高亮（字符串/注释里的括号不参与）；自己接管撤销重做（连续输入合并成一步、栈深 100、Ctrl+Z/Y）。新增 26 个测试（共 164）。
> - **0.13.0（C 标准库补齐）**：新增 scripts\c-coverage-test.ps1（44 头 × 18 组函数实测）。补 compat/iso646.h、compat/stdatomic.h（单线程语义，头内写明）、compat/complex.h（明确 #error 说人话）；垫片补 NULL / __PRETTY_FUNCTION__ / __CHAR16_TYPE__。结果：头文件 43/44、功能组 17/18、真实缺口 0；自检加第 7 项 headers 探针，TOOLCHAIN_VERSION 升 android-7。
> - **0.13.1**：修 0.13.0 自检第 7 项的误报 —— tcc 不支持 u'' / u"" 等 UTF-16/32 字面量（error: 'u' undeclared），探针改用 (char16_t)65 验证类型；该限制已写入「明确不支持」清单。
> - **1.0.0（C 收口）**：undefined symbol 现在先**自动补救**（找出缺失实现所在的 .c 一起编，哪怕「多文件编译」关着也救一次），仍失败再按四种情况给出可执行说明；C 支持边界定稿（43/44 头、17/18 功能组、3 项明确不支持）。
> - **0.3.7（真机日志）**：`stdio.h:46: include file 'stdarg.h' not found` —— tcc 只在自己**可执行文件旁边**找 `include/`，真机上它是 `lib/arm64/libtcc.so`，旁边只有 `.so`；`-B` 只影响 lib/ 不影响 include。修法：命令行补 `-I<toolchain>/tcc/include`（放最后，只补 bionic 没有的编译器自带头）。验收脚本新增第 7 个用例：把编译器搬进没 `include/` 的目录，先复现真机报错、再验证修复。
>
> 三处都已修，原因与验证见 [docs/phase3-checklist.md](docs/phase3-checklist.md) 第九～十一节。

---

## 一、现在能做什么

| 能力 | 说明 |
|------|------|
| 工程管理 | 首页列表、新建（选 C / C++ / Python）、删除、按更新时间排序 |
| 代码编辑 | C / C++ / Python **语法高亮**、行号、字号调节、深浅主题、多标签 |
| 文件操作 | 文件树「+」新建、「⋮」重命名 / 移动 / 删除（支持 `lib/a.c` 这类子目录） |
| 自动保存 | 停止输入 900 ms 后自动落盘，标题旁小圆点表示未保存 |
| **运行 C（真编译）** | 内置 tcc 0.9.27：`tcc <文件> -run` 内存编译后执行（`-run` 必须在源文件之后，否则后面的源文件只当程序参数），真实 stdout/stderr、真实退出码与耗时 |
| **编译错误跳行** | 报错行尾部「第 N 行」标签，点一下就切到对应文件、把光标放到该行 |
| **报错说人话** | 17 条常见报错的中文解释（隐式声明、缺分号、全角标点、重复定义…），运行前还会体检全角字符 |
| **多文件编译** | 一个 `.c` = 一个目标：不含 `main()` 的 `.c`（如 `util.c`）一起编译，带 `main()` 的互不干扰；失败自动退回单文件重试 |
| **标准输入 + EOF** | 控制台底部 `stdin` 行喂 `scanf`，⏹ 按钮发送 EOF 结束输入循环 |
| **编译器自检** | 设置页一键跑 5 个小程序（hello / 格式化 / math.h / 循环 / 多文件），逐项显示真实输出 |
| **一键复制输出** | 控制台标题栏复制按钮，出问题时一键拷走整段输出 |
| 设置持久化 | 主题 / 字号 / 行号开关 + 内置编译器状态，重启后保持 |
| 平板适配 | ≥ 840 逻辑像素（横屏）左侧常驻文件树，窄屏收进抽屉 |

### 下载安装包

[**⬇ 下载 CodePad 1.0.0（arm64）**](https://github.com/Chen2368/codepad/releases/latest)

- `CodePad-1.0.0-release-arm64.apk` — 10.8 MB，平板上直接安装（**仅 arm64**）
- `CodePad-1.0.0-debug-arm64.apk` — 49.1 MB，调试用（可 `adb logcat` 看原生日志）

校验（release 包）：

```
sha256 5E3C153E16F099B161B31782AB315A205B667F6F910ADD868D2F8F75FAD1B861
```

包信息（`aapt2 dump badging` / `dump xmltree` 实测）：

```
package: name='com.codepad.codepad' versionCode='24' versionName='1.0.0'
application-label:'CodePad'
minSdkVersion:'24'   targetSdkVersion:'36'   compileSdkVersion='36'
extractNativeLibs='true'
lib/arm64-v8a/libtcc.so                    内置 C 编译器（与源文件字节一致，未被 strip）
assets/toolchain/...                       1546 个条目：bionic 头文件（含 android/media/drm）+ libtcc1.a + crt
```

C 工具链随包增量约 6.6 MB（tcc 370 KB + libtcc1.a/crt 0.3 MB + bionic 头文件 5.9 MB；其中 `include/android/` 是 `sys/cdefs.h` 的硬依赖，不能裁）。

---

## 二、已验证的事实（本机实测，非推测）

```
Flutter 3.47.9 · Dart 3.13.7 · JDK Temurin 17.0.21+9 · Android SDK 36.0.0 · NDK 28.2.13676358
（开发机上这些 SDK 装在仓库之外的目录，不占用系统盘；仓库本身不含它们）

$ flutter analyze
No issues found! (ran in 5.2s)

$ flutter test
00:04 +167: All tests passed!
  模型层（3）        语言识别 / 路径拆分 / 仓库排序
  界面骨架（3）      首页渲染 / 运行链路 / 平板横屏文件树
  高亮（9）          C++ 关键字类型函数数字 / 注释字符串预处理 / 块注释跨行 /
                     C 与 C++ 关键字差异 / 未闭合代码不崩 / Python def·内置·三引号·装饰器 / 未知语言
  文件仓库（5）      保存读回 / 重命名删旧文件 / 删除目录 / 忽略非源文件 / 跳过无 meta 目录
  文件操作（7）      新建·重名·非法后缀 / 路径规范化 / 重命名改语言 / 保留最后一个文件 /
                     自动保存落盘 / 新建文件落盘 / updateContent 只通知一次
  设置持久化（3）    写入读回 / 非法值回退 / 字号夹紧
  文件操作 UI（3）   「+」新建后进标签栏 / 重名提示 / 删除确认框
  真实 C 引擎（19）  成功运行逐行回传 / 编译错误带 stderr 与退出码 / 启动失败不假装成功 /
                     头文件一起落盘 / 多 .c 一起编译 / 其它含 main() 的文件不参与编译 /
                     多文件失败自动单文件重试 / 缺头文件不重试 / 程序自身失败不重试 /
                     关掉多文件开关只编当前文件 / 缺 main 改换入口 / 每次运行清空工作目录 /
                     stdin 与 EOF / 取消透传 / 工具链可用→真实引擎 / 多文件开关实时生效 /
                     不可用→明确报错 / C++·Python→未接入 / 默认仍可模拟
  ★ 诊断与体检（17） file:line 解析 / 子目录路径 / 无位置错误 / 隐式声明提示 / 全角标点提示 /
                     正常输出不误判 / 整段只挑诊断行 / 全角分号体检 / 字符串注释不误报 /
                     跨行块注释不误报 / 注释外仍会报 / char 字面量与转义不错位 / 涂空后行号不变 /
                     最多 3 条 / 行号↔偏移换算
  ★ 错误跳转（4）    跨文件跳转并定位行 / 只给文件名也能匹配 / 文件不存在给提示 / 无位置不跳
  ★ 编译器自检（4）  5 项全通过 / 单项失败带原因 / 启动失败带错误 / 覆盖上次遗留文件

$ flutter build apk --release --target-platform android-arm64
√ Built build\app\outputs\flutter-apk\app-release.apk (10.1MB)
```

**开发机上的验收（0.3.5 起）**：下载 Windows 版 tcc 0.9.27（与 Termux 的 aarch64 版同版本同源码），
用 App 会发的同一条命令真跑一遍：

```
$ powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\acceptance-test.ps1
1) 单文件 hello                    [PASS] Hello, CodePad!
2) 多文件 main.c + util.c          [PASS] integral=0.33333350
3) 标准输入 scanf 21 → 441         [PASS] square 441
4) math.h + 浮点格式化              [PASS] sqrt2=1.41421 / 42 3.14 abc
5) 常用头文件全家桶（30 个）        [PASS] qsort/struct/malloc/stat/localtime
6) 编译错误格式（点击跳行依赖它）    [PASS] bad.c:4: error: identifier expected
7) 隔离编译器（模拟真机 libtcc.so 位置）
   [PASS] 不传 -I<tcc>/include 时复现真机报错（用例有效）
   [PASS] 传了 -I<tcc>/include 后正常编译运行
全部通过（7 个用例 / 8 项断言）
```

**仍然只能在真机上确认的**：arm64 上 `execve` 的限制、tcc 的 aarch64 后端、`math.h` 在 bionic 里的符号解析。
这三项都有兜底报错，不会静默输出假结果。装好后按 [docs/phase3-checklist.md](docs/phase3-checklist.md)
第五节 5 步自检，第 2 步的「编译器自检」会直接把这些答案打出来（6 项，含 `shim=on` 探针）。

---

## 三、目录结构

```
codepad\                      ← 仓库根（git clone 后就是这里）
    pubspec.yaml              path_provider / shared_preferences / path
    android\
      app\src\main\assets\toolchain\    ← 生成物（fetch-toolchain.ps1 产出，不入库）
        include\                       bionic 原样（含 android/ media/ drm/）
        compat\                        ★ tcc 兼容垫片：sys/cdefs.h 抹平 _Nonnull/__RENAME/__availability__，limits.h 自带 INT_MAX
        tcc\                           libtcc1.a + crt*.o + tcc 自带头
      compat-headers\                  ★ 垫片源文件（由 scripts\fetch-toolchain.ps1 复制进 assets）
      app\src\main\jniLibs\arm64-v8a\libtcc.so   ← 编译器本体，装后落在 nativeLibraryDir
      app\src\main\kotlin\…\NativeCompiler.kt    ← MethodChannel：解压工具链、跑 tcc、stdin/EOF
    dist\                     构建产物（.gitignore 忽略；对外发布走 GitHub Releases）
    build\ .dart_tool\          Flutter 构建缓存（.gitignore 忽略）
    （可选）toolchain\          脚本缓存，默认在仓库上一级；可用 CODEPAD_TOOLCHAIN_DIR 覆盖
    scripts\
      flutter-env.ps1         一键注入 SDK / JDK / Android SDK 与各类缓存路径
      fetch-toolchain.ps1     从 Termux 仓库重抓并组装内置 C 工具链（可重复构建，带自检 + 补 include guard）
      acceptance-test.ps1     ★ 用真实 tcc 跑「App 会发的命令」，7 项验收（含隔离编译器反证）
      c-coverage-test.ps1     ★ C 标准库覆盖：44 个头逐个编译 + 18 组函数实测
    lib\
      main.dart               启动：设置 + 文件仓库 + 探测内置编译器（失败不崩）
      app.dart                根组件（主题 + 依赖注入）
      core\
        constants\ settings\ theme\
        text\line_offsets.dart          行号 ↔ 字符偏移
      data\
        models\               ProgramLanguage / SourceFile / Project / RunResult / ConsoleMessage（含诊断）
        repositories\         ProjectRepository / SettingsStore 抽象 + 真实与内存实现
      runtime\
        runtime_engine.dart          引擎契约（projectFiles / writeInput / closeInput）
        native_runtime_engine.dart   ★ C 真编译：多文件、目录清理、路径缩短
        native_toolchain.dart        ToolchainGateway 抽口 + MethodChannel 实现
        compile_diagnostic.dart      ★ 诊断解析 + 17 条中文提示 + 全角标点体检
        toolchain_self_check.dart    ★ 5 项一键自检
        stub_runtime_engine.dart     模拟引擎（测试 / 降级）
        unavailable_runtime_engine.dart  缺运行时 → 明确报错，不伪造输出
        runtime_factory.dart         语言 → 引擎（preferNative 开关）
      features\ home\ editor\（含 highlight\）settings\ templates\ widgets\
    test\                     167 个测试（21 个文件）
    docs\
      architecture.md         分层、数据流、Phase 3 四个关键取舍、限制
      phase1-checklist.md     骨架阶段交付清单
      phase2-checklist.md     可用了：真实持久化 + 高亮
      phase3-checklist.md     ★ C 真编译 + 0.3.1 打磨：方案、5 步自检、限制
      toolchain-setup.md      工具链安装全流程（含 5 个实打实的坑）
```

---

## 四、怎么跑起来

> 换一台机器 / 想从零构建：看 [docs/build-from-source.md](docs/build-from-source.md)。
> 要发到 GitHub：看 [docs/publish-to-github.md](docs/publish-to-github.md)。

```bash
# 1) 依赖 / 检查 / 测试
flutter pub get
flutter analyze        # 期望 No issues found!
flutter test           # 期望 All tests passed! (167)

# 2) 组装内置 C 工具链（仓库不含二进制，首次构建必须跑一次）
pwsh -NoProfile -File ./scripts/fetch-toolchain.ps1

# 3) 打 APK（只支持 arm64）
flutter build apk --release --target-platform android-arm64
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

本机开发时可以用 `scripts/flutter-env.ps1` 一次性注入 SDK 路径（点号 source 才会生效）：

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
. .\scripts\flutter-env.ps1
```

跑通后的现象：首页三个示例工程 →「C 语言入门」（5 个文件：main.c / util.h / util.c / hello.c / input.c）→ 运行 `main.c`：

```
▶ 运行 main.c（C）
$ tcc main.c util.c -run
梯形法 n = 1000
积分值 = 0.33333333
精确值 = 0.33333333
误差   = -1.85e-09
✓ 运行结束，退出码 0，耗时 xx ms
```

把 `printf` 写成 `printff` 再运行，控制台会出现可点击的报错行 + 橙色中文提示。

---

## 五、数据存在哪

应用私有目录（无需存储权限，卸载即清空）：

```
/data/data/com.codepad.codepad/
  app_flutter/CodePad/projects/
    p-1720000000000000/
      meta.json              id / name / language / createdAt / updatedAt
      files/
        main.c
        lib/util.h           子目录结构原样保留
  files/toolchain/           Phase 3：首次运行 C 时解压的工具链
    tcc/  include/           1416 个头文件 + libtcc1.a + crt
    VERSION                  解压标记，升级 APK 后自动重解压
  cache/run/<源文件名>/      每次运行前落盘的工程副本（每次运行都会重建）
    selfcheck/<项名>/        编译器自检用的临时程序
```

设置单独存在 shared_preferences 的 `codepad.settings` 键里（`themeMode=dark|fontSize=14.0|lineNumbers=true`）。
首次启动仓库为空时，会自动写入「C 语言入门」「C++ 算法练习」「Python 入门」三个示例工程。

---

## 六、阶段进度

| 阶段 | 内容 | 状态 |
|------|------|------|
| Phase 1 | 界面骨架、状态机、控制台链路、模拟运行 | ✅ 完成并验证 |
| Phase 2 | 真实文件持久化、设置持久化、语法高亮、文件增删改名、自动保存、APK 构建 | ✅ 完成并验证 |
| Phase 3 | **C 真编译**：内置 tcc（`tcc <文件> -run` 内存编译）、bionic 头文件、MethodChannel 进程桥、stdin/EOF | ✅ 完成 |
| **Phase 3.1** | **C 打磨**：编译错误跳行 + 中文提示 + 全角体检、多 `.c` 编译、EOF、编译器自检 | ✅ 完成（但引入了多 `main()` 回归） |
| **Phase 3.2** | **修回归**：一个 `.c` = 一个目标、自动单文件兜底、多文件开关、控制台复制 | ✅ 完成 |
| **Phase 3.3** | **修工具链**：补回被裁掉的 `include/android/`（`sys/cdefs.h` 硬依赖）、脚本加一致性检查、显式传 `__ANDROID_API__`、块注释不再误报全角 | ✅ 完成（待真机自检确认） |
| Phase 3.5 | C++ 真编译：内嵌 clang（裁剪 llvm）或 NDK 交叉编译 + 自写 `dlopen` 加载器执行产物 | 待开始 |
| Phase 4 | Python 嵌入：嵌入式 CPython / Chaquopy，独立 isolate，复用控制台 stdin | 待开始 |
| Phase 5 | 发布打磨：图标启动页、正式签名、断点调试、分屏与手写笔适配 | 待开始 |

Phase 3 的技术路线为什么是 tcc 而不是 clang，见 [docs/phase3-checklist.md](docs/phase3-checklist.md) 第一、二节。

---

## 七、三个必须知道的前提

1. **系统版本**：鸿蒙 **4.2**（用户已确认）属于 Android 12 兼容层，APK 正常安装运行 ✅。
   若日后升级到 **HarmonyOS NEXT（纯血鸿蒙 5.x）**，AOSP 兼容层被移除，APK 将无法安装，届时需要改走 ArkTS 原生或 PWA。
2. **C++ / Python 暂时跑不了**：内置工具链只有 C 编译器。点这两个语言的「运行」会明确提示「计划 Phase 3.5 / Phase 4 接入」，**不会伪造输出**。
3. **APK 里的 `.so` 是压缩存放的**：`useLegacyPackaging = true` 让 tcc 能在安装时解压成可执行文件——这是 Phase 3 的硬要求，不要随手关掉（详见 phase3-checklist 第一节）。

工具链安装过程中踩到的 5 个坑（sdkmanager 拉不到清单、build-tools 多套一层目录、NDK 省不掉、android-35 也要装、licenses 可以为空）都记在 [docs/toolchain-setup.md](docs/toolchain-setup.md) 第四节，重装时照着做即可。

---

## 八、许可证与致谢

- 本项目代码：**MIT**（见 [LICENSE](LICENSE)）
- 内置 C 编译器 **TinyCC 0.9.27**：**LGPL-2.1**；bionic 头文件来自 **Android NDK / AOSP（Apache-2.0）**。
  二者都由 `scripts/fetch-toolchain.ps1` 在本地从 Termux 源下载组装，**仓库不包含这些二进制**。
- 分发自己构建的 APK 时，请一并附上 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

致谢：TinyCC 与 Termux 的打包者（没有 `tcc` 的 aarch64 构建就没有这个项目）、
Android NDK 提供的 bionic 头文件、以及 Flutter。
