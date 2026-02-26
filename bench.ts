#!/usr/bin/env bun
// bench.ts
// ========
// Unified benchmark runner for Bend/HVM benchmark suites.
//
// Sources:
// - `bench/*/main.bend` for Bend pipelines
// - `bench/*/main.hvm`  for HVM pipelines
//
// Sampling model:
// - warmup calls
// - timed calls until either min_runs or min_secs is satisfied
// - report mean seconds per call

import { spawn } from "node:child_process";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import * as url from "node:url";

// Config
// ------

var MODE_MIN_WID   = 11;
var NAME_MAX_WID   = 28;
var MAX_BUFFER     = 64 * 1024 * 1024;
var CMD_TIMEOUT_MS = 20 * 60 * 1000;
var CLEAR          = "\x1b[2J\x1b[H";

var DEF_WARMUP   = 1;
var DEF_MIN_RUNS = 1;
var DEF_MAX_RUNS = 1;
var DEF_MIN_SECS = 0.0;

var SECS_TAG       = "BENCH_SECS";
var TIMEOUT_PREFIX = "timed out after ";

var ROOT_DIR = path.dirname(url.fileURLToPath(import.meta.url));
var CASE_DIR = path.join(ROOT_DIR, "bench");
var TMP_DIR  = fs.mkdtempSync(path.join(os.tmpdir(), "bench-ts."));

var BEND_CMD           = process.env.BEND_CMD           ?? "bend";
var NEW_BEND_CMD       = process.env.NEW_BEND_CMD       ?? "newbend";
var BEND_NODE_ENTRY    = process.env.BEND_NODE_ENTRY    ?? null;
var NEW_BEND_NODE_ENTRY = process.env.NEW_BEND_NODE_ENTRY ?? null;
var HVM_CMD            = process.env.HVM_CMD            ?? "hvm";
var BUN_CMD            = process.env.BUN_CMD            ?? "bun";
var NODE_CMD           = process.env.NODE_CMD           ?? "node";

// Types
// -----

type CellState = "pending" | "running" | "done" | "error" | "timeout" | "na";

type Cell = {
  state: CellState;
  secs:  number | null;
  err:   string | null;
};

type Row = {
  name:      string;
  bend_file: string | null;
  hvm_file:  string | null;
  cells:     Record<string, Cell>;
};

type SampleCfg = {
  warmup:   number;
  min_runs: number;
  max_runs: number;
  min_secs: number;
};

type ModeInput = "bend" | "hvm";
type BendCmdSrc = "none" | "bend" | "newbend";

type ModeDef = {
  flag:          string;
  label:         string;
  input:         ModeInput;
  bend_cmd_src:  BendCmdSrc;
  needs_bend:    boolean;
  needs_hvm:     boolean;
  needs_bun:     boolean;
  needs_node:    boolean;
  needs_node_ts: boolean;
  hvm_threads:   boolean;
  run:           (row: Row, cfg: SampleCfg, threads: number, bend_cmd: string | null) => Promise<number>;
};

type Mode = {
  key:           string;
  flag:          string;
  label:         string;
  input:         ModeInput;
  bend_cmd:      string | null;
  needs_bend:    boolean;
  needs_hvm:     boolean;
  needs_bun:     boolean;
  needs_node:    boolean;
  needs_node_ts: boolean;
  run:           (row: Row, cfg: SampleCfg) => Promise<number>;
};

type CliCfg = {
  show_help:   boolean;
  timeout_ms:  number;
  mode_tokens: string[];
};

// Cells
// -----

// Creates one fresh table cell.
function cell_new(state: CellState = "pending"): Cell {
  return { state, secs: null, err: null };
}

// Process Management
// ------------------

var ACTIVE_CHILDREN = new Set<number>();
var SHUTTING_DOWN   = false;

// Kills one process group, or single pid fallback.
function kill_pg(pid: number): void {
  try {
    process.kill(-pid, "SIGKILL");
    return;
  } catch {}
  try {
    process.kill(pid, "SIGKILL");
  } catch {}
}

// Kills all active child processes.
function cleanup_children(): void {
  for (var pid of ACTIVE_CHILDREN) {
    kill_pg(pid);
  }
  ACTIVE_CHILDREN.clear();
}

// Deletes temporary runner files.
function cleanup_tmp(): void {
  try {
    fs.rmSync(TMP_DIR, { recursive: true, force: true });
  } catch {}
}

// Runs all cleanup actions.
function cleanup_all(): void {
  cleanup_children();
  cleanup_tmp();
}

// Handles process signals.
function on_signal(sig: string): void {
  if (SHUTTING_DOWN) {
    return;
  }
  SHUTTING_DOWN = true;
  cleanup_all();
  process.exit(sig === "SIGINT" ? 130 : 143);
}

process.on("SIGINT",  () => on_signal("SIGINT"));
process.on("SIGTERM", () => on_signal("SIGTERM"));
process.on("exit",    () => cleanup_all());

// Timer
// -----

// Returns current monotonic timestamp in nanoseconds.
function now_ns(): bigint {
  return process.hrtime.bigint();
}

// Returns elapsed seconds since a start timestamp.
function elapsed_secs(start: bigint): number {
  return Number(process.hrtime.bigint() - start) / 1e9;
}

// Env Parsing
// -----------

// Reads a positive integer env var.
function env_pos_int(name: string, fallback: number): number {
  var raw = process.env[name];
  if (raw === undefined || raw === "") {
    return fallback;
  }

  var val = Number(raw);
  if (!Number.isFinite(val)) {
    throw new Error("invalid env " + name + ": " + JSON.stringify(raw));
  }

  var val = Math.floor(val);
  if (val <= 0) {
    throw new Error("invalid env " + name + " (must be > 0): " + JSON.stringify(raw));
  }
  return val;
}

// Reads a non-negative integer env var.
function env_nonneg_int(name: string, fallback: number): number {
  var raw = process.env[name];
  if (raw === undefined || raw === "") {
    return fallback;
  }

  var val = Number(raw);
  if (!Number.isFinite(val)) {
    throw new Error("invalid env " + name + ": " + JSON.stringify(raw));
  }

  var val = Math.floor(val);
  if (val < 0) {
    throw new Error("invalid env " + name + " (must be >= 0): " + JSON.stringify(raw));
  }
  return val;
}

// Reads a non-negative number env var.
function env_nonneg_num(name: string, fallback: number): number {
  var raw = process.env[name];
  if (raw === undefined || raw === "") {
    return fallback;
  }

  var val = Number(raw);
  if (!Number.isFinite(val) || val < 0) {
    throw new Error("invalid env " + name + " (must be >= 0): " + JSON.stringify(raw));
  }
  return val;
}

