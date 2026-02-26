# huffman
# =======
# Huffman encoding/decoding benchmark. Builds frequency table from
# pseudo-random text, constructs Huffman tree, encodes to bits,
# decodes back, and checksums the result. Stresses multi-phase
# pipelines, tree construction, sorted insertion, and list ops.

# Types
# -----

type Bool() {
  T{}
  F{}
}

type Lst() {
  nil{}
  cons{U32, Lst}
}

type Tree() {
  leaf{U32}
  node{Tree, Tree}
}

type PQ() {
  pnil{}
  pcons{U32, Tree, PQ}
}

# Utils
# -----

# Converts U32 zero/nonzero to Bool
def u2b(n: U32) -> Bool:
  match n:
    case 0:
      F{}
    case x:
      T{}

# Advances a linear-congruential generator seed
def rng(seed: U32) -> U32:
  seed * 1664525 + 1013904223

# Reverses a list with tail-recursive accumulator
def rev(xs: Lst, acc: Lst) -> Lst:
  match xs:
    case []:
      acc
    case x<>xt:
      rev(xt, x<>acc)

# Text Generation
# ---------------

# Generates a list of pseudo-random symbols (0..7)
def gen(len: U32, seed: U32, acc: Lst) -> Lst:
  match len:
    case 0:
      rev(acc, [])
    case k:
      seed = rng(seed)
      sym  = (seed / 65536) % 8
      gen(k - 1, seed, sym<>acc)

# Frequency Counting
# ------------------

# Creates a list of n zeros
def zeros(n: U32) -> Lst:
  match n:
    case 0:
      []
    case k:
      0<>zeros(k - 1)

# Increments element at index i in a list
def inc_at(xs: Lst, i: U32) -> Lst:
  match xs:
    case []:
      []
    case x<>xt:
      inc_put(u2b(i === 0), x, xt, i)

# Places incremented value at correct index
def inc_put(at: Bool, x: U32, xt: Lst, i: U32) -> Lst:
  match at:
    case T{}:
      (x + 1)<>xt
    case F{}:
      x<>inc_at(xt, i - 1)

# Counts symbol frequencies in text
def freq(text: Lst, arr: Lst) -> Lst:
  match text:
    case []:
      arr
    case c<>rest:
      freq(rest, inc_at(arr, c))

# Priority Queue
# --------------

# Inserts (freq, tree) into sorted position
def pq_ins(f: U32, t: Tree, pq: PQ) -> PQ:
  match pq:
    case pnil{}:
      pcons{f, t, pnil{}}
    case pcons{f2, t2, rest}:
      pq_cmp(u2b(f <= f2), f, t, f2, t2, rest)

# Places at correct position based on comparison
def pq_cmp(le: Bool, f: U32, t: Tree, f2: U32, t2: Tree, rest: PQ) -> PQ:
  match le:
    case F{}:
      pcons{f2, t2, pq_ins(f, t, rest)}
    case T{}:
      pcons{f, t, pcons{f2, t2, rest}}

# Builds initial PQ from frequency array
def pq_from(arr: Lst, sym: U32) -> PQ:
  match arr:
    case []:
      pnil{}
    case f<>rest:
      pq = pq_from(rest, sym + 1)
      pq_add(u2b(f === 0), f, sym, pq)

# Adds symbol to PQ if frequency > 0
def pq_add(skip: Bool, f: U32, sym: U32, pq: PQ) -> PQ:
  match skip:
    case T{}:
      pq
    case F{}:
      pq_ins(f, leaf{sym}, pq)

# Tree Construction
# -----------------

# Builds Huffman tree by merging two lowest-freq items repeatedly
def build(pq: PQ) -> Tree:
  match pq:
    case pnil{}:
      leaf{0}
    case pcons{f1, t1, rest}:
      build_step(f1, t1, rest)

# Merges two items or returns the single remaining tree
def build_step(f1: U32, t1: Tree, rest: PQ) -> Tree:
  match rest:
    case pnil{}:
      t1
    case pcons{f2, t2, rest2}:
      pq = pq_ins(f1 + f2, node{t1, t2}, rest2)
      build(pq)

# Encoding
# --------

# Checks if symbol c exists in a subtree
def has(c: U32, tree: Tree) -> U32:
  match tree:
    case leaf{v}:
      c === v
    case node{l, r}:
      has(c, l) + has(c, r)

# Finds the bit-path from root to leaf containing c
def path(c: U32, tree: Tree) -> Lst:
  match tree:
    case leaf{v}:
      []
    case node{l, r}:
      path_dir(u2b(has(c, l)), c, l, r)

# Follows the direction where c was found
def path_dir(in_left: Bool, c: U32, l: Tree, r: Tree) -> Lst:
  match in_left:
    case T{}:
      0<>path(c, l)
    case F{}:
      1<>path(c, r)

# Prepends xs (reversed) onto accumulator
def rev_onto(xs: Lst, acc: Lst) -> Lst:
  match xs:
    case []:
      acc
    case x<>xt:
      rev_onto(xt, x<>acc)

# Encodes text to bits using the Huffman tree
def encode(text: Lst, tree: Tree, acc: Lst) -> Lst:
  match text:
    case []:
      rev(acc, [])
    case c<>rest:
      code = path(c, tree)
      acc  = rev_onto(code, acc)
      encode(rest, tree, acc)

# Decoding
# --------

# Picks left or right subtree based on bit value
def pick(b: U32, l: Tree, r: Tree) -> Tree:
  match b:
    case 0:
      l
    case k:
      r

# Decodes bits back to symbols using the Huffman tree
def decode(node: Tree, bits: Lst, root: Tree, acc: Lst) -> Lst:
  match node:
    case leaf{c}:
      decode(root, bits, root, c<>acc)
    case node{l, r}:
      decode_bit(bits, l, r, root, acc)

# Consumes one bit and descends into the tree
def decode_bit(bits: Lst, l: Tree, r: Tree, root: Tree, acc: Lst) -> Lst:
  match bits:
    case []:
      rev(acc, [])
    case b<>rest:
      next = pick(b, l, r)
      decode(next, rest, root, acc)

# Checksum
# --------

# Folds a list into a U32 checksum
def hash(xs: Lst, acc: U32) -> U32:
  match xs:
    case []:
      acc
    case x<>xt:
      acc = (acc ^ x) * 16777619 + 2166136261
      hash(xt, acc)

# Benchmark
# ---------

# Runs repeated encode/decode rounds
def bench(rounds: U32, seed: U32, acc: U32) -> U32:
  match rounds:
    case 0:
      acc
    case r:
      text = gen(500, seed, [])
      arr  = freq(text, zeros(8))
      tree = build(pq_from(arr, 0))
      bits = encode(text, tree, [])
      out  = decode(tree, bits, tree, [])
      acc  = hash(out, acc)
      seed = rng(seed)
      bench(r - 1, seed, acc)

# Main
# ----

# Entry point
def main() -> U32:
  bench(4750, 1, 0)
