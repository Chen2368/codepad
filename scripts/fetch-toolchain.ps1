# 用法（PowerShell）：
#     .\scripts\fetch-toolchain.ps1            # 重新抓取并组装内置 C 工具链
#     .\scripts\fetch-toolchain.ps1 -KeepDeb   # 保留下载的 .deb（默认也保留在 toolchain\tmp）
#
# 作用：从 Termux 官方仓库抓两个包，组装成 Phase 3 需要的样子：
#   android\app\src\main\jniLibs\arm64-v8a\libtcc.so     ← tcc 编译器本体（装后位于 nativeLibraryDir，可执行）
#   android\app\src\main\assets\toolchain\tcc\           ← libtcc1.a + crt*.o + tcc 内部头
#   android\app\src\main\assets\toolchain\include\       ← bionic 头文件（stdio.h 等，只裁掉 C++ 与 camera）
#
# 注意：裁剪必须谨慎！bionic 的 sys\cdefs.h 会 #include <android/versioning.h>，
# termios.h / unistd.h / threads.h 会 #include <android/legacy_*_inlines.h>，
# AMidi.h 引用 <media/...>、kfd_ioctl.h 引用 <drm/...>。
# 0.3.2 就是因为把 android\ 一起裁掉，导致所有 C 程序都报
#   "include file 'android/versioning.h' not found"
# 所以下面第 4 步加了「被引用却被裁掉」的自动检查，脚本会直接失败而不是产出坏包。
#
# 依赖：Windows 自带的 curl.exe 与 tar.exe（bsdtar），无需 WSL / 7z。
# 说明：这是可重复的「构建输入」，正常改代码不需要跑它；只有想升级 tcc 或换 sysroot 版本时才需要。

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path $PSScriptRoot -Parent
$workspace   = Split-Path $projectRoot -Parent
$tmp         = Join-Path $workspace 'toolchain\tmp'
$assets      = Join-Path $projectRoot 'android\app\src\main\assets\toolchain'
$jniDir      = Join-Path $projectRoot 'android\app\src\main\jniLibs\arm64-v8a'

# Termux 的包版本；升级时改这里
$tccDeb  = 'https://packages.termux.dev/apt/termux-main/pool/main/t/tcc/tcc_1%3A0.9.27-p20230415-2_aarch64.deb'
$sysDeb  = 'https://packages.termux.dev/apt/termux-main/pool/main/n/ndk-sysroot/ndk-sysroot_30_aarch64.deb'

function Get-Deb([string]$url, [string]$target) {
  if (Test-Path $target) {
    Write-Host "[skip] 已存在 $target" -ForegroundColor DarkGray
    return
  }
  Write-Host "[get ] $url" -ForegroundColor Cyan
  & curl.exe -L --retry 3 --connect-timeout 20 --max-time 300 -o $target $url --silent --show-error
  if ($LASTEXITCODE -ne 0) { throw "下载失败：$url" }
}

