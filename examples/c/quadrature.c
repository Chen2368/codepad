#include <stdio.h>
#include <math.h>

/* 被积函数 f(x) = sin(x)，积分区间 [0, pi] */
static double f(double x) { return sin(x); }

/* 复合梯形公式 */
static double trapezoid(double a, double b, int n) {
    double h = (b - a) / n;
    double sum = (f(a) + f(b)) / 2.0;
    for (int i = 1; i < n; i++) {
        sum += f(a + i * h);
    }
    return sum * h;
}

/* 复合辛普森公式（n 必须为偶数） */
static double simpson(double a, double b, int n) {
    double h = (b - a) / n;
    double sum = f(a) + f(b);
    for (int i = 1; i < n; i++) {
        sum += (i % 2 == 1 ? 4.0 : 2.0) * f(a + i * h);
    }
    return sum * h / 3.0;
}

int main(void) {
    const double pi = 3.14159265358979323846;
    const double a = 0.0;
    const double b = pi;
    const double exact = 2.0; /* ∫₀^π sin x dx = 2 */

    printf("%4s %14s %12s %14s %12s\n", "n", "trapezoid", "err", "simpson", "err");
    for (int n = 10; n <= 320; n *= 2) {
        double t = trapezoid(a, b, n);
        double s = simpson(a, b, n);
        printf("%4d %14.8f %12.2e %14.8f %12.2e\n",
               n, t, fabs(t - exact), s, fabs(s - exact));
    }
    return 0;
}
