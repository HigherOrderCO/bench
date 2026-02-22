# Gabriel TAKL benchmark (Takeuchi, 1978)
# ========================================
# TAK algorithm using list length comparison instead of integers.
# Exercises deep recursion with list construction and traversal.
# Standard Gabriel inputs: lists of length 18, 12, 6.

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

type Lst() {
  nil{}
  cons{Nat, Lst}
}

# Helpers
# -------

# Builds a list [n, n-1, ..., 1]
def listn(n: Nat) -> Lst:
  match n:
    case 0n:
      nil{}
    case 1n+p:
      cons{1n+p, listn(p)}

# Tail of a list (empty returns empty)
def tail(l: Lst) -> Lst:
  match l:
    case nil{}:
      nil{}
    case cons{h, t}:
      t

# Checks if list x is strictly shorter than list y
def shorterp(x: Lst, y: Lst) -> Bool:
  match x y:
    case nil{} nil{}:
      F{}
    case nil{} cons{h, t}:
      T{}
    case cons{xh, xt} nil{}:
      F{}
    case cons{xh, xt} cons{yh, yt}:
      shorterp(xt, yt)

# TAKL
# ----

# Dispatches on the shorterp result
def mas_go(c: Bool, x: Lst, y: Lst, z: Lst) -> Lst:
  match c x y z:
    case F{} x y z:
      z
    case T{} x y z:
      a = mas(tail(x), y, z)
      b = mas(tail(y), z, x)
      c = mas(tail(z), x, y)
      mas(a, b, c)

# TAK on lists: returns z when y is not shorter than x
def mas(x: Lst, y: Lst, z: Lst) -> Lst:
  mas_go(shorterp(y, x), x, y, z)

# Main
# ----

# Length of a list as U32
def len(l: Lst) -> U32:
  match l:
    case nil{}:
      0
    case cons{h, t}:
      len(t) + 1

def main() -> U32:
  len(mas(listn(18n), listn(12n), listn(6n)))
