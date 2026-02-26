# This benchmark evaluates the classic naive Fibonacci recursion over U32.
# It is intentionally non-memoized, so it stresses recursive call overhead
# and repeated subproblem re-evaluation.

def u32_fib(n: U32) -> U32:
  match n:
    case 0:
      0
    case 1:
      1
    case k:
      u32_fib(k - 1) + u32_fib(k - 2)

def main() -> U32:
  a = u32_fib(38)
  b = u32_fib(35)
  a + b
