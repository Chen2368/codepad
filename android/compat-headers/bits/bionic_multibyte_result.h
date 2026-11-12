/*
 * CodePad · tcc 兼容垫片（bits/bionic_multibyte_result.h）
 *
 * bionic 这份头用的是 C23 的「带底层类型的枚举」：
 *     enum : size_t { BIONIC_MULTIBYTE_RESULT_ILLEGAL_SEQUENCE = -1UL, ... };
 * tcc 不支持这种语法（struct/union/enum name expected），而 <wchar.h>、<uchar.h>
 * 都会 include 它，于是只要用到宽字符就编不过。
 *
 * 这些名字的真实用途只是「几个常量 + 可以用 #ifdef 判断存在性」，
 * 所以这里直接给成宏，语义等价。
 */

#ifndef CODEPAD_COMPAT_BIONIC_MULTIBYTE_RESULT_H
#define CODEPAD_COMPAT_BIONIC_MULTIBYTE_RESULT_H

#include <stddef.h>

#define BIONIC_MULTIBYTE_RESULT_ILLEGAL_SEQUENCE ((size_t)-1)
#define BIONIC_MULTIBYTE_RESULT_INCOMPLETE_SEQUENCE ((size_t)-2)
#define BIONIC_MULTIBYTE_RESULT_NO_BYTES_CONSUMED ((size_t)-3)

#endif /* CODEPAD_COMPAT_BIONIC_MULTIBYTE_RESULT_H */
