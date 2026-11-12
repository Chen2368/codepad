# 架构说明（Phase 3 · C 真编译）

## 1. 分层

```
┌──────────────────────────────────────────────────────────┐
│ features/            界面层（只依赖抽象）                  │
│   home/     工程列表、新建、删除                           │
│   editor/   编辑器页 + 控制器 + 组件 + highlight/          │
│   settings/ 主题、字号、行号、编译器状态                    │
│   templates/ 内置代码模板                                  │
├──────────────────────────────────────────────────────────┤
│ runtime/             运行层（唯一需要替换）                │
│   RuntimeEngine（抽象）                                    │
│   NativeRuntimeEngine（C：真实 tcc 编译执行）← Phase 3      │
│   StubRuntimeEngine（模拟，仅测试/降级）                   │
│   UnavailableRuntimeEngine（缺运行时 → 明确报错）          │
│   ToolchainGateway 抽象 + NativeToolchain（MethodChannel） │
│   compile_diagnostic（诊断解析 + 中文提示 + 全角体检）      │
│   toolchain_self_check（5 项一键自检）                     │
│   RuntimeFactory（语言 → 引擎）                            │
├──────────────────────────────────────────────────────────┤
│ data/                数据层                                │
│   models/       ProgramLanguage / SourceFile               │
│                 Project / RunResult / 控制台行              │
│   repositories/ ProjectRepository 抽象                     │
│                 + InMemoryProjectRepository                │
│                 + FileProjectRepository ← 真实文件          │
│                 SettingsStore 抽象                         │
│                 + InMemory / PrefsSettingsStore            │
├──────────────────────────────────────────────────────────┤
│ core/                基础设施                              │
│   constants/  theme/  settings/                            │
└──────────────────────────────────────────────────────────┘
                    ↕ MethodChannel `codepad/compiler`
┌──────────────────────────────────────────────────────────┐
│ android/…/NativeCompiler.kt   原生层：解压工具链、跑进程    │
│   ProcessBuilder(tcc -B … -I … -run source.c)              │
└──────────────────────────────────────────────────────────┘
```

依赖方向严格单向：`features → runtime → data → core`，`data` 从不 import `features`。
Phase 3 把模拟引擎换成真实引擎，`features/` 与 `data/` 没有任何结构性改动 —— 抽象起作用了。

## 2. 状态归属

| 状态 | 持有者 | 通知方式 |
|------|--------|----------|
| 主题模式、字号、行号开关 | `SettingsController` | `ChangeNotifier` + `ListenableBuilder` |
| 打开的文件、当前标签、控制台消息、运行状态、脏标记 | `EditorController` | 同上 |
| 工程列表 | `HomePage` 的 `Future` + `FutureBuilder` | `setState` 重新取数 |
| 文件文本内容 | `HighlightingTextEditingController`（每个文件一个，存在 `EditorController` 里） | 输入回调 |
| 工具链可用性 | `main.dart` 启动时 `probe()` 一次，随构造注入到 `RuntimeFactory` / 设置页 | 只读快照 |

刻意规避的三个坑：

1. **输入时不做全局 notify**：`EditorController.updateContent` 只在「干净 → 脏」的瞬间通知一次，
   否则每敲一个字符都会重建整页，平板输入法会被打断。
2. **构建期不产生副作用**：文本控制器在控制器构造时一次性建好，
   界面构建只做 `putIfAbsent` 兜底，避免 build 中改状态。
3. **高亮不重建控件**：高亮走 `TextEditingController.buildTextSpan` 的覆写，
   而不是给 TextField 套富文本，因此光标、选择、输入法组词（含下划线提示）行为不变。

## 3. 「点运行」的数据流（Phase 3 已接真实编译器）

