# Gabriel BOYER benchmark (Gabriel, 1985)
# ========================================
# Term rewriting and tautology checking over a database of 106 lemmas.
# Exercises unification, substitution, deep pattern matching, and
# large-scale ADT construction in a symbolic-computation workload.
# NOTE: overflows JS backend stack due to deep curried recursion
# through 106 lemmas.  Works on HVM4.
#
# Symbol table:
#  0:if       1:and      2:or       3:not      4:implies  5:plus
#  6:times    7:equal    8:lessp    9:zerop   10:fix     11:t
# 12:f       13:nil     14:zero    15:add1    16:sub1    17:remainder
# 18:quotient 19:difference 20:append 21:reverse 22:flatten
# 23:member  24:intersect  25:nth   26:length  27:cons    28:compile
# 29:codegen 30:optimize   31:eqp   32:greaterp 33:lesseqp
# 34:greatereqp 35:boolean 36:iff  37:even1   38:odd     39:countps_loop
# 40:countps_ 41:fact_   42:fact_loop 43:reverse_ 44:reverse_loop
# 45:divides 46:assume_true 47:assume_false 48:taut_checker
# 49:tautologyp_fn 50:normalize  51:falsify  52:falsify1
# 53:prime   54:prime1  55:numberp  56:nlistp   57:listp   58:exec
# 59:mc_flatten  60:meaning  61:plus_tree  62:plus_fringe
# 63:times_list  64:prime_list  65:exp_  66:gcd_  67:value
# 68:gopher  69:samefringe  70:greatest_factor  71:car  72:cdr
# 73:last    74:assignedp   75:assignment  76:sigma  77:count_list
# 78:sort_lp 79:power_eval  80:big_plus   81:big_plus1
# 82:power_rep  83:get_  84:set_  85:sort2  86:dsort  87:delete
# 88:greatereqpr  89:n1  90:n2  91:n6  92:f_sym
#
# Variable IDs (within lemma patterns):
#  0:x  1:y  2:z  3:u  4:w  5:a  6:b  7:c  8:d  9:e
# 10:i 11:j 12:k 13:l 14:form 15:pred 16:var_ 17:alist
# 18:p 19:q 20:val 21:mem 22:pds 23:envrn
# 24:x1 25:x2 26:x3 27:x4 28:x5 29:x6 30:x7 31:base

# Types
# -----

type Bool() {
  T{}
  F{}
}

# Term: variable (by ID) or application (symbol ID + arg list)
type Term() {
  tvar{U32}
  tapp{U32, TmLs}
}

# Term list
type TmLs() {
  tn{}
  tc{Term, TmLs}
}

# Substitution: list of (var_id, term) pairs
type Subst() {
  sn{}
  sc{U32, Term, Subst}
}

# Maybe substitution
type MbSb() {
  sb_none{}
  sb_some{Subst}
}

# Maybe term
type MbTm() {
  tm_none{}
  tm_some{Term}
}

# Lemma list: each lemma is (lhs, rhs)
type LmLs() {
  ln{}
  lc{Term, Term, LmLs}
}

# Term list for tautology checker (flat list of terms)
type TLs() {
  tln{}
  tlc{Term, TLs}
}

# Builders
# --------

# Variable term
def vv(id: U32) -> Term:
  tvar{id}

# 0-arg function symbol
def f0(s: U32) -> Term:
  tapp{s, tn{}}

# 1-arg function symbol
def f1(s: U32, a: Term) -> Term:
  tapp{s, tc{a, tn{}}}

# 2-arg function symbol
def f2(s: U32, a: Term, b: Term) -> Term:
  tapp{s, tc{a, tc{b, tn{}}}}

# 3-arg function symbol
def f3(s: U32, a: Term, b: Term, c: Term) -> Term:
  tapp{s, tc{a, tc{b, tc{c, tn{}}}}}

# 4-arg function symbol
def f4(s: U32, a: Term, b: Term, c: Term, d: Term) -> Term:
  tapp{s, tc{a, tc{b, tc{c, tc{d, tn{}}}}}}

# Lemma constructor (typed wrapper for lc)
def lm(lhs: Term, rhs: Term, rest: LmLs) -> LmLs:
  lc{lhs, rhs, rest}

# Utils
# -----

# Converts U32 (0 or nonzero) to Bool
def u2b(n: U32) -> Bool:
  λ{0: F{}; x => T{}}(n)

# Boolean AND
def band(a: Bool, b: Bool) -> Bool:
  match a b:
    case T{} b:
      b
    case F{} b:
      F{}

# Bool to U32
def b2u(b: Bool) -> U32:
  match b:
    case T{}:
      1
    case F{}:
      0

# Term Equality
# -------------

# Checks if two terms are equal
def eq_tm(a: Term, b: Term) -> Bool:
  match a b:
    case tvar{i} tvar{j}:
      u2b(i === j)
    case tapp{s1, l1} tapp{s2, l2}:
      eq_tm_app(s1, l1, s2, l2)
    case a b:
      F{}

# Checks if two tapp terms are equal (same symbol, same args)
def eq_tm_app(s1: U32, l1: TmLs, s2: U32, l2: TmLs) -> Bool:
  band(u2b(s1 === s2), eq_tl(l1, l2))

