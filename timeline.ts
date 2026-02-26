#!/usr/bin/env bun
// timeline.ts
// ===========
// Benchmarks bend-node across git commits and generates a timeline chart.
// Caches results in .timeline/cache.json to avoid re-running benchmarks.
// Output: .timeline/index.html (opens in browser).
//
// Usage:
//   ./timeline.ts <repo> [--since DATE] [--last N]
//
// Example:
//   ./timeline.ts ~/t/dev/bend2-ai-worker-aot --since 2026-02-25

import { spawnSync } from "node:child_process";
import * as fs   from "node:fs";
import * as os   from "node:os";
import * as path from "node:path";

// Config
// ------

var SELF_DIR    = import.meta.dir;
var BENCH_DIR   = path.join(SELF_DIR, "bench");
var OUT_DIR     = path.join(SELF_DIR, ".timeline");
var OUT_HTML    = path.join(OUT_DIR, "index.html");
var CACHE_FILE  = path.join(OUT_DIR, "cache.json");
var TMP         = fs.mkdtempSync(path.join(os.tmpdir(), "timeline-"));

var WARMUP   = 0;
var MIN_RUNS = 3;
var MAX_RUNS = 10;
var MIN_SECS = 0.5;
var TIMEOUT  = 60_000;

// Types
// -----

type Commit = { hash: string; msg: string };

// cache[commit_hash][bench_name] = secs | null
type Cache = Record<string, Record<string, number | null>>;

// Helpers
// -------

// Runs a command synchronously and returns stdout
function run(cmd: string, args: string[], cwd: string, timeout?: number): string {
  var res = spawnSync(cmd, args, {
    cwd,
    timeout:   timeout || 120_000,
    maxBuffer: 64 * 1024 * 1024,
    encoding:  "utf8",
  });
  if (res.status !== 0) {
    var err = (res.stderr || "").slice(0, 500).trim();
    throw new Error(`${cmd} failed: ${err}`);
  }
  return res.stdout;
}

// Commits
// -------

// Parses CLI args, returns repo path and commit list
function parse_args(args: string[]): { repo: string; commits: Commit[] } {
  if (args.length === 0) {
    console.log("usage: ./timeline.ts <repo> [--since DATE] [--last N]");
    process.exit(1);
  }

  var repo     = path.resolve(args[0]);
  var git_args = ["log", "--format=%H %s", "--reverse"];

  for (var i = 1; i < args.length; i++) {
    switch (args[i]) {
      case "--since": {
        git_args.push("--since=" + args[++i]);
        break;
      }
      case "--last": {
        git_args = ["log", "--format=%H %s", "--reverse", "-n", args[++i]];
        break;
      }
    }
  }

  var out     = run("git", git_args, repo);
  var commits = out.trim().split("\n").filter(Boolean).map(line => {
    var idx = line.indexOf(" ");
    return { hash: line.slice(0, idx), msg: line.slice(idx + 1) };
  });

  return { repo, commits };
}

// Benchmarks
// ----------

// Lists benchmark cases that have .bend source files
function get_benchmarks(): string[] {
  return fs.readdirSync(BENCH_DIR)
    .filter(d => fs.existsSync(path.join(BENCH_DIR, d, "main.bend")))
    .sort();
}

// Strips the run_main trailer from compiled JS output
function strip_run_main(js: string): string {
  var src = js.replace(/\r/g, "").replace(/\s*$/s, "");
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
  return src;
}

// Node Runner
// -----------

// Builds the node hot-run helper script (written once to TMP)
var RUNNER: string | null = null;
function runner_path(): string {
  if (RUNNER) {
    return RUNNER;
  }
  var src = [
    'import * as url from "node:url";',
    "function now_ns() { return process.hrtime.bigint(); }",
    "function elapsed(s) { return Number(process.hrtime.bigint() - s) / 1e9; }",
    "function get_main(mod) {",
    '  if (typeof mod.$main === "function") return mod.$main;',
    '  if (typeof mod.main  === "function") return mod.main;',
    '  throw new Error("missing main/$main");',
    "}",
    "async function main() {",
    "  var [fil, w, lo, hi, ms] = process.argv.slice(2);",
    "  var warmup   = Number(w);",
    "  var min_runs = Number(lo);",
    "  var max_runs = Number(hi);",
    "  var min_secs = Number(ms);",
    '  var mod = await import(url.pathToFileURL(fil).href + "?v=" + String(now_ns()));',
    "  var run = get_main(mod);",
    "  for (var i = 0; i < warmup; ++i) run();",
    "  var sum = 0, cnt = 0;",
    "  while (cnt === 0 || (cnt < max_runs && (cnt < min_runs || sum < min_secs))) {",
    "    var s = now_ns();",
    "    run();",
    "    sum += elapsed(s);",
    "    cnt += 1;",
    "  }",
    '  console.log("BENCH_SECS " + String(sum / cnt));',
    "}",
    "main().catch(e => { console.error(e.message); process.exit(1); });",
  ].join("\n");
  RUNNER = path.join(TMP, "runner.mjs");
  fs.writeFileSync(RUNNER, src);
  return RUNNER;
}

