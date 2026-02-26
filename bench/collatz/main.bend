# Computes the total Collatz stopping-steps for all U32s in [1..N].
# Each number is iterated via the 3n+1 rule until it reaches 1,
# counting steps with a tail-recursive accumulator.
# Stresses tail recursion, U32 arithmetic, and branching.

# Counts steps to reach 1 from n
def steps(n: U32, acc: U32) -> U32:
  match n:
    case 1:
      acc
    case k:
      rem = k % 2
      match rem:
        case 0:
          steps(k / 2, acc + 1)
        case r:
          steps(k * 3 + 1, acc + 1)

# Sums step counts for all numbers in [1..n]
def total(n: U32, acc: U32) -> U32:
  match n:
    case 0:
      acc
    case k:
      total(k - 1, acc + steps(k, 0))

def main() -> U32:
  total(4000000, 0)