// Returns benchmark sampling config.
function sample_cfg_get(): SampleCfg {
  return {
    warmup:   DEF_WARMUP,
    min_runs: DEF_MIN_RUNS,
    max_runs: DEF_MAX_RUNS,
    min_secs: DEF_MIN_SECS,
  };
}

// Formats sampling config.
function sample_cfg_show(cfg: SampleCfg): string {
  return [
    "sampling:",
    "warmup="   + cfg.warmup,
    "min_runs=" + cfg.min_runs,
    "max_runs=" + cfg.max_runs,
    "min_secs=" + cfg.min_secs.toFixed(3) + "s",
  ].join(" ");
}

// Paths
// -----

// Asserts one path exists.
function assert_exists(file: string, desc: string): void {
  if (!fs.existsSync(file)) {
    throw new Error("missing " + desc + ": " + file);
  }
}

// Returns true if a path is executable.
function is_exec(file: string): boolean {
  try {
    var st = fs.statSync(file);
    if (!st.isFile()) {
      return false;
    }
    return (st.mode & 0o111) !== 0;
  } catch {
    return false;
  }
}

// Resolves one command to an absolute executable path.
function resolve_cmd_path(cmd: string): string {
  if (cmd.includes("/")) {
    var abs = path.resolve(cmd);
    if (!is_exec(abs)) {
      throw new Error("command is not executable: " + abs);
    }
    return fs.realpathSync(abs);
  }

  var raw_path = process.env.PATH ?? "";
  var dirs = raw_path.split(path.delimiter).filter(p => p.length > 0);
  for (var dir of dirs) {
    var cand = path.join(dir, cmd);
    if (!is_exec(cand)) {
      continue;
    }
    return fs.realpathSync(cand);
  }

  throw new Error("command not found in $PATH: " + cmd);
}

// Converts text into a filesystem-safe token.
function tmp_tok(txt: string): string {
  var txt = txt.toLowerCase();
  var txt = txt.replace(/[^a-z0-9]+/g, "-");
  var txt = txt.replace(/^-+/, "");
  var txt = txt.replace(/-+$/, "");
  if (txt.length === 0) {
    return "tmp";
  }
  return txt;
}

// Creates one deterministic temp path under this run directory.
function tmp_path(parts: string[], ext: string): string {
  var nam = parts.map(tmp_tok).join("-");
  if (nam.length === 0) {
    nam = "tmp";
  }
  return path.join(TMP_DIR, nam + ext);
}

// Returns benchmark tag from benchmark file path.
function bench_tag(file: string): string {
  return path.basename(path.dirname(file));
}

// Commands
// --------

// Formats spawn errors for readable messages.
function spawn_err_msg(cmd: string, err: unknown): string {
  if (typeof err === "object" && err !== null && "code" in err) {
    if ((err as any).code === "ENOENT") {
      return "not found in $PATH: " + JSON.stringify(cmd);
    }
  }

  if (err instanceof Error && err.message.length > 0) {
    return err.message;
  }
  return String(err);
}

// Returns whether one error message corresponds to a timeout.
function err_is_timeout(msg: string): boolean {
  return msg.startsWith(TIMEOUT_PREFIX);
}

// Runs one command and returns stdout, or throws on failure.
async function run_cmd(cmd: string, args: string[], cwd: string = ROOT_DIR): Promise<string> {
  return await new Promise((resolve, reject) => {
    var done    = false;
    var out_len = 0;
    var err_len = 0;

    var out_bufs: Buffer[] = [];
    var err_bufs: Buffer[] = [];

    var cmd_txt = [cmd].concat(args).join(" ");

    var child = spawn(cmd, args, {
      cwd,
      detached: true,
      stdio: ["ignore", "pipe", "pipe"],
    });

    var pid = child.pid ?? null;
    if (pid !== null) {
      ACTIVE_CHILDREN.add(pid);
    }

    function fin_ok(out: string): void {
      if (done) {
        return;
      }
      done = true;
      clearTimeout(timer);
      if (pid !== null) {
        ACTIVE_CHILDREN.delete(pid);
      }
      resolve(out);
    }

    function fin_err(msg: string): void {
      if (done) {
        return;
      }
      done = true;
      clearTimeout(timer);
      if (pid !== null) {
        ACTIVE_CHILDREN.delete(pid);
      }
      reject(new Error(msg));
    }

    function on_chunk(bufs: Buffer[], chunk: Buffer, add_len: (n: number) => void): void {
      bufs.push(chunk);
      add_len(chunk.length);
      if (out_len + err_len > MAX_BUFFER) {
        if (pid !== null) {
          kill_pg(pid);
        } else {
          try {
            child.kill("SIGKILL");
          } catch {}
        }
        fin_err("output exceeded max buffer: " + cmd_txt);
      }
    }

    child.stdout.on("data", (chunk: Buffer | string) => {
      var buf = Buffer.isBuffer(chunk) ? chunk : Buffer.from(String(chunk));
      on_chunk(out_bufs, buf, n => {
        out_len += n;
      });
    });

    child.stderr.on("data", (chunk: Buffer | string) => {
      var buf = Buffer.isBuffer(chunk) ? chunk : Buffer.from(String(chunk));
      on_chunk(err_bufs, buf, n => {
        err_len += n;
      });
    });

    child.on("error", err => {
      fin_err(spawn_err_msg(cmd, err));
    });

    child.on("close", code => {
      var out = Buffer.concat(out_bufs).toString("utf8");
      var err = Buffer.concat(err_bufs).toString("utf8");
      if (code === 0) {
        fin_ok(out);
        return;
      }

      var msg = err.trim();
      if (msg.length === 0) {
        msg = out.trim();
      }
      if (msg.length === 0) {
        msg = "command failed: " + cmd_txt;
      }
      fin_err(msg);
    });

    var timer = setTimeout(() => {
      if (pid !== null) {
        kill_pg(pid);
      } else {
        try {
          child.kill("SIGKILL");
        } catch {}
      }
      fin_err(TIMEOUT_PREFIX + CMD_TIMEOUT_MS + "ms: " + cmd_txt);
    }, CMD_TIMEOUT_MS);
  });
}

// Sampling
// --------

// Returns whether sampling needs one more timed run.
function sample_needs_more(cnt: number, sum: number, cfg: SampleCfg): boolean {
  if (cnt === 0) {
    return true;
  }

  if (cnt >= cfg.max_runs) {
    return false;
  }

  if (cnt < cfg.min_runs && sum < cfg.min_secs) {
    return true;
  }

  return false;
}

