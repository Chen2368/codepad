#include <stdio.h>
#include <math.h>

/* e^x 的麦克劳林展开：1 + x + x^2/2! + ... + x^n/n! */
static double taylor_exp(double x, int n) {
    double term = 1.0;
    double sum = 1.0;
    for (int k = 1; k <= n; k++) {
        term *= x / k;
        sum += term;
    }
    return sum;
}

static double fact(int n) {
    double r = 1.0;
    for (int i = 2; i <= n; i++) {
        r *= i;
    }
    return r;
}

int main(void) {
    const double x = 1.0;
    const double exact = exp(x);

    printf("e^%.1f = %.10f\n\n", x, exact);
    printf("%3s %18s %12s %12s\n", "n", "taylor", "err", "bound");

    for (int n = 1; n <= 12; n++) {
        double t = taylor_exp(x, n);
        /* 拉格朗日余项：R_n = e^xi * x^(n+1) / (n+1)!，0 < xi < 1，故 e^xi < 3 */
        double bound = 3.0 / fact(n + 1);
        printf("%3d %18.10f %12.3e %12.3e\n", n, t, fabs(t - exact), bound);
    }

    return 0;
}
