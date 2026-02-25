bench
=====

Unified benchmarks for [HVM](https://github.com/HigherOrderCO/HVM4) and [Bend](https://github.com/HigherOrderCO/bend2-ts).

Each subdirectory under `bench/` contains a single benchmark case.
Files are named `main.hvm` (HVM) or `main.bend` (Bend).

Benchmarks
----------

- `cnot_04` — Applies λ-encoded NOT 2^4 times via cloned composition (HVM)
- `cnot_16` — Applies λ-encoded NOT 2^16 times via cloned composition (HVM)
- `cnot_24` — Applies λ-encoded NOT 2^24 times via cloned composition (HVM)
- `bignat_mul` — Schoolbook big-integer multiplication over immutable U32 limb lists (Bend)
- `edit_dist` — Row-DP Levenshtein distance over immutable U32 sequences (Bend)
- `gab_boyer` — Tautology checking with term rewriting over 106 lemmas (Bend)
- `gab_deriv` — Symbolic differentiation of a polynomial, 5000 iterations (Bend)
- `gab_tak` — Takeuchi triply-recursive function on Nat (18, 12, 6) (Bend)
- `gab_takl` — Takeuchi variant using list length comparison (18, 12, 6) (Bend)
- `gen_easy` — Type-directed proof search generating a sort function, small inputs (HVM)
- `gen_hard` — Type-directed proof search generating a sort function, large inputs (HVM)
- `gen_mul4k` — Proof search generating a multiplication function (HVM)
- `lambda_eval` — Lambda-calculus normalization with de Bruijn terms and Church arithmetic (Bend)
- `mat_mul` — Nat-driven nested loops with U32 pseudo-random mixing (Bend)
- `nqueens` — N-Queens backtracking over U32 bitset masks (Bend)
- `sort_merge` — Merge sort over immutable U32 lists with pseudo-random inputs (Bend)
- `trie_bitwise` — Persistent bitwise trie insert/query/fold over U32 keys (Bend)
- `seq_pingpong` — Mutual recursion via boxed continuations, 5M bounces (HVM)
- `spin_tree` — Binary tree to depth 8 with spin loops at 256 leaves (HVM)
- `tree_fold` — Builds and folds a binary tree to depth 24 (Bend)
- `u32_fib` — Naive Fibonacci on U32 to n=44 (Bend)

Runner
------

Run benchmarks with the unified script:

```sh
./bench.ts --hvm-interpreted
./bench.ts --hvm-compiled
./bench.ts --bend-via-bunjs --bend-via-nodejs
./bench.ts --bend-interpreted-via-bunjs --bend-interpreted-via-hvm-compiled
```

Available options:

- `--bend-via-bunjs` (`bend-bun`)
- `--bend-via-nodejs` (`bend-node`)
- `--bend-via-hvm-interpreted[-TN]` (`bend-hvmi[N]`)
- `--bend-via-hvm-compiled[-TN]` (`bend-hvmc[N]`)
- `--bend-interpreted-via-bunjs` (`bendi-bun`)
- `--bend-interpreted-via-nodejs` (`bendi-node`)
- `--bend-interpreted-via-hvm-interpreted[-TN]` (`bendi-hvmi[N]`)
- `--bend-interpreted-via-hvm-compiled[-TN]` (`bendi-hvmc[N]`)
- `--hvm-interpreted[-TN]` (`hvmi[N]`)
- `--hvm-compiled[-TN]` (`hvmc[N]`)

Examples:

- `./bench.ts hvmi hvmi4 hvmc8 bend-bun`
- `./bench.ts --hvm-interpreted-T4 --bend-via-hvm-compiled-T8`

Command overrides:

- `BEND_CMD` (default: `bend`)
- `HVM_CMD` (default: `hvm`)
- `BUN_CMD` (default: `bun`)
- `NODE_CMD` (default: `node`)
- `BEND_NODE_ENTRY` (optional explicit script path for `bendi-node`)