// Runs one async callback with warmup and sampled averaging.
async function run_sampled(run_once: () => Promise<void>, cfg: SampleCfg): Promise<number> {
  for (var i = 0; i < cfg.warmup; ++i) {
    await run_once();
  }

  var sum = 0;
  var cnt = 0;
  while (sample_needs_more(cnt, sum, cfg)) {
    var start = now_ns();
    await run_once();
    var secs = elapsed_secs(start);

    sum += secs;
    cnt += 1;
  }

  if (cnt === 0) {
    return NaN;
  }
  return sum / cnt;
}

// Runs one sync callback with warmup and sampled averaging.
function run_hot_sync(run: () => unknown, cfg: SampleCfg): number {
  for (var i = 0; i < cfg.warmup; ++i) {
    run();
  }

  var sum = 0;
  var cnt = 0;
  while (sample_needs_more(cnt, sum, cfg)) {
    var start = now_ns();
    run();
    var secs = elapsed_secs(start);

    sum += secs;
    cnt += 1;
  }

  if (cnt === 0) {
    return NaN;
  }
  return sum / cnt;
}

// JS Helpers
// ----------

// Builds a cache-busting module URL.
function js_mod_url(file: string): string {
  var base = url.pathToFileURL(file).href;
  return base + "?v=" + now_ns().toString();
}

// Finds the callable benchmark main function in one module.
function js_main_get(mod: Record<string, unknown>): () => unknown {
  var main = mod.$main;
  if (typeof main === "function") {
    return main as () => unknown;
  }

  var main = mod.main;
  if (typeof main === "function") {
    return main as () => unknown;
  }

  throw new Error("compiled JS module is missing `main`/`$main`");
}

// Removes `run_main` trailer from `bend --to-js` output.
function bend_js_strip_run_main(js: string): string {
  var src = js.replace(/\r/g, "");
  var src = src.replace(/\s*$/s, "");

  var pats = [
    /\nconsole\.log\(\s*JSON\.stringify\(\s*main\(\)\s*\)\s*\)\s*;?\s*$/s,
    /\nconsole\.log\(\s*JSON\.stringify\(\s*\$main\(\)\s*\)\s*\)\s*;?\s*$/s,
    /\nconsole\.log\(\s*JSON\.stringify\(\s*null\s*\)\s*\)\s*;?\s*$/s,
    /\nrun_main\(\)\s*;?\s*$/s,
  ];

  for (var pat of pats) {
    var out = src.replace(pat, "\n");
    if (out !== src) {
      return out;
    }
  }

  var lns = src.split("\n");
  if (lns.length > 0) {
    var lst = lns[lns.length - 1].trim();
    if (
      lst.startsWith("console.log(") &&
      (
        lst.includes("JSON.stringify(main())") ||
        lst.includes("JSON.stringify($main())") ||
        lst.includes("JSON.stringify(null)")
      )
    ) {
      lns.pop();
      return lns.join("\n") + "\n";
    }
  }

  return src + "\n";
}

// Parses one BENCH_SECS line from helper output.
function secs_parse(out: string): number {
  var tag = SECS_TAG + " ";
  var lns = out.replace(/\r/g, "").split("\n");

  for (var i = lns.length - 1; i >= 0; --i) {
    var lin = lns[i].trim();
    if (!lin.startsWith(tag)) {
      continue;
    }

    var txt = lin.slice(tag.length).trim();
    var val = Number(txt);
    if (!Number.isFinite(val) || val < 0) {
      throw new Error("invalid " + SECS_TAG + " value: " + JSON.stringify(txt));
    }
    return val;
  }

  throw new Error("missing " + SECS_TAG + " in output");
}

// Builds source for the Node JS hot-run helper.
function js_node_runner_src(): string {
  return [
    "import * as url from \"node:url\";",
    "",
    "function now_ns() {",
    "  return process.hrtime.bigint();",
    "}",
    "",
    "function elapsed_secs(start) {",
    "  return Number(process.hrtime.bigint() - start) / 1e9;",
    "}",
    "",
    "function parse_num(txt, nam) {",
    "  var val = Number(txt);",
    "  if (!Number.isFinite(val) || val < 0) {",
    "    throw new Error(\"invalid numeric arg: \" + nam + \"=\" + JSON.stringify(txt));",
    "  }",
    "  return val;",
    "}",
    "",
    "function parse_nonneg_int(txt, nam) {",
    "  var val = Math.floor(parse_num(txt, nam));",
    "  if (val < 0) {",
    "    throw new Error(\"invalid non-negative int arg: \" + nam + \"=\" + JSON.stringify(txt));",
    "  }",
    "  return val;",
    "}",
    "",
    "function parse_pos_int(txt, nam) {",
    "  var val = Math.floor(parse_num(txt, nam));",
    "  if (val <= 0) {",
    "    throw new Error(\"invalid positive int arg: \" + nam + \"=\" + JSON.stringify(txt));",
    "  }",
    "  return val;",
    "}",
    "",
    "function sample_needs_more(cnt, sum, min_runs, max_runs, min_secs) {",
    "  if (cnt === 0) {",
    "    return true;",
    "  }",
    "  if (cnt >= max_runs) {",
    "    return false;",
    "  }",
    "  if (cnt < min_runs && sum < min_secs) {",
    "    return true;",
    "  }",
    "  return false;",
    "}",
    "",
    "function js_main_get(mod) {",
    "  var main = mod.$main;",
    "  if (typeof main === \"function\") {",
    "    return main;",
    "  }",
    "  var main = mod.main;",
    "  if (typeof main === \"function\") {",
    "    return main;",
    "  }",
    "  throw new Error(\"compiled JS module is missing `main`/`$main`\");",
    "}",
    "",
    "async function main() {",
    "  var args = process.argv.slice(2);",
    "  if (args.length !== 5) {",
    "    throw new Error(\"usage: node runner.mjs <mod> <warmup> <min_runs> <max_runs> <min_secs>\");",
    "  }",
    "",
    "  var mod_fil  = args[0];",
    "  var warmup   = parse_nonneg_int(args[1], \"warmup\");",
    "  var min_runs = parse_pos_int(args[2], \"min_runs\");",
    "  var max_runs = parse_pos_int(args[3], \"max_runs\");",
    "  var min_secs = parse_num(args[4], \"min_secs\");",
    "",
    "  var mod = await import(url.pathToFileURL(mod_fil).href + \"?v=\" + String(now_ns()));",
    "  var run = js_main_get(mod);",
    "",
    "  for (var i = 0; i < warmup; ++i) {",
    "    run();",
    "  }",
    "",
    "  var sum = 0;",
    "  var cnt = 0;",
    "  while (sample_needs_more(cnt, sum, min_runs, max_runs, min_secs)) {",
    "    var start = now_ns();",
    "    run();",
    "    var secs = elapsed_secs(start);",
    "    sum += secs;",
    "    cnt += 1;",
    "  }",
    "",
    "  if (cnt === 0) {",
    "    throw new Error(\"no timed runs were executed\");",
    "  }",
    "",
    "  console.log(\"" + SECS_TAG + " \" + String(sum / cnt));",
    "}",
    "",
    "main().catch(err => {",
    "  var msg = err instanceof Error ? err.message : String(err);",
    "  console.error(msg);",
    "  process.exit(1);",
    "});",
    "",
  ].join("\n");
}

