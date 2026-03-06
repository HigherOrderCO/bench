// fib_nat/main.ts
// ===============
// Naive Fibonacci recursion over Peano naturals.
// Mirrors bench/fib_nat/main.hvm.

// Nat
// ---

export type Zer = { $: "ZER" };
export type Suc = { $: "SUC", pred: Nat };
export type Nat = Zer | Suc;

// Builds `#ZER{}`.
function ZER(): Zer {
  return { $: "ZER" };
}

// Builds `#SUC{pred}`.
function SUC(pred: Nat): Suc {
  return { $: "SUC", pred };
}

// Utils
// -----

// Builds one Peano nat from one JS number.
function nat(n: number): Nat {
  var out: Nat = ZER();
  while (n > 0) {
    out = SUC(out);
    n   = n - 1;
  }
  return out;
}

// Nat Arithmetic
// --------------

// Adds two unary naturals tail-recursively.
function add(a: Nat, b: Nat): Nat {
  while (true) {
    switch (a.$) {
      case "ZER": {
        return b;
      }
      case "SUC": {
        var a = a.pred;
        var b = SUC(b);
        continue;
      }
    }
  }
}

// Fibonacci
// ---------

// Computes Fibonacci over unary naturals.
function fib(n: Nat): Nat {
  switch (n.$) {
    case "ZER": {
      return ZER();
    }
    case "SUC": {
      var n = n.pred;
      switch (n.$) {
        case "ZER": {
          return SUC(ZER());
        }
        case "SUC": {
          var p   = n.pred;
          var p_0 = p;
          var p_1 = p;
          return add(fib(SUC(p_0)), fib(p_1));
        }
      }
    }
  }
}

// U32
// ---

// Converts one unary nat to one U32 accumulator.
function u32(n: Nat, acc: number): number {
  while (true) {
    switch (n.$) {
      case "ZER": {
        return acc;
      }
      case "SUC": {
        var n   = n.pred;
        var acc = 1 + acc;
        continue;
      }
    }
  }
}

// Main
// ----

// Evaluates fib(34) and converts the result to one JS number.
export function main(): number {
  return u32(fib(nat(34)), 0);
}
