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

// Solarized light accent colors for chart lines
var SOL_LINES = [
  "#268bd2", "#dc322f", "#859900", "#b58900",
  "#d33682", "#2aa198", "#cb4b16", "#6c71c4",
  "#1a6091", "#a32422", "#5e6e00", "#866100",
  "#982870", "#1e756e", "#8e3510", "#4d508a",
  "#45a5dc", "#e35b59", "#9eb800", "#8b6914",
];

// Fixes u32_fib cache entries < 0.15 (spurious near-zero bug)
function fix_fib_cache(cache: Cache, commits: Commit[]): void {
  var last = null as number | null;
  for (var c of commits) {
    var e = cache[c.hash];
    if (!e || !("u32_fib" in e)) continue;
    var v = e.u32_fib;
    if (v != null && v >= 0.15) {
      last = v;
    } else if (v != null && v < 0.15 && last != null) {
      e.u32_fib = last;
    }
  }
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
    borderColor:     SOL_LINES[i % SOL_LINES.length],
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
    body {
      background: #fdf6e3;
      color: #657b83;
      font: 13px Menlo, Consolas, monospace;
      display: flex;
      flex-direction: column;
      height: 100vh;
      overflow: hidden;
    }
    #top { flex: 1; display: flex; overflow: hidden; }
    #scroll {
      flex: 1; overflow-x: auto; overflow-y: hidden;
      cursor: crosshair;
    }
    #scroll.dragging { cursor: grabbing; }
    #inner { height: 100%; }
    #legend {
      width: 170px; padding: 32px 8px 8px; overflow-y: auto;
      background: #eee8d5; border-left: 1px solid #93a1a1;
      font-size: 11px; flex-shrink: 0;
    }
    .li {
      display: flex; align-items: center; gap: 6px;
      padding: 3px 5px; cursor: pointer; border-radius: 3px;
      white-space: nowrap; color: #657b83;
    }
    .li:hover { background: rgba(0,0,0,0.06); }
    .li.hl { background: rgba(0,0,0,0.1); color: #073642; }
    .li.off { opacity: 0.35; text-decoration: line-through; }
    .box { width: 12px; height: 12px; border-radius: 2px; flex-shrink: 0; }
    #bar {
      height: 24px; background: #eee8d5;
      border-top: 1px solid #93a1a1;
      display: flex; align-items: center;
      padding: 0 12px; font-size: 12px;
      color: #586e75; gap: 16px;
    }
    #bar .mode {
      font-weight: bold; padding: 1px 8px;
      border-radius: 2px;
    }
    #bar .mode.normal { background: #859900; color: #fdf6e3; }
    #bar .mode.select { background: #268bd2; color: #fdf6e3; }
    #bar .info {
      flex: 1; overflow: hidden;
      text-overflow: ellipsis; white-space: nowrap;
    }
    #bar .right { white-space: nowrap; }
    #scroll::-webkit-scrollbar { height: 8px; }
    #scroll::-webkit-scrollbar-track { background: #eee8d5; }
    #scroll::-webkit-scrollbar-thumb { background: #93a1a1; border-radius: 4px; }
  </style>