var JS_NODE_RUNNER: string | null = null;

// Returns path to the shared Node JS hot-run helper.
function js_node_runner_path(): string {
  if (JS_NODE_RUNNER !== null) {
    return JS_NODE_RUNNER;
  }

  var file = tmp_path(["js", "node", "runner"], ".mjs");
  fs.writeFileSync(file, js_node_runner_src(), "utf8");
  JS_NODE_RUNNER = file;
  return file;
}

// Repo Discovery
// --------------

// Discovers benchmarks under `bench/*`.
function discover_rows(): Row[] {
  if (!fs.existsSync(CASE_DIR)) {
    return [];
  }

  var rows: Row[] = [];
  var entries = fs.readdirSync(CASE_DIR);
  entries.sort();

  for (var name of entries) {
    var dir = path.join(CASE_DIR, name);
    var st  = fs.statSync(dir);
    if (!st.isDirectory()) {
      continue;
    }

    var bend_file = path.join(dir, "main.bend");
    var hvm_file  = path.join(dir, "main.hvm");

    var has_bend = fs.existsSync(bend_file);
    var has_hvm  = fs.existsSync(hvm_file);
    if (!has_bend && !has_hvm) {
      continue;
    }

    rows.push({
      name,
      bend_file: has_bend ? bend_file : null,
      hvm_file: has_hvm ? hvm_file : null,
      cells: {},
    });
  }

  return rows;
}

// Caches
// ------

var BEND_JS_CACHE  = new Map<string, string>();
var BEND_HVM_CACHE = new Map<string, string>();
var HVM_BIN_CACHE  = new Map<string, string>();

// HVM Helpers
// -----------

// Returns extra HVM args for known benchmark families.
function hvm_extra_args(name: string): string[] {
  if (name.startsWith("gen_")) {
    return ["-C1"];
  }
  if (name.startsWith("collapse_")) {
    return ["-C"];
  }
  return [];
}

// Runs one `.hvm` file once via interpreted mode.
async function hvm_run_file_once(file: string, name: string, threads: number): Promise<void> {
  var args = [file, "-S", "-T" + String(threads)].concat(hvm_extra_args(name));
  await run_cmd(HVM_CMD, args, ROOT_DIR);
}

// Runs one compiled benchmark executable once.
async function hvm_run_bin_once(bin: string): Promise<void> {
  await run_cmd(bin, [], ROOT_DIR);
}

// Compiles one `.hvm` file to binary and caches output path.
async function hvm_compile_bin(file: string, name: string, flow: string, threads: number): Promise<string> {
  var key = [flow, String(threads), file, hvm_extra_args(name).join(" ")].join("|");
  var old = HVM_BIN_CACHE.get(key);
  if (old !== undefined) {
    return old;
  }

  var out = tmp_path([flow, String(threads), bench_tag(file)], ".bin");
  var args = [file, "-S", "-T" + String(threads)].concat(hvm_extra_args(name), ["-o", out]);
  await run_cmd(HVM_CMD, args, ROOT_DIR);

  HVM_BIN_CACHE.set(key, out);
  return out;
}

// Bend Helpers
// ------------

var BEND_ENTRY_CACHE = new Map<string, string>();
var BEND_NODE_BUNDLE_CACHE = new Map<string, string>();

// Returns node-entry override for one Bend command, if configured.
function bend_node_entry_override_get(bend_cmd: string): string | null {
  if (bend_cmd === BEND_CMD) {
    return BEND_NODE_ENTRY;
  }
  if (bend_cmd === NEW_BEND_CMD) {
    return NEW_BEND_NODE_ENTRY;
  }
  return null;
}

// Resolves script path behind one Bend command for node strip-types mode.
function bend_entry_get(bend_cmd: string): string {
  var old = BEND_ENTRY_CACHE.get(bend_cmd);
  if (old !== undefined) {
    return old;
  }

  var exe = resolve_cmd_path(bend_cmd);
  var ext = path.extname(exe).toLowerCase();
  if (ext !== ".ts" && ext !== ".js" && ext !== ".mjs" && ext !== ".cjs") {
    throw new Error("could not derive script entry from bend command: " + exe + " (set *_BEND_NODE_ENTRY)");
  }

  var entry = bend_node_entry_override_get(bend_cmd) ?? exe;
  BEND_ENTRY_CACHE.set(bend_cmd, entry);
  return entry;
}

// Builds (or returns) a Node-runnable bundled Bend CLI entry.
async function bend_node_bundle_get(bend_cmd: string): Promise<string> {
  var old = BEND_NODE_BUNDLE_CACHE.get(bend_cmd);
  if (old !== undefined) {
    return old;
  }

  var entry = bend_entry_get(bend_cmd);
  var out   = tmp_path(["bend", "node", "bundle", bend_cmd], ".mjs");
  await run_cmd(BUN_CMD, [
    "build",
    entry,
    "--target=node",
    "--format=esm",
    "--outfile",
    out,
  ], ROOT_DIR);

  BEND_NODE_BUNDLE_CACHE.set(bend_cmd, out);
  return out;
}

// Compiles one `.bend` file to `.hvm` through Bend CLI and caches output.
async function bend_compile_hvm(
  file: string,
  cli_flag: "--to-hvm" | "--to-chk",
  bend_cmd: string = BEND_CMD,
): Promise<string> {
  var key = bend_cmd + "|" + cli_flag + "|" + file;
  var old = BEND_HVM_CACHE.get(key);
  if (old !== undefined) {
    return old;
  }

  var out = await run_cmd(bend_cmd, [file, cli_flag], ROOT_DIR);
  var fil = tmp_path(["bend", cli_flag, bend_cmd, bench_tag(file)], ".hvm");
  fs.writeFileSync(fil, out, "utf8");

  BEND_HVM_CACHE.set(key, fil);
  return fil;
}

