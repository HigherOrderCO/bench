# prime_sieve
# ===========
# Sieve of Eratosthenes on a linked list of U32s. Builds [2..N],
# repeatedly filters out multiples of each prime, and checksums
# the result. Stresses list filtering, tail recursion, and U32 ops.

# Types
# -----

type Bool() {
  T{}
  F{}
}

type Lst() {
  nil{}
  cons{U32, Lst}
}

# Utils
# -----

# Converts U32 zero/nonzero to Bool
def u2b(n: U32) -> Bool:
  match n:
    case 0:
      F{}
    case x:
      T{}

# Reverses a list with tail-recursive accumulator
def rev(xs: Lst, acc: Lst) -> Lst:
  match xs:
    case []:
      acc
    case x<>xt:
      rev(xt, x<>acc)

# Range
# -----

# Builds [cur-n .. cur] as a list (tail-recursive)
def range(n: U32, cur: U32, acc: Lst) -> Lst:
  match n:
    case 0:
      cur<>acc
    case k:
      range(k - 1, cur - 1, cur<>acc)

# Filter
# ------

# Conditionally prepends x to acc
def maybe_cons(keep: Bool, x: U32, acc: Lst) -> Lst:
  match keep:
    case F{}:
      acc
    case T{}:
      x<>acc

# Filters out multiples of p from a list (tail-recursive)
def filter(p: U32, xs: Lst, acc: Lst) -> Lst:
  match xs:
    case []:
      rev(acc, [])
    case x<>xt:
      keep = u2b(x % p)
      acc  = maybe_cons(keep, x, acc)
      filter(p, xt, acc)

# Sieve
# -----

# Runs the sieve: picks head as prime, filters rest, recurses
def sieve(xs: Lst, primes: Lst, max: U32) -> Lst:
  match xs:
    case []:
      primes
    case p<>rest:
      sieve_chk(u2b(p * p <= max), p, rest, primes, max)

# If p*p <= max, filter and continue; otherwise all remaining are prime
def sieve_chk(cont: Bool, p: U32, rest: Lst, primes: Lst, max: U32) -> Lst:
  match cont:
    case T{}:
      filtered = filter(p, rest, [])
      sieve(filtered, p<>primes, max)
    case F{}:
      rev(p<>rest, primes)

# Checksum
# --------

# Folds a list into a U32 checksum
def hash(xs: Lst, acc: U32) -> U32:
  match xs:
    case []:
      acc
    case x<>xt:
      acc = (acc ^ x) * 16777619 + 2166136261
      hash(xt, acc)

# Main
# ----

# Entry point
def main() -> U32:
  xs     = range(1999998, 2000000, [])
  primes = sieve(xs, [], 2000000)
  hash(primes, 0)
