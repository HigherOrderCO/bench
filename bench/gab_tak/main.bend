# Gabriel TAK benchmark (Takeuchi, 1978)
# =======================================
# Triply-recursive function over Nat that exercises deep branching
# recursion with highly non-linear call expansion.
# Standard Gabriel inputs: (18, 12, 6).

# Types
# -----

type Nat() {
  zero{}
  succ{Nat}
}

type Bool() {
  T{}
  F{}
}

# Helpers
# -------

# Predecessor of a natural number
def pred(n: Nat) -> Nat:
  match n:
    case 0n:
      0n
    case 1n+p:
      p

# Less-than-or-equal comparison
def lte(a: Nat, b: Nat) -> Bool:
  match a b:
    case 0n b:
      T{}
    case 1n+p 0n:
      F{}
    case 1n+p 1n+q:
      lte(p, q)

# TAK
# ---

# Dispatches on the comparison result
def tak_go(c: Bool, x: Nat, y: Nat, z: Nat) -> Nat:
  match c x y z:
    case T{} x y z:
      y
    case F{} x y z:
      a = tak(pred(x), y, z)
      b = tak(pred(y), z, x)
      c = tak(pred(z), x, y)
      tak(a, b, c)

# Takeuchi function
def tak(x: Nat, y: Nat, z: Nat) -> Nat:
  tak_go(lte(x, y), x, y, z)

# Main
# ----

# Converts a Nat to U32
def u32_to(n: Nat) -> U32:
  match n:
    case 0n:
      0
    case 1n+p:
      u32_to(p) + 1

def main() -> U32:
  u32_to(tak(18n, 12n, 6n))
