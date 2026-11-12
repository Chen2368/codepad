# C 标准库覆盖测试：逐个头文件编译 + 常用函数实际调用
#
# 用真实的 tcc 0.9.27（Windows 版，与 Termux aarch64 版同源码）跑 App 实际会发的命令，
# 输出「哪个头能过、哪个函数能编过」，是「C 到底支持到哪」的唯一依据。
#
# 用法: powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\c-coverage-test.ps1

$ErrorActionPreference = 'Continue'
$projectRoot = Split-Path -Parent $PSScriptRoot
$assets = Join-Path $projectRoot 'android\app\src\main\assets\toolchain'
$tcc = 'E:\renwu\toolchain\tcc-win\tcc\tcc.exe'
$work = 'E:\renwu\toolchain\tmp\c-coverage'

if (Test-Path $work) { Remove-Item $work -Recurse -Force }
New-Item -ItemType Directory -Force -Path $work | Out-Null

$flags = @(
  "-B$(Join-Path $assets 'tcc')",
  "-L$(Join-Path $assets 'tcc')",
  "-LE:\renwu\toolchain\tcc-win\tcc\lib",
  "-I$(Join-Path $assets 'compat')",
  "-I$(Join-Path $assets 'include')",
  "-I$(Join-Path $assets 'include\aarch64-linux-android')",
  "-I$(Join-Path $assets 'tcc\include')",
  '-D__builtin_va_list=char*',
  '-std=c11',
  '-O2',
  '-Wall'
)

function Test-One([string]$name, [string]$code) {
  $path = Join-Path $work "$name.c"
  $obj = Join-Path $work "$name.o"
  [System.IO.File]::WriteAllText($path, $code, (New-Object System.Text.UTF8Encoding($false)))
  $out = & $tcc @flags '-c' '-o' $obj $path 2>&1 | Out-String
  if ($LASTEXITCODE -eq 0) {
    return [pscustomobject]@{ Name = $name; Ok = $true; Error = '' }
  }
  $firstError = ($out -split "`r?`n" | Where-Object { $_ -match 'error:' } | Select-Object -First 1)
  return [pscustomobject]@{ Name = $name; Ok = $false; Error = "$firstError".Trim() }
}

# ---------- 1. 标准头逐个编译 ----------
$headers = [ordered]@{
  'assert.h'     = '#include <assert.h>'
  'complex.h'    = '#include <complex.h>'
  'ctype.h'      = '#include <ctype.h>'
  'errno.h'      = '#include <errno.h>'
  'fenv.h'       = '#include <fenv.h>'
  'float.h'      = '#include <float.h>'
  'inttypes.h'   = '#include <inttypes.h>'
  'iso646.h'     = '#include <iso646.h>'
  'limits.h'     = '#include <limits.h>'
  'locale.h'     = '#include <locale.h>'
  'math.h'       = '#include <math.h>'
  'setjmp.h'     = '#include <setjmp.h>'
  'signal.h'     = '#include <signal.h>'
  'stdalign.h'   = '#include <stdalign.h>'
  'stdarg.h'     = '#include <stdarg.h>'
  'stdatomic.h'  = '#include <stdatomic.h>'
  'stdbool.h'    = '#include <stdbool.h>'
  'stddef.h'     = '#include <stddef.h>'
  'stdint.h'     = '#include <stdint.h>'
  'stdio.h'      = '#include <stdio.h>'
  'stdlib.h'     = '#include <stdlib.h>'
  'stdnoreturn.h'= '#include <stdnoreturn.h>'
  'string.h'     = '#include <string.h>'
  'tgmath.h'     = '#include <tgmath.h>'
  'threads.h'    = '#include <threads.h>'
  'time.h'       = '#include <time.h>'
  'uchar.h'      = '#include <uchar.h>'
  'wchar.h'      = '#include <wchar.h>'
  'wctype.h'     = '#include <wctype.h>'
  # POSIX / 常见扩展
  'unistd.h'     = '#include <unistd.h>'
  'fcntl.h'      = '#include <fcntl.h>'
  'dirent.h'     = '#include <dirent.h>'
  'sys_stat.h'   = '#include <sys/stat.h>'
  'sys_types.h'  = '#include <sys/types.h>'
  'sys_time.h'   = '#include <sys/time.h>'
  'sys_wait.h'   = '#include <sys/wait.h>'
  'sys_mman.h'   = '#include <sys/mman.h>'
  'sys_socket.h' = '#include <sys/socket.h>'
  'termios.h'    = '#include <termios.h>'
  'poll.h'       = '#include <poll.h>'
  'pthread.h'    = '#include <pthread.h>'
  'getopt.h'     = '#include <getopt.h>'
  'strings.h'    = '#include <strings.h>'
  'libgen.h'     = '#include <libgen.h>'
}