# Checks if two term lists are equal
def eq_tl(a: TmLs, b: TmLs) -> Bool:
  match a b:
    case tn{} tn{}:
      T{}
    case tc{x, xs} tc{y, ys}:
      band(eq_tm(x, y), eq_tl(xs, ys))
    case a b:
      F{}

# Substitution
# ------------

# Looks up a variable in a substitution
def sb_find(id: U32, s: Subst) -> MbTm:
  match s:
    case sn{}:
      tm_none{}
    case sc{k, v, rest}:
      sb_find_go(u2b(id === k), id, v, rest)

# Dispatches on whether key matched
def sb_find_go(hit: Bool, id: U32, v: Term, rest: Subst) -> MbTm:
  match hit:
    case T{}:
      tm_some{v}
    case F{}:
      sb_find(id, rest)

# Gets a variable from substitution, or returns the variable itself
def sb_get(id: U32, s: Subst) -> Term:
  mb = sb_find(id, s)
  sb_get_go(mb, id)

# Dispatches on maybe term
def sb_get_go(mb: MbTm, id: U32) -> Term:
  match mb:
    case tm_none{}:
      tvar{id}
    case tm_some{t}:
      t

# Applies a substitution to a term
def apply_sb(s: Subst, t: Term) -> Term:
  match t:
    case tvar{id}:
      sb_get(id, s)
    case tapp{sym, args}:
      tapp{sym, apply_sb_ls(s, args)}

# Applies a substitution to a term list
def apply_sb_ls(s: Subst, ls: TmLs) -> TmLs:
  match ls:
    case tn{}:
      tn{}
    case tc{h, t}:
      tc{apply_sb(s, h), apply_sb_ls(s, t)}

# Unification
# -----------

# Unifies two terms, returning a substitution or failure
def unify(t1: Term, t2: Term) -> MbSb:
  u1(t1, t2, sn{})

# Unification with an accumulating substitution
def u1(t1: Term, t2: Term, s: Subst) -> MbSb:
  match t1:
    case tvar{id}:
      u1_var(id, t2, s)
    case tapp{s1, l1}:
      u1_app(s1, l1, t2, s)

# Unifies a variable with a term
def u1_var(id: U32, t2: Term, s: Subst) -> MbSb:
  mb = sb_find(id, s)
  u1_var_go(mb, id, t2, s)

# Dispatches on whether var is already bound
def u1_var_go(mb: MbTm, id: U32, t2: Term, s: Subst) -> MbSb:
  match mb:
    case tm_some{bound}:
      u1_var_bound(bound, t2, s)
    case tm_none{}:
      sb_some{sc{id, t2, s}}

# If var is bound, unify the bound value with t2
def u1_var_bound(bound: Term, t2: Term, s: Subst) -> MbSb:
  match bound t2:
    case tvar{i} t2:
      u1_var_bound_var(i, t2, s)
    case tapp{s1, l1} tapp{s2, l2}:
      u1_var_bound_app(s1, l1, s2, l2, s)
    case bound t2:
      sb_none{}

# Bound is a var: check if equal to t2
def u1_var_bound_var(i: U32, t2: Term, s: Subst) -> MbSb:
  match t2:
    case tvar{j}:
      u1_var_eq(u2b(i === j), s)
    case tapp{s2, l2}:
      sb_none{}

# Dispatches on var equality
def u1_var_eq(eq: Bool, s: Subst) -> MbSb:
  match eq:
    case T{}:
      sb_some{s}
    case F{}:
      sb_none{}

# Bound and t2 are both tapps: check symbol and unify args
def u1_var_bound_app(s1: U32, l1: TmLs, s2: U32, l2: TmLs, s: Subst) -> MbSb:
  u1_app_check(u2b(s1 === s2), l1, l2, s)

# Unifies a tapp with a term
def u1_app(s1: U32, l1: TmLs, t2: Term, s: Subst) -> MbSb:
  match t2:
    case tvar{id}:
      sb_some{sc{id, tapp{s1, l1}, s}}
    case tapp{s2, l2}:
      u1_app_check(u2b(s1 === s2), l1, l2, s)

# Dispatches on symbol equality
def u1_app_check(eq: Bool, l1: TmLs, l2: TmLs, s: Subst) -> MbSb:
  match eq:
    case T{}:
      u1_ls(l1, l2, s)
    case F{}:
      sb_none{}

# Unifies two term lists element-wise
def u1_ls(l1: TmLs, l2: TmLs, s: Subst) -> MbSb:
  match l1 l2:
    case tn{} tn{}:
      sb_some{s}
    case tc{h1, t1} tc{h2, t2}:
      u1_ls_step(h1, t1, h2, t2, s)
    case l1 l2:
      sb_none{}

# Unifies heads then tails
def u1_ls_step(h1: Term, t1: TmLs, h2: Term, t2: TmLs, s: Subst) -> MbSb:
  mb = u1(h1, h2, s)
  u1_ls_cont(mb, t1, t2)

# Continues list unification after head succeeded
def u1_ls_cont(mb: MbSb, t1: TmLs, t2: TmLs) -> MbSb:
  match mb:
    case sb_none{}:
      sb_none{}
    case sb_some{s}:
      u1_ls(t1, t2, s)