// Compiles one `.bend` file to JS library (main exported, no auto-run).
async function bend_compile_js_lib(file: string, bend_cmd: string = BEND_CMD): Promise<string> {
  var key = bend_cmd + "|" + file;
  var old = BEND_JS_CACHE.get(key);
  if (old !== undefined) {
    return old;
  }

  var js  = await run_cmd(bend_cmd, [file, "--to-js"], ROOT_DIR);
  var js  = bend_js_strip_run_main(js);
  var out = tmp_path(["bend", "js", bend_cmd, bench_tag(file)], ".mjs");
  fs.writeFileSync(out, js, "utf8");

  BEND_JS_CACHE.set(key, out);
  return out;
}

// Runs one Bend benchmark once via Bun runtime.
async function bend_run_once_bun(file: string, bend_cmd: string = BEND_CMD): Promise<void> {
  var entry = bend_entry_get(bend_cmd);
  await run_cmd(BUN_CMD, ["run", entry, file], ROOT_DIR);
}

// Runs one Bend benchmark once via Node strip-types runtime.
async function bend_run_once_node(file: string, bend_cmd: string = BEND_CMD): Promise<void> {
  var bundle = await bend_node_bundle_get(bend_cmd);
  await run_cmd(NODE_CMD, [bundle, file], ROOT_DIR);
}

// Modes
// -----

// Runs native Bend via Bun (compile once, hot-call main in-process).
async function mode_bend_bun(row: Row, cfg: SampleCfg, _threads: number, bend_cmd: string | null): Promise<number> {
  var file = row.bend_file;
  if (file === null) {
    throw new Error("internal: missing bend file");
  }
  if (bend_cmd === null) {
    throw new Error("internal: missing bend command");
  }

  var mod_file = await bend_compile_js_lib(file, bend_cmd);
  var mod      = await import(js_mod_url(mod_file));
  var run      = js_main_get(mod as Record<string, unknown>);
  return run_hot_sync(run, cfg);
}

// Runs native Bend via Node (compile once, hot-call main in one helper).
async function mode_bend_node(row: Row, cfg: SampleCfg, _threads: number, bend_cmd: string | null): Promise<number> {
  var file = row.bend_file;
  if (file === null) {
    throw new Error("internal: missing bend file");
  }
  if (bend_cmd === null) {
    throw new Error("internal: missing bend command");
  }

  var mod_file = await bend_compile_js_lib(file, bend_cmd);
  var runner   = js_node_runner_path();

  var out = await run_cmd(NODE_CMD, [
    runner,
    mod_file,
    String(cfg.warmup),
    String(cfg.min_runs),
    String(cfg.max_runs),
    String(cfg.min_secs),
  ], ROOT_DIR);
  return secs_parse(out);
}

// Runs native Bend via HVM interpreted.
async function mode_bend_hvmi(row: Row, cfg: SampleCfg, threads: number, bend_cmd: string | null): Promise<number> {
  var file = row.bend_file;
  if (file === null) {
    throw new Error("internal: missing bend file");
  }
  if (bend_cmd === null) {
    throw new Error("internal: missing bend command");
  }

  var hvm_file = await bend_compile_hvm(file, "--to-hvm", bend_cmd);
  return await run_sampled(() => hvm_run_file_once(hvm_file, row.name, threads), cfg);
}

// Runs native Bend via HVM compiled (compile time excluded).
async function mode_bend_hvmc(row: Row, cfg: SampleCfg, threads: number, bend_cmd: string | null): Promise<number> {
  var file = row.bend_file;
  if (file === null) {
    throw new Error("internal: missing bend file");
  }
  if (bend_cmd === null) {
    throw new Error("internal: missing bend command");
  }

  var hvm_file = await bend_compile_hvm(file, "--to-hvm", bend_cmd);
  var bin_file = await hvm_compile_bin(hvm_file, row.name, "bend-hvmc", threads);
  return await run_sampled(() => hvm_run_bin_once(bin_file), cfg);
}

// Runs interpreted Bend via Bun.
async function mode_bendi_bun(row: Row, cfg: SampleCfg, _threads: number, bend_cmd: string | null): Promise<number> {
  var file = row.bend_file;
  if (file === null) {
    throw new Error("internal: missing bend file");
  }
  if (bend_cmd === null) {
    throw new Error("internal: missing bend command");
  }

  return await run_sampled(() => bend_run_once_bun(file, bend_cmd), cfg);
}

// Runs interpreted Bend via Node.
async function mode_bendi_node(row: Row, cfg: SampleCfg, _threads: number, bend_cmd: string | null): Promise<number> {
  var file = row.bend_file;
  if (file === null) {
    throw new Error("internal: missing bend file");
  }
  if (bend_cmd === null) {
    throw new Error("internal: missing bend command");
  }

  return await run_sampled(() => bend_run_once_node(file, bend_cmd), cfg);
}

// Runs interpreted Bend via HVM interpreted.
async function mode_bendi_hvmi(row: Row, cfg: SampleCfg, threads: number, bend_cmd: string | null): Promise<number> {
  var file = row.bend_file;
  if (file === null) {
    throw new Error("internal: missing bend file");
  }
  if (bend_cmd === null) {
    throw new Error("internal: missing bend command");
  }

  var hvm_file = await bend_compile_hvm(file, "--to-chk", bend_cmd);
  return await run_sampled(() => hvm_run_file_once(hvm_file, row.name, threads), cfg);
}

// Runs interpreted Bend via HVM compiled (compile time excluded).
async function mode_bendi_hvmc(row: Row, cfg: SampleCfg, threads: number, bend_cmd: string | null): Promise<number> {
  var file = row.bend_file;
  if (file === null) {
    throw new Error("internal: missing bend file");
  }
  if (bend_cmd === null) {
    throw new Error("internal: missing bend command");
  }

  var hvm_file = await bend_compile_hvm(file, "--to-chk", bend_cmd);
  var bin_file = await hvm_compile_bin(hvm_file, row.name, "bendi-hvmc", threads);
  return await run_sampled(() => hvm_run_bin_once(bin_file), cfg);
}

// Runs HVM benchmark via interpreted mode.
async function mode_hvmi(row: Row, cfg: SampleCfg, threads: number, _bend_cmd: string | null): Promise<number> {
  var file = row.hvm_file;
  if (file === null) {
    throw new Error("internal: missing hvm file");
  }

  return await run_sampled(() => hvm_run_file_once(file, row.name, threads), cfg);
}

