# bignat_mul
# ===========
# Pure functional big-integer multiplication benchmark over U32 limbs.
# Big integers are immutable little-endian lists in base 2^15.
# Workload runs repeated schoolbook multiplications and folds checksums.

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

type St() {
  st{U32, U32}
}

# Config
# ------

# Returns the limb base (2^15).
def base_u32() -> U32:
  32768

# Utils
# -----

# Converts U32 (0/nonzero) to Bool.
def u2b(n: U32) -> Bool:
  match n:
    case 0:
      F{}
    case x:
      T{}

# Advances a U32 LCG seed.
def rng(seed: U32) -> U32:
  seed * 1664525 + 1013904223

# Bigint Build
# ------------

# Builds a pseudo-random bigint with `len` limbs.
def gen(len: U32, seed: U32) -> Lst:
  done = u2b(len === 0)
  gen_go(done, len, seed)

# Builds one limb and recurs.
def gen_go(done: Bool, len: U32, seed: U32) -> Lst:
  match done:
    case T{}:
      []
    case F{}:
      seed = rng(seed)
      limb = seed % base_u32()
      len  = len - 1
      limb<>gen(len, seed)

# Bigint Add
# ----------

# Adds two limb lists with a carry.
def add(xs: Lst, ys: Lst, car: U32) -> Lst:
  add_l(xs, ys, car)

# Handles the left-focused add recursion.
def add_l(xs: Lst, ys: Lst, car: U32) -> Lst:
  match xs:
    case []:
      add_nil(ys, car)
    case x<>xt:
      add_pair(x, xt, ys, car)

# Handles pairwise addition when left list is non-empty.
def add_pair(x: U32, xt: Lst, ys: Lst, car: U32) -> Lst:
  match ys:
    case []:
      add_one(x, xt, car)
    case y<>yt:
      s = x + y + car
      b = base_u32()
      d = s % b
      c = s / b
      d<>add(xt, yt, c)

# Adds a carry into an empty-left case.
def add_nil(ys: Lst, car: U32) -> Lst:
  match ys:
    case []:
      add_end(car)
    case y<>yt:
      add_one(y, yt, car)

# Adds one limb plus carry, then recurs.
def add_one(x: U32, xt: Lst, car: U32) -> Lst:
  s = x + car
  b = base_u32()
  d = s % b
  c = s / b
  d<>add(xt, [], c)

# Emits final carry if nonzero.
def add_end(car: U32) -> Lst:
  done = u2b(car === 0)
  add_end_go(done, car)

# Dispatches final carry emission.
def add_end_go(done: Bool, car: U32) -> Lst:
  match done:
    case T{}:
      []
    case F{}:
      car<>[]

# Bigint Mul
# ----------

# Multiplies a limb list by one scalar limb with carry.
def mul_scalar(xs: Lst, k: U32, car: U32) -> Lst:
  match xs:
    case []:
      add_end(car)
    case x<>xt:
      p = x * k + car
      b = base_u32()
      d = p % b
      c = p / b
      d<>mul_scalar(xt, k, c)

# Prepends `n` zero limbs to a bigint.
def shift(xs: Lst, n: U32) -> Lst:
  done = u2b(n === 0)
  shift_go(done, xs, n)

# Dispatches zero/nonzero shift depth.
def shift_go(done: Bool, xs: Lst, n: U32) -> Lst:
  match done:
    case T{}:
      xs
    case F{}:
      n = n - 1
      0<>shift(xs, n)

# Accumulates schoolbook rows for full multiplication.
def mul_rows(as: Lst, bs: Lst, sh: U32, acc: Lst) -> Lst:
  match as:
    case []:
      acc
    case a<>at:
      row = mul_scalar(bs, a, 0)
      row = shift(row, sh)
      acc = add(acc, row, 0)
      sh  = sh + 1
      mul_rows(at, bs, sh, acc)

# Multiplies two bigints.
def mul(as: Lst, bs: Lst) -> Lst:
  mul_rows(as, bs, 0, [])

# Hash
# ----

# Folds a limb list into a U32 checksum.
def hash(xs: Lst, acc: U32) -> U32:
  match xs:
    case []:
      acc
    case x<>xt:
      acc = (acc ^ x) * 16777619 + 2166136261
      hash(xt, acc)

# Benchmark
# ---------

# Runs one multiplication-heavy round and returns next state.
def round(seed: U32, acc: U32) -> St:
  a_seed = rng(seed)
  b_seed = rng(a_seed)
  c_seed = rng(b_seed)
  a      = gen(96, a_seed)
  b      = gen(96, b_seed)
  c      = gen(96, c_seed)
  p      = mul(a, b)
  q      = mul(b, c)
  acc    = hash(p, acc ^ seed)
  acc    = hash(q, acc)
  seed   = rng(c_seed)
  st{seed, acc}

# Runs one round from a benchmark state.
def round_st(s: St) -> St:
  match s:
    case st{seed, acc}:
      round(seed, acc)

# Runs benchmark rounds.
def bench(rounds: U32, seed: U32, acc: U32) -> U32:
  done = u2b(rounds === 0)
  bench_go(done, rounds, seed, acc)

# Performs four rounds per recursion step.
def bench_go(done: Bool, rounds: U32, seed: U32, acc: U32) -> U32:
  match done:
    case T{}:
      acc
    case F{}:
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
  bench(146, 1, 0)
