/* CodePad 兼容垫片：stdatomic.h（单线程语义）
 *
 * 为什么需要它：tcc 没有 `_Atomic` 类型说明符，也没有 `__ATOMIC_*`，
 * bionic 的 <bits/stdatomic.h> 在 tcc 下必然报 `'__ATOMIC_RELAXED' undeclared`。
 *
 * 这里给一份 **非原子** 的实现：类型就是普通整数，操作就是普通读写。
 * 对单线程的学生程序（计数、标志位）行为完全正确；**不能用于多线程同步**。
 * 选择“能编译且行为可预期”，而不是“假装支持但语义错误却不吭声”——
 * 头文件里已经写明这一点，出错时也不会有静默的并发 bug 被掩盖。
 */
#ifndef CODEPAD_COMPAT_STDATOMIC_H
#define CODEPAD_COMPAT_STDATOMIC_H

#include <stdint.h>
#include <stdbool.h>

/* 内存序：取值与 C11 一致，但我们不做任何屏障 */
typedef enum {
  memory_order_relaxed = 0,
  memory_order_consume = 1,
  memory_order_acquire = 2,
  memory_order_release = 3,
  memory_order_acq_rel = 4,
  memory_order_seq_cst = 5
} memory_order;

#define __CODEPAD_ATOMIC_TYPE(name, type) \
  typedef volatile type atomic_##name;

/* bool 要单独写：<stdbool.h> 把 bool 定义成 _Bool，套进宏会变成
   `typedef _Bool _Bool;`（too many basic types） */
typedef volatile _Bool atomic_bool;
__CODEPAD_ATOMIC_TYPE(char, char)
__CODEPAD_ATOMIC_TYPE(schar, signed char)
__CODEPAD_ATOMIC_TYPE(uchar, unsigned char)
__CODEPAD_ATOMIC_TYPE(short, short)
__CODEPAD_ATOMIC_TYPE(ushort, unsigned short)
__CODEPAD_ATOMIC_TYPE(int, int)
__CODEPAD_ATOMIC_TYPE(uint, unsigned int)
__CODEPAD_ATOMIC_TYPE(long, long)
__CODEPAD_ATOMIC_TYPE(ulong, unsigned long)
__CODEPAD_ATOMIC_TYPE(llong, long long)
__CODEPAD_ATOMIC_TYPE(ullong, unsigned long long)
__CODEPAD_ATOMIC_TYPE(intptr, intptr_t)
__CODEPAD_ATOMIC_TYPE(uintptr, uintptr_t)

#undef __CODEPAD_ATOMIC_TYPE

#define atomic_init(obj, value) (*(obj) = (value))

#define atomic_load(obj) (*(obj))
#define atomic_load_explicit(obj, order) ((void)(order), *(obj))

#define atomic_store(obj, value) (*(obj) = (value))
#define atomic_store_explicit(obj, value, order) \
  ((void)(order), *(obj) = (value))

#define atomic_exchange(obj, value) (*(obj) = (value))
#define atomic_exchange_explicit(obj, value, order) \
  ((void)(order), *(obj) = (value))

#define atomic_load_explicit_ptr atomic_load_explicit

#define atomic_fetch_add(obj, arg) (*(obj) += (arg))
#define atomic_fetch_add_explicit(obj, arg, order) \
  ((void)(order), *(obj) += (arg))
#define atomic_fetch_sub(obj, arg) (*(obj) -= (arg))
#define atomic_fetch_sub_explicit(obj, arg, order) \
  ((void)(order), *(obj) -= (arg))
#define atomic_fetch_or(obj, arg) (*(obj) |= (arg))
#define atomic_fetch_and(obj, arg) (*(obj) &= (arg))
#define atomic_fetch_xor(obj, arg) (*(obj) ^= (arg))

/* 比较交换：单线程下就是一次普通的条件赋值 */
#define atomic_compare_exchange_strong(obj, expected, desired)          \
  (*(obj) == *(expected) ? (*(obj) = (desired), true)                   \
                         : (*(expected) = *(obj), false))
#define atomic_compare_exchange_strong_explicit(obj, expected, desired, \
                                                succ, fail)             \
  ((void)(succ), (void)(fail),                                          \
   atomic_compare_exchange_strong(obj, expected, desired))
#define atomic_compare_exchange_weak(obj, expected, desired) \
  atomic_compare_exchange_strong(obj, expected, desired)

#define atomic_thread_fence(order) ((void)(order))
#define atomic_signal_fence(order) ((void)(order))

/* 标志位 */
typedef struct {
  volatile int __v;
} atomic_flag;

#define ATOMIC_FLAG_INIT \
  { 0 }

#define atomic_flag_test_and_set(flag) (*(flag) = (atomic_flag){1}, 1)
#define atomic_flag_test_and_set_explicit(flag, order) \
  ((void)(order), atomic_flag_test_and_set(flag))
#define atomic_flag_clear(flag) (*(flag) = (atomic_flag){0})
#define atomic_flag_clear_explicit(flag, order) \
  ((void)(order), atomic_flag_clear(flag))

#define ATOMIC_VAR_INIT(value) (value)



#endif /* CODEPAD_COMPAT_STDATOMIC_H */
