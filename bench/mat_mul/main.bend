# This benchmark runs a matrix-like numeric kernel over U32 values using nested
# Nat-driven loops and pseudo-random mixing.  It approximates dense matmul
# traversal (rows, columns, depth) without materializing matrices, stressing
# recursion, arithmetic throughput, and match dispatch on a computation-heavy
# workload.

type Nat() {
  zero{}
  succ{Nat}
}

def dot(steps: Nat, a: U32, b: U32, acc: U32) -> U32:
  match steps a b acc:
    case 0n a b acc:
      acc
    case 1n+p a b acc:
      mix = (a ^ b) * 2654435761
      dot(p, a + 1664525, b + 1013904223, acc + mix)

def row(cols: Nat, depth: Nat, row_seed: U32, col_seed: U32, acc: U32) -> U32:
  match cols depth row_seed col_seed acc:
    case 0n depth row_seed col_seed acc:
      acc
    case 1n+p depth row_seed col_seed acc:
      cell = dot(depth, row_seed, col_seed, 0)
      row(p, depth, row_seed + 374761393, col_seed + 668265263, acc ^ cell)

def matmul_like(rows: Nat, cols: Nat, depth: Nat, seed: U32, acc: U32) -> U32:
  match rows cols depth seed acc:
    case 0n cols depth seed acc:
      acc
    case 1n+p cols depth seed acc:
      row_sum = row(cols, depth, seed, 1, 0)
      matmul_like(p, cols, depth, seed + 2246822519, acc + row_sum)

def main() -> U32:
  matmul_like(256n, 256n, 256n, 1, 0)
