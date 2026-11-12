# Phase 1 交付清单

## 一、源码骨架（全部完成）

- [x] `pubspec.yaml`（零第三方依赖）、`analysis_options.yaml`、`.gitignore`
- [x] `lib/main.dart` / `lib/app.dart` 入口与根组件
- [x] `core/`：常量、Material 3 深/浅色主题、等宽字体、`SettingsController`
- [x] `data/models/`：`ProgramLanguage`、`SourceFile`、`Project`、`RunResult`、`ConsoleMessage`
- [x] `data/repositories/`：`ProjectRepository` 抽象 + `InMemoryProjectRepository`
- [x] `runtime/`：`RuntimeEngine` 抽象、`StubRuntimeEngine`、`RuntimeFactory`
- [x] `features/home/`：工程列表、新建对话框（语言选择 + Hello World 模板）、删除确认
- [x] `features/editor/`：`EditorController`、`EditorPage`、工具栏、文件标签、行号编辑器、控制台
- [x] `features/settings/`：主题模式、字号、行号开关、关于信息
- [x] `features/templates/`：C / C++ / Python 模板与两个示例工程
- [x] `widgets/app_empty_state.dart`：空状态 / 错误状态组件
- [x] 宽窄屏自适应（断点 840）：≥840 常驻文件树，<840 收进抽屉
- [x] 运行状态机 + 流式控制台 + 可取消
- [x] `test/smoke_test.dart`：6 个测试
- [x] `android/` 平台目录（含 gradlew、MainActivity.kt、local.properties 指向工作区 SDK）
- [x] `scripts/flutter-env.ps1`：一键把 SDK / 缓存 / 临时目录指向工作区

## 二、本机实测结论

| 检查项 | 命令 | 结果 |
|--------|------|------|
| 依赖解析 | `flutter pub get` | ✅ 通过（27 个依赖） |
| 静态分析 | `flutter analyze` | ✅ **No issues found!** |
| 单元 / Widget 测试 | `flutter test` | ✅ **6 passed** |
| 运行链路 | 测试「进入编辑器并点运行」 | ✅ 状态机 → 运行成功，控制台输出收尾消息 |
| 平板宽屏布局 | 测试「1280x800 下文件树常驻」 | ✅ 资源管理器可见 |
| APK 构建 | `flutter build apk` | ⛔ 未验证：缺 JDK 17 + Android SDK |
| 真机安装 | `flutter run -d <id>` | ⛔ 未验证：无连接设备 |

测试清单：

```
✓ 模型层 按文件名后缀识别语言
✓ 模型层 SourceFile 能拆出目录与文件名
✓ 模型层 内存仓库按更新时间倒序返回工程
✓ 界面骨架 首页渲染示例工程列表
✓ 界面骨架 进入编辑器并点运行，控制台给出模拟结果
✓ 界面骨架 平板横屏宽度下左侧文件树常驻
```

## 三、踩过的坑（记录，避免重复）

1. **官方 CDN 在本地只有 ~60 KB/s**，1.85 GB 的 SDK 包要十几小时；换 `storage.flutter-io.cn` 镜像后 ~1.7 MB/s。
2. **`flutter` 会往 `%APPDATA%\.flutter_tool_state` 写状态**，权限受限时直接报 `Unable to create dart snapshot`；把 `APPDATA`、`TMP/TEMP`、`HOME` 一起重定向到工作区即可（`scripts/flutter-env.ps1` 已封装）。
3. **`Set-Content` 在 PowerShell 5.1 默认按 ANSI 写盘**，会把中文注释写坏；批量改文件要用 `-Encoding UTF8`，或直接用编辑工具。
4. **Windows 默认执行策略会拦截 `.ps1`**：需先 `Set-ExecutionPolicy -Scope Process Bypass`。

## 四、下一步（Phase 2 建议顺序）

1. `path_provider`：工程落盘到应用私有目录，重启后恢复
2. `shared_preferences`：主题 / 字号 / 行号持久化
3. 语法高亮（C/C++/Python）
4. 文件树的新建 / 重命名 / 删除
5. 搜索替换 + 撤销重做
6. 再往 Phase 3 接真实编译器
