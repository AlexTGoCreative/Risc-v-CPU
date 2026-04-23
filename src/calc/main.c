#include <stdio.h>
#include <string.h>

/* -------------------------------------------------------
 * Command interpreter firmware — simulation demo
 *
 * Processes a hardcoded command script (no real UART input
 * needed in simulation). Prints results for each command.
 * Ends with '>' which triggers $finish() in darkuart.v.
 *
 * Commands:
 *   sum  N  -> 1 + 2 + ... + N
 *   max  N  -> largest prime <= N  (brute force)
 *   fib  N  -> Nth Fibonacci number
 *   fact N  -> N! (factorial)
 *   end     -> print summary and exit
 * ------------------------------------------------------- */

/* ---- helpers ---- */

static int sum(int n)
{
    int s = 0, i;
    for (i = 1; i <= n; i++) s += i;
    return s;
}

static int is_prime(int n)
{
    int i;
    if (n < 2) return 0;
    for (i = 2; i * i <= n; i++)
        if (n % i == 0) return 0;
    return 1;
}

static int max_prime(int n)
{
    int i;
    for (i = n; i >= 2; i--)
        if (is_prime(i)) return i;
    return -1;
}

static int fib(int n)
{
    int a = 0, b = 1, i, t;
    if (n == 0) return 0;
    for (i = 1; i < n; i++) { t = a + b; a = b; b = t; }
    return b;
}

static int fact(int n)
{
    int r = 1, i;
    for (i = 2; i <= n; i++) r *= i;
    return r;
}

/* ---- command table ---- */

struct cmd { const char *name; int arg; };

static const struct cmd script[] = {
    { "sum",  10    },
    { "sum",  100   },
    { "sum",  1000  },
    { "fib",  10    },
    { "fib",  20    },
    { "fib",  30    },
    { "fact", 5     },
    { "fact", 10    },
    { "fact", 12    },
    { "max",  50    },
    { "max",  500   },
    { "max",  1000  },
    { "end",  0     },
};

#define NSCRIPT (int)(sizeof(script)/sizeof(script[0]))

/* ---- main ---- */

int main(void)
{
    int i, result;

    printf("=== Command Interpreter ===\n");
    printf("Running %d commands...\n\n", NSCRIPT - 1);

    for (i = 0; i < NSCRIPT; i++)
    {
        const char *cmd = script[i].name;
        int arg = script[i].arg;

        if (!strcmp(cmd, "end"))
        {
            printf("--- end ---\n");
            printf("All commands executed successfully.\n");

            /* printing '>' ends the simulation (darkuart.v -> $finish) */
            printf(">\n");
            while (1);  /* halt — simulation will finish after '>' */
        }

        /* echo the command */
        printf("%s %d = ", cmd, arg);

        if (!strcmp(cmd, "sum"))
        {
            result = sum(arg);
            printf("%d  (formula: %d)\n", result, arg*(arg+1)/2);
        }
        else if (!strcmp(cmd, "fib"))
        {
            result = fib(arg);
            printf("%d\n", result);
        }
        else if (!strcmp(cmd, "fact"))
        {
            result = fact(arg);
            printf("%d\n", result);
        }
        else if (!strcmp(cmd, "max"))
        {
            result = max_prime(arg);
            printf("largest prime up to %d is %d\n", arg, result);
        }
        else
        {
            printf("unknown command\n");
        }
    }

    return 0;
}