// Tests whether a CLI.ts supports --to-js by compiling the smallest benchmark
function supports_to_js(cli: string, benchmarks: string[]): boolean {
  var test_file = path.join(BENCH_DIR, benchmarks[0], "main.bend");
  var res = spawnSync("bun", ["run", cli, test_file, "--to-js"], {
    cwd:       SELF_DIR,
    timeout:   15_000,
    maxBuffer: 64 * 1024 * 1024,
    encoding:  "utf8",
  });
  return res.status === 0 && res.stdout.length > 0;
}

// Compiles and benchmarks one case using a given CLI.ts path
function bench_one(cli: string, bend_file: string): number {
  // Compile .bend to JS
  var js  = run("bun", ["run", cli, bend_file, "--to-js"], SELF_DIR, TIMEOUT);
  var js  = strip_run_main(js);
  var tmp = path.join(TMP, "m_" + Math.random().toString(36).slice(2) + ".mjs");
  fs.writeFileSync(tmp, js);

  // Run via node with sampling
  var out = run("node", [
    runner_path(), tmp,
    String(WARMUP), String(MIN_RUNS),
    String(MAX_RUNS), String(MIN_SECS),
  ], SELF_DIR, TIMEOUT);

  try { fs.unlinkSync(tmp); } catch {}

  // Parse BENCH_SECS
  var m = out.match(/BENCH_SECS\s+([\d.eE+-]+)/);
  if (!m) {
    throw new Error("no BENCH_SECS in output");
  }
  return parseFloat(m[1]);
}

// Cache
// -----

// Loads cached results from disk
function cache_load(): Cache {
  try {
    return JSON.parse(fs.readFileSync(CACHE_FILE, "utf8"));
  } catch {
    return {};
  }
}

// Saves cached results to disk
function cache_save(cache: Cache): void {
  fs.mkdirSync(OUT_DIR, { recursive: true });
  fs.writeFileSync(CACHE_FILE, JSON.stringify(cache, null, 2));
}

// Checks if a commit has a cached result for a benchmark
function cache_has(cache: Cache, hash: string, bench: string): boolean {
  return cache[hash] !== undefined && bench in cache[hash];
}

// Chart
// -----

// Generates a distinct HSL color for line index i out of n total
function hsl(i: number, n: number): string {
  var hue = Math.floor((i * 360) / n);
  return `hsl(${hue}, 70%, 55%)`;
}

