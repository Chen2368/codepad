/* CodePad 兼容垫片：iso646.h
 *
 * 这套宏是 C95 的“替代拼写”（alternative spellings），标准库要求提供。
 * bionic 的 ndk-sysroot 里没有这个文件（clang 也不需要），tcc 更不会有，
 * 所以由我们补一份 —— 内容就是标准里规定的 11 个宏，没有别的。
 */
#ifndef CODEPAD_COMPAT_ISO646_H
#define CODEPAD_COMPAT_ISO646_H

#ifndef __cplusplus
#define and    &&
#define and_eq &=
#define bitand &
#define bitor  |
#define compl  ~
#define not    !
#define not_eq !=
#define or     ||
#define or_eq  |=
#define xor    ^
#define xor_eq ^=
#endif

#endif /* CODEPAD_COMPAT_ISO646_H */
