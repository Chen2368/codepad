/*
 * CodePad · tcc 兼容垫片（sys/cdefs.h）
 *
 * 为什么需要这个文件：
 *   Termux 的 ndk-sysroot 打包的是 NDK r30 的 bionic 头文件，它们是给 clang 写的：
 *     · _Nonnull / _Nullable  —— clang 的类型限定符，cdefs.h 之外出现 2104 次
 *     · __RENAME(x) = __asm__(#x)          —— clang 的汇编符号别名
 *     · __attribute__((__availability__(android,strict,introduced=30)))  —— clang 专有属性
 *     · __has_include(<android/ndk-version.h>) 且未定义 __ANDROID_MIN_SDK_VERSION__ 时 #error
 *     · __pass_object_size / __builtin_available 等 builtin
 *   tcc 全都不支持，所以只要 include <stdio.h> 就会在某个 clang 词汇上炸掉。
 *
 * 做法：
 *   把它放在 -I 搜索路径的第一个位置（compat/sys/cdefs.h）。bionic 的每个头文件
 *   第一句几乎都是 #include <sys/cdefs.h>，因此会先命中本文件。这里把上述词汇
 *   全部定义成「无副作用」的形式，其余 1500 多个真实声明（printf、malloc…）保持原样。
 *
 * 代价与边界：
 *   · 不启用 _FORTIFY_SOURCE（__BIONIC_FORTIFY=0），因此没有 fortify 检查，但也不会用到 builtin
 *   · __availability__ 之类的 API 版本标注被抹平：可能编出「设备上没有的符号」，
 *     但只在学生用了很新的函数时才会遇到（<math.h>、<stdio.h> 里的常用函数都自 API 1 就有）
 *   · 这些宏只对 C 生效；将来 C++ 阶段走 clang，自带完整的真实 cdefs.h，不会用这个文件
 */

#ifndef CODEPAD_COMPAT_SYS_CDEFS_H
#define CODEPAD_COMPAT_SYS_CDEFS_H

/* ---------- 目标平台宏：tcc 不是 clang 驱动，不会自动注入 ---------- */
#ifndef __ANDROID_MIN_SDK_VERSION__
#define __ANDROID_MIN_SDK_VERSION__ 24
#endif
#ifndef __ANDROID_API__
#define __ANDROID_API__ __ANDROID_MIN_SDK_VERSION__
#endif
#ifndef __ANDROID_API_FUTURE__
#define __ANDROID_API_FUTURE__ 10000
#endif

/* ---------- clang 的空值限定符：直接抹掉 ----------
 * 注意：Termux 的 aarch64 tcc 在自己的预置头 tccdefs.h 里，`__ANDROID__` 分支
 * 已经定义了这三个（取值与我们相同，重复定义不会告警）。为了在别的 tcc（例如
 * 开发机上验证用的 Windows 版）上也能编译，这里仍然提供，但用 #ifndef 保护。 */
#ifndef _Nonnull
#define _Nonnull
#endif
#ifndef _Nullable
#define _Nullable
#endif
#ifndef _Null_unspecified
#define _Null_unspecified
#endif
#ifndef _Nullable_result
#define _Nullable_result
#endif

/* ---------- __has_include：一律当作「没有」，避免 tcc 不认识 ---------- */
#ifndef __has_include
#define __has_include(x) 0
#endif
#ifndef __has_include_next
#define __has_include_next(x) 0
#endif

/* ---------- extern "C" 包装 ---------- */
#ifdef __cplusplus
#define __BEGIN_DECLS extern "C" {
#define __END_DECLS }
#else
#define __BEGIN_DECLS
#define __END_DECLS
#endif

/* ---------- 符号别名 / 汇编标签：tcc 不支持，定义为空 ----------
 * 有的 tcc 构建（例如 Termux 的 aarch64 版）在预置头里把 __RENAME 定义成
 * `__asm__("_"X)`，取值不同会触发 redefined 警告，所以这里先判存在。 */
#ifndef __RENAME
#define __RENAME(x)
#endif
#define __RENAME_IF_FILE_OFFSET64(func)
#define __strong_alias(alias, sym)
#define __weak_reference(sym, alias)
#define __BIONIC_WEAK_FOR_NATIVE_BRIDGE

/* ---------- API 版本标注：抹平 ---------- */
#define __INTRODUCED_IN(api_level)
#define __INTRODUCED_IN_32(api_level)
#define __INTRODUCED_IN_64(api_level)
#define __DEPRECATED_IN(api_level, msg)
#define __REMOVED_IN(api_level, msg)
#define __BIONIC_AVAILABILITY(what, ...)
#define __BIONIC_AVAILABILITY_GUARD(api_level) 1
#define __LIBC_ABI_DEPRECATED(msg)
#define __LIBC32_LEGACY_PUBLIC__

/* ---------- 属性：一律清空（tcc 对未知属性只会告警，但没有更保险） ---------- */
#define __attribute_const__ __attribute__((__const__))
#define __attribute_pure__ __attribute__((__pure__))
#define __dead __attribute__((__noreturn__))
#define __noreturn __attribute__((__noreturn__))
#define __pure __attribute__((__pure__))
#define __pure2 __attribute__((__const__))
#define __wur
#define __nodiscard
#define __unused __attribute__((__unused__))
#define __used __attribute__((__used__))
#define __packed __attribute__((__packed__))
#define __aligned(x) __attribute__((__aligned__(x)))
#define __section(x) __attribute__((__section__(x)))
#define __mallocfunc __attribute__((__malloc__))
#define __always_inline __attribute__((__always_inline__))
#define __inline inline
#define __returns_twice
#define __overloadable
#define __enable_if(...)
#define __diagnose_as_builtin(...)
#define __clang_error_if(...)
#define __clang_warning_if(...)
#define __warnattr_strict(msg)
/* 格式串类属性用可变参数接收：bionic 里 __strftimelike(2)(3) 等用法参数个数不一致 */
#define __printflike(...)
#define __scanflike(...)
#define __strftimelike(...)
#define __format_arg(...)
#define __nonnull(...)
#define __nonnull_all
#define __nullability_unspecified
#define __result_use_check
#define __predict_true(exp) (exp)
#define __predict_false(exp) (exp)
/* C 里 __BIONIC_CAST(static_cast, unsigned, x) 要变成 ((unsigned)(x))，参数是 3 个 */
#ifdef __cplusplus
#define __BIONIC_CAST(_k, _t, _v) (_k<_t>(_v))
#else
#define __BIONIC_CAST(_k, _t, _v) ((_t)(_v))
#endif
#define __BIONIC_COMPLICATED_NULLNESS