# Rewriting
# ---------

# Rewrites a term using the lemma database (one step, outermost)
def rw(t: Term, db: LmLs) -> Term:
  match t:
    case tvar{id}:
      tvar{id}
    case tapp{sym, args}:
      rw_app(sym, rw_args(args, db), db)

# Rewrites at the top level after rewriting args
def rw_app(sym: U32, args: TmLs, db: LmLs) -> Term:
  rw_wl(tapp{sym, args}, db, db)

# Rewrites all arguments in a term list
def rw_args(ls: TmLs, db: LmLs) -> TmLs:
  match ls:
    case tn{}:
      tn{}
    case tc{h, t}:
      tc{rw(h, db), rw_args(t, db)}

# Tries each lemma in the worklist against term t
def rw_wl(t: Term, wl: LmLs, db: LmLs) -> Term:
  match wl:
    case ln{}:
      t
    case lc{lhs, rhs, rest}:
      mb = unify(lhs, t)
      rw_try(mb, t, rhs, rest, db)

# Dispatches on unification result
def rw_try(mb: MbSb, t: Term, rhs: Term, rest: LmLs, db: LmLs) -> Term:
  match mb:
    case sb_none{}:
      rw_wl(t, rest, db)
    case sb_some{s}:
      rw(apply_sb(s, rhs), db)

# Tautology Checker
# -----------------

# Checks if term x appears in true-list
def mem_tm(x: Term, ls: TLs) -> Bool:
  match ls:
    case tln{}:
      F{}
    case tlc{h, t}:
      mem_tm_go(eq_tm(x, h), x, t)

# Dispatches on equality check
def mem_tm_go(eq: Bool, x: Term, rest: TLs) -> Bool:
  match eq:
    case T{}:
      T{}
    case F{}:
      mem_tm(x, rest)

# Checks if term is known true
def truep(x: Term, tls: TLs) -> Bool:
  match x:
    case tapp{sym, args}:
      truep_app(sym, tapp{sym, args}, tls)
    case tvar{id}:
      mem_tm(tvar{id}, tls)

# Symbol 11 (t) is always true; otherwise check the list
def truep_app(sym: U32, x: Term, tls: TLs) -> Bool:
  truep_app_go(u2b(sym === 11), x, tls)

# Dispatches on whether symbol is t
def truep_app_go(is_t: Bool, x: Term, tls: TLs) -> Bool:
  match is_t:
    case T{}:
      T{}
    case F{}:
      mem_tm(x, tls)

# Checks if term is known false
def falsep(x: Term, fls: TLs) -> Bool:
  match x:
    case tapp{sym, args}:
      falsep_app(sym, tapp{sym, args}, fls)
    case tvar{id}:
      mem_tm(tvar{id}, fls)

# Symbol 12 (f) is always false; otherwise check the list
def falsep_app(sym: U32, x: Term, fls: TLs) -> Bool:
  falsep_app_go(u2b(sym === 12), x, fls)

# Dispatches on whether symbol is f
def falsep_app_go(is_f: Bool, x: Term, fls: TLs) -> Bool:
  match is_f:
    case T{}:
      T{}
    case F{}:
      mem_tm(x, fls)

# Main tautology checker: x is the (rewritten) formula
def tautologyp(x: Term, tls: TLs, fls: TLs) -> Bool:
  match x:
    case tvar{id}:
      truep(tvar{id}, tls)
    case tapp{sym, args}:
      tautp_app(sym, args, tapp{sym, args}, tls, fls)

# Dispatches on top-level symbol
def tautp_app(sym: U32, args: TmLs, x: Term, tls: TLs, fls: TLs) -> Bool:
  tautp_app_go(u2b(sym === 0), sym, args, x, tls, fls)

# sym == 0 means if(a, b, c)
def tautp_app_go(is_if: Bool, sym: U32, args: TmLs, x: Term, tls: TLs, fls: TLs) -> Bool:
  match is_if:
    case T{}:
      tautp_if(args, tls, fls)
    case F{}:
      truep(x, tls)

# Handles if(a, b, c): check tautology of both branches
def tautp_if(args: TmLs, tls: TLs, fls: TLs) -> Bool:
  match args:
    case tc{a, rest}:
      tautp_if2(a, rest, tls, fls)
    case tn{}:
      F{}

# Extracts b from arg list
def tautp_if2(a: Term, rest: TmLs, tls: TLs, fls: TLs) -> Bool:
  match rest:
    case tc{b, rest2}:
      tautp_if3(a, b, rest2, tls, fls)
    case tn{}:
      F{}

# Extracts c from arg list
def tautp_if3(a: Term, b: Term, rest: TmLs, tls: TLs, fls: TLs) -> Bool:
  match rest:
    case tc{c, rest3}:
      tautp_if_go(a, b, c, tls, fls)
    case tn{}:
      F{}

# Checks: if a is known true, check b; if known false, check c; otherwise split
def tautp_if_go(a: Term, b: Term, c: Term, tls: TLs, fls: TLs) -> Bool:
  tautp_if_true(truep(a, tls), a, b, c, tls, fls)

