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

# Runs repeated Fibonacci evaluations and mixes results.
def bench(rounds: U32, acc: U32) -> U32:
  match rounds:
    case 0:
      acc
    case r:
      a = u32_fib(38)
      b = u32_fib(35)
      acc = (acc ^ a) + b * 97 + r
      bench(r - 1, acc)

def main() -> U32:
  bench(240000, 0)