```
EditorToolbar.onRun
  └─ EditorController.run()
       ├─ status = running，控制台追加「▶ 运行 main.c（C）」
       ├─ RuntimeFactory.create(language) → RuntimeEngine
       │    preferNative ? (C → NativeRuntimeEngine / 缺运行时 → UnavailableRuntimeEngine)
       │                  : StubRuntimeEngine
       ├─ engine.run(file, onOutput: _handleChunk, projectFiles: 工程内全部文件)
       │    ├─ 把工程文件写到 cache/run/<file>/  （#include "util.h" 因此可用）
       │    ├─ ToolchainGateway.run(sourcePath)
       │    │    └─ MethodChannel 'run' → Kotlin NativeCompiler
       │    │         ├─ ensureToolchain(): assets → filesDir/toolchain（一次）
       │    │         ├─ ProcessBuilder(nativeLibraryDir/libtcc.so,
       │    │         │      -B<tcc> -I<include> -I<include>/aarch64-linux-android,
       │    │         │      -run <source>).start()
       │    │         ├─ stdout/stderr 双线程逐行 → channel.invokeMethod('onOutput')
       │    │         └─ 返回 { exitCode, durationMs }
       │    ├─ onOutput('...')           每行立即进入控制台，边跑边看
       │    └─ 返回 RunResult            状态 + 退出码 + stdout/stderr + 耗时
       └─ 收尾：status = success/failed/cancelled，关闭引擎，notifyListeners
```

`cancelRun()` → `engine.cancel()` → 原生 `Process.destroy()`（tcc 的编译与运行在同一进程，
所以停止是「连编译带运行一起杀」，无法只停运行）。

`sendInput(line)` → `engine.writeInput()` → 原生写进进程 stdin，所以 `scanf` 能真的读到值；
`endInput()` → `engine.closeInput()` → 原生 `stdin.close()` 发 EOF，让输入循环收尾。
控制台底部的 `stdin` 输入行与 ⏹ 按钮就是它们的入口。

界面永远只认 `RunResult`，不关心引擎内部怎么终止 —— 这也是 Phase 3.5/4 换实现时 UI 不动的原因。

### 3.1 编译诊断：从「一堆英文」到「可点的位置」（0.3.1）

```
tcc stderr 行 "main.c:12: error: implicit declaration of function 'printf'"
  └─ CompileDiagnosticParser.parseLine()        runtime/compile_diagnostic.dart
       ├─ CompileDiagnostic{file, line, column, severity, message, hint}
       ├─ hintFor(message)：17 条关键字规则 → 中文说明
       └─ 交给 EditorController._handleChunk()
            ├─ 主行：ConsoleMessage(level: error, diagnostic: d)  → 可点击
            └─ 提示行：ConsoleMessage(level: hint, text: '　↳ …') → 橙色
点主行 → EditorController.jumpToDiagnostic(d)
       ├─ _matchFileIndex：先精确匹配路径，再退化到 basename（`util.c` → `lib/util.c`）
       ├─ controllerFor(目标文件).selection = collapsed(offsetForLine(text, line))
       └─ notifyListeners → 标签切过去、光标落在报错行
```

解析器与体检（`SourceLint`：全角标点）都是纯函数，不依赖 Flutter，因此可以直接单测；
`offsetForLine` 在 `core/text/line_offsets.dart`，同样纯函数。

### 3.2 多文件编译的取舍

`NativeRuntimeEngine._selectUnits()`：

1. 当前文件有 `main()` → 它当入口；
2. 当前文件没有、工程里恰好一个 `.c` 有 → 用那个（并提示）；
3. 其余不含 `main()` 的 `.c` 全部参与编译链接；
4. 多个 `main()` → 提前提示会重复定义，交给编译器给出准确报错。

`.h` 会落盘（供 `#include` 找到）但不参与编译；每次运行前清空工作目录，避免上一次的残留影响本次。


## 4. 持久化

### 4.1 磁盘布局

工程写在应用私有目录下（`getApplicationDocumentsDirectory()/CodePad/projects`），
真机上是 `/data/data/com.codepad.codepad/app_flutter/...`，卸载即清理，无需存储权限：

```
CodePad/projects/
  p-1720000000000000/
    meta.json             id / name / language / createdAt / updatedAt
    files/
      main.cpp
      lib/util.h         子目录结构原样保留
```

`FileProjectRepository.save()` 每次做三件事：写回有变化的文件、删除磁盘上已不存在的
文件（覆盖重命名与删除）、更新 `meta.json`。因此「重命名」在磁盘上表现为删旧建新，
不会留下孤儿文件。

### 4.2 自动保存

