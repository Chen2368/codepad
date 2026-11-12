# 从源码构建

本文假设你已经装好 **Flutter（3.24+）**、**Android SDK（platform 33+ / build-tools 34+）**、
**JDK 17**，并且 `flutter doctor` 的 Android 一项是绿的。

> 仓库里**不含** C 编译器与 bionic 头文件（体积大、且属于第三方二进制），
> 需要跑一次脚本在本机生成。这是唯一一个额外步骤。

## 1. 取代码

```bash
git clone https://github.com/<你的账号>/codepad.git
cd codepad
flutter pub get
```

## 2. 组装内置 C 工具链（只需一次）

```powershell
# Windows（PowerShell 5.1 或 7 都可以）
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\fetch-toolchain.ps1
```

```bash
# macOS / Linux：用 pwsh
pwsh -NoProfile -File ./scripts/fetch-toolchain.ps1
```

脚本会：

1. 从 Termux 官方源下载 `tcc` 与 `ndk-sysroot` 两个 `.deb`；
2. 解包并把编译器放进 `android/app/src/main/jniLibs/arm64-v8a/libtcc.so`；
3. 把 bionic 头文件裁剪后放进 `android/app/src/main/assets/toolchain/`（只保留 C 需要的，去掉 C++/camera）；
4. 复制 `android/compat-headers/`（我们写的 tcc 兼容垫片）到 `assets/toolchain/compat/`；
5. 给每个头文件补 include guard（tcc 的 `#pragma once` 对 `<...>` 无效）。

完成后会打印 `工具链就绪 … 1527 个头文件`。中间产物留在脚本同级的临时目录，可随时删。

> 脚本默认把缓存放在仓库**上一级**的 `toolchain/` 目录（Windows 上是为了避开 C 盘）。
> 想换位置：设置环境变量 `CODEPAD_TOOLCHAIN_DIR`，或直接改脚本顶部的 `$toolchain`。

## 3. 跑测试

```bash
flutter analyze
flutter test          # 167 个用例
```

## 4. 构建 APK

```bash
flutter build apk --release --target-platform android-arm64
# 产物：build/app/outputs/flutter-apk/app-release.apk
```

只支持 **arm64-v8a**（内置的 tcc 是 aarch64 版）。x86 模拟器上能启动界面，
但「运行 C」会提示编译器不可用。

## 5. 真机自检（强烈建议）

装到设备后：**设置 → 编译器 → 运行编译器自检**，应看到 **7 项全绿**：

```
shim      → shim=on
hello     → OK-HELLO
format    → 42 3.14 abc
math      → sqrt2=1.41421
loop      → sum=5050
multi     → add=7
headers   → headers=65,6,7
```

任一项红，点弹窗右上角「复制全部」把报告发出来 —— 报告里带完整命令行和原始报错。

## 开发者工具（可选）

| 脚本 | 作用 |
|---|---|
| `scripts/acceptance-test.ps1` | 用真实 tcc 跑「App 会发的命令」，7 个用例 / 8 项断言 |
| `scripts/c-coverage-test.ps1` | C 标准库覆盖矩阵：44 个头逐个编译 + 18 组函数实测 |

两个脚本都需要**本机有一份 Windows 版 tcc 0.9.27**（与真机同源码），
用环境变量指过去即可：

```powershell
$env:CODEPAD_TCC_WIN = 'D:\tools\tcc-win\cc\tcc.exe'
```

没设置时默认找 `E:\renwu\toolchain\tcc-win\cc\tcc.exe`（原作者的位置）。
脚本的临时产物写在仓库的 `build/` 下，已被 git 忽略。

## 常见问题

**`libtcc1.a not found`** —— 先跑第 2 步；确认 `android/app/src/main/assets/toolchain/tcc/libtcc1.a` 存在。

**`include file 'stdarg.h' not found`** —— 同上，说明工具链没解压全；重跑脚本即可。

**`undefined symbol 'f'`** —— 你的工程里 `f()` 定义在别的 `.c`，但那文件没参与编译。
1.0.0 起会自动带上它重试；若仍失败，控制台会明确告诉你是哪种情况（见正文说明）。
