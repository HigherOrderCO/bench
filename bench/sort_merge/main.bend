# sort_merge
# ==========
# Pure functional merge-sort benchmark over immutable U32 lists.
# It builds pseudo-random lists, sorts them, then folds a checksum.
# Workload is repeated to target ~1s on the JS backend.

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

type Split() {
  sp{Lst, Lst}
}

type St() {
  st{U32, U32}
}

# Utils
# -----

# Converts U32 (0/nonzero) to Bool.
def u2b(n: U32) -> Bool:
  match n:
    case 0:
      F{}
    case x:
      T{}

# Advances a U32 linear-congruential generator seed.
def rng(seed: U32) -> U32:
  seed * 1664525 + 1013904223

# List Build
# ----------

# Builds a list of pseudo-random U32 values.
def gen(len: U32, seed: U32) -> Lst:
  done = u2b(len === 0)
  gen_go(done, len, seed)

# Builds one list step or stops at zero length.
def gen_go(done: Bool, len: U32, seed: U32) -> Lst:
  match done:
    case T{}:
      []
    case F{}:
      val = rng(seed)
      len = len - 1
      val<>gen(len, val)

# Split
# -----

# Splits a list into two lists by alternating elements.
def split(xs: Lst) -> Split:
  match xs:
    case []:
      sp{[], []}
    case x<>[]:
      sp{[x], []}
    case x<>y<>ys:
      p = split(ys)
      split_pair(x, y, p)

# Prepends the extracted pair onto a recursive split result.
def split_pair(x: U32, y: U32, p: Split) -> Split:
  match p:
    case sp{xs, ys}:
      sp{x<>xs, y<>ys}

# Merge Sort
# ----------

# Merges two sorted lists.
def merge(xs: Lst, ys: Lst) -> Lst:
  match xs:
    case []:
      ys
    case x<>xt:
      merge_l(x, xt, ys)

# Merges a non-empty left list against the right list.
def merge_l(x: U32, xt: Lst, ys: Lst) -> Lst:
  match ys:
    case []:
      x<>xt
    case y<>yt:
      le = u2b(x <= y)
      merge_pick(le, x, xt, y, yt)

# Picks the next head when merging sorted lists.
def merge_pick(le: Bool, x: U32, xt: Lst, y: U32, yt: Lst) -> Lst:
  match le:
    case T{}:
      x<>merge(xt, y<>yt)
    case F{}:
      y<>merge(x<>xt, yt)

# Sorts a list with merge sort.
def sort(xs: Lst) -> Lst:
  match xs:
    case []:
      []
    case x<>[]:
      [x]
    case x<>y<>ys:
      p = split(x<>y<>ys)
      sort_split(p)

# Sorts each split side and merges the results.
def sort_split(p: Split) -> Lst:
  match p:
    case sp{xs, ys}:
      l = sort(xs)
      r = sort(ys)
      merge(l, r)

# Checksum
# --------

# Folds a list into a U32 checksum.
def hash(xs: Lst, acc: U32) -> U32:
  match xs:
    case []:
      acc
    case x<>xt:
      acc = (acc ^ x) * 16777619 + 2166136261
      hash(xt, acc)

# Benchmark
# ---------

# Runs one build + sort + hash step and advances the seed.
def step(seed: U32, acc: U32) -> St:
  xs   = gen(2048, seed)
  ys   = sort(xs)
  acc  = hash(ys, acc ^ seed)
  seed = rng(seed)
  st{seed, acc}

# Runs one step from a benchmark state.
def step_st(s: St) -> St:
  match s:
    case st{seed, acc}:
      step(seed, acc)

# Runs repeated list-build + merge-sort + hash rounds.
def bench(rounds: U32, seed: U32, acc: U32) -> U32:
  done = u2b(rounds === 0)
  bench_go(done, rounds, seed, acc)

# Runs one benchmark round, then recurs.
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

# Continues the benchmark from a computed state.
def bench_take(rounds: U32, s: St) -> U32:
  match s:
    case st{seed, acc}:
      bench(rounds, seed, acc)

# Main
# ----

# Entry point.
def main() -> U32:
  bench(5, 1, 0)
