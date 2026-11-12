# 发布到 GitHub

## 0. 先确认要提交什么

`.gitignore` 已经排除了这些东西，它们**不应该**进仓库：

| 不提交 | 原因 |
|---|---|
| `build/`、`.dart_tool/` | Flutter 构建缓存（本项目约 4 GB） |
| `dist/*.apk` | 二进制产物，走 GitHub Releases |
| `android/app/src/main/assets/toolchain/` | 由脚本生成（6.8 MB、1527 个头文件） |
| `android/app/src/main/jniLibs/.../libtcc.so` | 第三方编译器二进制（370 KB） |
| `.idea/`、`*.iml` | IDE 私有配置 |
| 根目录的 `fn_*.exe` | 调试残留（已清理） |

提交后仓库大小应在 **1 MB 上下**（源码 + 文档 + 脚本）。可先用这条检查：

```powershell
git add -A
git status --short
# 若看到 assets/toolchain 或 *.apk 出现在列表里，说明 .gitignore 没生效，不要急着 commit
```

## 1. 初始化并提交

在 `codepad/` 目录下：

```bash
git init
git branch -M main
git config user.name  "你的名字"
git config user.email "你的邮箱"

git add -A
git commit -m "CodePad 1.0.0: 平板上的 C 语言 IDE（内置 tcc，真编译真运行）"
```

## 2. 在 GitHub 建仓库

网页方式：<https://github.com/new> → 填名字（例如 `codepad`）→ **不要**勾选
“Add a README / .gitignore / license”（本地已经有了）→ Create。

命令行方式（需先装 `gh` 并登录）：

```bash
gh repo create codepad --public --source=. --remote=origin --push
```

## 3. 推上去

```bash
git remote add origin https://github.com/<你的账号>/codepad.git
git push -u origin main
```

如果本机没配好 SSH/凭据，GitHub 现在要求用 **Personal Access Token** 当密码，
或走 `gh auth login` / GitHub Desktop。

## 4. 把 APK 作为 Release 发布（推荐做法）

不要把 APK 提交进仓库，而是上传到 Releases：

```bash
gh release create v1.0.0 \
  dist/CodePad-1.0.0-release-arm64.apk \
  --title "CodePad 1.0.0 — C 语言支持定稿" \
  --notes "C 标准库覆盖 43/44 头；链接失败自动补救；自检 7 项。"
```

网页方式：仓库 → **Releases → Draft a new release** → Tag `v1.0.0` →
上传 `CodePad-1.0.0-release-arm64.apk` → Publish。

## 5. 发布前自查清单

- [ ] `git status` 里没有 `assets/toolchain/`、`*.apk`、`build/`
- [ ] README 里的「构建步骤」指向 `docs/build-from-source.md`，而不是本机路径
- [ ] `LICENSE` 与 `THIRD_PARTY_NOTICES.md` 都在（tcc 是 LGPL-2.1，分发 APK 时需要）
- [ ] CI 能通过（`.github/workflows/ci.yml`：analyze + test）
- [ ] Release 里附上 APK，并在说明里写清「只支持 arm64」

## 6. 后续维护

- 改完代码：`git commit -am "..."` → `git push`
- 发新版本：改 `pubspec.yaml` 与 `lib/core/constants/app_constants.dart` 的版本号 →
  构建 → `gh release create vX.Y.Z ...`
- 工具链变更（例如 Termux 更新了 tcc）：把 `NativeCompiler.kt` 里的
  `TOOLCHAIN_VERSION` 加一，确保老用户会重新解压（否则手机上还用旧头文件）。
