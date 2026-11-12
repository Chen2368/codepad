# Phase 2 交付清单（可用版）

Phase 1 是「能看」的骨架：界面齐、状态机在、运行是模拟的、数据只在内存。
Phase 2 把它变成「能用来写作业」的版本：文件真落盘、设置记得住、代码有颜色、文件能增删改名。

## 一、这次做了什么

| # | 能力 | 实现位置 | 说明 |
|---|------|----------|------|
| 1 | 工程 / 文件真实持久化 | `lib/data/repositories/file_project_repository.dart` | 写入应用私有目录，`meta.json` + `files/` 目录树 |
| 2 | 设置持久化 | `lib/data/repositories/settings_store.dart`、`prefs_settings_store.dart` | 主题 / 字号 / 行号开关，重启后保持 |
| 3 | 语法高亮 | `lib/features/editor/highlight/` | C / C++ / Python，7 类记号，深浅两套配色 |
| 4 | 新建文件 | `EditorController.createFile` + 文件树「+」 | 支持 `lib/util.cpp` 这样的相对路径 |
| 5 | 重命名 / 移动文件 | `EditorController.renameFile` + 文件树「⋮」菜单 | 改名后语言随后缀自动切换，磁盘上删旧建新 |
| 6 | 删除文件 | `EditorController.deleteFile` + 确认弹窗 | 至少保留一个文件 |
| 7 | 自动保存 | `EditorController._persistSoon` | 停止输入 900 ms 后落盘，标题旁圆点表示脏 |
| 8 | 工程改名 | `EditorController.renameProject` | 点编辑器标题即可改名 |
| 9 | 首次启动示例 | `lib/main.dart` | 仓库为空时写入两个示例工程 |

## 二、新增 / 修改的文件

```
新增
  lib/data/repositories/file_project_repository.dart
  lib/data/repositories/settings_store.dart
  lib/data/repositories/prefs_settings_store.dart
  lib/features/editor/highlight/code_token.dart
  lib/features/editor/highlight/code_tokenizer.dart
  lib/features/editor/highlight/code_palette.dart
  lib/features/editor/highlight/highlighting_controller.dart
  lib/features/editor/widgets/file_name_dialog.dart
  test/highlight_test.dart
  test/file_repository_test.dart
  test/editor_file_ops_test.dart
  test/settings_persistence_test.dart
  docs/phase2-checklist.md

改写
  lib/main.dart                    装配真实仓库 + 回退策略
  lib/core/settings/settings_controller.dart   接 SettingsStore
  lib/features/editor/editor_controller.dart   文件增删改名 + 自动保存 + 高亮控制器
  lib/features/editor/editor_page.dart         菜单 / 弹窗 / 改名入口
  lib/features/editor/widgets/file_tree_panel.dart  「+」与「⋮」操作
  lib/core/constants/app_constants.dart        版本 0.2.0、阶段标签
  pubspec.yaml                     + path_provider、shared_preferences、path
  scripts/flutter-env.ps1          + JAVA_HOME / ANDROID_SDK_ROOT / platform-tools
  docs/architecture.md             持久化与高亮设计
  android/gradle/wrapper/gradle-wrapper.properties   腾讯云 gradle 镜像
  android/settings.gradle.kts + android/build.gradle.kts  阿里云 maven 镜像
  android/app/build.gradle.kts     项目内调试签名（codepad-debug.keystore）
  android/app/src/main/AndroidManifest.xml  应用名 CodePad
```

## 三、验证方式

```powershell
. E:\renwu\codepad\scripts\flutter-env.ps1
cd E:\renwu\codepad
flutter analyze          # 期望：No issues found!
flutter test             # 期望：33 个测试全部通过
flutter build apk --debug --target-platform android-arm64
flutter build apk --release --target-platform android-arm64
```

打包结果（实测）：

```
build\app\outputs\flutter-apk\app-debug.apk     78.9 MB
build\app\outputs\flutter-apk\app-release.apk   17.7 MB
已复制到 dist\CodePad-0.2.0-{debug,release}-arm64.apk
```

为了让 APK 真正构建出来，`android/` 里有 4 处必要改动（都是踩坑后的修复）：

| 文件 | 改动 | 原因 |
|------|------|------|
| `gradle/wrapper/gradle-wrapper.properties` | 换成腾讯云 gradle-9.3.1-bin.zip | 官方 services.gradle.org 直接超时 |
| `settings.gradle.kts` / `build.gradle.kts` | 阿里云 maven 排在 google()/mavenCentral() 前面 | 官方 maven 常超时 |
| `app/build.gradle.kts` | `signingConfigs.debug` 指向项目内 `codepad-debug.keystore` | AGP 默认读 `C:\Users\...\.android\debug.keystore`，不可写 |
| `src/main/AndroidManifest.xml` | `android:label="CodePad"` | 模板生成的小写 `codepad` 会显示在桌面上 |

真机上验证这四条：

1. 新建 `lib/a.cpp` → 退出应用重进 → 文件还在，内容也在（自动保存生效）。
2. 把 `main.cpp` 改名成 `app.cpp` → 标题旁语言标签不变，内容不丢。
3. 设置里改成浅色主题 + 字号 18 → 杀掉应用重开 → 仍是浅色、18 号。
4. C++ 文件里关键字紫色、注释灰色斜体、字符串绿色；Python 里 `def` 名称与 `print` 不同色。

## 四、刻意留下的坑（下一阶段处理）

- 运行结果仍是模拟的（`StubRuntimeEngine`），Phase 3 换成 NDK clang 真实编译 + `Process.run`。
- 没有撤销重做、搜索替换、自动补全 —— 平板上优先级低于「能编译能跑」。
- 多文件联合编译还没做：目前只编译当前文件。
- 高亮是全量重扫，5000 行以上文件会有轻微卡顿，届时改增量扫描。
