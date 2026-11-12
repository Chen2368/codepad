# 一键推送到 GitHub（首次或后续都可用）
#
# 用法:
#   .\scripts\publish.ps1 -RepoUrl https://github.com/你的账号/codepad.git
#   .\scripts\publish.ps1 -RepoUrl https://github.com/你的账号/codepad.git -DryRun   # 只演练不推送
#
# 需要：本机已装 git，且已在 GitHub 上建好空仓库（不要勾选 README/License）。
# 认证：HTTPS 方式下 GitHub 不接受密码，必须用 Personal Access Token 当密码，
#       或者提前用 `gh auth login` / Git Credential Manager 登录一次。

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$RepoUrl,
  [string]$Branch = 'main',
  [string]$CommitMessage = '',
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
Set-Location $projectRoot

function Step($n, $text) { Write-Host "`n[$n] $text" -ForegroundColor Cyan }
function Ok($text) { Write-Host "    ✔ $text" -ForegroundColor Green }
function Warn($text) { Write-Host "    ! $text" -ForegroundColor Yellow }

# 0. 前置检查
Step 0 '检查环境'
if (-not (Test-Path (Join-Path $projectRoot '.git'))) {
  throw "这里不是 git 仓库：$projectRoot（先运行 git init）"
}
if ($RepoUrl -notmatch '^https://github\.com/.+/.+(\.git)?$' -and $RepoUrl -notmatch '^git@github\.com:.+/.+(\.git)?$') {
  Warn "地址看起来不像 GitHub 仓库：$RepoUrl（继续，但请确认没写错）"
}
$name = git config user.name
$email = git config user.email
if ($name -eq 'CodePad' -or $email -eq 'codepad@example.com') {
  Warn "git 身份还是占位值（$name <$email>），建议先改成你自己的："
  Write-Host "      git config user.name  `"你的名字`""
  Write-Host "      git config user.email `"你的邮箱`""
}
Ok "仓库：$projectRoot"

# 1. 确认没有误提交生成物
Step 1 '检查是否有不该提交的东西'
$bad = git ls-files | Select-String -Pattern 'assets/toolchain|\.apk$|\.so$|libtcc|^build/|\.dart_tool|keystore'
if ($bad) {
  Write-Host '    以下文件已被跟踪，但它们不该进仓库：' -ForegroundColor Red
  $bad | ForEach-Object { "      $($_.Line)" }
  throw '请先从 git 移除（git rm --cached <路径>）再发布'
}
Ok "没有二进制 / 生成物 / 密钥（跟踪文件 $((git ls-files).Count) 个）"

# 2. 提交本地改动（如果有）
Step 2 '提交本地改动'
$pending = git status --porcelain
if ($pending) {
  if ([string]::IsNullOrWhiteSpace($CommitMessage)) {
    $CommitMessage = "更新：$(Get-Date -Format 'yyyy-MM-dd HH:mm')"
  }
  Write-Host "    待提交：$((($pending -split "`n").Count)) 个文件"
  if ($DryRun) {
    Warn "演练模式：不提交（实际会执行 git add -A && git commit -m `"$CommitMessage`"）"
  } else {
    git add -A
    git commit -q -m $CommitMessage
    Ok "已提交：$CommitMessage"
  }
} else {
  Ok '工作区干净，无需提交'
}

# 3. 配置远程
Step 3 '配置远程 origin'
$remotes = @(git remote)
$existing = if ($remotes -contains 'origin') { (git remote get-url origin) } else { '' }
if ($existing) {
  if ($existing -ne $RepoUrl) {
    Warn "已有 origin = $existing，将改为 $RepoUrl"
    if ($DryRun) {
      Warn "演练模式：不修改 remote"
    } else {
      git remote set-url origin $RepoUrl
      Ok "origin 已更新"
    }
  } else {
    Ok "origin 已指向 $RepoUrl"
  }
} else {
  if ($DryRun) {
    Warn "演练模式：不添加 remote（实际会执行 git remote add origin $RepoUrl）"
  } else {
    git remote add origin $RepoUrl
    Ok "已添加 origin = $RepoUrl"
  }
}

# 4. 推送
Step 4 "推送到 origin/$Branch"
if ($DryRun) {
  Warn '演练模式：不执行推送。实际会运行：'
  Write-Host "      git push -u origin $Branch"
} else {
  git push -u origin $Branch
  Ok "已推送。仓库地址：$($RepoUrl -replace '\.git$','')"
}

# 5. 后续步骤提示
Step 5 '接下来（发版）'
$ver = (Select-String -Path (Join-Path $projectRoot 'pubspec.yaml') -Pattern '^version:\s*(\S+)').Matches.Groups[1].Value
Write-Host @"
    1) 打开 https://github.com/<你的账号>/<仓库名>/releases/new
    2) Tag 填 v$($ver.Split('+')[0])，标题写这个版本的主要变化
    3) 上传 dist\CodePad-$($ver.Split('+')[0])-release-arm64.apk
    4) 说明里注明「仅支持 arm64」，并附 THIRD_PARTY_NOTICES.md 的要点

    以后更新代码：git add -A && git commit -m "..." && git push
"@ -ForegroundColor DarkGray
