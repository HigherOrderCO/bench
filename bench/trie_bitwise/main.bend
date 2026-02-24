# trie_bitwise
# ============
# Pure functional persistent bitwise trie benchmark over U32 keys.
# Builds a map with immutable inserts, runs lookup sweeps, then folds.
# Workload is tuned for ~1s on JS mode.

# Types
# -----

type Bool() {
  T{}
  F{}
}

type Mb() {
  none{}
  some{U32}
}

type Trie() {
  emp{}
  nod{Mb, Trie, Trie}
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

# Reads one bit from a key at shift position `sh`.
def key_bit(key: U32, sh: U32) -> U32:
  (key >> sh) & 1

# Trie Insert
# -----------

# Inserts or replaces `key -> val` at depth `dep`.
def ins(t: Trie, key: U32, val: U32, dep: U32) -> Trie:
  done = u2b(dep === 0)
  ins_go(done, t, key, val, dep)

# Dispatches leaf/internal insertion.
def ins_go(done: Bool, t: Trie, key: U32, val: U32, dep: U32) -> Trie:
  match done:
    case T{}:
      ins_leaf(t, val)
    case F{}:
      dep = dep - 1
      bit = key_bit(key, dep)
      ins_bit(bit, t, key, val, dep)

# Sets the value at the current trie node.
def ins_leaf(t: Trie, val: U32) -> Trie:
  match t:
    case emp{}:
      nod{some{val}, emp{}, emp{}}
    case nod{mb, l, r}:
      nod{some{val}, l, r}

# Branches insertion on bit value.
def ins_bit(bit: U32, t: Trie, key: U32, val: U32, dep: U32) -> Trie:
  match bit:
    case 0:
      ins_lft(t, key, val, dep)
    case x:
      ins_rgt(t, key, val, dep)

# Inserts into the left branch.
def ins_lft(t: Trie, key: U32, val: U32, dep: U32) -> Trie:
  match t:
    case emp{}:
      l = ins(emp{}, key, val, dep)
      nod{none{}, l, emp{}}
    case nod{mb, l, r}:
      l = ins(l, key, val, dep)
      nod{mb, l, r}

# Inserts into the right branch.
def ins_rgt(t: Trie, key: U32, val: U32, dep: U32) -> Trie:
  match t:
    case emp{}:
      r = ins(emp{}, key, val, dep)
      nod{none{}, emp{}, r}
    case nod{mb, l, r}:
      r = ins(r, key, val, dep)
      nod{mb, l, r}

# Trie Lookup
# -----------

# Looks up a key at depth `dep`, defaulting to 0 when absent.
def get(t: Trie, key: U32, dep: U32) -> U32:
  done = u2b(dep === 0)
  get_go(done, t, key, dep)

# Dispatches leaf/internal lookup.
def get_go(done: Bool, t: Trie, key: U32, dep: U32) -> U32:
  match done:
    case T{}:
      get_leaf(t)
    case F{}:
      dep = dep - 1
      bit = key_bit(key, dep)
      get_bit(bit, t, key, dep)

# Returns the value at the current node, or 0 if absent.
def get_leaf(t: Trie) -> U32:
  match t:
    case emp{}:
      0
    case nod{mb, l, r}:
      mb_u32(mb)

# Converts maybe-value to U32.
def mb_u32(mb: Mb) -> U32:
  match mb:
    case none{}:
      0
    case some{v}:
      v

# Branches lookup on bit value.
def get_bit(bit: U32, t: Trie, key: U32, dep: U32) -> U32:
  match bit:
    case 0:
      get_lft(t, key, dep)
    case x:
      get_rgt(t, key, dep)

# Looks up in the left branch.
def get_lft(t: Trie, key: U32, dep: U32) -> U32:
  match t:
    case emp{}:
      0
    case nod{mb, l, r}:
      get(l, key, dep)

# Looks up in the right branch.
def get_rgt(t: Trie, key: U32, dep: U32) -> U32:
  match t:
    case emp{}:
      0
    case nod{mb, l, r}:
      get(r, key, dep)

# Trie Fold
# ---------

# Folds trie contents into a checksum.
def fold(t: Trie, acc: U32) -> U32:
  match t:
    case emp{}:
      acc
    case nod{mb, l, r}:
      acc = fold_mb(mb, acc)
      acc = fold(l, acc * 16777619 + 2166136261)
      fold(r, acc * 2246822519 + 3266489917)

# Mixes one optional value into the checksum.
def fold_mb(mb: Mb, acc: U32) -> U32:
  match mb:
    case none{}:
      acc
    case some{v}:
      (acc ^ v) * 2654435761 + 1013904223

# Benchmark
# ---------

# Builds a trie from pseudo-random key/value pairs.
def build(n: U32, seed: U32, t: Trie) -> Trie:
  done = u2b(n === 0)
  build_go(done, n, seed, t)

# Runs one build step and recurs.
def build_go(done: Bool, n: U32, seed: U32, t: Trie) -> Trie:
  match done:
    case T{}:
      t
    case F{}:
      key  = rng(seed)
      val  = rng(key)
      t    = ins(t, key, val, 20)
      n    = n - 1
      seed = rng(val)
      build(n, seed, t)

# Runs lookup queries and accumulates hits.
def query(n: U32, seed: U32, t: Trie, acc: U32) -> U32:
  done = u2b(n === 0)
  query_go(done, n, seed, t, acc)

# Runs one lookup step and recurs.
def query_go(done: Bool, n: U32, seed: U32, t: Trie, acc: U32) -> U32:
  match done:
    case T{}:
      acc
    case F{}:
      key  = rng(seed)
      hit  = get(t, key, 20)
      acc  = (acc ^ hit) + seed
      n    = n - 1
      seed = rng(seed)
      query(n, seed, t, acc)

# Runs one full round and returns the next benchmark state.
def round(seed: U32, acc: U32) -> St:
  t    = build(1200, seed, emp{})
  acc  = query(1600, rng(seed), t, acc)
  acc  = fold(t, acc)
  seed = rng(seed)
  st{seed, acc}

# Runs one full round from an existing benchmark state.
def round_st(s: St) -> St:
  match s:
    case st{seed, acc}:
      round(seed, acc)

# Runs full trie workload rounds.
def bench(rounds: U32, seed: U32, acc: U32) -> U32:
  done = u2b(rounds === 0)
  bench_go(done, rounds, seed, acc)

# Runs one benchmark round and recurs.
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
  bench(4, 1, 0)