// Runs HVM benchmark via compiled mode (compile time excluded).
async function mode_hvmc(row: Row, cfg: SampleCfg, threads: number, _bend_cmd: string | null): Promise<number> {
  var file = row.hvm_file;
  if (file === null) {
    throw new Error("internal: missing hvm file");
  }

  var bin_file = await hvm_compile_bin(file, row.name, "hvmc", threads);
  return await run_sampled(() => hvm_run_bin_once(bin_file), cfg);
}

var MODE_DEFS: ModeDef[] = [
  { flag: "--bend-via-bunjs",                       label: "bend-bun",      input: "bend", bend_cmd_src: "bend",    needs_bend: true,  needs_hvm: false, needs_bun: true,  needs_node: false, needs_node_ts: false, hvm_threads: false, run: mode_bend_bun  },
  { flag: "--bend-via-nodejs",                      label: "bend-node",     input: "bend", bend_cmd_src: "bend",    needs_bend: true,  needs_hvm: false, needs_bun: false, needs_node: true,  needs_node_ts: false, hvm_threads: false, run: mode_bend_node },
  { flag: "--bend-via-hvm-interpreted",             label: "bend-hvmi",     input: "bend", bend_cmd_src: "bend",    needs_bend: true,  needs_hvm: true,  needs_bun: false, needs_node: false, needs_node_ts: false, hvm_threads: true,  run: mode_bend_hvmi },
  { flag: "--bend-via-hvm-compiled",                label: "bend-hvmc",     input: "bend", bend_cmd_src: "bend",    needs_bend: true,  needs_hvm: true,  needs_bun: false, needs_node: false, needs_node_ts: false, hvm_threads: true,  run: mode_bend_hvmc },
  { flag: "--bend-interpreted-via-bunjs",           label: "bendi-bun",     input: "bend", bend_cmd_src: "bend",    needs_bend: true,  needs_hvm: false, needs_bun: true,  needs_node: false, needs_node_ts: false, hvm_threads: false, run: mode_bendi_bun },
  { flag: "--bend-interpreted-via-nodejs",          label: "bendi-node",    input: "bend", bend_cmd_src: "bend",    needs_bend: true,  needs_hvm: false, needs_bun: true,  needs_node: true,  needs_node_ts: true,  hvm_threads: false, run: mode_bendi_node },
  { flag: "--bend-interpreted-via-hvm-interpreted", label: "bendi-hvmi",    input: "bend", bend_cmd_src: "bend",    needs_bend: true,  needs_hvm: true,  needs_bun: false, needs_node: false, needs_node_ts: false, hvm_threads: true,  run: mode_bendi_hvmi },
  { flag: "--bend-interpreted-via-hvm-compiled",    label: "bendi-hvmc",    input: "bend", bend_cmd_src: "bend",    needs_bend: true,  needs_hvm: true,  needs_bun: false, needs_node: false, needs_node_ts: false, hvm_threads: true,  run: mode_bendi_hvmc },

  { flag: "--newbend-via-bunjs",                    label: "newbend-bun",   input: "bend", bend_cmd_src: "newbend", needs_bend: true,  needs_hvm: false, needs_bun: true,  needs_node: false, needs_node_ts: false, hvm_threads: false, run: mode_bend_bun  },
  { flag: "--newbend-via-nodejs",                   label: "newbend-node",  input: "bend", bend_cmd_src: "newbend", needs_bend: true,  needs_hvm: false, needs_bun: false, needs_node: true,  needs_node_ts: false, hvm_threads: false, run: mode_bend_node },
  { flag: "--newbend-via-hvm-interpreted",          label: "newbend-hvmi",  input: "bend", bend_cmd_src: "newbend", needs_bend: true,  needs_hvm: true,  needs_bun: false, needs_node: false, needs_node_ts: false, hvm_threads: true,  run: mode_bend_hvmi },
  { flag: "--newbend-via-hvm-compiled",             label: "newbend-hvmc",  input: "bend", bend_cmd_src: "newbend", needs_bend: true,  needs_hvm: true,  needs_bun: false, needs_node: false, needs_node_ts: false, hvm_threads: true,  run: mode_bend_hvmc },
  { flag: "--newbend-interpreted-via-bunjs",        label: "newbendi-bun",  input: "bend", bend_cmd_src: "newbend", needs_bend: true,  needs_hvm: false, needs_bun: true,  needs_node: false, needs_node_ts: false, hvm_threads: false, run: mode_bendi_bun },
  { flag: "--newbend-interpreted-via-nodejs",       label: "newbendi-node", input: "bend", bend_cmd_src: "newbend", needs_bend: true,  needs_hvm: false, needs_bun: true,  needs_node: true,  needs_node_ts: true,  hvm_threads: false, run: mode_bendi_node },
  { flag: "--newbend-interpreted-via-hvm-interpreted", label: "newbendi-hvmi", input: "bend", bend_cmd_src: "newbend", needs_bend: true,  needs_hvm: true,  needs_bun: false, needs_node: false, needs_node_ts: false, hvm_threads: true,  run: mode_bendi_hvmi },
  { flag: "--newbend-interpreted-via-hvm-compiled", label: "newbendi-hvmc", input: "bend", bend_cmd_src: "newbend", needs_bend: true,  needs_hvm: true,  needs_bun: false, needs_node: false, needs_node_ts: false, hvm_threads: true,  run: mode_bendi_hvmc },

  { flag: "--hvm-interpreted",                      label: "hvmi",          input: "hvm",  bend_cmd_src: "none",    needs_bend: false, needs_hvm: true,  needs_bun: false, needs_node: false, needs_node_ts: false, hvm_threads: true,  run: mode_hvmi      },
  { flag: "--hvm-compiled",                         label: "hvmc",          input: "hvm",  bend_cmd_src: "none",    needs_bend: false, needs_hvm: true,  needs_bun: false, needs_node: false, needs_node_ts: false, hvm_threads: true,  run: mode_hvmc      },
];

// Table
// -----

// Fits text to one fixed width.
function fit(txt: string, wid: number): string {
  if (txt.length <= wid) {
    return txt;
  }
  if (wid <= 3) {
    return txt.slice(0, wid);
  }
  return txt.slice(0, wid - 3) + "...";
}

// Left-pads text.
function pad_left(txt: string, wid: number): string {
  if (txt.length >= wid) {
    return txt;
  }
  return " ".repeat(wid - txt.length) + txt;
}

