/*
 * CodePad · tcc 兼容垫片（limits.h）
 *
 * bionic 的 limits.h 是「配合 clang 的 limits.h 使用」的：它自己只补 POSIX 部分，
 * INT_MAX / LONG_MAX 这些 C 标准宏由编译器自带的 limits.h 提供（第 51 行
 * `#if __has_include_next(<limits.h>)` 就是去找编译器那份）。
 * tcc 没有系统 limits.h，于是 <limits.h> 里 INT_MAX 不存在 —— 学生写
 * `int a[INT_MAX]` 或 `if (x == INT_MAX)` 就会报 undeclared。
 *
 * 这里给一份自足的版本（aarch64 = LP64，与设备一致），把它放在 -I 的首位。
 */

#ifndef CODEPAD_COMPAT_LIMITS_H
#define CODEPAD_COMPAT_LIMITS_H

#define CHAR_BIT 8
#define MB_LEN_MAX 4

#define SCHAR_MIN (-128)
#define SCHAR_MAX 127
#define UCHAR_MAX 255

#ifdef __CHAR_UNSIGNED__
#define CHAR_MIN 0
#define CHAR_MAX UCHAR_MAX
#else
#define CHAR_MIN SCHAR_MIN
#define CHAR_MAX SCHAR_MAX
#endif

#define SHRT_MIN (-32768)
#define SHRT_MAX 32767
#define USHRT_MAX 65535

#define INT_MIN (-2147483647 - 1)
#define INT_MAX 2147483647
#define UINT_MAX 4294967295U

#define LONG_MIN (-9223372036854775807L - 1L)
#define LONG_MAX 9223372036854775807L
#define ULONG_MAX 18446744073709551615UL

#define LLONG_MIN (-9223372036854775807LL - 1LL)
#define LLONG_MAX 9223372036854775807LL
#define ULLONG_MAX 18446744073709551615ULL

#define WORD_BIT 32
#define LONG_BIT 64
#define SSIZE_MAX LONG_MAX

/* POSIX 部分（常用值，够作业用） */
#define PASS_MAX 128
#define PATH_MAX 4096
#define NAME_MAX 255
#define NGROUPS_MAX 65536
#define PIPE_BUF 4096
#define ARG_MAX 2097152
#define CHILD_MAX 640
#define OPEN_MAX 1024
#define LINK_MAX 127
#define MAX_CANON 256
#define MAX_INPUT 256
#define PAGESIZE 4096
#define PAGE_SIZE 4096
#define RE_DUP_MAX 255
#define STREAM_MAX 8
#define TZNAME_MAX 6
#define IOV_MAX 1024
#define HOST_NAME_MAX 255
#define LOGIN_NAME_MAX 256
#define TTY_NAME_MAX 32
#define NL_ARGMAX 9
#define NL_LANGMAX 32
#define NL_MSGMAX 32767
#define NL_SETMAX 255
#define NL_TEXTMAX 255
#define NZERO 20
#define SYMLOOP_MAX 40

#endif /* CODEPAD_COMPAT_LIMITS_H */