# Dispatches on truep(a)
def tautp_if_true(at: Bool, a: Term, b: Term, c: Term, tls: TLs, fls: TLs) -> Bool:
  match at:
    case T{}:
      tautologyp(b, tls, fls)
    case F{}:
      tautp_if_false(falsep(a, fls), a, b, c, tls, fls)

# Dispatches on falsep(a)
def tautp_if_false(af: Bool, a: Term, b: Term, c: Term, tls: TLs, fls: TLs) -> Bool:
  match af:
    case T{}:
      tautologyp(c, tls, fls)
    case F{}:
      tautp_split(a, b, c, tls, fls)

# Splits: assume a true for b, assume a false for c
def tautp_split(a: Term, b: Term, c: Term, tls: TLs, fls: TLs) -> Bool:
  tb = tautologyp(b, tlc{a, tls}, fls)
  tautp_split_go(tb, a, c, tls, fls)

# Dispatches on true-branch result
def tautp_split_go(tb: Bool, a: Term, c: Term, tls: TLs, fls: TLs) -> Bool:
  match tb:
    case T{}:
      tautologyp(c, tls, tlc{a, fls})
    case F{}:
      F{}

# Top-level: rewrite then check tautology
def tautp(x: Term, db: LmLs) -> Bool:
  tautologyp(rw(x, db), tln{}, tln{})

# Lemma Database
# --------------
# All 106 lemmas, built bottom-up with shadowing.
# Each lemma: l = lc{LHS, RHS, l}