// Generates the self-contained HTML chart page
function gen_html(commits: Commit[], benchmarks: string[], cache: Cache): string {
  // Drop commits where every benchmark is null (no --to-js support)
  var visible = commits.filter(c => {
    return benchmarks.some(b => cache[c.hash]?.[b] != null);
  });

  // Filter to benchmarks that have at least one valid data point
  var active = benchmarks.filter(b => {
    return visible.some(c => cache[c.hash]?.[b] != null);
  });

  // Build Chart.js datasets
  var datasets = active.map((b, i) => ({
    label:           b,
    data:            visible.map(c => cache[c.hash]?.[b] ?? null),
    borderColor:     hsl(i, active.length),
    backgroundColor: "transparent",
    borderWidth:     2,
    pointRadius:     2,
    spanGaps:        true,
    tension:         0.15,
  }));

  var labels = visible.map(c => c.hash.slice(0, 7));
  var msgs   = visible.map(c => c.msg);

  return `<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Bend-Node Timeline</title>
  <script src="https://cdn.jsdelivr.net/npm/chart.js@4"></script>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { background: #0d1117; display: flex; height: 100vh; overflow: hidden; }
    #scroll { flex: 1; overflow-x: auto; overflow-y: hidden; cursor: grab; }
    #scroll.dragging { cursor: grabbing; }
    #inner { height: 100%; }
    #legend {
      width: 170px; padding: 32px 8px 8px; overflow-y: auto;
      font: 11px monospace; color: #8b949e; flex-shrink: 0;
    }
    .li {
      display: flex; align-items: center; gap: 6px;
      padding: 3px 5px; cursor: pointer; border-radius: 3px;
      white-space: nowrap;
    }
    .li:hover { background: rgba(255,255,255,0.05); }
    .li.hl { background: rgba(255,255,255,0.12); color: #e6edf3; }
    .li.off { opacity: 0.3; text-decoration: line-through; }
    .box { width: 12px; height: 12px; border-radius: 2px; flex-shrink: 0; }
  </style>
</head>
<body>
  <div id="scroll"><div id="inner"><canvas id="c"></canvas></div></div>
  <div id="legend"></div>
  <script>
    var MSGS     = ${JSON.stringify(msgs)};
    var DATA     = { labels: ${JSON.stringify(labels)}, datasets: ${JSON.stringify(datasets)} };
    var scrollEl = document.getElementById("scroll");
    var innerEl  = document.getElementById("inner");
    var legendEl = document.getElementById("legend");
    var nPoints  = DATA.labels.length;
    var pxPer    = 50;

    // Pre-compute original and dimmed colors
    DATA.datasets.forEach(function(ds) {
      ds._origColor = ds.borderColor;
      ds._dimColor  = ds.borderColor.replace("70%", "30%").replace("55%", "35%");
    });

    // Resize chart width based on zoom level
    function resizeChart() {
      var w = Math.max(nPoints * pxPer, scrollEl.clientWidth);
      innerEl.style.width = w + "px";
      chart.resize();
    }

    // Highlight: bold one line, dim all others, highlight legend entry
    var hlIdx = -1;
    function setHighlight(idx) {
      if (hlIdx === idx) return;
      hlIdx = idx;
      chart.data.datasets.forEach(function(ds, i) {
        if (idx < 0) {
          ds.borderWidth = 2;
          ds.borderColor = ds._origColor;
        } else if (i === idx) {
          ds.borderWidth = 3;
          ds.borderColor = ds._origColor;
        } else {
          ds.borderWidth = 1;
          ds.borderColor = ds._dimColor;
        }
      });
      chart.update("none");
      document.querySelectorAll(".li").forEach(function(el, i) {
        el.classList.toggle("hl", i === idx);
      });
    }

    // Build legend
    DATA.datasets.forEach(function(ds, i) {
      var el = document.createElement("div");
      el.className = "li";
      el.innerHTML = '<div class="box" style="background:' + ds._origColor + '"></div>' + ds.label;
      el.addEventListener("click", function() {
        var meta = chart.getDatasetMeta(i);
        meta.hidden = !meta.hidden;
        el.classList.toggle("off");
        chart.update();
      });
      el.addEventListener("mouseenter", function() { setHighlight(i); });
      el.addEventListener("mouseleave", function() { setHighlight(-1); });
      legendEl.appendChild(el);
    });

    // Drag-to-scroll
    var dragging = false;
    var dragX    = 0;
    var dragSL   = 0;
    scrollEl.addEventListener("mousedown", function(e) {
      dragging = true;
      dragX    = e.clientX;
      dragSL   = scrollEl.scrollLeft;
      scrollEl.classList.add("dragging");
    });
    window.addEventListener("mousemove", function(e) {
      if (!dragging) return;
      scrollEl.scrollLeft = dragSL - (e.clientX - dragX);
    });
    window.addEventListener("mouseup", function() {
      dragging = false;
      scrollEl.classList.remove("dragging");
    });

    // Ctrl/Cmd+wheel to zoom, plain wheel to scroll
    scrollEl.addEventListener("wheel", function(e) {
      if (e.ctrlKey || e.metaKey) {
        e.preventDefault();
        var oldW  = innerEl.clientWidth;
        var frac  = (scrollEl.scrollLeft + e.offsetX) / oldW;
        pxPer     = Math.max(10, Math.min(200, pxPer + (e.deltaY > 0 ? -5 : 5)));
        resizeChart();
        var newW  = innerEl.clientWidth;
        scrollEl.scrollLeft = frac * newW - e.offsetX;
      }
    }, { passive: false });

    // Create chart (no built-in legend, no tooltip, no zoom plugin)
    var chart = new Chart(document.getElementById("c"), {
      type: "line",
      data: DATA,
      options: {
        responsive: true,
        maintainAspectRatio: false,
        animation: false,
        interaction: { mode: "nearest", intersect: false },
        onHover: function(evt, elms) {
          if (dragging) return;
          setHighlight(elms.length > 0 ? elms[0].datasetIndex : -1);
        },
        plugins: {
          title: {
            display: true,
            text: "Bend-Node Benchmark Timeline",
            color: "#e6edf3",
            font: { size: 16, family: "monospace" },
          },
          legend:  { display: false },
          tooltip: { enabled: false },
        },
        scales: {
          x: {
            ticks: { color: "#484f58", font: { family: "monospace", size: 9 }, maxRotation: 90 },
            grid:  { color: "#21262d" },
          },
          y: {
            max: 0.4, min: 0,
            ticks: { color: "#484f58", font: { family: "monospace" } },
            grid:  { color: "#21262d" },
            title: { display: true, text: "seconds", color: "#484f58", font: { family: "monospace" } },
          },
        },
      },
    });

    resizeChart();
  </script>
</body>
</html>`;
}

