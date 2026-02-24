# nqueens
# =======
# Pure functional N-Queens benchmark over U32 bitsets.
# Columns and diagonals are immutable masks updated by recursion.
# Workload repeats solves to target ~1s on JS mode.

# Types
# -----

type Bool() {
  T{}
  F{}
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

# Builds a mask with the low `n` bits set.
def low_mask(n: U32) -> U32:
  (1 << n) - 1

# Search
# ------

# Counts N-Queens solutions for board size `n`.
def solve_n(n: U32) -> U32:
  all = low_mask(n)
  solve(all, 0, 0, 0)

# Solves from a partial placement state.
def solve(all: U32, cols: U32, diag_l: U32, diag_r: U32) -> U32:
  done = u2b(cols === all)
  solve_go(done, all, cols, diag_l, diag_r)

# Returns 1 when all rows are placed; otherwise iterates free bits.
def solve_go(done: Bool, all: U32, cols: U32, diag_l: U32, diag_r: U32) -> U32:
  match done:
    case T{}:
      1
    case F{}:
      used = cols | diag_l | diag_r
      free = all ^ used
      pick(all, cols, diag_l, diag_r, free, 0)

# Iterates all candidate bits for the current row.
def pick(all: U32, cols: U32, diag_l: U32, diag_r: U32, bits: U32, acc: U32) -> U32:
  done = u2b(bits === 0)
  pick_go(done, all, cols, diag_l, diag_r, bits, acc)

# Explores one candidate and recurs on the remaining candidates.
def pick_go(done: Bool, all: U32, cols: U32, diag_l: U32, diag_r: U32, bits: U32, acc: U32) -> U32:
  match done:
    case T{}:
      acc
    case F{}:
      bit    = bits & (0 - bits)
      bits   = bits - bit
      cols2  = cols | bit
      l2     = ((diag_l | bit) << 1) & all
      r2     = ((diag_r | bit) >> 1) & all
      acc    = acc + solve(all, cols2, l2, r2)
      pick(all, cols, diag_l, diag_r, bits, acc)

# Benchmark
# ---------

# Runs repeated solves and mixes the results.
def bench(rounds: U32, acc: U32) -> U32:
  done = u2b(rounds === 0)
  bench_go(done, rounds, acc)

# Runs one benchmark round and recurs.
def bench_go(done: Bool, rounds: U32, acc: U32) -> U32:
  match done:
    case T{}:
      acc
    case F{}:
      s12    = solve_n(11)
      s13    = solve_n(12)
      acc    = (acc ^ s12) + s13 * 97
      rounds = rounds - 1
      bench(rounds, acc)

# Main
# ----

# Entry point.
def main() -> U32:
  bench(1, 0)