def lms() -> LmLs:
  # -- variables (short aliases) --
  x  = vv(0)
  y  = vv(1)
  z  = vv(2)
  u  = vv(3)
  w  = vv(4)
  a  = vv(5)
  b  = vv(6)
  c  = vv(7)
  d  = vv(8)
  e  = vv(9)
  i  = vv(10)
  j  = vv(11)
  k  = vv(12)
  l  = vv(13)
  fm = vv(14)
  pr = vv(15)
  vr = vv(16)
  al = vv(17)
  p  = vv(18)
  q  = vv(19)
  vl = vv(20)
  mm = vv(21)
  pd = vv(22)
  ev = vv(23)
  x1 = vv(24)
  x2 = vv(25)
  x3 = vv(26)
  x4 = vv(27)
  x5 = vv(28)
  x6 = vv(29)
  x7 = vv(30)
  bs = vv(31)

  # -- start with empty list, add lemmas 106..1 --
  r = (ln{} :: LmLs)

  # 106: get_(j, set_(i,val,mem)) = if(eqp(j,i), val, get_(j,mem))
  r = lm(f2(83, j, f3(84, i, vl, mm)), f3(0, f2(31, j, i), vl, f2(83, j, mm)), r)

  # 105: quotient(times(y,x), y) = if(zerop(y), zero, fix(x))
  r = lm(f2(18, f2(6, y, x), y), f3(0, f1(9, y), f0(14), f1(10, x)), r)

  # 104: flatten(cdr(gopher(x))) = if(listp(x), cdr(flatten(x)), cons(zero,nil))
  r = lm(f1(22, f1(72, f1(68, x))), f3(0, f1(57, x), f1(72, f1(22, x)), f2(27, f0(14), f0(13))), r)

  # 103: car(gopher(x)) = if(listp(x), car(flatten(x)), zero)
  r = lm(f1(71, f1(68, x)), f3(0, f1(57, x), f1(71, f1(22, x)), f0(14)), r)

  # 102: assignment(x, append(a,b)) = if(assignedp(x,a), assignment(x,a), assignment(x,b))
  r = lm(f2(75, x, f2(20, a, b)), f3(0, f2(74, x, a), f2(75, x, a), f2(75, x, b)), r)

  # 101: equal(lessp(x,y), z) = if(lessp(x,y), equal(t,z), equal(f,z))
  r = lm(f2(7, f2(8, x, y), z), f3(0, f2(8, x, y), f2(7, f0(11), z), f2(7, f0(12), z)), r)

  # 100: last(append(a,b)) = if(listp(b), last(b), if(listp(a), cons(car(last(a)),b), b))
  r = lm(f1(73, f2(20, a, b)), f3(0, f1(57, b), f1(73, b), f3(0, f1(57, a), f2(27, f1(71, f1(73, a)), b), b)), r)

  # 99: nth(nil, i) = if(zerop(i), nil, zero)
  r = lm(f2(25, f0(13), i), f3(0, f1(9, i), f0(13), f0(14)), r)

  # 98: times(x, add1(y)) = if(numberp(y), plus(x,times(x,y)), fix(x))
  r = lm(f2(6, x, f1(15, y)), f3(0, f1(55, y), f2(5, x, f2(6, x, y)), f1(10, x)), r)

  # 97: meaning(plus_tree(delete(x,y)), a) = if(member(x,y), difference(meaning(plus_tree(y),a), meaning(x,a)), meaning(plus_tree(y),a))
  r = lm(f2(60, f1(61, f2(87, x, y)), a), f3(0, f2(23, x, y), f2(19, f2(60, f1(61, y), a), f2(60, x, a)), f2(60, f1(61, y), a)), r)

  # 96: equal(difference(x,y), difference(z,y)) = if(lessp(x,y), not(lessp(y,z)), if(lessp(z,y), not(lessp(y,x)), equal(fix(x),fix(z))))
  r = lm(f2(7, f2(19, x, y), f2(19, z, y)), f3(0, f2(8, x, y), f1(3, f2(8, y, z)), f3(0, f2(8, z, y), f1(3, f2(8, y, x)), f2(7, f1(10, x), f1(10, z)))), r)

  # 95: plus(x, add1(y)) = if(numberp(y), add1(plus(x,y)), add1(x))
  r = lm(f2(5, x, f1(15, y)), f3(0, f1(55, y), f1(15, f2(5, x, y)), f1(15, x)), r)

  # 94: sigma(zero, i) = quotient(times(i, add1(i)), n2)
  r = lm(f2(76, f0(14), i), f2(18, f2(6, i, f1(15, i)), f0(90)), r)

  # 93: quotient(plus(x, plus(x,y)), n2) = plus(x, quotient(y,n2))
  r = lm(f2(18, f2(5, x, f2(5, x, y)), f0(90)), f2(5, x, f2(18, y, f0(90))), r)

  # 92: difference(add1(add1(x)), n2) = fix(x)
  r = lm(f2(19, f1(15, f1(15, x)), f0(90)), f1(10, x), r)

  # 91: length(cons(x1, cons(x2, cons(x3, cons(x4, cons(x5, cons(x6, x7))))))) = plus(n6, length(x7))
  r = lm(f1(26, f2(27, x1, f2(27, x2, f2(27, x3, f2(27, x4, f2(27, x5, f2(27, x6, x7))))))), f2(5, f0(91), f1(26, x7)), r)

  # 90: dsort(x) = sort2(x)
  r = lm(f1(86, x), f1(85, x), r)

  # 89: sort2(delete(x,l)) = delete(x, sort2(l))
  r = lm(f1(85, f2(87, x, l)), f2(87, x, f1(85, l)), r)

  # 88: lessp(length(delete(x,l)), length(l)) = member(x,l)
  r = lm(f2(8, f1(26, f2(87, x, l)), f1(26, l)), f2(23, x, l), r)

  # 87: equal(times(a,b), n1) = and(not(equal(a,zero)), not(equal(b,zero)), numberp(a), numberp(b), equal(sub1(a),zero), equal(sub1(b),zero))
  # Note: 6-arg and — build manually as tapp{1, tc{...6 args...}}
  r = lm(f2(7, f2(6, a, b), f0(89)), tapp{1, tc{f1(3, f2(7, a, f0(14))), tc{f1(3, f2(7, b, f0(14))), tc{f1(55, a), tc{f1(55, b), tc{f2(7, f1(16, a), f0(14)), tc{f2(7, f1(16, b), f0(14)), tn{}}}}}}}}, r)

  # 86: remainder(times(y,x), y) = zero
  r = lm(f2(17, f2(6, y, x), y), f0(14), r)

  # 85: equal(x, times(x,y)) = or(equal(x,zero), and(numberp(x), equal(y,n1)))
  r = lm(f2(7, x, f2(6, x, y)), f2(2, f2(7, x, f0(14)), f2(1, f1(55, x), f2(7, y, f0(89)))), r)

  # 84: greatereqpr(x,y) = not(lessp(x,y))
  r = lm(f2(88, x, y), f1(3, f2(8, x, y)), r)

  # 83: equal(z, times(w,z)) = and(numberp(z), or(equal(z,zero), equal(w,n1)))
  r = lm(f2(7, z, f2(6, w, z)), f2(1, f1(55, z), f2(2, f2(7, z, f0(14)), f2(7, w, f0(89)))), r)

  # 82: prime_list(append(x,y)) = and(prime_list(x), prime_list(y))
  r = lm(f1(64, f2(20, x, y)), f2(1, f1(64, x), f1(64, y)), r)

  # 81: times_list(append(x,y)) = times(times_list(x), times_list(y))
  r = lm(f1(63, f2(20, x, y)), f2(6, f1(63, x), f1(63, y)), r)

  # 80: numberp(greatest_factor(x,y)) = not(and(or(zerop(y), equal(y,n1)), not(numberp(x))))
  r = lm(f1(55, f2(70, x, y)), f1(3, f2(1, f2(2, f1(9, y), f2(7, y, f0(89))), f1(3, f1(55, x)))), r)

  # 79: equal(greatest_factor(x,y), n1) = equal(x,n1)
  r = lm(f2(7, f2(70, x, y), f0(89)), f2(7, x, f0(89)), r)

  # 78: equal(greatest_factor(x,y), zero) = and(or(zerop(y), equal(y,n1)), equal(x,zero))
  r = lm(f2(7, f2(70, x, y), f0(14)), f2(1, f2(2, f1(9, y), f2(7, y, f0(89))), f2(7, x, f0(14))), r)

  # 77: samefringe(x,y) = equal(flatten(x), flatten(y))
  r = lm(f2(69, x, y), f2(7, f1(22, x), f1(22, y)), r)

  # 76: listp(gopher(x)) = listp(x)
  r = lm(f1(57, f1(68, x)), f1(57, x), r)

  # 75: equal(flatten(x), cons(y,nil)) = and(nlistp(x), equal(x,y))
  r = lm(f2(7, f1(22, x), f2(27, y, f0(13))), f2(1, f1(56, x), f2(7, x, y)), r)

  # 74: value(normalize(x), a) = value(x,a)
  r = lm(f2(67, f1(50, x), a), f2(67, x, a), r)

  # 73: gcd_(times(x,z), times(y,z)) = times(z, gcd_(x,y))
  r = lm(f2(66, f2(6, x, z), f2(6, y, z)), f2(6, z, f2(66, x, y)), r)

  # 72: lessp(y, plus(x,y)) = not(zerop(x))
  r = lm(f2(8, y, f2(5, x, y)), f1(3, f1(9, x)), r)

  # 71: lessp(times(x,z), times(y,z)) = and(not(zerop(z)), lessp(x,y))
  r = lm(f2(8, f2(6, x, z), f2(6, y, z)), f2(1, f1(3, f1(9, z)), f2(8, x, y)), r)

  # 70: lessp(plus(x,y), plus(x,z)) = lessp(y,z)
  r = lm(f2(8, f2(5, x, y), f2(5, x, z)), f2(8, y, z), r)

  # 69: difference(add1(plus(y,z)), z) = add1(y)
  r = lm(f2(19, f1(15, f2(5, y, z)), z), f1(15, y), r)

  # 68: difference(plus(b, plus(a,c)), a) = plus(b,c)
  r = lm(f2(19, f2(5, b, f2(5, a, c)), a), f2(5, b, c), r)

  # 67: remainder(times(x,z), z) = zero
  r = lm(f2(17, f2(6, x, z), z), f0(14), r)

  # 66: times(x, difference(c,w)) = difference(times(c,x), times(w,x))
  r = lm(f2(6, x, f2(19, c, w)), f2(19, f2(6, c, x), f2(6, w, x)), r)

  # 65: difference(plus(x,y), plus(x,z)) = difference(y,z)
  r = lm(f2(19, f2(5, x, y), f2(5, x, z)), f2(19, y, z), r)

  # 64: difference(plus(y,x), x) = fix(y)
  r = lm(f2(19, f2(5, y, x), x), f1(10, y), r)

  # 63: difference(plus(x,y), x) = fix(y)
  r = lm(f2(19, f2(5, x, y), x), f1(10, y), r)

  # 62: nth(append(a,b), i) = append(nth(a,i), nth(b, difference(i, length(a))))
  r = lm(f2(25, f2(20, a, b), i), f2(20, f2(25, a, i), f2(25, b, f2(19, i, f1(26, a)))), r)

  # 61: gcd_(x,y) = gcd_(y,x)
  r = lm(f2(66, x, y), f2(66, y, x), r)

  # 60: power_eval(big_plus(power_rep(i,base), power_rep(j,base), zero, base), base) = plus(i,j)
  r = lm(f2(79, f4(80, f2(82, i, bs), f2(82, j, bs), f0(14), bs), bs), f2(5, i, j), r)

  # 59: power_eval(power_rep(i,base), base) = fix(i)
  r = lm(f2(79, f2(82, i, bs), bs), f1(10, i), r)

  # 58: lessp(remainder(x,y), x) = and(not(zerop(y)), not(zerop(x)), not(lessp(x,y)))
  # Note: 3-arg and
  r = lm(f2(8, f2(17, x, y), x), f3(1, f1(3, f1(9, y)), f1(3, f1(9, x)), f1(3, f2(8, x, y))), r)

  # 57: lessp(quotient(i,j), i) = and(not(zerop(i)), or(zerop(j), not(equal(j,n1))))
  r = lm(f2(8, f2(18, i, j), i), f2(1, f1(3, f1(9, i)), f2(2, f1(9, j), f1(3, f2(7, j, f0(89))))), r)

  # 56: remainder(x,x) = zero
  r = lm(f2(17, x, x), f0(14), r)

  # 55: lessp(remainder(x,y), y) = not(zerop(y))
  r = lm(f2(8, f2(17, x, y), y), f1(3, f1(9, y)), r)

  # 54: remainder(y, n1) = zero
  r = lm(f2(17, y, f0(89)), f0(14), r)

  # 53: power_eval(big_plus(x,y,i,base), base) = plus(i, plus(power_eval(x,base), power_eval(y,base)))
  r = lm(f2(79, f4(80, x, y, i, bs), bs), f2(5, i, f2(5, f2(79, x, bs), f2(79, y, bs))), r)

  # 52: power_eval(big_plus1(l,i,base), base) = plus(power_eval(l,base), i)
  r = lm(f2(79, f3(81, l, i, bs), bs), f2(5, f2(79, l, bs), i), r)

  # 51: plus(remainder(x,y), times(y,quotient(x,y))) = fix(x)
  r = lm(f2(5, f2(17, x, y), f2(6, y, f2(18, x, y))), f1(10, x), r)

  # 50: equal(append(a,b), append(a,c)) = equal(b,c)
  r = lm(f2(7, f2(20, a, b), f2(20, a, c)), f2(7, b, c), r)

  # 49: count_list(z, sort_lp(x,y)) = plus(count_list(z,x), count_list(z,y))
  r = lm(f2(77, z, f2(78, x, y)), f2(5, f2(77, z, x), f2(77, z, y)), r)

  # 48: reverse_loop(x, nil) = reverse(x)
  r = lm(f2(44, x, f0(13)), f1(21, x), r)

  # 47: reverse_loop(x,y) = append(reverse(x), y)
  r = lm(f2(44, x, y), f2(20, f1(21, x), y), r)

  # 46: exp_(i, times(j,k)) = exp_(exp_(i,j), k)
  r = lm(f2(65, i, f2(6, j, k)), f2(65, f2(65, i, j), k), r)

  # 45: exp_(i, plus(j,k)) = times(exp_(i,j), exp_(i,k))
  r = lm(f2(65, i, f2(5, j, k)), f2(6, f2(65, i, j), f2(65, i, k)), r)

  # 44: nth(zero, i) = zero
  r = lm(f2(25, f0(14), i), f0(14), r)

  # 43: member(a, intersect(b,c)) = and(member(a,b), member(a,c))
  r = lm(f2(23, a, f2(24, b, c)), f2(1, f2(23, a, b), f2(23, a, c)), r)

  # 42: length(reverse(x)) = length(x)
  r = lm(f1(26, f1(21, x)), f1(26, x), r)

  # 41: member(x, reverse(y)) = member(x,y)
  r = lm(f2(23, x, f1(21, y)), f2(23, x, y), r)

  # 40: member(x, append(a,b)) = or(member(x,a), member(x,b))
  r = lm(f2(23, x, f2(20, a, b)), f2(2, f2(23, x, a), f2(23, x, b)), r)

  # 39: mc_flatten(x,y) = append(flatten(x), y)
  r = lm(f2(59, x, y), f2(20, f1(22, x), y), r)

  # 38: exec(append(x,y), pds, envrn) = exec(y, exec(x,pds,envrn), envrn)
  r = lm(f3(58, f2(20, x, y), pd, ev), f3(58, y, f3(58, x, pd, ev), ev), r)

  # 37: equal(times(x,y), zero) = or(zerop(x), zerop(y))
  r = lm(f2(7, f2(6, x, y), f0(14)), f2(2, f1(9, x), f1(9, y)), r)

  # 36: times(times(x,y), z) = times(x, times(y,z))
  r = lm(f2(6, f2(6, x, y), z), f2(6, x, f2(6, y, z)), r)

  # 35: times(x, plus(y,z)) = plus(times(x,y), times(x,z))
  r = lm(f2(6, x, f2(5, y, z)), f2(5, f2(6, x, y), f2(6, x, z)), r)

  # 34: reverse(append(a,b)) = append(reverse(b), reverse(a))
  r = lm(f1(21, f2(20, a, b)), f2(20, f1(21, b), f1(21, a)), r)

  # 33: append(append(x,y), z) = append(x, append(y,z))
  r = lm(f2(20, f2(20, x, y), z), f2(20, x, f2(20, y, z)), r)

  # 32: meaning(plus_tree(plus_fringe(x)), a) = fix(meaning(x,a))
  r = lm(f2(60, f1(61, f1(62, x)), a), f1(10, f2(60, x, a)), r)

  # 31: meaning(plus_tree(append(x,y)), a) = plus(meaning(plus_tree(x),a), meaning(plus_tree(y),a))
  r = lm(f2(60, f1(61, f2(20, x, y)), a), f2(5, f2(60, f1(61, x), a), f2(60, f1(61, y), a)), r)

  # 30: equal(x, difference(x,y)) = and(numberp(x), or(equal(x,zero), zerop(y)))
  r = lm(f2(7, x, f2(19, x, y)), f2(1, f1(55, x), f2(2, f2(7, x, f0(14)), f1(9, y))), r)

  # 29: equal(zero, difference(x,y)) = not(lessp(y,x))
  r = lm(f2(7, f0(14), f2(19, x, y)), f1(3, f2(8, y, x)), r)

  # 28: equal(plus(a,b), plus(a,c)) = equal(fix(b), fix(c))
  r = lm(f2(7, f2(5, a, b), f2(5, a, c)), f2(7, f1(10, b), f1(10, c)), r)

  # 27: difference(x,x) = zero
  r = lm(f2(19, x, x), f0(14), r)

  # 26: equal(plus(a,b), zero) = and(zerop(a), zerop(b))
  r = lm(f2(7, f2(5, a, b), f0(14)), f2(1, f1(9, a), f1(9, b)), r)

  # 25: plus(plus(x,y), z) = plus(x, plus(y,z))
  r = lm(f2(5, f2(5, x, y), z), f2(5, x, f2(5, y, z)), r)

  # 24: zerop(x) = or(equal(x,zero), not(numberp(x)))
  r = lm(f1(9, x), f2(2, f2(7, x, f0(14)), f1(3, f1(55, x))), r)

  # 23: if(if(a,b,c), d, e) = if(a, if(b,d,e), if(c,d,e))
  r = lm(f3(0, f3(0, a, b, c), d, e), f3(0, a, f3(0, b, d, e), f3(0, c, d, e)), r)

  # 22: fix(x) = if(numberp(x), x, zero)
  r = lm(f1(10, x), f3(0, f1(55, x), x, f0(14)), r)

  # 21: implies(p,q) = if(p, if(q,t,f), t)
  r = lm(f2(4, p, q), f3(0, p, f3(0, q, f0(11), f0(12)), f0(11)), r)

  # 20: not(p) = if(p, f, t)
  r = lm(f1(3, p), f3(0, p, f0(12), f0(11)), r)

  # 19: or(p,q) = if(p, t, if(q,t,f))
  r = lm(f2(2, p, q), f3(0, p, f0(11), f3(0, q, f0(11), f0(12))), r)

  # 18: and(p,q) = if(p, if(q,t,f), f)
  r = lm(f2(1, p, q), f3(0, p, f3(0, q, f0(11), f0(12)), f0(12)), r)

  # 17: prime(x) = and(not(zerop(x)), not(equal(x,add1(zero))), prime1(x, sub1(x)))
  # Note: 3-arg and
  r = lm(f1(53, x), f3(1, f1(3, f1(9, x)), f1(3, f2(7, x, f1(15, f0(14)))), f2(54, x, f1(16, x))), r)

  # 16: falsify(x) = falsify1(normalize(x), nil)
  r = lm(f1(51, x), f2(52, f1(50, x), f0(13)), r)

  # 15: taut_checker(x) = tautologyp_fn(normalize(x), nil)
  r = lm(f1(48, x), f2(49, f1(50, x), f0(13)), r)

  # 14: assume_false(var_,alist) = cons(cons(var_,f), alist)
  r = lm(f2(47, vr, al), f2(27, f2(27, vr, f0(12)), al), r)

  # 13: assume_true(var_,alist) = cons(cons(var_,t), alist)
  r = lm(f2(46, vr, al), f2(27, f2(27, vr, f0(11)), al), r)

  # 12: divides(x,y) = zerop(remainder(y,x))
  r = lm(f2(45, x, y), f1(9, f2(17, y, x)), r)

  # 11: reverse_(x) = reverse_loop(x, nil)
  r = lm(f1(43, x), f2(44, x, f0(13)), r)

  # 10: fact_(i) = fact_loop(i, n1)
  r = lm(f1(41, i), f2(42, i, f0(89)), r)

  # 9: countps_(l,pred) = countps_loop(l, pred, zero)
  r = lm(f2(40, l, pr), f3(39, l, pr, f0(14)), r)

  # 8: even1(x) = if(zerop(x), t, odd(sub1(x)))
  r = lm(f1(37, x), f3(0, f1(9, x), f0(11), f1(38, f1(16, x))), r)

  # 7: iff(x,y) = and(implies(x,y), implies(y,x))
  r = lm(f2(36, x, y), f2(1, f2(4, x, y), f2(4, y, x)), r)

  # 6: boolean(x) = or(equal(x,t), equal(x,f))
  r = lm(f1(35, x), f2(2, f2(7, x, f0(11)), f2(7, x, f0(12))), r)

  # 5: greatereqp(x,y) = not(lessp(x,y))
  r = lm(f2(34, x, y), f1(3, f2(8, x, y)), r)

  # 4: lesseqp(x,y) = not(lessp(y,x))
  r = lm(f2(33, x, y), f1(3, f2(8, y, x)), r)

  # 3: greaterp(x,y) = lessp(y,x)
  r = lm(f2(32, x, y), f2(8, y, x), r)

  # 2: eqp(x,y) = equal(fix(x), fix(y))
  r = lm(f2(31, x, y), f2(7, f1(10, x), f1(10, y)), r)

  # 1: compile(form) = reverse(codegen(optimize(form), nil))
  r = lm(f1(28, fm), f1(21, f2(29, f1(30, fm), f0(13))), r)

  r