// Right-pads text.
function pad_right(txt: string, wid: number): string {
  if (txt.length >= wid) {
    return txt;
  }
  return txt + " ".repeat(wid - txt.length);
}

// Center-pads text.
function pad_center(txt: string, wid: number): string {
  if (txt.length >= wid) {
    return txt;
  }
  var rem = wid - txt.length;
  var lft = Math.floor(rem / 2);
  return " ".repeat(lft) + txt + " ".repeat(rem - lft);
}

// Draws one horizontal divider line.
function hline(widths: number[]): string {
  var out = "+";
  for (var w of widths) {
    out += "-".repeat(w + 2) + "+";
  }
  return out;
}

// Draws one table row.
function tline(cells: string[], widths: number[], aligns: ("L" | "R" | "C")[]): string {
  var out = "|";
  for (var i = 0; i < cells.length; ++i) {
    var txt = fit(cells[i], widths[i]);
    if (aligns[i] === "L") {
      var txt = pad_right(txt, widths[i]);
    } else if (aligns[i] === "R") {
      var txt = pad_left(txt, widths[i]);
    } else {
      var txt = pad_center(txt, widths[i]);
    }
    out += " " + txt + " |";
  }
  return out;
}

// Formats seconds for display.
function fmt_secs(secs: number, wid: number): string {
  if (!Number.isFinite(secs) || secs < 0) {
    return fit("NaN", wid);
  }
  if (secs >= 1000) {
    return fit(">999.000s", wid);
  }

  for (var d = 6; d >= 3; --d) {
    var txt = secs.toFixed(d) + "s";
    if (txt.length <= wid) {
      return txt;
    }
  }

  return fit(secs.toFixed(3) + "s", wid);
}

// Formats one cell for display.
function fmt_cell(cell: Cell, wid: number): string {
  switch (cell.state) {
    case "pending": {
      return pad_right("-", wid);
    }
    case "running": {
      return pad_right("...", wid);
    }
    case "done": {
      return pad_left(fmt_secs(cell.secs ?? 0, wid), wid);
    }
    case "error": {
      return pad_left("ERROR", wid);
    }
    case "timeout": {
      return pad_left("TIMEOUT", wid);
    }
    case "na": {
      return pad_left("N/A", wid);
    }
  }
}

// Computes per-mode column widths.
function mode_widths(modes: Mode[]): number[] {
  var out: number[] = [];
  for (var mode of modes) {
    out.push(Math.max(MODE_MIN_WID, mode.label.length));
  }
  return out;
}

// Renders the full table.
function render(rows: Row[], modes: Mode[], name_wid: number): string {
  var m_wid  = mode_widths(modes);
  var widths = [name_wid].concat(m_wid);

  var out: string[] = [];
  out.push(hline(widths));

  var hdr = ["benchmark"].concat(modes.map(m => m.label));
  var hal: ("L" | "R" | "C")[] = ["L"].concat(modes.map(() => "C"));
  out.push(tline(hdr, widths, hal));
  out.push(hline(widths));

  for (var row of rows) {
    var dat = [row.name];
    for (var mode of modes) {
      dat.push(fmt_cell(row.cells[mode.flag], Math.max(MODE_MIN_WID, mode.label.length)));
    }
    var dal: ("L" | "R" | "C")[] = ["L"].concat(modes.map(() => "R"));
    out.push(tline(dat, widths, dal));
  }

  out.push(hline(widths));
  return out.join("\n");
}

// Redraws table in terminal.
function redraw(rows: Row[], modes: Mode[], name_wid: number): void {
  var tab = render(rows, modes, name_wid);
  if (process.stdout.isTTY) {
    process.stdout.write(CLEAR + tab + "\n");
  } else {
    process.stdout.write(tab + "\n\n");
  }
}

// Setup
// -----

// Ensures command dependencies for selected modes.
function ensure_mode_deps(modes: Mode[]): void {
  var need_hvm     = modes.some(m => m.needs_hvm);
  var need_bun     = modes.some(m => m.needs_bun);
  var need_node    = modes.some(m => m.needs_node);
  var bend_cmds = new Set<string>();
  for (var mode of modes) {
    if (mode.bend_cmd === null) {
      continue;
    }
    bend_cmds.add(mode.bend_cmd);
  }
  for (var bend_cmd of bend_cmds) {
    resolve_cmd_path(bend_cmd);
  }
  if (need_hvm) {
    resolve_cmd_path(HVM_CMD);
  }
  if (need_bun) {
    resolve_cmd_path(BUN_CMD);
  }
  if (need_node) {
    resolve_cmd_path(NODE_CMD);
  }
  for (var mode of modes) {
    if (!mode.needs_node_ts) {
      continue;
    }
    var bend_cmd = mode.bend_cmd;
    if (bend_cmd === null) {
      continue;
    }
    bend_entry_get(bend_cmd);
  }
}

// Runner
// ------

// Runs all selected benchmarks/modes and fills table cells.
async function bench_all(modes: Mode[], cfg: SampleCfg): Promise<number> {
  var rows = discover_rows();
  if (rows.length === 0) {
    console.error("error: no benchmark cases found under " + CASE_DIR);
    return 1;
  }

  for (var row of rows) {
    for (var mode of modes) {
      var state: CellState = "pending";
      if (mode.input === "bend" && row.bend_file === null) {
        state = "na";
      }
      if (mode.input === "hvm" && row.hvm_file === null) {
        state = "na";
      }
      row.cells[mode.flag] = cell_new(state);
    }
  }

  var had_error = false;
  var name_wid = Math.min(
    NAME_MAX_WID,
    Math.max("benchmark".length, ...rows.map(r => r.name.length)),
  );

  redraw(rows, modes, name_wid);
  for (var row of rows) {
    for (var mode of modes) {
      var cell = row.cells[mode.flag];
      if (cell.state === "na") {
        continue;
      }

      cell.state = "running";
      cell.err   = null;
      redraw(rows, modes, name_wid);

      try {
        var secs = await mode.run(row, cfg);
        cell.state = "done";
        cell.secs  = secs;
      } catch (err) {
        var msg = err instanceof Error ? err.message : String(err);
        cell.state = err_is_timeout(msg) ? "timeout" : "error";
        cell.err   = msg;
        had_error = true;
      }

      redraw(rows, modes, name_wid);
    }
  }

  if (had_error) {
    return 1;
  }

  return 0;
}

// CLI
// ---

