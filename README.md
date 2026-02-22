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
- `gab_boyer` — Tautology checking with term rewriting over 106 lemmas (Bend)
- `gab_deriv` — Symbolic differentiation of a polynomial, 5000 iterations (Bend)
- `gab_tak` — Takeuchi triply-recursive function on Nat (18, 12, 6) (Bend)
- `gab_takl` — Takeuchi variant using list length comparison (18, 12, 6) (Bend)
- `gen_easy` — Type-directed proof search generating a sort function, small inputs (HVM)
- `gen_hard` — Type-directed proof search generating a sort function, large inputs (HVM)
- `gen_mul4k` — Proof search generating a multiplication function (HVM)
- `mat_mul` — Nat-driven nested loops with U32 pseudo-random mixing (Bend)
- `seq_pingpong` — Mutual recursion via boxed continuations, 5M bounces (HVM)
- `spin_tree` — Binary tree to depth 8 with spin loops at 256 leaves (HVM)
- `tree_fold` — Builds and folds a binary tree to depth 24 (Bend)
- `u32_fib` — Naive Fibonacci on U32 to n=44 (Bend)