# Test Formula
# ------------

# Template: implies(and(implies(x,y), and(implies(y,z), and(implies(z,u), implies(u,w)))), implies(x,w))
# With substitution applied:
#   x -> f_sym(plus(plus(a,b), plus(c,zero)))
#   y -> f_sym(times(times(a,b), plus(c,d)))
#   z -> f_sym(reverse(append(append(a,b), nil)))
#   u -> equal(plus(a,b), difference(x,y))     (x=v(0), y=v(1) as atoms)
#   w -> lessp(remainder(a,b), member(a, length(b)))
# where a=v(5), b=v(6), c=v(7), d=v(8)

def test_form() -> Term:
  a = vv(5)
  b = vv(6)
  c = vv(7)
  d = vv(8)
  # x,y in u's value are atom variables
  vx = vv(0)
  vy = vv(1)
  # substituted values
  sx = f1(92, f2(5, f2(5, a, b), f2(5, c, f0(14))))
  sy = f1(92, f2(6, f2(6, a, b), f2(5, c, d)))
  sz = f1(92, f1(21, f2(20, f2(20, a, b), f0(13))))
  su = f2(7, f2(5, a, b), f2(19, vx, vy))
  sw = f2(8, f2(17, a, b), f2(23, a, f1(26, b)))
  # template with substitution applied
  f2(4, f2(1, f2(4, sx, sy), f2(1, f2(4, sy, sz), f2(1, f2(4, sz, su), f2(4, su, sw)))), f2(4, sx, sw))

# Main
# ----

def main() -> U32:
  b2u(tautp(test_form(), lms()))