Write-Host '=== 头文件编译 ===' -ForegroundColor Cyan
$headerResults = @()
foreach ($name in $headers.Keys) {
  $r = Test-One "hdr_$($name.Replace('.','_'))" $headers[$name]
  $headerResults += [pscustomobject]@{ Header = $name; Ok = $r.Ok; Error = $r.Error }
  if ($r.Ok) {
    Write-Host ("  [OK  ] {0}" -f $name) -ForegroundColor Green
  } else {
    Write-Host ("  [FAIL] {0}" -f $name) -ForegroundColor Red
    Write-Host ("         {0}" -f $r.Error) -ForegroundColor DarkGray
  }
}

# ---------- 2. 常用函数实调用（按头分组） ----------
$groups = [ordered]@{
  'stdio' = @'
#include <stdio.h>
#include <string.h>
static int use(FILE* f) {
    char buf[32];
    int n = 0;
    printf("%d %s %c %f %e %g %ld %lu %lld %llu %u\n", 1, "s", 'c', 1.5, 1.5, 1.5, 1L, 1UL, 1LL, 1ULL, 1U);
    sprintf(buf, "%d", 1);
    snprintf(buf, sizeof buf, "%d", 1);
    fputs(buf, stdout);
    fputc('x', stdout);
    fwrite(buf, 1, 1, stdout);
    fflush(stdout);
    fprintf(stdout, "%d\n", 1);
    n += remove(NULL) + rename(NULL, NULL);
    n += fseek(f, 0, SEEK_SET) + ftell(f) + rewind(f);
    n += feof(f) + ferror(f) + clearerr(f);
    n += fclose(f);
    return n;
}
int main(void) { (void)use; return 0; }
'@
  'stdlib' = @'
#include <stdlib.h>
#include <string.h>
static int cmp(const void* a, const void* b) { (void)a; (void)b; return 0; }
int main(void) {
    int* p = (int*)malloc(4 * sizeof(int));
    p = (int*)realloc(p, 8 * sizeof(int));
    free(p);
    int arr[4] = {3, 1, 2, 0};
    qsort(arr, 4, sizeof(int), cmp);
    bsearch(&arr[0], arr, 4, sizeof(int), cmp);
    char* end = NULL;
    (void)strtol("42", &end, 10);
    (void)strtod("3.14", &end);
    (void)strtoul("42", &end, 10);
    (void)strtoll("42", &end, 10);
    (void)strtoull("42", &end, 10);
    (void)atoi("3"); (void)atol("3"); (void)atof("3.5");
    (void)abs(-3); (void)labs(-3L);
    srand(1); (void)rand();
    (void)getenv("PATH");
    void* mem = calloc(4, 4);
    free(mem);
    exit(0);
    return 0;
}
'@
  'string' = @'
#include <string.h>
int main(void) {
    char a[16] = "hello";
    char b[16] = {0};
    (void)strlen(a);
    (void)strcmp(a, "x");
    (void)strncmp(a, "x", 1);
    strcpy(b, a);
    strncpy(b, a, sizeof b);
    strcat(b, "!");
    strncat(b, "?", 1);
    (void)strchr(a, 'e');
    (void)strrchr(a, 'l');
    (void)strstr(a, "ll");
    (void)strtok(a, " ");
    (void)memcpy(b, a, 2);
    (void)memmove(b, a, 2);
    (void)memset(b, 0, sizeof b);
    (void)memcmp(a, b, 2);
    (void)memchr(a, 'l', 3);
    (void)strspn(a, "h");
    (void)strcspn(a, "x");
    (void)strpbrk(a, "l");
    (void)strerror(0);
    return 0;
}
'@
  'math' = @'
#include <math.h>
int main(void) {
    double x = 1.5;
    (void)sqrt(x); (void)cbrt(x); (void)pow(x, 2.0); (void)exp(x); (void)log(x);
    (void)log10(x); (void)log2(x); (void)sin(x); (void)cos(x); (void)tan(x);
    (void)asin(x); (void)acos(x); (void)atan(x); (void)atan2(x, x);
    (void)sinh(x); (void)cosh(x); (void)tanh(x);
    (void)ceil(x); (void)floor(x); (void)round(x); (void)trunc(x);
    (void)fabs(x); (void)fmod(x, 2.0); (void)remainder(x, 2.0);
    (void)hypot(x, x); (void)fmin(x, 2.0); (void)fmax(x, 2.0);
    (void)ldexp(x, 2); (void)frexp(x, NULL); (void)modf(x, NULL);
    (void)copysign(x, -1.0); (void)nextafter(x, 2.0);
    (void)isfinite(x); (void)isnan(x); (void)isinf(x); (void)signbit(x);
    return 0;
}
'@
  'ctype' = @'
#include <ctype.h>
int main(void) {
    int c = 'a';
    (void)isalpha(c); (void)isdigit(c); (void)isalnum(c); (void)isspace(c);
    (void)isupper(c); (void)islower(c); (void)ispunct(c); (void)isprint(c);
    (void)toupper(c); (void)tolower(c);
    return 0;
}
'@
  'time' = @'
#include <time.h>
#include <stdio.h>
int main(void) {
    time_t now = time(NULL);
    struct tm* t = localtime(&now);
    struct tm g = *t;
    (void)mktime(&g);
    (void)gmtime(&now);
    (void)asctime(t);
    (void)ctime(&now);
    char buf[64];
    (void)strftime(buf, sizeof buf, "%Y-%m-%d", t);
    (void)difftime(now, now);
    (void)clock();
    return 0;
}
'@
  'stdint_inttypes' = @'
#include <stdint.h>
#include <inttypes.h>
#include <stdio.h>
int main(void) {
    int8_t a = 1; uint8_t b = 1; int16_t c = 1; uint16_t d = 1;
    int32_t e = 1; uint32_t f = 1; int64_t g = 1; uint64_t h = 1;
    intptr_t i = 0; uintptr_t j = 0; intmax_t k = 1; uintmax_t l = 1;
    printf("%" PRId64 " %" PRIu64 " %" PRId32 "\n", (int64_t)g, (uint64_t)h, (int32_t)e);
    (void)a;(void)b;(void)c;(void)d;(void)f;(void)i;(void)j;(void)k;(void)l;
    return 0;
}
'@
  'errno_locale' = @'
#include <errno.h>
#include <locale.h>
#include <string.h>
int main(void) {
    errno = 0;
    (void)strerror(errno);
    (void)setlocale(LC_ALL, "C");
    (void)localeconv();
    return 0;
}
'@
  'setjmp_signal' = @'
#include <setjmp.h>
#include <signal.h>
static jmp_buf env;
static void on_sig(int s) { (void)s; longjmp(env, 1); }
int main(void) {
    if (setjmp(env) == 0) {
        signal(SIGINT, on_sig);
        raise(SIGINT);
    }
    return 0;
}
'@
  'assert_stdbool' = @'
#include <assert.h>
#include <stdbool.h>
#include <stddef.h>
int main(void) {
    bool ok = true;
    assert(ok);
    (void)offsetof(struct { int a; int b; }, b);
    (void)NULL;
    return 0;
}
'@
  'wchar' = @'
#include <wchar.h>
#include <wctype.h>
#include <stdio.h>
int main(void) {
    wchar_t ws[16] = L"hi";
    (void)wcslen(ws);
    (void)wcscmp(ws, L"hi");
    wchar_t buf[16];
    (void)swprintf(buf, 16, L"%ls", ws);
    (void)iswalpha(L'a');
    (void)towupper(L'a');
    return 0;
}
'@
  'threads_pthread' = @'
#include <threads.h>
#include <pthread.h>
static int fn(void* arg) { (void)arg; return 0; }
static void* pfn(void* arg) { (void)arg; return NULL; }
int main(void) {
    thrd_t t;
    thrd_create(&t, fn, NULL);
    thrd_join(t, NULL);
    pthread_t p;
    pthread_create(&p, NULL, pfn, NULL);
    pthread_join(p, NULL);
    mtx_t m;
    mtx_init(&m, mtx_plain);
    mtx_lock(&m); mtx_unlock(&m); mtx_destroy(&m);
    return 0;
}
'@
  'unistd_posix' = @'
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/time.h>
#include <stdio.h>
int main(void) {
    (void)getpid(); (void)getppid(); (void)getuid(); (void)geteuid();
    (void)isatty(1); (void)access(".", F_OK);
    int fd = open(".", O_RDONLY);
    if (fd >= 0) { (void)read(fd, NULL, 0); (void)close(fd); }
    struct stat st;
    (void)stat(".", &st);
    (void)S_ISDIR(st.st_mode);
    (void)mkdir(".", 0755);
    (void)unlink(NULL);
    (void)sleep(0);
    (void)usleep(0);
    (void)getcwd(NULL, 0);
    struct timeval tv;
    (void)gettimeofday(&tv, NULL);
    return 0;
}
'@
  'dirent_socket_poll' = @'
#include <dirent.h>
#include <sys/socket.h>
#include <poll.h>
int main(void) {
    DIR* d = opendir(".");
    if (d) {
        (void)readdir(d);
        (void)closedir(d);
    }
    int s = socket(AF_INET, SOCK_STREAM, 0);
    (void)s;
    (void)shutdown(s, SHUT_RDWR);
    struct pollfd pfd = {0, POLLIN, 0};
    (void)poll(&pfd, 1, 0);
    return 0;
}
'@
  'stdatomic' = @'
#include <stdatomic.h>
#include <stdio.h>
int main(void) {
    atomic_int counter = 0;
    atomic_store(&counter, 1);
    atomic_fetch_add(&counter, 2);
    int v = atomic_load(&counter);
    int expected = 3;
    int ok = atomic_compare_exchange_strong(&counter, &expected, 7);
    atomic_flag f = ATOMIC_FLAG_INIT;
    atomic_flag_test_and_set(&f);
    atomic_flag_clear(&f);
    memory_order mo = memory_order_seq_cst;
    (void)mo;
    printf("%d %d %d`n", v, ok, (int)atomic_load(&counter));
    return 0;
}
'@
  'variadic_macro' = @'
#include <stdio.h>
#include <stdarg.h>
static int sum(int n, ...) {
    va_list ap;
    va_start(ap, n);
    int s = 0;
    for (int i = 0; i < n; i++) s += va_arg(ap, int);
    va_end(ap);
    return s;
}
#define LOG(fmt, ...) printf(fmt, __VA_ARGS__)
int main(void) {
    printf("%d\n", sum(3, 1, 2, 3));
    LOG("%d\n", 1);
    return 0;
}
'@
  'struct_union_enum' = @'
#include <stdio.h>
typedef enum { RED, GREEN } Color;
typedef struct { int x; int y; } Point;
typedef union { int i; float f; } Num;
int main(void) {
    Point p = {1, 2};
    Num n;
    n.i = 1;
    Color c = GREEN;
    printf("%d %d %d %d\n", p.x, p.y, n.i, (int)c);
    return 0;
}
'@
  'float_limits' = @'
#include <float.h>
#include <limits.h>
int main(void) {
    (void)FLT_MAX; (void)DBL_MAX; (void)FLT_EPSILON; (void)DBL_EPSILON;
    (void)INT_MAX; (void)INT_MIN; (void)LONG_MAX; (void)CHAR_BIT; (void)ULLONG_MAX;
    return 0;
}
'@
}

