#!/usr/bin/env bash
# bench_table.sh
# ==============
# Runs all benchmarks under bench/* and prints a complete timing table.
# For each main.hvm:
# - runs HVM interpreted
# - compiles to native, then times only native run (compile time excluded)
# If a sibling main.bend exists, also runs Bend JS reference and reports parity.

set -euo pipefail
export LC_ALL=C

# Config
# ------

# Global timeout (seconds) for each timed run.
bench_timeout_s="${BENCH_TIMEOUT:-20}"

# Compile timeout (seconds) for `hvm -o ...` steps.
bench_compile_timeout_s="${BENCH_COMPILE_TIMEOUT:-60}"

# Temp
# ----

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/bench_table.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT
issue_file="$tmp_dir/issues.txt"
: > "$issue_file"

# Utils
# -----

# Returns one-line command output, or empty string.
read_out() {
  local file="$1"
  if [ ! -s "$file" ]; then
    echo ""
    return
  fi
  head -c 256 "$file" \
    | tr -cd '\11\12\15\40-\176' \
    | tr '\n' ' ' \
    | sed 's/[[:space:]]\+$//'
}

# Formats output cell to a compact single line.
fmt_out() {
  local txt="$1"
  txt="$(printf '%s' "$txt" | tr -s ' ')"
  txt="${txt//|/\\|}"
  if [ -z "$txt" ]; then
    echo "-"
    return
  fi
  if [ "${#txt}" -gt 36 ]; then
    printf '%s...' "${txt:0:33}"
    return
  fi
  echo "$txt"
}

# Records one issue line for end-of-run summary.
append_issue() {
  local msg="$1"
  printf '%s\n' "$msg" >> "$issue_file"
}

# Runs command with timeout and wall-clock timing.
# Prints "<exit_code>|<real_seconds>".
run_timed() {
  local out_file="$1"
  local err_file="$2"
  shift 2

  set +e
  /usr/bin/time -p timeout "$bench_timeout_s" "$@" > "$out_file" 2> "$err_file"
  local ec="$?"
  set -e

  local tm
  tm="$(awk '/^real / { val = $2 } END { print val }' "$err_file")"
  if [ -z "$tm" ]; then
    tm="NA"
  fi

  printf '%s|%s\n' "$ec" "$tm"
}

# Bench
# -----

# Runs one benchmark row.
run_one() {
  local name="$1"
  local hvm_file="$2"
  local bend_file="$3"
  local has_bend="$4"

  local row_dir="$tmp_dir/$name"
  mkdir -p "$row_dir"

  local bend_tm="-"
  local bend_out=""
  local bend_ec="0"
  local hvi_tm="-"
  local hvi_out=""
  local hvi_ec="0"
  local hvc_tm="-"
  local hvc_out=""
  local hvc_ec="0"
  local parity="n/a"

  if [ "$has_bend" = "1" ]; then
    local bend_res
    bend_res="$(
      run_timed \
        "$row_dir/bend.out" \
        "$row_dir/bend.err" \
        bend "$bend_file" --as-js
    )"
    bend_ec="${bend_res%%|*}"
    bend_tm="${bend_res#*|}"
    bend_out="$(read_out "$row_dir/bend.out")"
  fi

  local hvi_res
  hvi_res="$(
    run_timed \
      "$row_dir/hvi.out" \
      "$row_dir/hvi.err" \
      hvm "$hvm_file"
  )"
  hvi_ec="${hvi_res%%|*}"
  hvi_tm="${hvi_res#*|}"
  hvi_out="$(read_out "$row_dir/hvi.out")"

  local bin_file="$row_dir/$name.bin"
  set +e
  /usr/bin/time -p timeout "$bench_compile_timeout_s" \
    hvm "$hvm_file" -o "$bin_file" \
    > "$row_dir/hvc_build.out" \
    2> "$row_dir/hvc_build.err"
  local build_ec="$?"
  set -e
  if [ "$build_ec" -ne 0 ]; then
    hvc_ec="$build_ec"
    hvc_tm="-"
    hvc_out=""
  else
    local hvc_res
    hvc_res="$(
      run_timed \
        "$row_dir/hvc.out" \
        "$row_dir/hvc.err" \
        "$bin_file"
    )"
    hvc_ec="${hvc_res%%|*}"
    hvc_tm="${hvc_res#*|}"
    hvc_out="$(read_out "$row_dir/hvc.out")"
  fi

  if [ "$has_bend" = "1" ]; then
    if [ "$bend_ec" -ne 0 ]; then
      parity="bend_fail"
      append_issue "$name: bend_js failed (exit=$bend_ec, t=${bend_tm}s)"
    elif [ "$hvi_ec" -ne 0 ] || [ "$hvc_ec" -ne 0 ]; then
      parity="hvm_fail"
      append_issue "$name: hvm failed (interp_exit=$hvi_ec, comp_exit=$hvc_ec)"
    else
      local b_raw
      local i_raw
      local c_raw
      b_raw="$bend_out"
      i_raw="$hvi_out"
      c_raw="$hvc_out"
      if [ "$b_raw" = "$i_raw" ] && [ "$b_raw" = "$c_raw" ]; then
        parity="ok"
      else
        parity="mismatch"
        append_issue "$name: output mismatch"
      fi
    fi
  elif [ "$hvi_ec" -ne 0 ] || [ "$hvc_ec" -ne 0 ]; then
    append_issue "$name: hvm-only bench failed (interp_exit=$hvi_ec, comp_exit=$hvc_ec)"
  fi

  last_parity="$parity"
  last_row="| $name | $bend_tm | $hvi_tm | $hvc_tm |"
}

main() {
  local -a hvm_files=()
  while IFS= read -r file; do
    hvm_files+=("$file")
  done < <(rg --files bench | rg '/main\.hvm$' | sort)

  echo "BENCH_TIMEOUT=${bench_timeout_s}s"
  echo "BENCH_COMPILE_TIMEOUT=${bench_compile_timeout_s}s"
  echo
  echo '| benchmark | bend_js_s | hvm_i_s | hvm_c_s |'
  echo '|---|---:|---:|---:|'

  local total=0
  local bend_total=0
  local parity_ok=0
  local parity_fail=0
  local mismatch_count=0

  local hvm_file
  local last_parity="n/a"
  local last_row=""
  for hvm_file in "${hvm_files[@]}"; do
    total=$((total + 1))

    local dir
    dir="$(dirname "$hvm_file")"
    local name
    name="$(basename "$dir")"
    local bend_file="$dir/main.bend"
    local has_bend=0
    if [ -f "$bend_file" ]; then
      has_bend=1
      bend_total=$((bend_total + 1))
    fi

    run_one "$name" "$hvm_file" "$bend_file" "$has_bend"
    echo "$last_row"

    if [ "$has_bend" = "1" ]; then
      if [ "$last_parity" = "ok" ]; then
        parity_ok=$((parity_ok + 1))
      else
        parity_fail=$((parity_fail + 1))
        if [ "$last_parity" = "mismatch" ]; then
          mismatch_count=$((mismatch_count + 1))
        fi
      fi
    fi
  done

  echo
  echo "total_hvm_benchmarks=$total"
  echo "with_bend_reference=$bend_total"
  echo "parity_ok=$parity_ok"
  echo "parity_not_ok=$parity_fail"
  echo "output_mismatches=$mismatch_count"
  if [ -s "$issue_file" ]; then
    echo "issues:"
    sed 's/^/- /' "$issue_file"
  fi
}

main "$@"
