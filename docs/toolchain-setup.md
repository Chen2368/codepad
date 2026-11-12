# 工具链安装指南（全部落在 E:\renwu，不装 C 盘）

## 0. 关键前提：先确认平板的系统版本

| 系统 | 能否安装 Android APK | 结论 |
|------|----------------------|------|
| HarmonyOS 4.x / EMUI（鸿蒙 2、3、4） | 能 | Flutter 方案可行，按本指南走 |
| **HarmonyOS NEXT（纯血鸿蒙 5.0+）** | **不能**（已移除 AOSP 兼容层） | Flutter APK 装不上，需改走 ArkTS 原生或 PWA |

在平板「设置 → 关于本机」看版本号。若是 NEXT，请先确认，否则做出来的 APK 装不上。

## 1. 当前已就绪（本机实测）

| 组件 | 版本 | 位置 | 状态 |
|------|------|------|------|
| Flutter SDK | 3.47.9 / Dart 3.13.7 | `E:\renwu\toolchain\flutter-sdk` | ✅ |
| JDK | Temurin 17.0.21+9 | `E:\renwu\toolchain\jdk` | ✅ `JAVA_HOME` |
| Android SDK | platform-tools r37.0.3 | `...\android-sdk\platform-tools` | ✅ |
| Android 平台 | android-36、android-35 | `...\android-sdk\platforms\` | ✅ 两个都要（插件模块用 35 编译） |
| build-tools | 36.0.0 | `...\android-sdk\build-tools\36.0.0` | ✅ 含 aapt2 |
| NDK | 28.2.13676358（r28c，713 MB） | `...\android-sdk\ndk\28.2.13676358` | ✅ Flutter 的 Gradle 插件强制要求 |
| pub 包缓存 | — | `E:\renwu\toolchain\pub-cache` | ✅ |
| Gradle 缓存 | — | `E:\renwu\toolchain\gradle` | ✅ |
| 状态文件 / HOME / TEMP | — | `...\appdata` `...\home` `...\tmp` | ✅ |
| Git | 系统已有（`D:\Git`） | — | ✅ |

`flutter doctor` 现在的结论：

```
[√] Flutter (Channel stable, 3.47.9, on Microsoft Windows 10.0.22631, locale zh-CN)
[√] Android toolchain - develop for Android devices (Android SDK version 36.0.0)
    • Java binary at: E:\renwu\toolchain\jdk\bin\java  (Temurin-17.0.21+9)
[X] Visual Studio - develop Windows apps        ← 与移动端无关，可忽略
```

## 2. 一条命令搞定环境（推荐）

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
. E:\renwu\codepad\scripts\flutter-env.ps1
```

脚本会把下面这些变量全部指向 `E:\renwu\toolchain`：

```powershell
$env:TMP / $env:TEMP / $env:HOME / $env:APPDATA / $env:LOCALAPPDATA
$env:PUB_CACHE / $env:GRADLE_USER_HOME
$env:JAVA_HOME        = $toolchain\jdk
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME = $toolchain\android-sdk
$env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'
$env:PUB_HOSTED_URL           = 'https://pub.flutter-io.cn'
$env:Path += flutter-sdk\bin、jdk\bin、platform-tools
```

### 为什么必须重定向 APPDATA 和 TMP

Flutter 首次运行会做三件事，默认都写到 C 盘：

1. 编译 flutter_tool 快照 → 需要可写的**临时目录**（`TMP`）。
   权限受限时报 `Creation of temporary directory failed ... OS Error: 拒绝访问 (errno = 5)`。
2. 写工具状态 `%APPDATA%\.flutter_tool_state`。
   写不了就报 `Unable to create dart snapshot for flutter tool`，并无限重试。
3. 解析 pub 依赖到 `%LOCALAPPDATA%\Pub\Cache`（由 `PUB_CACHE` 接管）。

三个都被重定向后，整套流程不再碰 C 盘。

## 3. 下载源（重装时参考，均为本次实测）

| 用途 | 地址 | 实测速度 |
|------|------|----------|
| Flutter SDK | `https://storage.flutter-io.cn/flutter_infra_release/releases/stable/windows/flutter_windows_3.47.9-stable.zip` | ~1.7 MB/s |
| 腾讯云备用 | `https://mirrors.cloud.tencent.com/flutter/...` | ~1.5 MB/s |
| 官方（不推荐） | `https://storage.googleapis.com/flutter_infra_release/...` | ~60 KB/s |
| JDK 17 | `https://mirrors.tuna.tsinghua.edu.cn/Adoptium/17/jdk/x64/windows/OpenJDK17U-jdk_x64_windows_hotspot_17.0.21_9.zip` | 快 |
| Android 各组件 | `https://dl.google.com/android/repository/...` | ~2.8 MB/s（NDK 实测 ~11 MB/s） |
| **Gradle 发行包** | `https://mirrors.cloud.tencent.com/gradle/gradle-9.3.1-bin.zip` | 官方源**超时**，必须用镜像 |
| Maven 依赖 | `https://maven.aliyun.com/repository/{google,public,gradle-plugin}` | 官方源常超时 |

`android/gradle/wrapper/gradle-wrapper.properties` 与 `android/settings.gradle.kts`、
`android/build.gradle.kts` 里已经把镜像排在官方源前面，重装时不用再改。

## 4. Android SDK 的正确装法（踩过的坑）

