# Gabriel DERIV benchmark (Gabriel, 1985)
# ========================================
# Symbolic differentiation of a fixed polynomial expression.
# Exercises ADT construction, pattern matching, and tree growth
# via product/quotient rules.
# Standard: 5000 iterations over the test expression.

# Types
# -----

type Nat() {
  zero{}
  succ{Nat}
}

type Expr() {
  var{}
  con{U32}
  add{Expr, Expr}
  sub{Expr, Expr}
  mul{Expr, Expr}
  div{Expr, Expr}
}

# Deriv
# -----

# Differentiates an expression w.r.t. the single variable
def deriv(e: Expr) -> Expr:
  match e:
    case var{}:
      con{1}
    case con{v}:
      con{0}
    case add{a, b}:
      add{deriv(a), deriv(b)}
    case sub{a, b}:
      sub{deriv(a), deriv(b)}
    case mul{a, b}:
      da = deriv(a)
      db = deriv(b)
      add{mul{da, b}, mul{a, db}}
    case div{a, b}:
      da = deriv(a)
      db = deriv(b)
      div{sub{mul{da, b}, mul{a, db}}, mul{b, b}}

# Size
# ----

# Counts nodes in an expression tree
def size(e: Expr) -> U32:
  match e:
    case var{}:
      1
    case con{v}:
      1
    case add{a, b}:
      size(a) + size(b) + 1
    case sub{a, b}:
      size(a) + size(b) + 1
    case mul{a, b}:
      size(a) + size(b) + 1
    case div{a, b}:
      size(a) + size(b) + 1

# Main
# ----

# Test expression: 3*x*x + 10*x*x + 20*x + 5
def test_expr() -> Expr:
  add{mul{con{3}, mul{var{}, var{}}},
  add{mul{con{10}, mul{var{}, var{}}},
  add{mul{con{20}, var{}},
  con{5}}}}

# Loop: differentiate n times, summing sizes to force evaluation
def loop(n: Nat, acc: U32) -> U32:
  match n acc:
    case 0n acc:
      acc
    case 1n+p acc:
      loop(p, acc + size(deriv(test_expr())))

# Runs repeated derivation batches and accumulates checksums.
def bench(rounds: U32, acc: U32) -> U32:
  match rounds:
    case 0:
      acc
    case r:
      acc = acc + loop(1000n, 0)
      bench(r - 1, acc)

def main() -> U32:
  bench(1560, 0)