`EditorController` 内置防抖定时器：停止输入 900 ms 后调用 `repository.save()`，
成功后清掉脏标记（标题旁的小圆点）。新建 / 重命名 / 删除文件同样是「立即改内存状态 + 防抖落盘」。
传 `repository: null` 时退化为纯内存模式（单元测试用）。

### 4.3 设置

`SettingsStore` 抽象隔离平台插件，`PrefsSettingsStore` 用 shared_preferences 存在
`codepad.settings` 一个键里（`themeMode=dark|fontSize=14.0|lineNumbers=true`）。
插件不可用时 `main.dart` 自动回退到 `InMemorySettingsStore`，界面不报错。

### 4.4 运行期文件（Phase 3 新增，都在缓存目录，可随时清）

```
<filesDir>/toolchain/          解压后的 tcc 工具链（含 VERSION 标记，只解压一次）
  tcc/libtcc1.a  tcc/crt/  tcc/include/     tcc 自己的运行库与内部头
  include/…                                bionic 头文件（stdio.h 等，1416 个 .h）
<cacheDir>/run/<源文件名>/      每次运行前把工程文件写到这里
```

## 5. 语法高亮

```
lib/features/editor/highlight/
  code_token.dart             TokenKind + CodeToken(start, end, kind)
  code_tokenizer.dart         轻量 tokenizer（CLikeTokenizer / PythonTokenizer）
  code_palette.dart           深/浅两套配色（keyword / type / string / comment / number / function / preprocessor）
  highlighting_controller.dart 继承 TextEditingController，覆写 buildTextSpan
```

- **不解 AST**：逐字符扫描，识别注释（`//` `/* */` `#`）、字符串（含三引号与转义）、
  数字（含 `0x` / 浮点 / 后缀）、关键字、类型、`#include` 等预处理器行、以及「后面紧跟 `(` 的标识符」当函数名。
- **容错优先**：未闭合的字符串 / 注释、写到一半的代码都不会抛异常，颜色只是不完整。
- **性能**：token 结果按 `(语言, 全文)` 缓存，只有文本真正变化时才重新扫描；
  1000 行量级的文件重建开销可忽略。
- **不改控件**：仍是普通 TextField，所以光标、选择、滚动、输入法全部保持原生行为。

## 6. Phase 3 的四个关键取舍

| 问题 | 选择 | 理由 |
|------|------|------|
| 用哪个编译器 | Termux 的 **tcc**（370 KB） | 单文件、无运行时依赖；NDK 的 Windows 包**没有 arm64 宿主 clang**，搬不进 APK；Termux clang 要拖 65 MB 依赖 |
| 怎么跑起来 | `tcc -run`（内存编译 + 进程内执行） | targetSdk ≥ 29 禁止 `execve` 应用数据目录的文件；不产生产物文件就绕开限制 |
| 编译器放哪 | `jniLibs/arm64-v8a/libtcc.so` | `nativeLibraryDir` 下的文件可执行，与 targetSdk 无关；`packaging { jniLibs { useLegacyPackaging = true } }` 保证解压 |
| C++ 怎么办 | 暂时明确报错 | tcc 不支持 C++；等 Phase 3.5（内嵌 clang + 自写 `dlopen` 加载器） |

`RuntimeEngine` 契约（`language` / `isRunning` / `buildCommand` / `run(file, {onOutput, projectFiles})` /
`writeInput` / `cancel` / `dispose`）保持稳定；`ToolchainGateway` 是二道抽象，
让 `NativeRuntimeEngine` 的单元测试完全不碰 MethodChannel。

## 7. 已知限制（Phase 3 明确不做）

- **C++ / Python 还不能真跑**：`UnavailableRuntimeEngine` 明确说明原因，绝不伪造输出
- **多文件有限制**：一个工程只能有一个 `main()`；tcc 不做增量编译
- **输出块缓冲**：管道 + C 标准库默认块缓冲，`printf` 不带换行时可能延迟到结束才出现
- **无优化**：tcc 不优化代码，跑大循环比 gcc 慢
- **只有跳行，没有调试器**：没有断点 / 单步 / 变量监视（Phase 5）
- **中文提示靠关键字匹配**：没收录的报错只显示原文，不猜
- 无自动补全、无撤销重做（系统级撤销可用）、无搜索替换
- 大文件（> 5000 行）的全量 tokenize 尚未做增量优化
