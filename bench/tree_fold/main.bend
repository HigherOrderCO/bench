# This benchmark builds a complete binary tree of Nat-indexed depth, assigns
# pseudo-random U32 seeds to leaves, then folds the entire tree with a mixing
# function.  It stresses ADT construction, multi-constructor pattern matching,
# and balanced recursive traversal on a data-structure-heavy workload.

type Nat() {
  zero{}
  succ{Nat}
}

type Tree() {
  leaf{U32}
  node{Tree, Tree}
}

def build(depth: Nat, seed: U32) -> Tree:
  match depth seed:
    case 0n seed:
      leaf{seed}
    case 1n+p seed:
      l = build(p, seed * 1664525 + 1013904223)
      r = build(p, seed * 214013 + 2531011)
      node{l, r}

def fold(t: Tree) -> U32:
  match t:
    case leaf{v}:
      v
    case node{l, r}:
      a = fold(l)
      b = fold(r)
      (a + b) ^ (a * 31)

def main() -> U32:
  fold(build(24n, 42))
