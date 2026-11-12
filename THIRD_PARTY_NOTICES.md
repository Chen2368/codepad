# 第三方组件与许可证

本仓库**代码**以 MIT 许可发布（见 [LICENSE](LICENSE)）。
仓库里**不包含第三方二进制**：C 编译器与头文件通过 `scripts/fetch-toolchain.ps1`
在使用者本地下载、解包、裁剪后放进 `android/app/src/main/assets/toolchain/`（该目录已被 git 忽略）。
构建出的 APK 里会包含这些组件，因此分发 APK 时请遵守下列许可。

| 组件 | 用途 | 许可证 | 来源 |
|---|---|---|---|
| **TinyCC (tcc) 0.9.27** | APK 内置的 C 编译器（`libtcc.so`） | **LGPL-2.1** | [Termux 软件源](https://packages.termux.dev/apt/termux-main/pool/main/t/tcc/) 的 `tcc_1:0.9.27-p20230415-2_aarch64.deb`；上游 <https://bellard.org/tcc/> |
| **ndk-sysroot 30**（bionic 头文件） | 提供 `stdio.h`、`stdlib.h` 等 Android 系统头 | **Apache-2.0**（AOSP 头文件另有 BSD 条款） | Termux 的 `ndk-sysroot_30_aarch64.deb`；头文件源自 Android NDK / AOSP bionic |
| **Flutter SDK / Flutter Engine** | UI 框架与运行时 | BSD-3-Clause | <https://github.com/flutter/flutter> |
| **path_provider / shared_preferences 等** | Flutter 官方插件 | BSD-3-Clause | pub.dev |

## LGPL-2.1 的实际含义（给分发者）

tcc 是 LGPL-2.1。以「可替换的独立程序」形式随应用分发（本项目的做法：把 tcc 作为
独立的 `libtcc.so` 可执行体，通过 `ProcessBuilder` 调用，应用与编译器之间只有命令行交互），
通常被视为**动态链接/独立进程**使用，因此：

1. 需要保留版权与许可声明（本文件 + tcc 源码内的声明）；
2. 需要说明如何获取 tcc 的完整源码（上游 bellard.org 或 Termux 的构建配方）；
3. 需要允许用户用修改过的 tcc 替换它 —— 本项目的编译器路径是按构建产物固定的，
   若要满足该点，可在自己的分支里替换 `android/app/src/main/jniLibs/arm64-v8a/libtcc.so` 后重新打包。

> 以上只是项目维护者的理解，不构成法律意见。正式发布前建议按你所在地区的规则复核，
> 或在仓库里同时提供 tcc 的源码链接与构建脚本说明。

## 我（使用者）需要注意的

- 本仓库**不含** `assets/toolchain/`、`libtcc.so`、任何 APK；这些都需要本地生成。
- 若要分发自己构建的 APK，请一并附上本文件（或等价的许可说明）。