**坑 1：`sdkmanager` 下载不到清单。** 本机 Java 侧访问 `dl.google.com` 的
repository 清单会失败（`Warning: Failed to download any source lists!` /
`IO exception while downloading manifest`），但 PowerShell / 浏览器下载正常。
所以不要指望 `sdkmanager "platform-tools"`，直接下官方 zip 解压：

```powershell
# 先从清单里查真实文件名（文件名和版本号不一定同名）
$x = [xml](Invoke-WebRequest 'https://dl.google.com/android/repository/repository2-3.xml' -UseBasicParsing).Content
$base = 'https://dl.google.com/android/repository/'

# 包路径 → 实际 zip 名（本次实测）
#   platform-tools          → platform-tools_r37.0.3-win.zip         → <sdk>\platform-tools
#   platforms;android-36    → platform-36_r02.zip                    → <sdk>\platforms\android-36
#   platforms;android-35    → platform-35_r02.zip                    → <sdk>\platforms\android-35
#   build-tools;36.0.0      → build-tools_r36_windows.zip            → <sdk>\build-tools\36.0.0
#   ndk;28.2.13676358       → android-ndk-r28c-windows.zip           → <sdk>\ndk\28.2.13676358
```

**坑 2：`build-tools_r36_windows.zip` 里多套了一层 `android-16/`。** 解压后要把它里面的
文件**上移到版本目录**，否则 Gradle 找不到 `aapt2.exe`：

```powershell
$bt = 'E:\renwu\toolchain\android-sdk\build-tools\36.0.0'
Get-ChildItem "$bt\android-16" -Force | Move-Item -Destination $bt -Force
Remove-Item "$bt\android-16" -Recurse -Force
```

**坑 3：NDK 省不掉。** Flutter 的 Gradle 插件会强制校验 `flutter.ndkVersion`
（3.47 是 `28.2.13676358`），删掉 `app/build.gradle.kts` 里的 `ndkVersion` 行也没用，
报错依旧是 `NDK not configured. Preferred NDK version is '28.2.13676358'`。
必须装，713 MB，本机 1 分钟下完。

**坑 4：`platforms;android-35` 也要装。** 插件里的 `:jni` 子模块用 35 编译，
只装 36 会报 `Failed to find Platform SDK with path: platforms;android-35`。

**坑 5：licenses 目录可以没有。** 组件是手工解压进去的，Gradle 不需要下载任何缺失组件，
就不会触发 license 校验，`<sdk>\licenses\` 为空也能正常打包。

## 5. 打包与验证

```powershell
. E:\renwu\codepad\scripts\flutter-env.ps1
cd E:\renwu\codepad
flutter pub get
flutter analyze                 # No issues found!
flutter test                    # All tests passed!
flutter build apk --debug       # 产物 build\app\outputs\flutter-apk\app-debug.apk
```

### 内置 C 工具链（只有换 tcc / sysroot 版本时才需要）

```powershell
# 从 Termux 仓库重新抓取并组装 assets/toolchain 与 jniLibs/libtcc.so
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\fetch-toolchain.ps1
```

⚠️ **裁剪 bionic 头文件前务必确认引用关系**。0.3.2 的「所有 C 程序都报
`include file 'android/versioning.h' not found`」就是裁剪的后果：

| 被保留的头文件 | 硬依赖 |
|---|---|
| `sys/cdefs.h`（所有头文件都引它） | `android/versioning.h`、`android/api-level.h`、`android/ndk-version.h` |
| `termios.h` / `unistd.h` / `threads.h` | `android/legacy_termios_inlines.h` 等 |
| `AMidi.h` / `kfd_ioctl.h` | `media/NdkMediaError.h` / `drm/drm.h` |

所以现在只裁 `c++`（12.6 MB，C 用不上）与 `camera`（788 KB）；脚本里加了
「被 `#include <dir/…>` 引用却不存在的目录就直接失败」的检查，不会再悄悄产出坏包。
改了工具链内容要同步改 `NativeCompiler.kt` 里的 `TOOLCHAIN_VERSION`，否则手机上不会重新解压。

装到平板：

```powershell
# 方式一：USB 直装
adb install -r dist\CodePad-0.3.3-release-arm64.apk

# 方式二：把 apk 拷到平板，用文件管理器点开安装（需允许「安装未知来源应用」）
```

## 6. 已知的环境噪声

- `Command exited with code 128: fetch --tags ... Recv failure: Connection was reset`
  —— 想访问 GitHub 拿版本标签失败，镜像下载的 SDK 没有 `.git`，**不影响**本地开发（`flutter upgrade` 不可用）。
- `flutter.bat : Flutter assets will be downloaded from https://storage.flutter-io.cn ...`
  —— PowerShell 把它记成 `NativeCommandError` 红字，退出码仍是 0。
- `flutter test` 输出末尾出现 `exit code: 1` 但正文是 `All tests passed!`
  —— 同样是上面那条 stderr 造成的假象，以正文为准。
- 首次构建 Gradle 要下 131 MB 发行包 + 若干 AAR，之后走缓存，二次构建约 1 分钟。

## 7. 平板侧准备

1. 设置 → 关于本机 → 连续点「版本号」7 次开启开发者模式
2. 设置 → 系统和更新 → 开发人员选项 → 打开「USB 调试」
3. USB 连电脑，平板上点「允许调试」
4. `flutter devices` 看到设备后 `flutter run -d <id>`，或用上面 `adb install`
