# edit_dist
# =========
# Pure functional Levenshtein distance benchmark over U32 sequences.
# Uses immutable row-DP with recursion and pattern matching.
# Workload repeats independent pair distances to target ~1s on JS mode.

# Types
# -----

type Lst() {
  nil{}
  cons{U32, Lst}
}

type St() {
  st{U32, U32}
}

# Utils
# -----

# Advances a U32 linear-congruential generator seed.
def rng(seed: U32) -> U32:
  seed * 1664525 + 1013904223

# Returns the minimum of two U32 values.
def min2(a: U32, b: U32) -> U32:
  match a <= b:
    case 0:
      b
    case x:
      a

# Returns the minimum of three U32 values.
def min3(a: U32, b: U32, c: U32) -> U32:
  min2(min2(a, b), c)

# Returns 1 when values differ, else 0.
def neq_u32(a: U32, b: U32) -> U32:
  match a !== b:
    case 0:
      0
    case x:
      1

# Reverses a list using an accumulator.
def rev(xs: Lst, acc: Lst) -> Lst:
  match xs:
    case []:
      acc
    case x<>xt:
      rev(xt, x<>acc)

# Returns the final element of a non-empty row.
def last(xs: Lst) -> U32:
  match xs:
    case []:
      0
    case x<>xt:
      last_go(x, xt)

# Scans to the final element of a non-empty suffix.
def last_go(x: U32, xs: Lst) -> U32:
  match xs:
    case []:
      x
    case y<>yt:
      last_go(y, yt)

# Sequence Build
# --------------

# Builds a pseudo-random U32 sequence of length `len`.
def gen(len: U32, seed: U32) -> Lst:
  match len === 0:
    case 0:
      gen_go(len, seed)
    case x:
      []

# Builds one random element and recurs.
def gen_go(len: U32, seed: U32) -> Lst:
  seed = rng(seed)
  val  = seed % 26
  len  = len - 1
  val<>gen(len, seed)

# Returns sequence length as U32.
def len(xs: Lst, acc: U32) -> U32:
  match xs:
    case []:
      acc
    case x<>xt:
      len(xt, acc + 1)

# Builds an initial DP row [0, 1, ..., n].
def init_row(n: U32) -> Lst:
  init_row_go(0, n)

# Builds one cell of the initial row.
def init_row_go(i: U32, n: U32) -> Lst:
  match i === n:
    case 0:
      init_row_step(i, n)
    case x:
      i<>[]

# Builds the recursive branch for initial row construction.
def init_row_step(i: U32, n: U32) -> Lst:
  i<>init_row_go(i + 1, n)

# Edit Distance
# -------------

# Scans one row cell-by-cell and returns the completed row.
def row_scan(x: U32, ys: Lst, ups: Lst, diag: U32, left: U32, rev_row: Lst) -> Lst:
  match ys ups:
    case [] []:
      rev(rev_row, [])
    case y<>yt up<>ut:
      ins = left + 1
      del = up + 1
      sub = diag + neq_u32(x, y)
      cur = min3(ins, del, sub)
      row_scan(x, yt, ut, up, cur, cur<>rev_row)
    case ys ups:
      rev(rev_row, [])

# Builds the next DP row for one source character.
def build_row(x: U32, ys: Lst, prev: Lst, i: U32) -> Lst:
  match prev:
    case []:
      [i]
    case p0<>pt:
      row_scan(x, ys, pt, p0, i, [i])

# Iterates source rows and returns final edit distance.
def dist_rows(xs: Lst, ys: Lst, prev: Lst, i: U32) -> U32:
  match xs:
    case []:
      last(prev)
    case x<>xt:
      row = build_row(x, ys, prev, i)
      dist_rows(xt, ys, row, i + 1)

# Computes Levenshtein distance between two sequences.
def dist(xs: Lst, ys: Lst) -> U32:
  n   = len(ys, 0)
  row = init_row(n)
  dist_rows(xs, ys, row, 1)

# Benchmark
# ---------

# Runs one edit-distance round and returns next state.
def round(seed: U32, acc: U32) -> St:
  a_seed = rng(seed)
  b_seed = rng(a_seed)
  c_seed = rng(b_seed)
  a      = gen(144, a_seed)
  b      = gen(144, b_seed)
  c      = gen(144, c_seed)
  d0     = dist(a, b)
  d1     = dist(b, c)
  acc    = (acc ^ d0) + d1 * 131 + seed
  seed   = rng(c_seed)
  st{seed, acc}

# Runs one round from an existing benchmark state.
def round_st(s: St) -> St:
  match s:
    case st{seed, acc}:
      round(seed, acc)

# Runs benchmark rounds.
def bench(rounds: U32, seed: U32, acc: U32) -> U32:
  match rounds === 0:
    case 0:
      bench_go(rounds, seed, acc)
    case x:
      acc

# Runs four rounds per recursion step.
def bench_go(rounds: U32, seed: U32, acc: U32) -> U32:
  s      = round(seed, acc)
  s      = round_st(s)
  s      = round_st(s)
  s      = round_st(s)
  rounds = rounds - 1
  bench_take(rounds, s)

# Continues benchmark recursion from a state pair.
def bench_take(rounds: U32, s: St) -> U32:
  match s:
    case st{seed, acc}:
      bench(rounds, seed, acc)

# Main
# ----

# Entry point.
def main() -> U32:
  bench(224, 1, 0)
