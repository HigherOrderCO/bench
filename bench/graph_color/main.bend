# graph_color
# ===========
# Counts all valid 3-colorings of a pseudo-random graph via backtracking.
# Stresses recursive search, constraint checking, and list traversal.

# Types
# -----

type Lst() {
  nil{}
  cons{U32, Lst}
}

# Utils
# -----

# Returns 1 if n is zero, else 0
def is_zero(n: U32) -> U32:
  match n:
    case 0:
      1
    case x:
      0

# Graph
# -----

# Returns 1 if an edge exists between nodes i and j
def edge(i: U32, j: U32) -> U32:
  a = (i + j + 1) * 17
  b = (i * j + 1) * 31
  is_zero((a ^ b) % 5)

# Coloring
# --------

# Checks if assigning `color` to `node` conflicts with prior assignments.
# Colors list is most-recent-first; idx tracks the corresponding node.
def valid(node: U32, color: U32, cs: Lst, idx: U32) -> U32:
  match cs:
    case []:
      1
    case c<>rest:
      conflict = edge(node, idx) * (c === color)
      no_conf  = is_zero(conflict)
      no_conf * valid(node, color, rest, idx - 1)

# Tries one color for a node; returns count of valid extensions
def try_color(n: U32, node: U32, color: U32, cs: Lst) -> U32:
  ok = valid(node, color, cs, node - 1)
  ok * solve(n, node + 1, color<>cs)

# Counts all valid 3-colorings by trying each color at each node
def solve(n: U32, node: U32, cs: Lst) -> U32:
  rem = n - node
  match rem:
    case 0:
      1
    case k:
      c0 = try_color(n, node, 0, cs)
      c1 = try_color(n, node, 1, cs)
      c2 = try_color(n, node, 2, cs)
      c0 + c1 + c2

# Benchmark
# ---------

# Runs coloring R times, accumulating results
def bench(rounds: U32, n: U32, acc: U32) -> U32:
  match rounds:
    case 0:
      acc
    case r:
      count = solve(n, 0, [])
      bench(r - 1, n, acc + count)

# Main
# ----

# Entry point
def main() -> U32:
  bench(2, 14, 0)
