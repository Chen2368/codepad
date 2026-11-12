/*
 * CodePad · tcc 兼容垫片（stddef.h）
 *
 * 为什么需要：
 *   tcc 自带的 stddef.h 里多定义了两个「按标准应该属于 <stdint.h>」的类型：
 *       typedef __PTRDIFF_TYPE__ intptr_t;
 *       typedef __SIZE_TYPE__    uintptr_t;
 *   bionic 的 <stdint.h> 又要定义一遍（typedef long __intptr_t; typedef __intptr_t intptr_t;）。
 *   在 aarch64 上两者恰好同宽度，tcc 能容忍；但在 32 位 long 的目标上就是
 *   「incompatible redefinition of 'intptr_t'」，直接把编译卡死在 include <stdio.h> 那一步。
 *
 *   bionic 的头文件是照 clang 的 stddef.h 写的（clang 那份不含 intptr_t/uintptr_t），
 *   所以这里给一份「形同 clang」的版本：只放标准规定的东西。
 */

#ifndef CODEPAD_COMPAT_STDDEF_H
#define CODEPAD_COMPAT_STDDEF_H

typedef __SIZE_TYPE__ size_t;
typedef __PTRDIFF_TYPE__ ptrdiff_t;
typedef __WCHAR_TYPE__ wchar_t;

/* C11 对齐类型 */
#if !defined(__cplusplus)
typedef union {
  long long __max_align_ll;
  long double __max_align_ld;
} max_align_t;
#endif

#ifndef NULL
#define NULL ((void*)0)
#endif

#undef offsetof
#define offsetof(type, field) ((size_t)&((type*)0)->field)

#endif /* CODEPAD_COMPAT_STDDEF_H */