function Expand-Deb([string]$deb, [string]$outDir) {
  if (Test-Path $outDir) { Remove-Item $outDir -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $outDir | Out-Null
  Push-Location $outDir
  try {
    & tar.exe -xf $deb            # data.tar.xz + control.tar.*
    & tar.exe -xf data.tar.xz     # 解出 data\data\com.termux\files\usr\...
  } finally {
    Pop-Location
  }
}

New-Item -ItemType Directory -Force -Path $tmp, $assets, $jniDir | Out-Null

$tccPath = Join-Path $tmp 'tcc.deb'
$sysPath = Join-Path $tmp 'ndk-sysroot.deb'
Get-Deb $tccDeb $tccPath
Get-Deb $sysDeb $sysPath

Expand-Deb $tccPath (Join-Path $tmp 'ex-tcc')
Expand-Deb $sysPath (Join-Path $tmp 'ex-sysroot')

$tccUsr = Join-Path $tmp 'ex-tcc\data\data\com.termux\files\usr'
$sysUsr = Join-Path $tmp 'ex-sysroot\data\data\com.termux\files\usr'

# 1) 编译器本体：放进 jniLibs，名字必须是 .so 才会被 AGP 打进 lib/<abi>/
Copy-Item (Join-Path $tccUsr 'bin\tcc') (Join-Path $jniDir 'libtcc.so') -Force

# 2) tcc 运行库
if (Test-Path $assets) { Remove-Item $assets -Recurse -Force }
New-Item -ItemType Directory -Force -Path (Join-Path $assets 'tcc') | Out-Null
Copy-Item (Join-Path $tccUsr 'lib\tcc\*') (Join-Path $assets 'tcc') -Recurse -Force

# 3) bionic 头文件。
#    只裁 c++（libc++，12.6 MB，C 用不上；C++ 阶段由 clang 自带）与 camera（788 KB，数学课用不到）。
#    android / media / drm 必须保留：被 sys\cdefs.h、termios.h、unistd.h、threads.h、AMidi.h、kfd_ioctl.h 引用。
New-Item -ItemType Directory -Force -Path (Join-Path $assets 'include') | Out-Null
Copy-Item (Join-Path $sysUsr 'include\*') (Join-Path $assets 'include') -Recurse -Force
$prunedDirs = @('c++', 'camera')
foreach ($drop in $prunedDirs) {
  $p = Join-Path $assets "include\$drop"
  if (Test-Path $p) { Remove-Item $p -Recurse -Force }
}

# 3b) tcc 兼容垫片：用自己的 sys\cdefs.h 顶掉 bionic 的，把 _Nonnull / __RENAME /
#     __attribute__((__availability__(…))) / __has_include 这些 clang 专有词汇抹平。
#     源文件在 android\compat-headers\（不在 assets 下，避免被 android 资源打包规则误处理）。
$compatSrc = Join-Path $projectRoot 'android\compat-headers'
$compatDst = Join-Path $assets 'compat'
if (Test-Path $compatDst) { Remove-Item $compatDst -Recurse -Force }
Copy-Item $compatSrc $compatDst -Recurse -Force
if (-not (Test-Path (Join-Path $compatDst 'sys\cdefs.h'))) {
  throw "兼容垫片没复制成功：$compatDst\sys\cdefs.h"
}

# 3c) 给每个头文件补经典 include guard。
#     tcc 0.9.27 的 #pragma once 只对 #include "x.h"（双引号）生效，
#     对 #include <x.h>（尖括号）完全不去重 —— 实测：同一文件用尖括号 include 两次，
#     tcc 会重新解析一遍，匿名结构体 typedef 就变成 incompatible redefinition；
#     而 bionic 的头文件清一色用尖括号，等于整套头文件在 tcc 下没有去重。
#     只要某个头文件在一条 include 链上被走到两次（signal.h、pthread.h、threads.h 都是）就炸。
#     解决：给每个头文件套一层 #ifndef guard。按字节修改，不经过文本编码，避免动坏内容。
$guarded = 0
$incRoot = Join-Path $assets 'include'
foreach ($f in (Get-ChildItem $incRoot -Recurse -Filter *.h)) {
  $rel = $f.FullName.Substring($incRoot.Length).TrimStart('\', '/')
  $guard = 'CODEPAD_GUARD_' + ($rel -replace '[^A-Za-z0-9]', '_').ToUpperInvariant()
  $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
  $probeLen = [Math]::Min(300, $bytes.Length)
  $head = [System.Text.Encoding]::ASCII.GetString($bytes, 0, $probeLen)
  $head = $head.TrimStart([char]0xEF, [char]0xBB, [char]0xBF)
  if ($head.Contains($guard)) { continue }
  # 去掉文件开头的 BOM（BOM 在 tcc 眼里是一行垃圾 token）
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    $bytes = $bytes[3..($bytes.Length - 1)]
  }
  $prefix = [System.Text.Encoding]::ASCII.GetBytes("#ifndef $guard`n#define $guard 1`n")
  $suffix = [System.Text.Encoding]::ASCII.GetBytes("`n#endif /* $guard */`n")
  $out = New-Object byte[] ($prefix.Length + $bytes.Length + $suffix.Length)
  [Array]::Copy($prefix, 0, $out, 0, $prefix.Length)
  [Array]::Copy($bytes, 0, $out, $prefix.Length, $bytes.Length)
  [Array]::Copy($suffix, 0, $out, $prefix.Length + $bytes.Length, $suffix.Length)
  [System.IO.File]::WriteAllBytes($f.FullName, $out)
  $guarded++
}
Write-Host "[guard] 补 include guard: $guarded 个头文件"

# 4) 自检
$must = @(
  (Join-Path $jniDir 'libtcc.so'),
  (Join-Path $assets 'tcc\libtcc1.a'),
  (Join-Path $assets 'tcc\crt\crtbegin_dynamic.o'),
  (Join-Path $assets 'include\stdio.h'),
  (Join-Path $assets 'include\stdlib.h'),
  # 这几个是 0.3.2 踩过的坑，必须存在
  (Join-Path $assets 'include\sys\cdefs.h'),
  (Join-Path $assets 'include\android\versioning.h'),
  (Join-Path $assets 'include\android\api-level.h'),
  (Join-Path $assets 'include\android\legacy_termios_inlines.h'),
  (Join-Path $assets 'include\android\legacy_unistd_inlines.h'),
  (Join-Path $assets 'include\android\legacy_threads_inlines.h'),
  (Join-Path $assets 'include\math.h'),
  (Join-Path $assets 'include\string.h'),
  # tcc 兼容垫片（必须有，且必须排在 -I 的第一位，见 NativeCompiler.kt）
  (Join-Path $assets 'compat\sys\cdefs.h')
)
foreach ($f in $must) {
  if (-not (Test-Path $f)) { throw "组装失败，缺少 $f" }
}

# 4b) 一致性检查：每个被 #include <dir/...> 引用到的目录都必须真的存在
#     $prunedDirs 是我们主动裁掉的；$knownAbsent 是 Termux 的 ndk-sysroot 本身没有的
#     （bionic 对这些的引用都在条件编译分支里，只有真正用到对应平台 API 时才会缺）。
$knownAbsent = @('asm', 'cutils', 'log')
$includeRoot = Join-Path $assets 'include'
$referenced = Get-ChildItem $includeRoot -Recurse -Filter *.h |
  Select-String -Pattern '#\s*include\s*<([A-Za-z0-9_]+)/' -AllMatches |
  ForEach-Object { $_.Matches } |
  ForEach-Object { $_.Groups[1].Value } |
  Sort-Object -Unique
$missingDirs = $referenced |
  Where-Object { $prunedDirs -notcontains $_ } |
  Where-Object { $knownAbsent -notcontains $_ } |
  Where-Object { -not (Test-Path (Join-Path $includeRoot $_)) }
if ($missingDirs) {
  throw "这些头文件目录被引用但不存在，编译会报 not found：$($missingDirs -join '、')"
}
$elf = [System.IO.File]::ReadAllBytes((Join-Path $jniDir 'libtcc.so'))[0..18]
$isElf64Aarch64 = $elf[0] -eq 0x7F -and $elf[1] -eq 0x45 -and $elf[4] -eq 2 -and $elf[18] -eq 0xB7
if (-not $isElf64Aarch64) { throw 'libtcc.so 不是 ELF64 AArch64，检查下载的包架构' }

$headerCount = (Get-ChildItem (Join-Path $assets 'include') -Recurse -Filter *.h).Count
$size = [math]::Round(((Get-ChildItem $assets -Recurse -File | Measure-Object Length -Sum).Sum / 1MB), 1)
Write-Host ""
Write-Host "✔ 工具链就绪" -ForegroundColor Green
Write-Host "  libtcc.so       $(Join-Path $jniDir 'libtcc.so')"
Write-Host "  assets/toolchain $size MB（$headerCount 个头文件）"
Write-Host "  下一步：flutter build apk --release --target-platform android-arm64"