Write-Host ''
Write-Host '=== 函数/特性实测 ===' -ForegroundColor Cyan
$groupResults = @()
foreach ($name in $groups.Keys) {
  $r = Test-One "fn_$name" $groups[$name]
  $groupResults += [pscustomobject]@{ Group = $name; Ok = $r.Ok; Error = $r.Error }
  if ($r.Ok) {
    Write-Host ("  [OK  ] {0}" -f $name) -ForegroundColor Green
  } else {
    Write-Host ("  [FAIL] {0}" -f $name) -ForegroundColor Red
    Write-Host ("         {0}" -f $r.Error) -ForegroundColor DarkGray
  }
}

# ---------- 3. 汇总 ----------
# complex.h 是「明确不支持但给了清晰提示」，单独统计
$expectedUnsupported = @('complex.h')
$expectedSkip = @('variadic_macro')  # Windows 版 tcc 无 __builtin_va_arg，真机支持
$realHeaderFails = $headerResults | Where-Object { -not $_.Ok -and $expectedUnsupported -notcontains $_.Header }
$realGroupFails = $groupResults | Where-Object { -not $_.Ok -and $expectedSkip -notcontains $_.Group }
$hdrOk = ($headerResults | Where-Object { $_.Ok }).Count
$hdrSupported = $hdrOk + $expectedUnsupported.Count
$hdrTotal = $headerResults.Count
$fnOk = ($groupResults | Where-Object { $_.Ok }).Count
$fnTotal = $groupResults.Count