// Escapes regex metacharacters.
function re_esc(txt: string): string {
  return txt.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

// Builds display label for one mode/thread tuple.
function mode_label(def: ModeDef, threads: number): string {
  if (!def.hvm_threads || threads === 1) {
    return def.label;
  }
  return def.label + String(threads);
}

// Builds unique cell key for one mode/thread tuple.
function mode_flag(def: ModeDef, threads: number): string {
  if (!def.hvm_threads || threads === 1) {
    return def.flag;
  }
  return def.flag + "-T" + String(threads);
}

// Returns Bend command for one mode definition.
function mode_bend_cmd(def: ModeDef): string | null {
  switch (def.bend_cmd_src) {
    case "none": {
      return null;
    }
    case "bend": {
      return BEND_CMD;
    }
    case "newbend": {
      return NEW_BEND_CMD;
    }
  }
}

// Instantiates one selected mode.
function mode_make(def: ModeDef, threads: number): Mode {
  var bend_cmd = mode_bend_cmd(def);
  return {
    key:           def.label + "@" + String(threads),
    flag:          mode_flag(def, threads),
    label:         mode_label(def, threads),
    input:         def.input,
    bend_cmd,
    needs_bend:    def.needs_bend,
    needs_hvm:     def.needs_hvm,
    needs_bun:     def.needs_bun,
    needs_node:    def.needs_node,
    needs_node_ts: def.needs_node_ts,
    run:           (row, cfg) => def.run(row, cfg, threads, bend_cmd),
  };
}

// Parses one mode token into one selected mode.
function mode_parse(arg: string): Mode | null {
  for (var def of MODE_DEFS) {
    if (def.hvm_threads) {
      var f_re = "^" + re_esc(def.flag) + "(?:-T([1-9][0-9]*))?$";
      var f_mt = arg.match(new RegExp(f_re));
      if (f_mt !== null) {
        var thr = f_mt[1] === undefined ? 1 : Number(f_mt[1]);
        return mode_make(def, thr);
      }

      var l_re = "^" + re_esc(def.label) + "([1-9][0-9]*)?$";
      var l_mt = arg.match(new RegExp(l_re));
      if (l_mt !== null) {
        var thr = l_mt[1] === undefined ? 1 : Number(l_mt[1]);
        return mode_make(def, thr);
      }
    } else {
      if (arg === def.flag || arg === def.label) {
        return mode_make(def, 1);
      }
    }
  }

  return null;
}

// Parses one positive timeout argument in seconds.
function timeout_parse_ms(txt: string): number {
  var secs = Number(txt);
  if (!Number.isFinite(secs) || secs <= 0) {
    throw new Error("invalid --timeout value (seconds > 0): " + JSON.stringify(txt));
  }

  var ms = Math.floor(secs * 1000);
  if (ms <= 0) {
    throw new Error("invalid --timeout value (too small): " + JSON.stringify(txt));
  }
  return ms;
}

// Parses CLI options and returns remaining mode tokens.
function parse_cli(args: string[]): CliCfg {
  var cfg: CliCfg = {
    show_help:   false,
    timeout_ms:  CMD_TIMEOUT_MS,
    mode_tokens: [],
  };

  for (var i = 0; i < args.length; ++i) {
    var arg = args[i];

    if (arg === "-h" || arg === "--help") {
      cfg.show_help = true;
      continue;
    }

    if (arg === "--timeout") {
      if (i + 1 >= args.length) {
        throw new Error("missing value for --timeout");
      }
      var val = args[i + 1];
      cfg.timeout_ms = timeout_parse_ms(val);
      i += 1;
      continue;
    }

    if (arg.startsWith("--timeout=")) {
      var val = arg.slice("--timeout=".length);
      cfg.timeout_ms = timeout_parse_ms(val);
      continue;
    }

    cfg.mode_tokens.push(arg);
  }

  return cfg;
}

// Prints usage.
function usage(): void {
  var flags = MODE_DEFS.map(def => {
    if (def.hvm_threads) {
      return def.flag + "[-TN]";
    }
    return def.flag;
  });
  var flg_wid = Math.max(...flags.map(f => f.length)) + 2;

  var lines = MODE_DEFS.map(def => {
    var flag = def.hvm_threads ? def.flag + "[-TN]" : def.flag;
    var nam  = def.hvm_threads ? def.label + "[N]" : def.label;
    var lhs  = pad_right(flag, flg_wid);
    return "  " + lhs + nam;
  });

  process.stdout.write([
    "usage: bench.ts [--timeout SECS] <mode> [mode ...]",
    "",
    "options:",
    "  --timeout SECS  max seconds per spawned command (default: 1200)",
    "",
    "modes:",
    ...lines,
    "",
    "name aliases:",
    "  you can also pass labels directly (example: hvmi hvmi4 hvmc8 bend-bun)",
    "",
    "env overrides:",
    "  BEND_CMD, NEW_BEND_CMD, HVM_CMD, BUN_CMD, NODE_CMD",
    "  BEND_NODE_ENTRY, NEW_BEND_NODE_ENTRY",
    "  BENCH_WARMUP, BENCH_MIN_RUNS, BENCH_MAX_RUNS, BENCH_MIN_SECS",
    "",
  ].join("\n"));
}

// Parses selected modes from CLI args.
function parse_modes(args: string[]): Mode[] {
  if (args.length === 0) {
    return [];
  }

  var out: Mode[] = [];
  var seen = new Set<string>();
  for (var arg of args) {
    if (arg === "-h" || arg === "--help") {
      return [];
    }

    var mode = mode_parse(arg);
    if (mode === null) {
      throw new Error("unknown mode: " + arg);
    }

    if (seen.has(mode.key)) {
      continue;
    }
    seen.add(mode.key);
    out.push(mode);
  }

  return out;
}

// Main
// ----

// Runs benchmark CLI.
async function main(): Promise<number> {
  var args = process.argv.slice(2);
  if (args.length === 0) {
    usage();
    return 1;
  }

  var cli = parse_cli(args);
  if (cli.show_help) {
    usage();
    return 0;
  }

  CMD_TIMEOUT_MS = cli.timeout_ms;

  var modes = parse_modes(cli.mode_tokens);
  if (modes.length === 0) {
    usage();
    return 1;
  }

  var cfg = sample_cfg_get();
  process.stdout.write("timeout: " + (CMD_TIMEOUT_MS / 1000).toFixed(3) + "s\n");
  process.stdout.write(sample_cfg_show(cfg) + "\n");

  ensure_mode_deps(modes);
  return await bench_all(modes, cfg);
}

main().then(code => {
  process.exit(code);
}).catch(err => {
  var msg = err instanceof Error ? err.message : String(err);
  console.error("error: " + msg);
  process.exit(1);
});