</head>
<body>
  <div id="top">
    <div id="scroll"><div id="inner"><canvas id="c"></canvas></div></div>
    <div id="legend"></div>
  </div>
  <div id="bar">
    <span class="mode normal" id="mode">NORMAL</span>
    <span class="info" id="info"></span>
    <span class="right" id="right"></span>
  </div>
  <script>
    // Data
    // ----

    var MSGS     = ${JSON.stringify(msgs)};
    var DATA     = { labels: ${JSON.stringify(labels)}, datasets: ${JSON.stringify(datasets)} };
    var scrollEl = document.getElementById("scroll");
    var innerEl  = document.getElementById("inner");
    var legendEl = document.getElementById("legend");
    var modeEl   = document.getElementById("mode");
    var infoEl   = document.getElementById("info");
    var rightEl  = document.getElementById("right");

    // State
    // -----

    var nPoints  = DATA.labels.length;
    var pxPer    = 50;
    var cursor   = 0;
    var selected = new Set();
    var hlIdx    = -1;
    var dragging = false;
    var dragX    = 0;
    var dragSL   = 0;

    // Snapshot for reset after filter
    var origLabels   = DATA.labels.slice();
    var origMsgs     = MSGS.slice();
    var origDatasets  = DATA.datasets.map(function(ds) {
      return { data: ds.data.slice() };
    });

    // Helpers
    // -------

    // Converts hex color to rgba with given alpha
    function dimHex(hex) {
      var r = parseInt(hex.slice(1, 3), 16);
      var g = parseInt(hex.slice(3, 5), 16);
      var b = parseInt(hex.slice(5, 7), 16);
      return "rgba(" + r + "," + g + "," + b + ",0.25)";
    }

    // Pre-compute original and dimmed colors
    DATA.datasets.forEach(function(ds) {
      ds._origColor = ds.borderColor;
      ds._dimColor  = dimHex(ds.borderColor);
    });

    // Chart Plugin
    // ------------

    // Draws cursor line and selection highlights
    var overlayPlugin = {
      id: "overlays",
      afterDraw: function(ch) {
        var ctx  = ch.ctx;
        var xAx  = ch.scales.x;
        var area = ch.chartArea;
        if (!area) return;

        // Selected columns
        selected.forEach(function(idx) {
          if (idx >= nPoints) return;
          var x = xAx.getPixelForValue(idx);
          var w = Math.max(pxPer * 0.7, 6);
          ctx.fillStyle = "rgba(38, 139, 210, 0.15)";
          ctx.fillRect(x - w / 2, area.top, w, area.bottom - area.top);
        });

        // Cursor
        if (cursor >= 0 && cursor < nPoints) {
          var x = xAx.getPixelForValue(cursor);
          ctx.save();
          ctx.strokeStyle = "#268bd2";
          ctx.lineWidth   = 1.5;
          ctx.setLineDash([4, 3]);
          ctx.beginPath();
          ctx.moveTo(x, area.top);
          ctx.lineTo(x, area.bottom);
          ctx.stroke();
          ctx.restore();
        }
      }
    };

    // Layout
    // ------

    // Resizes chart width based on zoom level
    function resizeChart() {
      var w = Math.max(nPoints * pxPer, scrollEl.clientWidth);
      innerEl.style.width = w + "px";
      chart.resize();
    }

    // Returns [first, last] visible point indices
    function visibleRange() {
      var xAx = chart.scales.x;
      if (!xAx) return [0, nPoints - 1];
      var sl = scrollEl.scrollLeft;
      var vw = scrollEl.clientWidth;
      var lo = nPoints;
      var hi = -1;
      for (var i = 0; i < nPoints; i++) {
        var px = xAx.getPixelForValue(i);
        if (px >= sl - 20 && px <= sl + vw + 20) {
          if (i < lo) lo = i;
          if (i > hi) hi = i;
        }
      }
      if (lo > hi) { lo = 0; hi = nPoints - 1; }
      return [lo, hi];
    }

    // Updates y-axis max to fit visible data
    var yPending = false;
    function scheduleYUpdate() {
      if (yPending) return;
      yPending = true;
      requestAnimationFrame(function() {
        yPending = false;
        updateYAxis();
      });
    }

    function updateYAxis() {
      var range  = visibleRange();
      var maxVal = 0;
      var found  = false;
      chart.data.datasets.forEach(function(ds, di) {
        if (chart.getDatasetMeta(di).hidden) return;
        for (var i = range[0]; i <= range[1]; i++) {
          var v = ds.data[i];
          if (v != null && v > maxVal) {
            maxVal = v;
            found  = true;
          }
        }
      });
      if (!found) return;
      maxVal = Math.ceil(maxVal * 110) / 100;
      if (maxVal < 0.05) maxVal = 0.1;
      chart.options.scales.y.max = maxVal;
      chart.update("none");
    }

    // Highlight
    // ---------

    // Bolds one dataset line, dims all others
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

    // Status Bar
    // ----------

    // Updates the vim-like status bar
    function updateBar() {
      var has = selected.size > 0;
      modeEl.textContent = has ? "SELECT" : "NORMAL";
      modeEl.className   = "mode " + (has ? "select" : "normal");
      if (cursor >= 0 && cursor < nPoints) {
        infoEl.textContent = DATA.labels[cursor] + "  " + MSGS[cursor];
      } else {
        infoEl.textContent = "";
      }
      var parts = [];
      if (has) parts.push(selected.size + " selected");
      parts.push(nPoints + " commits");
      rightEl.textContent = parts.join(" | ");
    }

    // Legend
    // ------

    // Builds clickable legend sidebar
    DATA.datasets.forEach(function(ds, i) {
      var el = document.createElement("div");
      el.className = "li";
      el.innerHTML = '<div class="box" style="background:' + ds._origColor + '"></div>' + ds.label;
      el.addEventListener("click", function() {
        var meta = chart.getDatasetMeta(i);
        meta.hidden = !meta.hidden;
        el.classList.toggle("off");
        chart.update();
        scheduleYUpdate();
      });
      el.addEventListener("mouseenter", function() { setHighlight(i); });
      el.addEventListener("mouseleave", function() { setHighlight(-1); });
      legendEl.appendChild(el);
    });

    // Selection
    // ---------

    // Scrolls to keep cursor visible
    function ensureCursorVisible() {
      var xAx = chart.scales.x;
      if (!xAx) return;
      var px     = xAx.getPixelForValue(cursor);
      var sl     = scrollEl.scrollLeft;
      var vw     = scrollEl.clientWidth;
      var margin = 40;
      if (px < sl + margin) {
        scrollEl.scrollLeft = px - margin;
      } else if (px > sl + vw - margin) {
        scrollEl.scrollLeft = px - vw + margin;
      }
    }

    // Keeps only selected columns, rebuilds chart
    function applyFilter() {
      var indices   = Array.from(selected).sort(function(a, b) { return a - b; });
      var newLabels = indices.map(function(i) { return DATA.labels[i]; });
      var newMsgs   = indices.map(function(i) { return MSGS[i]; });
      var newData   = DATA.datasets.map(function(ds) {
        return indices.map(function(i) { return ds.data[i]; });
      });
      chart.data.labels = newLabels;
      chart.data.datasets.forEach(function(ds, di) {
        ds.data = newData[di];
      });
      DATA.labels = newLabels;
      MSGS        = newMsgs;
      nPoints     = newLabels.length;
      cursor      = 0;
      selected.clear();
      pxPer = Math.max(10, Math.floor(scrollEl.clientWidth / nPoints));
      resizeChart();
      scheduleYUpdate();
      updateBar();
    }

    // Restores original unfiltered data
    function resetFilter() {
      chart.data.labels = origLabels.slice();
      DATA.labels       = origLabels.slice();
      MSGS              = origMsgs.slice();
      chart.data.datasets.forEach(function(ds, di) {
        ds.data = origDatasets[di].data.slice();
      });
      nPoints = origLabels.length;
      cursor  = 0;
      selected.clear();
      pxPer = Math.max(2, Math.floor(scrollEl.clientWidth / nPoints));
      resizeChart();
      scheduleYUpdate();
      updateBar();
    }

    // Events
    // ------

    // Drag-to-scroll
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

    // Hover to set cursor
    document.getElementById("c").addEventListener("mousemove", function(e) {
      if (dragging) return;
      var xAx = chart.scales.x;
      if (!xAx) return;
      var rect = e.target.getBoundingClientRect();
      var x    = e.clientX - rect.left;
      var idx  = Math.round(xAx.getValueForPixel(x));
      var idx  = Math.max(0, Math.min(nPoints - 1, idx));
      if (idx !== cursor) {
        cursor = idx;
        chart.update("none");
        updateBar();
      }
    });

    // Ctrl/Cmd+wheel to zoom, plain wheel to scroll
    scrollEl.addEventListener("wheel", function(e) {
      if (e.ctrlKey || e.metaKey) {
        e.preventDefault();
        var oldW = innerEl.clientWidth;
        var frac = (scrollEl.scrollLeft + e.offsetX) / oldW;
        pxPer    = Math.max(2, Math.min(200, pxPer + (e.deltaY > 0 ? -5 : 5)));
        resizeChart();
        var newW = innerEl.clientWidth;
        scrollEl.scrollLeft = frac * newW - e.offsetX;
        scheduleYUpdate();
      }
    }, { passive: false });

    // Y-axis update on scroll
    scrollEl.addEventListener("scroll", function() {
      scheduleYUpdate();
    });

    // Keyboard navigation and selection
    document.addEventListener("keydown", function(e) {
      switch (e.key) {
        case "ArrowLeft":
        case "h": {
          e.preventDefault();
          cursor = Math.max(0, cursor - 1);
          ensureCursorVisible();
          chart.update("none");
          updateBar();
          break;
        }
        case "ArrowRight":
        case "l": {
          e.preventDefault();
          cursor = Math.min(nPoints - 1, cursor + 1);
          ensureCursorVisible();
          chart.update("none");
          updateBar();
          break;
        }
        case " ": {
          e.preventDefault();
          if (cursor >= 0 && cursor < nPoints) {
            selected.add(cursor);
            cursor = Math.min(nPoints - 1, cursor + 1);
            ensureCursorVisible();
            chart.update("none");
            updateBar();
          }
          break;
        }
        case "Enter": {
          e.preventDefault();
          if (selected.size > 0) applyFilter();
          break;
        }
        case "Escape": {
          e.preventDefault();
          if (selected.size > 0) {
            selected.clear();
            chart.update("none");
            updateBar();
          } else {
            resetFilter();
          }
          break;
        }
      }
    });

    // Chart
    // -----

    // Create chart with solarized light theme
    var chart = new Chart(document.getElementById("c"), {
      type: "line",
      data: DATA,
      plugins: [overlayPlugin],
      options: {
        responsive:          true,
        maintainAspectRatio: false,
        animation:           false,
        interaction: { mode: "nearest", intersect: false },
        onHover: function(evt, elms) {
          if (dragging) return;
          setHighlight(elms.length > 0 ? elms[0].datasetIndex : -1);
        },
        plugins: {
          title: {
            display: true,
            text:    "Bend-Node Benchmark Timeline",
            color:   "#073642",
            font:    { size: 16, family: "Menlo, monospace" },
          },
          legend:  { display: false },
          tooltip: { enabled: false },
        },
        scales: {
          x: {
            ticks: {
              color:       "#657b83",
              font:        { family: "Menlo, monospace", size: 9 },
              maxRotation: 90,
            },
            grid: { color: "#eee8d5" },
          },
          y: {
            min: 0,
            ticks: {
              color: "#657b83",
              font:  { family: "Menlo, monospace" },
            },
            grid:  { color: "#eee8d5" },
            title: {
              display: true,
              text:    "seconds",
              color:   "#586e75",
              font:    { family: "Menlo, monospace" },
            },
          },
        },
      },
    });

    // Init
    // ----

    // Start maximally zoomed out
    pxPer = Math.max(2, Math.floor(scrollEl.clientWidth / nPoints));
    resizeChart();
    scheduleYUpdate();
    updateBar();
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

  // Fix spurious u32_fib entries and generate chart
  fix_fib_cache(cache, commits);
  cache_save(cache);
  fs.mkdirSync(OUT_DIR, { recursive: true });
  fs.writeFileSync(OUT_HTML, gen_html(commits, benchmarks, cache));
  spawnSync("open", [OUT_HTML]);
  console.log(`\nDone! Chart: ${OUT_HTML}`);
}

main();
