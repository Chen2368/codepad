# 验收测试：用真实的 tcc 0.9.27 跑「App 实际会发给它的命令」
#
# 本机是 x86_64 Windows，没有 arm64 设备，所以用 Windows 版 tcc 0.9.27
# （与 Termux 的 aarch64 版同版本、同源码）验证三件事：
#   1. 这套 bionic 头文件 + 兼容垫片，tcc 能不能编译
#   2. 命令格式（尤其是 -run 的位置）对不对
#   3. 程序能不能真跑出结果（含 stdin、math.h、浮点格式化、编译错误格式）
#
# 已知平台差异（只会让真机比这里更宽松）：
#   Windows 版 tcc 未定义 __builtin_va_list（aarch64 版在 tccdefs.h 里定义了），
#   所以这里多传一个 -D__builtin_va_list=char*；真机不需要。
#
# 用法: powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\acceptance-test.ps1

$ErrorActionPreference = 'Continue'   # 编译器往 stderr 写错误是正常现象，不能让 PS 当成致命错误
$projectRoot = Split-Path -Parent $PSScriptRoot
$assets = Join-Path $projectRoot 'android\app\src\main\assets\toolchain'
$tcc = if ($env:CODEPAD_TCC_WIN) { $env:CODEPAD_TCC_WIN } else { 'E:\renwu\toolchain\tcc-win\tcc\tcc.exe' }
$work = Join-Path $projectRoot 'build\acceptance'   # build/ 已被 .gitignore 忽略

if (-not (Test-Path $tcc)) {
  throw "找不到 tcc：$tcc"
}
if (Test-Path $work) { Remove-Item $work -Recurse -Force }
New-Item -ItemType Directory -Force -Path $work | Out-Null

# 与 NativeCompiler.kt 拼出来的参数保持一致（顺序也一样）
$commonArgs = @(
  "-I$(Join-Path $assets 'compat')",
  "-I$(Join-Path $assets 'include')",
  "-I$(Join-Path $assets 'include\aarch64-linux-android')",
  "-I$(Join-Path $assets 'tcc\include')",
  '-D__ANDROID_MIN_SDK_VERSION__=24',
  '-D__ANDROID_API__=24',
  '-D__builtin_va_list=char*'
)
$script:tccBin = $tcc
$script:commonArgs = $commonArgs
$script:fail = 0

function Write-Case([string]$name, [string]$body) {
  $path = Join-Path $work $name
  [System.IO.File]::WriteAllText($path, $body, (New-Object System.Text.UTF8Encoding($false)))
  return $path
}

function Invoke-Tcc([string[]]$sources, [string]$stdin) {
  $cmdArgs = @()
  $cmdArgs += $script:commonArgs
  $cmdArgs += $sources
  $cmdArgs += '-run'
  if ($PSBoundParameters.ContainsKey('stdin')) {
    $out = $stdin | & $script:tccBin @cmdArgs 2>&1
  } else {
    $out = & $script:tccBin @cmdArgs 2>&1
  }
  $code = $LASTEXITCODE
  $text = ($out | Out-String)
  return [pscustomobject]@{ Output = $text; Code = $code }
}

function Check([string]$title, $result, [string[]]$mustContain) {
  $missing = @()
  foreach ($needle in $mustContain) {
    if ($result.Output -notmatch [regex]::Escape($needle)) { $missing += $needle }
  }
  if ($result.Code -eq 0 -and $missing.Count -eq 0) {
    Write-Host ("  [PASS] {0}" -f $title) -ForegroundColor Green
  } else {
    Write-Host ("  [FAIL] {0}" -f $title) -ForegroundColor Red
    Write-Host ("         退出码={0}  缺少={1}" -f $result.Code, ($missing -join ', ')) -ForegroundColor Red
    Write-Host ("         实际输出: {0}" -f $result.Output.Trim()) -ForegroundColor DarkGray
    $script:fail++
  }
}