// Main
// ----

// Runs benchmarks across commits and generates the timeline chart
function main(): void {
  var { repo, commits } = parse_args(process.argv.slice(2));
  var benchmarks        = get_benchmarks();
  var cache             = cache_load();

  console.log(`repo: ${repo}`);
  console.log(`${commits.length} commits, ${benchmarks.length} benchmarks\n`);

  // Create a temporary worktree for checking out commits
  var wt = path.join(TMP, "wt");
  run("git", ["-C", repo, "worktree", "add", "--detach", wt, "HEAD"], repo);

  try {
    for (var ci = 0; ci < commits.length; ci++) {
      var hash  = commits[ci].hash;
      var short = hash.slice(0, 7);
      var msg   = commits[ci].msg;

      // Check if every benchmark is already cached for this commit
      var all_cached = benchmarks.every(b => cache_has(cache, hash, b));
      if (all_cached) {
        console.log(`[${ci + 1}/${commits.length}] ${short} ${msg} (cached)`);
        continue;
      }

      console.log(`[${ci + 1}/${commits.length}] ${short} ${msg}`);

      // Checkout this commit in the worktree
      spawnSync("git", ["-C", wt, "checkout", "--detach", "--quiet", hash]);

      // Skip commits without CLI.ts or --to-js support
      var cli = path.join(wt, "src", "ts", "CLI.ts");
      if (!fs.existsSync(cli) || !supports_to_js(cli, benchmarks)) {
        console.log("  (skip)");
        if (!cache[hash]) cache[hash] = {};
        for (var b of benchmarks) {
          cache[hash][b] = null;
        }
        cache_save(cache);
        continue;
      }

      if (!cache[hash]) cache[hash] = {};
      for (var b of benchmarks) {
        if (cache_has(cache, hash, b)) {
          var val = cache[hash][b];
          var tag = val != null ? val.toFixed(5) + "s" : "ERROR";
          console.log(`  ${b}: ${tag} (cached)`);
          continue;
        }

        var bend_file = path.join(BENCH_DIR, b, "main.bend");
        try {
          var secs = bench_one(cli, bend_file);
          cache[hash][b] = secs;
          console.log(`  ${b}: ${secs.toFixed(5)}s`);
        } catch {
          cache[hash][b] = null;
          console.log(`  ${b}: ERROR`);
        }
      }

      // Save after each commit so progress survives interrupts
      cache_save(cache);
    }
  } finally {
    try {
      spawnSync("git", ["-C", repo, "worktree", "remove", "--force", wt]);
    } catch {}
  }

  // Generate and open the chart
  fs.mkdirSync(OUT_DIR, { recursive: true });
  fs.writeFileSync(OUT_HTML, gen_html(commits, benchmarks, cache));
  spawnSync("open", [OUT_HTML]);
  console.log(`\nDone! Chart: ${OUT_HTML}`);
}

main();
