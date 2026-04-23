#include <stdio.h>
#include <io.h>

int fibonacci(int n)
{
    if (n <= 1) return n;
    return fibonacci(n - 1) + fibonacci(n - 2);
}

int factorial(int n)
{
    int result = 1;
    int i;
    for (i = 2; i <= n; i++)
        result *= i;
    return result;
}

int main(void)
{
    int i;

    printf("=== DarkRISCV Test Program ===\n\n");

    /* basic arithmetic */
    printf("--- Arithmetic ---\n");
    printf("  2 + 3 = %d\n", 2 + 3);
    printf("  10 - 4 = %d\n", 10 - 4);
    printf("  6 * 7 = %d\n", 6 * 7);
    printf("  100 / 3 = %d remainder %d\n", 100 / 3, 100 % 3);

    /* fibonacci sequence */
    printf("\n--- Fibonacci ---\n");
    for (i = 0; i < 15; i++)
        printf("  fib(%d) = %d\n", i, fibonacci(i));

    /* factorials */
    printf("\n--- Factorials ---\n");
    for (i = 1; i <= 10; i++)
        printf("  %d! = %d\n", i, factorial(i));

    /* bitwise operations */
    printf("\n--- Bitwise Ops ---\n");
    printf("  0xFF & 0x0F = 0x%x\n", 0xFF & 0x0F);
    printf("  0xA0 | 0x05 = 0x%x\n", 0xA0 | 0x05);
    printf("  0xFF ^ 0x55 = 0x%x\n", 0xFF ^ 0x55);
    printf("  1 << 10 = %d\n", 1 << 10);

    /* memory-mapped I/O: blink LEDs */
    printf("\n--- LED Test ---\n");
    for (i = 0; i < 4; i++)
    {
        io->led = (1 << i);
        printf("  LED = 0x%x\n", io->led);
    }
    io->led = 0;

    /* array sorting (bubble sort) */
    printf("\n--- Bubble Sort ---\n");
    int arr[] = {42, 17, 93, 5, 28, 61, 3, 84};
    int n = 8;
    int j, tmp;

    printf("  before: ");
    for (i = 0; i < n; i++) printf("%d ", arr[i]);
    printf("\n");

    for (i = 0; i < n - 1; i++)
        for (j = 0; j < n - i - 1; j++)
            if (arr[j] > arr[j + 1])
            {
                tmp = arr[j];
                arr[j] = arr[j + 1];
                arr[j + 1] = tmp;
            }

    printf("  after:  ");
    for (i = 0; i < n; i++) printf("%d ", arr[i]);
    printf("\n");

    printf("\n=== Test Complete ===\n");

    return 0;
}
