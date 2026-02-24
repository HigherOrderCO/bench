# queue_bank
# ==========
# Banker's queue (two-list) benchmark. Enqueues N items per round,
# drains all, repeats M rounds. Stresses amortized list reversal,
# ADT pattern matching, and tail-recursive accumulation.

# Types
# -----

type Lst() {
  nil{}
  cons{U32, Lst}
}

type Queue() {
  queue{Lst, Lst}
}

# Utils
# -----

# Advances a linear-congruential generator seed
def rng(seed: U32) -> U32:
  seed * 1664525 + 1013904223

# Reverse
# -------

# Reverses a list with tail-recursive accumulator
def rev(xs: Lst, acc: Lst) -> Lst:
  match xs:
    case []:
      acc
    case x<>xt:
      rev(xt, x<>acc)

# Queue Operations
# ----------------

# Enqueues n pseudo-random values into a queue
def fill(f: Lst, b: Lst, n: U32, seed: U32) -> Queue:
  match n:
    case 0:
      queue{f, b}
    case k:
      seed = rng(seed)
      fill(f, seed<>b, k - 1, seed)

# Drains front list, folding checksum
def drain_f(f: Lst, b: Lst, acc: U32) -> U32:
  match f:
    case x<>xt:
      acc = (acc ^ x) * 16777619 + 2166136261
      drain_f(xt, b, acc)
    case []:
      drain_b(b, acc)

# When front empty, reverses back and continues draining
def drain_b(b: Lst, acc: U32) -> U32:
  match b:
    case []:
      acc
    case x<>xt:
      drain_f(rev(xt, [x]), [], acc)

# Benchmark
# ---------

# Runs repeated fill + drain rounds
def bench(rounds: U32, size: U32, seed: U32, acc: U32) -> U32:
  match rounds:
    case 0:
      acc
    case r:
      q    = fill([], [], size, seed)
      acc  = drain_q(q, acc)
      seed = rng(seed)
      bench(r - 1, size, seed, acc)

# Unpacks queue for draining
def drain_q(q: Queue, acc: U32) -> U32:
  match q:
    case queue{f, b}:
      drain_f(f, b, acc)

# Main
# ----

# Entry point
def main() -> U32:
  bench(400, 512, 1, 0)
