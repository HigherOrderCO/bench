# lambda_eval
# ===========
# Pure functional lambda-calculus normalization benchmark.
# Uses de Bruijn terms, capture-avoiding substitution, and recursive NF.
# Workload evaluates Church arithmetic terms to target ~1s on JS mode.

# Types
# -----

type Tm() {
  var{U32}
  lam{Tm}
  app{Tm, Tm}
}

type Bool() {
  T{}
  F{}
}

type St() {
  st{U32, U32}
}

# Utils
# -----

# Advances a U32 linear-congruential generator seed.
def rng(seed: U32) -> U32:
  seed * 1664525 + 1013904223

# Converts a numeric predicate into Bool.
def u2b(x: U32) -> Bool:
  match x:
    case 0:
      F{}
    case k:
      T{}

# Shifts free variables by `by` at depth >= `dep`.
def shift_above(tm: Tm, by: U32, dep: U32) -> Tm:
  match tm:
    case var{k}:
      shift_var(k, by, dep)
    case lam{bod}:
      lam{shift_above(bod, by, dep + 1)}
    case app{fun, arg}:
      app{shift_above(fun, by, dep), shift_above(arg, by, dep)}

# Shifts one variable index when needed.
def shift_var(k: U32, by: U32, dep: U32) -> Tm:
  shift_var_go(u2b(k < dep), k, by)

# Selects shift branch from a typed Bool.
def shift_var_go(ok: Bool, k: U32, by: U32) -> Tm:
  match ok:
    case T{}:
      var{k}
    case F{}:
      var{k + by}

# Substitutes outermost bound variable in `tm` with `arg`.
def subst0(tm: Tm, arg: Tm) -> Tm:
  subst_dep(tm, arg, 0)

# Substitutes a variable at de Bruijn depth `dep`.
def subst_dep(tm: Tm, arg: Tm, dep: U32) -> Tm:
  match tm:
    case var{k}:
      subst_var(k, arg, dep)
    case lam{bod}:
      lam{subst_dep(bod, arg, dep + 1)}
    case app{fun, val}:
      fun = subst_dep(fun, arg, dep)
      val = subst_dep(val, arg, dep)
      app{fun, val}

# Substitutes one variable occurrence.
def subst_var(k: U32, arg: Tm, dep: U32) -> Tm:
  subst_var_go(u2b(k === dep), k, arg, dep)

# Selects substitution branch from a typed Bool.
def subst_var_go(eq: Bool, k: U32, arg: Tm, dep: U32) -> Tm:
  match eq:
    case T{}:
      shift_above(arg, dep, 0)
    case F{}:
      subst_var_ne(k, dep)

# Handles non-equal variable case during substitution.
def subst_var_ne(k: U32, dep: U32) -> Tm:
  subst_var_ne_go(u2b(k > dep), k)

# Selects non-equal substitution branch from a typed Bool.
def subst_var_ne_go(gt: Bool, k: U32) -> Tm:
  match gt:
    case T{}:
      var{k - 1}
    case F{}:
      var{k}

# Reduces to weak-head normal form.
def wnf(tm: Tm) -> Tm:
  match tm:
    case var{k}:
      var{k}
    case lam{bod}:
      lam{bod}
    case app{fun, arg}:
      wnf_app(fun, arg)

# Reduces an application to weak-head normal form.
def wnf_app(fun: Tm, arg: Tm) -> Tm:
  wnf_app_go(wnf(fun), arg)

# Reduces a typed weak-head application.
def wnf_app_go(fun: Tm, arg: Tm) -> Tm:
  match fun:
    case lam{bod}:
      wnf(subst0(bod, arg))
    case var{k}:
      app{var{k}, arg}
    case app{f0, f1}:
      app{app{f0, f1}, arg}

# Reduces to full normal form.
def nf(tm: Tm) -> Tm:
  nf_go(wnf(tm))

# Reduces a typed weak-head-normal term to normal form.
def nf_go(tm: Tm) -> Tm:
  match tm:
    case var{k}:
      var{k}
    case lam{bod}:
      lam{nf(bod)}
    case app{fun, arg}:
      fun = nf(fun)
      arg = nf(arg)
      app{fun, arg}

# Church Terms
# ------------

# Church numeral zero.
def c_zero() -> Tm:
  lam{lam{var{0}}}

# Church successor.
def c_succ() -> Tm:
  lam{lam{lam{app{var{1}, app{app{var{2}, var{1}}, var{0}}}}}}

# Church addition.
def c_add() -> Tm:
  lam{lam{lam{lam{app{app{var{3}, var{1}}, app{app{var{2}, var{1}}, var{0}}}}}}}

# Church multiplication.
def c_mul() -> Tm:
  lam{lam{lam{lam{app{app{var{3}, app{var{2}, var{1}}}, var{0}}}}}}

# Builds a Church numeral from U32.
def church(n: U32) -> Tm:
  church_go(u2b(n === 0), n)

# Selects Church constructor branch from a typed Bool.
def church_go(eq: Bool, n: U32) -> Tm:
  match eq:
    case T{}:
      c_zero()
    case F{}:
      church_suc(n)

# Builds successor branch for Church numeral construction.
def church_suc(n: U32) -> Tm:
  app{c_succ(), church(n - 1)}

# Decodes a normalized Church numeral into U32.
def church_to_u32(tm: Tm) -> U32:
  match tm:
    case lam{bod}:
      church_to_u32_lam(bod)
    case tm:
      0

# Decodes second lambda layer of a Church numeral.
def church_to_u32_lam(bod: Tm) -> U32:
  match bod:
    case lam{inner}:
      count_apps(inner)
    case bod:
      0

# Detects if a term is `var{idx}`.
def is_var(tm: Tm, idx: U32) -> U32:
  match tm:
    case var{k}:
      match k === idx:
        case 0:
          0
        case x:
          1
    case tm:
      0

# Counts f-applications in Church numeral body.
def count_apps(tm: Tm) -> U32:
  match tm:
    case var{k}:
      0
    case lam{bod}:
      count_apps(bod)
    case app{fun, arg}:
      count_app(fun, arg)

# Counts one application node in Church body.
def count_app(fun: Tm, arg: Tm) -> U32:
  match is_var(fun, 1):
    case 0:
      count_apps(fun) + count_apps(arg)
    case x:
      count_apps(arg) + 1

# Benchmark
# ---------

# Builds and normalizes one Church arithmetic expression.
def eval_expr(a: Tm, b: Tm, c: Tm) -> U32:
  church_to_u32(
    nf(
      app{
        app{c_mul(), app{app{c_add(), app{app{c_mul(), a}, b}}, c}},
        church(2)
      }
    )
  )

# Runs one benchmark round and returns next state.
def round(seed: U32, acc: U32) -> St:
  na   = 20 + seed % 4
  nb   = 19 + (seed >> 3) % 4
  nc   = 17 + (seed >> 5) % 3
  r0   = eval_expr(church(na), church(nb), church(nc))
  r1   = eval_expr(church(nb), church(nc), church(na))
  acc  = (acc ^ r0) * 16777619 + r1 * 131 + seed
  seed = rng(seed)
  st{seed, acc}

# Runs one round from an existing benchmark state.
def round_st(s: St) -> St:
  match s:
    case st{seed, acc}:
      round(seed, acc)

# Runs benchmark rounds.
def bench(rounds: U32, seed: U32, acc: U32) -> U32:
  match rounds === 0:
    case 0:
      bench_go(rounds, seed, acc)
    case x:
      acc

# Runs four rounds per recursion step.
def bench_go(rounds: U32, seed: U32, acc: U32) -> U32:
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
  bench(12, 1, 0)
