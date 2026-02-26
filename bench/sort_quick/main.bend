# sort_quick
# ==========
# Pure functional quicksort over immutable U32 lists.
# Partitions by pivot, recurses on halves, appends results.
# Stresses list traversal, conditional branching, and allocation.

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

type Pair() {
  pair{Lst, Lst}
}

type St() {
  st{U32, U32}
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

# Advances a linear-congruential generator seed
def rng(seed: U32) -> U32:
  seed * 1664525 + 1013904223

# List Build
# ----------

# Builds a list of pseudo-random U32 values
def gen(len: U32, seed: U32) -> Lst:
  done = u2b(len === 0)
  gen_go(done, len, seed)

# Builds one step or stops
def gen_go(done: Bool, len: U32, seed: U32) -> Lst:
  match done:
    case T{}:
      []
    case F{}:
      val = rng(seed)
      val<>gen(len - 1, val)

# Partition
# ---------

# Partitions a list into elements <= pivot and > pivot
def part(piv: U32, xs: Lst) -> Pair:
  match xs:
    case []:
      pair{[], []}
    case x<>xt:
      le = u2b(x <= piv)
      p  = part(piv, xt)
      part_put(le, x, p)

# Unpacks the pair from a partition result
def part_put(le: Bool, x: U32, p: Pair) -> Pair:
  match p:
    case pair{lo, hi}:
      part_ins(le, x, lo, hi)

# Inserts element into the correct side
def part_ins(le: Bool, x: U32, lo: Lst, hi: Lst) -> Pair:
  match le:
    case T{}:
      pair{x<>lo, hi}
    case F{}:
      pair{lo, x<>hi}

# Append
# ------

# Appends two lists
def app(xs: Lst, ys: Lst) -> Lst:
  match xs:
    case []:
      ys
    case x<>xt:
      x<>app(xt, ys)

# Quicksort
# ---------

# Sorts a list with quicksort (head as pivot)
def sort(xs: Lst) -> Lst:
  match xs:
    case []:
      []
    case x<>xt:
      p = part(x, xt)
      sort_pair(x, p)

# Sorts both halves and combines with pivot in between
def sort_pair(piv: U32, p: Pair) -> Lst:
  match p:
    case pair{lo, hi}:
      lo = sort(lo)
      hi = sort(hi)
      app(lo, piv<>hi)

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

# Benchmark
# ---------

# Runs one build + sort + hash step
def step(seed: U32, acc: U32) -> St:
  xs   = gen(2048, seed)
  ys   = sort(xs)
  acc  = hash(ys, acc ^ seed)
  seed = rng(seed)
  st{seed, acc}

# Advances one step from a state
def step_st(s: St) -> St:
  match s:
    case st{seed, acc}:
      step(seed, acc)

# Runs repeated rounds of build + sort + hash
def bench(rounds: U32, seed: U32, acc: U32) -> U32:
  done = u2b(rounds === 0)
  bench_go(done, rounds, seed, acc)

# One benchmark round, then recurs
def bench_go(done: Bool, rounds: U32, seed: U32, acc: U32) -> U32:
  match done:
    case T{}:
      acc
    case F{}:
      s      = step(seed, acc)
      s      = step_st(s)
      s      = step_st(s)
      s      = step_st(s)
      rounds = rounds - 1
      bench_take(rounds, s)

# Continues benchmark from a computed state
def bench_take(rounds: U32, s: St) -> U32:
  match s:
    case st{seed, acc}:
      bench(rounds, seed, acc)

# Main
# ----

# Entry point
def main() -> U32:
  bench(390, 1, 0)