Push-Location $work
try {
  Write-Host '1) 单文件 hello'
  $hello = Write-Case 'hello.c' @'
#include <stdio.h>
int main(void) { printf("Hello, CodePad!\n"); return 0; }
'@
  Check 'hello -> Hello, CodePad!' (Invoke-Tcc @($hello)) @('Hello, CodePad!')

  Write-Host '2) 多文件 main.c + util.c（示例工程默认场景）'
  $main = Write-Case 'main.c' @'
#include <stdio.h>
#include "util.h"

int main(void) {
    const int n = 1000;
    const double h = 1.0 / n;
    double sum = (f(0.0) + f(1.0)) / 2.0;
    for (int i = 1; i < n; i++) {
        sum += f(i * h);
    }
    printf("integral=%.8f\n", sum * h);
    return 0;
}
'@
  $utilh = Write-Case 'util.h' @'
#ifndef UTIL_H
#define UTIL_H
double f(double x);
#endif
'@
  $utilc = Write-Case 'util.c' @'
#include "util.h"
double f(double x) { return x * x; }
'@
  Check 'main.c + util.c -> integral=0.33333350' (Invoke-Tcc @($main, $utilc)) @('integral=0.33333350')

  Write-Host '3) 标准输入 scanf：21 -> 441'
  $inp = Write-Case 'input.c' @'
#include <stdio.h>
int main(void) {
    int n;
    printf("input n: ");
    fflush(NULL);   /* Windows CRT 没有 stdout 这个符号，真机 bionic 有 */
    if (scanf("%d", &n) != 1) { printf("no input\n"); return 1; }
    printf("square %d\n", n * n);
    return 0;
}
'@
  Check 'stdin 21 -> square 441' (Invoke-Tcc @($inp) -stdin '21') @('square 441')

  Write-Host '4) math.h + 浮点格式化'
  $math = Write-Case 'math.c' @'
#include <stdio.h>
#include <math.h>
int main(void) {
    printf("sqrt2=%.5f\n", sqrt(2.0));
    printf("%d %.2f %s\n", 42, 3.14, "abc");
    return 0;
}
'@
  Check 'sqrt 与格式化' (Invoke-Tcc @($math)) @('sqrt2=1.41421', '42 3.14 abc')

  Write-Host '5) 常用头文件全家桶'
  $all = Write-Case 'all.c' @'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <ctype.h>
#include <time.h>
#include <stdint.h>
#include <inttypes.h>
#include <limits.h>
#include <stdbool.h>
#include <errno.h>
#include <assert.h>
#include <signal.h>
#include <unistd.h>
#include <locale.h>
#include <setjmp.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/select.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/wait.h>
#include <sys/socket.h>
#include <poll.h>
#include <termios.h>
#include <dirent.h>
#include <fcntl.h>
#include <wchar.h>
#include <wctype.h>

typedef struct { char name[16]; double score; } Student;
static int cmp(const void* a, const void* b) {
    const Student* x = (const Student*)a;
    const Student* y = (const Student*)b;
    return (x->score < y->score) - (x->score > y->score);
}

int main(int argc, char** argv) {
    (void)argc; (void)argv;
    Student s[3] = { {"A", 88.5}, {"B", 92.0}, {"C", 76.5} };
    qsort(s, 3, sizeof(Student), cmp);
    for (int i = 0; i < 3; i++) { printf("%s:%.1f ", s[i].name, s[i].score); }
    printf("\n");
    double sum = 0.0;
    for (int i = 1; i <= 10; i++) { sum += sqrt((double)i); }
    printf("sum=%.4f\n", sum);
    char* heap = (char*)malloc(32);
    if (heap) { strcpy(heap, "heap-ok"); printf("%s %d\n", heap, (int)strlen(heap)); free(heap); }
    struct stat st;
    if (stat(".", &st) == 0) { printf("stat-ok\n"); }
    time_t now = time(NULL);
    struct tm* tmv = localtime(&now);
    printf("year-ok %d\n", (tmv != NULL && tmv->tm_year + 1900 >= 2024) ? 1 : 0);
    return 0;
}
'@
  Check '30 个头文件 + qsort/struct/malloc/stat/time' (Invoke-Tcc @($all)) @('sum=', 'heap-ok 7', 'stat-ok', 'year-ok 1')

  Write-Host '6) 编译错误格式（App 点击跳行靠它）'
  $bad = Write-Case 'bad.c' @'
#include <stdio.h>
int main(void) {
    int x = ;
    return 0;
}
'@
  $r = Invoke-Tcc @($bad)
  if ($r.Output -match 'bad\.c:(\d+):.*error') {
    Write-Host ("  [PASS] 能解析出文件:行号 -> {0}" -f (($r.Output -split "`r?`n")[0]).Trim()) -ForegroundColor Green
  } else {
    Write-Host ("  [FAIL] 错误格式不匹配：{0}" -f $r.Output.Trim()) -ForegroundColor Red
    $script:fail++
  }
  Write-Host '7) 隔离编译器：模拟真机 libtcc.so 旁边既没有 include/ 也没有 lib/'
  # 真机上编译器是 APK 里的 lib/arm64/libtcc.so：
  #   · 旁边没有 include/  → 编译器自带头（stdarg.h）找不到 ⇒ 必须 -I<tcc>/include（0.3.7）
  #   · 旁边没有 lib/      → libtcc1.a 找不到               ⇒ 必须 -L<tcc>（0.3.9）
  $iso = 'E:\renwu\toolchain\tmp\iso-compiler'
  if (Test-Path $iso) { Remove-Item $iso -Recurse -Force }
  Copy-Item 'E:\renwu\toolchain\tcc-win\tcc' $iso -Recurse -Force
  Rename-Item (Join-Path $iso 'include') '_include' -Force
  Rename-Item (Join-Path $iso 'lib') '_lib' -Force
  $isoTcc = Join-Path $iso 'tcc.exe'
  $winLib = 'E:\renwu\toolchain\tmp\win-lib'
  if (Test-Path $winLib) { Remove-Item $winLib -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $winLib | Out-Null
  Copy-Item 'E:\renwu\toolchain\tcc-win\tcc\lib\libtcc1-64.a' $winLib
  $hello2 = Join-Path $work 'hello.c'
  $isoBase = @("-B$iso", '-D__builtin_va_list=char*', "-I$(Join-Path $assets 'compat')", "-I$(Join-Path $assets 'include')", "-I$(Join-Path $assets 'include\aarch64-linux-android')", "-I$(Join-Path $assets 'tcc\include')")

  # ① 只给 -B（0.3.8 的命令形状）：必须复现真机「libtcc1.a not found」
  $noLib = & $isoTcc @isoBase $hello2 -run 2>&1 | Out-String
  if ($noLib -match 'not found') {
    Write-Host '  [PASS] 只给 -B 时复现真机 libtcc1.a 报错（用例有效）' -ForegroundColor Green
  } else {
    Write-Host ("  [FAIL] 没能复现 libtcc1.a 报错：{0}" -f $noLib.Trim()) -ForegroundColor Red
    $script:fail++
  }

  # ② 补上 -L：必须真跑出结果（0.3.9 的修法）
  $withLib = & $isoTcc @isoBase "-L$winLib" $hello2 -run 2>&1 | Out-String
  if ($LASTEXITCODE -eq 0 -and $withLib -match 'Hello, CodePad!') {
    Write-Host '  [PASS] 补上 -L 后正常编译运行' -ForegroundColor Green
  } else {
    Write-Host ("  [FAIL] 隔离编译器 + -L 仍失败：{0}" -f $withLib.Trim()) -ForegroundColor Red
    $script:fail++
  }
}
finally {
  Pop-Location
}

Write-Host ''
if ($script:fail -eq 0) {
  Write-Host '全部通过（7 个用例 / 8 项断言，含 2 条反证）' -ForegroundColor Green
  exit 0
} else {
  Write-Host ("有 {0} 项失败" -f $script:fail) -ForegroundColor Red
  exit 1
}