/* pass_object_size 系列：tcc 没有，统一退化成「不知道大小」 */
#define __bos(ptr) ((size_t)-1)
#define __bos0(ptr) ((size_t)-1)
#define __bosn(ptr, size) ((size_t)-1)
#define __pass_object_size(x)
#define __pass_object_size0
#define __pass_object_size_n(n)
#define __BIONIC_FORTIFY_UNKNOWN_SIZE ((size_t)-1)

/* ---------- fortify 整套关掉 ---------- */
#define __BIONIC_FORTIFY 0
#define __BIONIC_FORTIFY_INLINE static inline __attribute__((__unused__))
#define __BIONIC_FORTIFY_VARIADIC static inline __attribute__((__unused__))
#define __BIONIC_FORTIFY_RUNTIME_CHECKS_ENABLED() 0
#define __BIONIC_ERROR_FUNCTION_VISIBILITY static inline __attribute__((__unused__))

/* ---------- libc 内部可见性 ---------- */
#define __LIBC_HIDDEN__
#define __LIBC_ABI_PUBLIC__

/* bits/ioctl.h 的「有符号/无符号重载」是给 clang 的重载技巧，tcc 会把两条声明
   看成冲突（int vs unsigned），所以显式关掉它。
   真机日志提示：Termux 的 aarch64 tcc 预置头里已经定义过这个宏（空值），
   我们若再定义成 1 会触发 "redefined" 警告 —— 所以判存在，并且保持空值。 */
#ifndef BIONIC_IOCTL_NO_SIGNEDNESS_OVERLOAD
#define BIONIC_IOCTL_NO_SIGNEDNESS_OVERLOAD
#endif

/* ---------- 128 位整数 ----------
 * aarch64 的内核头 asm/sigcontext.h、asm/ptrace.h 把 __uint128_t 当 16 字节字段用
 * （vregs[32]、apiakey …）。
 *   · 真机：Termux 的 aarch64 tcc 已经把 __int128 当基本类型支持，__uint128_t 已存在，
 *     我们再 typedef 一次就是 "too many basic types"（真机日志 145/155 行那两个错误）。
 *   · 开发机（Windows 版 tcc）：没有这个类型，需要补一份 16 字节结构体，布局一致。
 * 所以只在非 __ANDROID__ 目标上补。注意 asm/types.h 里的 `unsigned __int128` 是关键字
 * 用法，这个补不了，linux/*.h 一类内核头仍然不支持（作业用不到）。 */
#if !defined(__ANDROID__) && !defined(__SIZEOF_INT128__) && !defined(__CODEPAD_INT128_T_DEFINED)
#define __CODEPAD_INT128_T_DEFINED 1
typedef struct { unsigned long long __h[2]; } __uint128_t;
typedef struct { unsigned long long __h[2]; } __int128_t;
#endif

/* ---------- 其他杂项宏 ---------- */
#define __CONCAT1(x, y) x##y
#define __CONCAT(x, y) __CONCAT1(x, y)
#define ___CONCAT(x, y) __CONCAT(x, y)
#define __STRING1(x) #x
#define __STRING(x) __STRING1(x)
#define ___STRING(x) __STRING(x)
#define __P(protos) protos
#define __IDSTRING(name, string) static const char name[] __attribute__((__unused__)) = string
#define __RCSID(s) __IDSTRING(rcsid, s)
#define __SCCSID(s) __IDSTRING(sccsid, s)
#define __COPYRIGHT(s) __IDSTRING(copyright, s)
#define __FBSDID(s) __IDSTRING(fbsdid, s)
#define __USE_BSD 1
#define __USE_GNU 1

#ifndef __WORDSIZE
#if defined(__LP64__) || defined(__aarch64__)
#define __WORDSIZE 64
#else
#define __WORDSIZE 32
#endif
#endif

/* __BIONIC__ 刻意保持不定义：避免打开 bionic 专有的 inline 重定向（它们大量使用 builtin） */

#endif /* CODEPAD_COMPAT_SYS_CDEFS_H */

/* ---------- 标准里要求、但 tcc / bionic 组合下会缺的几个小东西 ---------- */

/* 有些头（例如只包含 <math.h> 时用 NULL）不会把 <stddef.h> 带进来 */
#ifndef NULL
#define NULL ((void*)0)
#endif

/* bionic 的 assert.h 用到了它；aarch64 的 tcc 预置头里有，别的 tcc 没有 */
#ifndef __PRETTY_FUNCTION__
#define __PRETTY_FUNCTION__ __FUNCTION__
#endif

/* <uchar.h> 用这两个宏定义 char16_t / char32_t；tcc 没有内建它们 */
#ifndef __CHAR16_TYPE__
#define __CHAR16_TYPE__ unsigned short
#endif
#ifndef __CHAR32_TYPE__
#define __CHAR32_TYPE__ unsigned int
#endif