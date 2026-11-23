# 固定的构建输入（第三方 .deb）

这两个包是 `scripts/fetch-toolchain.ps1` 组装的来源，**故意提交进仓库**：

| 文件 | 内容 | 大小 | 许可证 |
|---|---|---|---|
| `tcc_0.9.27-p20230415-2_aarch64.deb` | TinyCC 编译器（aarch64，Termux 构建） | 0.24 MB | LGPL-2.1 |
| `ndk-sysroot_30_aarch64.deb` | Android NDK r30 的 bionic 头文件（sysroot 子集） | 1.90 MB | Apache-2.0 |

## 为什么要放进仓库

1. **可复现**：APK 里到底用的是哪个编译器版本，写在仓库里，谁 clone 都能装出一模一样的工具链；
2. **上游会删包**：2026-11 起 Termux 已把 tcc 升到 `0.9.28~p20261118`，并且把包结构改成了
   `bin/tcc`（20 KB 启动器）+ `lib/libtcc.so`（真正的编译器）；原来 `0.9.27` 的地址直接 404，
   CI 和新机器全都装不出来（这是本项目 1.0.1 期间发现的问题）；
3. **不盲升级**：开发者手上只有 Windows 版 0.9.27 可以用来验证命令与头文件行为，
   换成 0.9.28 等于「看不见的改动直接发给用户」。等有人在真机上验证过 0.9.28，
   再按新结构改脚本、改 `TOOLCHAIN_VERSION`，而不是被动跟着上游走。

## 升级步骤（将来）

1. 下载新版 tcc 的 deb，解包确认结构（0.9.28 起 `bin/tcc` 只是启动器，编译器在 `lib/libtcc.so`）；
2. 若结构变了，`scripts/fetch-toolchain.ps1` 里复制那一段要跟着改；
3. 在**真机**上跑一遍「设置 → 编译器 → 运行编译器自检」（7 项全绿）与
   `scripts/c-coverage-test.ps1`（44 头 × 18 组）；
4. 改 `NativeCompiler.kt` 的 `TOOLCHAIN_VERSION`（例如 `-android-8`），否则老用户不会重新解压；
5. 把新 deb 放进本目录，删掉旧的。

## 许可

两个包都是**原样分发、未修改**。本项目代码是 MIT；分发 APK 时的第三方声明见仓库根目录
`THIRD_PARTY_NOTICES.md`（tcc 为 LGPL-2.1，bionic 头文件为 Apache-2.0）。