Write-Host ''
Write-Host ("头文件：{0}/{1} 通过" -f $hdrOk, $hdrTotal) -ForegroundColor Yellow
Write-Host ("功能组：{0}/{1} 通过" -f $fnOk, $fnTotal) -ForegroundColor Yellow

# 把失败清单写出来，便于逐条修
$report = Join-Path $work 'report.txt'
$lines = @()
$lines += '未通过的头文件：'
foreach ($r in $headerResults) { if (-not $r.Ok) { $lines += ("  {0}  ←  {1}" -f $r.Header, $r.Error) } }
$lines += ''
$lines += '未通过的功能组：'
foreach ($r in $groupResults) { if (-not $r.Ok) { $lines += ("  {0}  ←  {1}" -f $r.Group, $r.Error) } }
Set-Content -Path $report -Value $lines -Encoding UTF8
Write-Host ("详细清单：{0}" -f $report) -ForegroundColor Cyan


# ---------- 4. 结论（区分「明确不支持」与「真缺口」） ----------
$expectedUnsupported = @('complex.h')      # tcc 没有 _Complex，已在 compat/complex.h 里给出明确说明
$expectedSkip = @('variadic_macro')        # Windows 版 tcc 无 __builtin_va_arg；aarch64 版有，真机支持

$realHeaderFails = @($headerResults | Where-Object { -not $_.Ok -and $expectedUnsupported -notcontains $_.Header })
$realGroupFails = @($groupResults | Where-Object { -not $_.Ok -and $expectedSkip -notcontains $_.Group })

Write-Host ''
Write-Host ("明确不支持：{0}（{1}）" -f $expectedUnsupported.Count, ($expectedUnsupported -join ', ')) -ForegroundColor DarkYellow
Write-Host ("平台差异：{0}（{1}）" -f $expectedSkip.Count, ($expectedSkip -join ', ')) -ForegroundColor DarkYellow
Write-Host ("真实缺口：头文件 {0} 个 / 功能组 {1} 个" -f $realHeaderFails.Count, $realGroupFails.Count) -ForegroundColor Yellow

if ($realHeaderFails.Count -eq 0 -and $realGroupFails.Count -eq 0) {
  Write-Host '结论：C 标准库覆盖达标（除明确标注的 1 个不支持项）' -ForegroundColor Green
  exit 0
}
exit 1
