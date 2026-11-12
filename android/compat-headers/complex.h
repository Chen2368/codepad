/* CodePad 兼容垫片：complex.h
 *
 * tcc 没有 `_Complex` 类型说明符（它是编译器关键字，宏补不出来），
 * 所以 bionic 的 complex.h 在 tcc 下会报一句很难懂的
 *   error: ';' expected (got "cacos")
 * —— 因为 `double complex cacos(...)` 被当成了两个标识符。
 *
 * 与其让用户对着这种报错猜，不如在这里给一句能读懂的话。
 * 复数的替代方案：自己定义 `typedef struct { double re, im; } complex_t;`
 * 并写加减乘除（教材里的复数运算通常只用到这几步）。
 */
#ifndef CODEPAD_COMPAT_COMPLEX_H
#define CODEPAD_COMPAT_COMPLEX_H

#error "CodePad 的 C 编译器（tcc）不支持 <complex.h>：它没有 _Complex 类型。需要复数时请自己定义 struct { double re, im; } 并实现运算。"

#endif /* CODEPAD_COMPAT_COMPLEX_H */
