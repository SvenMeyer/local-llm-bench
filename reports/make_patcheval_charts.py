#!/usr/bin/env python3
"""PatchEval charts: score vs time, score vs decode speed, outcomes per run.

Writes reports/charts/*.svg (standalone, light/dark aware) and reports/patcheval-charts.html (all charts,
hover tooltips, data table). Data comes from patcheval-data.json via make_patcheval_report.py, so rebuild
after every run:

    python3 reports/build_patcheval_data.py && python3 reports/make_patcheval_report.py \
        && python3 reports/make_patcheval_charts.py

New arm? Add it to FAMILY and LABEL below (and to OFFSETS if its label collides).
"""

from __future__ import annotations

import html
import math
import re
from pathlib import Path

import make_patcheval_report as R

HERE = Path(__file__).resolve().parent
OUT = HERE / "charts"

# Color group per arm: who made the quant for local runs (GSQ-RCO vs Unsloth, in Unsloth's logo green
# #14b789), the model for hosted runs. These four hues pass the dataviz validator all-pairs (CVD and
# normal vision, light and dark); anything else shares the neutral "other" ink and relies on its label.
FAMILY = {
    "deepseek": "deepseek", "iq3xxs": "gsq", "iq3s": "gsq", "udiq4xs": "unsloth", "ud31iq4xs": "unsloth",
    "ornith": "unsloth", "bonsai": "other", "mm_pi": "minimax", "mm_mcode": "minimax",
}  # fmt: skip
FAMILIES = [  # legend order
    ("gsq", "GSQ-RCO quants (local)"),
    ("unsloth", "Unsloth quants (local)"),
    ("deepseek", "DeepSeek V4.1 Flash (hosted)"),
    ("minimax", "MiniMax M3.1 Flash (hosted)"),
    ("other", "other local"),
]
LABEL = {
    "deepseek": "DeepSeek V4.1 Flash",
    "iq3xxs": "Qwen3.8 GSQ IQ3_XXS",
    "iq3s": "Qwen3.8 GSQ IQ3_S",
    "udiq4xs": "Qwen3.8 UD-IQ4_XS (Oct)",
    "ud31iq4xs": "Qwen3.8 UD-IQ4_XS v3.1",
    "ornith": "Ornith-1.5 122B",
    "bonsai": "Bonsai 2 27B",
    "mm_pi": "MiniMax · pi",
    "mm_mcode": "MiniMax · mcode",
}
HOSTED = {k for k in R.ARMS if R.D[k]["runtime"].startswith("hosted")}
PARTIAL = set(R.STATUS)

# Label placement per chart: key -> (label x, label y) in data units, or (dx, dy) px when "px".
OFFSETS: dict[str, dict[str, tuple]] = {
    "time": {
        "deepseek": ("px", 14, 4, "start"),
        "iq3s": ("at", 21, 84, "end"),
        "iq3xxs": ("at", 27.5, 86, "middle"),
        "udiq4xs": ("at", 21, 72, "end"),
        "ud31iq4xs": ("at", 21, 60, "end"),
        "mm_mcode": ("at", 21, 52, "end"),
        "ornith": ("at", 21, 44, "end"),
        "mm_pi": ("at", 21, 36, "end"),
        "bonsai": ("at", 21, 28, "end"),
    },
    "speed": {
        "deepseek": ("px", -12, -12, "end"),
        "iq3xxs": ("px", 12, -10, "start"),
        "iq3s": ("px", -12, -10, "end"),
        "udiq4xs": ("px", -12, 4, "end"),
        "ud31iq4xs": ("px", 12, 4, "start"),
        "ornith": ("px", 0, 22, "middle"),
        "bonsai": ("px", 12, 18, "start"),
        "mm_pi": ("px", 12, 18, "start"),
        "mm_mcode": ("px", -12, 18, "end"),
    },
}

STATUS_ORDER = [("pass", "pass"), ("fail", "fail"), ("timeout", "timeout (30 min)"),
                ("length_exceeded", "reply hit output cap"), ("harness_error", "harness error")]  # fmt: skip

STYLE_LIGHT = """
svg{font-family:system-ui,-apple-system,"Segoe UI",sans-serif;
--surface:#fcfcfb;--ink:#0b0b0b;--ink2:#52514e;--muted:#898781;--grid:#e1e0d9;--axis:#c3c2b7;
--gsq:#2a78d6;--unsloth:#14b789;--deepseek:#eb6834;--minimax:#b8338a;--other:#898781;
--pass:#0ca30c;--fail:#d03b3b;--timeout:#fab219;--length_exceeded:#ec835a;--harness_error:#898781}
"""
STYLE = STYLE_LIGHT + """@media (prefers-color-scheme:dark){svg{--surface:#1a1a19;--ink:#f0efec;--ink2:#c3c2b7;--grid:#2c2c2a;--axis:#383835;
--gsq:#3987e5;--deepseek:#d95926;--minimax:#c94c9c}}
"""
CHART_CSS = """
.bg{fill:var(--surface)}.grid{stroke:var(--grid);stroke-width:1}.axis{stroke:var(--axis);stroke-width:1}
.tick{fill:var(--muted);font-size:12px;font-variant-numeric:tabular-nums}
.axlabel{fill:var(--ink2);font-size:13px;font-weight:600}
.lbl{fill:var(--ink);font-size:12.5px}.lbl .sc{fill:var(--ink2)}.note{fill:var(--muted);font-size:12px}
.lead{stroke:var(--muted);stroke-width:1;fill:none}.ref{stroke:var(--axis);stroke-width:1.5}
.dot{stroke:var(--surface);stroke-width:2}.hollow{fill:var(--surface)!important;stroke-width:2.5}
.f-gsq{fill:var(--gsq)}.f-unsloth{fill:var(--unsloth)}.f-deepseek{fill:var(--deepseek)}.f-minimax{fill:var(--minimax)}.f-other{fill:var(--other)}
.hollow.f-gsq{stroke:var(--gsq)}.hollow.f-unsloth{stroke:var(--unsloth)}.hollow.f-deepseek{stroke:var(--deepseek)}.hollow.f-minimax{stroke:var(--minimax)}
.hollow.f-other{stroke:var(--other)}
.seg-pass{fill:var(--pass)}.seg-fail{fill:var(--fail)}.seg-timeout{fill:var(--timeout)}
.seg-length_exceeded{fill:var(--length_exceeded)}.seg-harness_error{fill:var(--harness_error)}
.segtxt{font-size:12px;font-weight:600;fill:#fff}.segtxt.dark{fill:#0b0b0b}
.hit{fill:transparent;cursor:default}.mark:hover .dot,.mark:focus .dot{stroke:var(--ink)}
.rowlbl{fill:var(--ink);font-size:12.5px}.rowsub{fill:var(--muted);font-size:11.5px}
"""


def esc(x: object) -> str:
    return html.escape(str(x), quote=True)


def tip(k: str) -> str:
    s, a = R.S[k], R.D[k]
    extra = f" · {R.STATUS[k]}" if k in PARTIAL else ""
    return (f"{LABEL[k]} — {s['passed']}/{s['n']} ({s['pct']:.0f}%) · {s['mean_task_min']:.1f} min/task mean · "
            f"{s['tok_s']:.0f} tok/s · {s['out_per_task'] / 1000:.0f}k output tokens/task · {a['runtime']}{extra}")


def marker(k: str, x: float, y: float) -> str:
    cls = f"dot f-{FAMILY[k]}" + (" hollow" if k in PARTIAL else "")
    if k in HOSTED:
        return f"<rect class='{cls}' x='{x - 6:.1f}' y='{y - 6:.1f}' width='12' height='12' rx='2.5'/>"
    return f"<circle class='{cls}' cx='{x:.1f}' cy='{y:.1f}' r='6.5'/>"


def score_label(k: str) -> str:
    s = R.S[k]
    sc = f"{s['passed']}/{s['n']}" + (" (stopped)" if k in PARTIAL else "")
    return f"{esc(LABEL[k])} <tspan class='sc'>{esc(sc)}</tspan>"


def scatter(name: str, title: str, xs: dict[str, float], x_label: str, x_ticks: list[float], x_fmt,
            x_map, notes: list[str], ref: tuple[float, str] | None, standalone: bool) -> str:
    W, H = 960, 600
    L, Rm, T, B = 70, 30, 30, 64
    pw, ph = W - L - Rm, H - T - B

    def px(v: float) -> float:
        return L + x_map(v) * pw

    def py(pct: float) -> float:
        return T + ph - pct / 100 * ph

    o = [f"<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 {W} {H}' role='img' aria-labelledby='t-{name}'>",
         f"<title id='t-{name}'>{esc(title)}</title>"]
    if standalone:
        o.append(f"<style>{STYLE}{CHART_CSS}</style>")
    o.append(f"<rect class='bg' width='{W}' height='{H}' rx='10'/>")
    for p in range(0, 101, 20):
        o.append(f"<line class='grid' x1='{L}' x2='{L + pw}' y1='{py(p):.1f}' y2='{py(p):.1f}'/>"
                 f"<text class='tick' x='{L - 10}' y='{py(p) + 4:.1f}' text-anchor='end'>{p}%</text>")
    for t in x_ticks:
        o.append(f"<line class='grid' x1='{px(t):.1f}' x2='{px(t):.1f}' y1='{T}' y2='{T + ph}'/>"
                 f"<text class='tick' x='{px(t):.1f}' y='{T + ph + 20}' text-anchor='middle'>{esc(x_fmt(t))}</text>")
    o.append(f"<line class='axis' x1='{L}' x2='{L + pw}' y1='{T + ph}' y2='{T + ph}'/>"
             f"<line class='axis' x1='{L}' x2='{L}' y1='{T}' y2='{T + ph}'/>")
    if ref:
        rx, rtxt = ref
        o.append(f"<line class='ref' x1='{px(rx):.1f}' x2='{px(rx):.1f}' y1='{T}' y2='{T + ph}'/>"
                 f"<text class='note' x='{px(rx) - 6:.1f}' y='{T + 16}' text-anchor='end'>{esc(rtxt)}</text>")
    o.append(f"<text class='axlabel' x='{L + pw / 2}' y='{H - 18}' text-anchor='middle'>{esc(x_label)}</text>"
             f"<text class='axlabel' transform='translate(20 {T + ph / 2}) rotate(-90)' text-anchor='middle'>"
             "PatchEval pass rate (20 real bug fixes)</text>")
    for i, n in enumerate(notes):
        o.append(f"<text class='note' x='{L + 14}' y='{T + 20 + i * 17}'>{esc(n)}</text>")
    # draw qwen last so the cluster's focus series sits on top
    order = sorted(R.ARMS, key=lambda k: (FAMILY[k] in ("gsq", "unsloth"), k))
    for k in order:
        x, y = px(xs[k]), py(R.S[k]["pct"])
        spec = OFFSETS[name][k]
        if spec[0] == "px":
            _, dx, dy, anchor = spec
            lx, ly, lead = x + dx, y + dy, ""
        else:
            _, dxv, dyv, anchor = spec
            lx, ly = px(dxv), py(dyv)
            ex = lx + (4 if anchor == "start" else -4 if anchor == "end" else 0)
            if anchor == "middle":
                lead = f"<path class='lead' d='M{x:.1f},{y:.1f} L{lx:.1f},{ly + 5:.1f}'/>"
            else:
                lead = f"<path class='lead' d='M{x:.1f},{y:.1f} L{ex + (6 if anchor == 'end' else -6):.1f},{ly - 4:.1f} L{ex:.1f},{ly - 4:.1f}'/>"
        o.append(f"<g class='mark' tabindex='0' data-tip='{esc(tip(k))}'><title>{esc(tip(k))}</title>{lead}"
                 f"<circle class='hit' cx='{x:.1f}' cy='{y:.1f}' r='14'/>{marker(k, x, y)}"
                 f"<text class='lbl' x='{lx:.1f}' y='{ly:.1f}' text-anchor='{anchor}'>{score_label(k)}</text></g>")
    o.append("</svg>")
    return "".join(o)


def chart_time(standalone: bool) -> str:
    xs = {k: R.S[k]["mean_task_min"] for k in R.ARMS}
    return scatter(
        "time", "PatchEval pass rate vs mean time per task", xs, "Mean wall-clock time per task (minutes)",
        [0, 5, 10, 15, 20, 25, 30, 35], lambda t: f"{t:.0f}", lambda v: v / 35,
        ["↖ better: more fixes, less time", "circle = local laptop · square = hosted API · hollow = stopped after 6 of 20"],
        (30, "30-min limit per task"), standalone)


def chart_speed(standalone: bool) -> str:
    lo, hi = math.log10(5), math.log10(400)
    xs = {k: R.S[k]["tok_s"] for k in R.ARMS}
    return scatter(
        "speed", "PatchEval pass rate vs decode speed", xs, "Average stream decode speed (tokens/s, log scale)",
        [5, 10, 20, 50, 100, 200, 400], lambda t: f"{t:.0f}", lambda v: (math.log10(v) - lo) / (hi - lo),
        ["↗ better: more fixes, faster decode", "x axis is logarithmic; pass rate still starts at 0%"],
        None, standalone)


def chart_outcomes(standalone: bool) -> str:
    rows = R.ARMS
    W, rowh, T, L, Rm = 960, 40, 56, 250, 70
    H = T + rowh * len(rows) + 46
    pw = W - L - Rm
    o = [f"<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 {W} {H}' role='img' aria-labelledby='t-out'>",
         "<title id='t-out'>PatchEval outcome per task, by run</title>"]
    if standalone:
        o.append(f"<style>{STYLE}{CHART_CSS}</style>")
    o.append(f"<rect class='bg' width='{W}' height='{H}' rx='10'/>")
    # legend row
    lx = L
    for key, word in STATUS_ORDER[:4]:
        o.append(f"<rect class='seg-{key}' x='{lx}' y='22' width='12' height='12' rx='3'/>"
                 f"<text class='tick' x='{lx + 18}' y='32'>{esc(word)}</text>")
        lx += 30 + len(word) * 7
    for t in range(0, 21, 5):
        x = L + t / 20 * pw
        o.append(f"<line class='grid' x1='{x:.1f}' x2='{x:.1f}' y1='{T - 6}' y2='{T + rowh * len(rows)}'/>"
                 f"<text class='tick' x='{x:.1f}' y='{T + rowh * len(rows) + 20}' text-anchor='middle'>{t}</text>")
    o.append(f"<text class='note' x='{L + pw / 2}' y='{H - 8}' text-anchor='middle'>tasks (of 20)</text>")
    for i, k in enumerate(rows):
        s = R.S[k]
        y = T + i * rowh
        sub = re.sub(r",\s*\d+k ctx$", "", R.D[k]["runtime"]).replace("local: ", "").replace("hosted: ", "")
        o.append(f"<text class='rowlbl' x='{L - 12}' y='{y + 15}' text-anchor='end'>{esc(LABEL[k])}</text>"
                 f"<text class='rowsub' x='{L - 12}' y='{y + 30}' text-anchor='end'>{esc(sub)}</text>")
        x = L
        for key, word in STATUS_ORDER:
            n = s["outcomes"].get(key, 0)
            if not n:
                continue
            w = n / 20 * pw
            t = f"{LABEL[k]}: {n} {word}"
            o.append(f"<g class='mark' tabindex='0' data-tip='{esc(t)}'><title>{esc(t)}</title>"
                     f"<rect class='seg-{key}' x='{x + 1:.1f}' y='{y + 6}' width='{max(w - 2, 1):.1f}' height='24' rx='4'/>")
            if w >= 22:
                dark = " dark" if key == "timeout" else ""
                o.append(f"<text class='segtxt{dark}' x='{x + w / 2:.1f}' y='{y + 22}' text-anchor='middle'>{n}</text>")
            o.append("</g>")
            x += w
        end = f"{s['passed']}/{s['n']}" + (" stopped" if k in PARTIAL else "")
        o.append(f"<text class='lbl' x='{L + pw + 8 if s['n'] == 20 else x + 8:.1f}' y='{y + 22}'>{esc(end)}</text>")
    o.append("</svg>")
    return "".join(o)


CHARTS = [
    ("score-vs-time", chart_time, "Pass rate vs time per task",
     "The main view: how many of the 20 bug fixes each setup got right, against how long it took per task. "
     "Top left is best. Local runs bunch up at the 30-minute limit: they are slow enough that most tasks run out the clock."),
    ("score-vs-speed", chart_speed, "Pass rate vs decode speed",
     "Same pass rate against decode speed. Hosted models decode 6–15× faster. Among the local Qwen3.8 quants, "
     "the faster ones score higher, because fewer tasks hit the time limit."),
    ("outcomes", chart_outcomes, "Where the tasks went",
     "Outcome of every task per run. Yellow is a 30-minute timeout: that is where the local runs, and the v3.1 quant above all, lose points."),
]

PAGE_CSS = """
:root{--page:#f9f9f7;--card:#fcfcfb;--ink:#0b0b0b;--ink2:#52514e;--muted:#898781;--line:rgba(11,11,11,.10)}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){--page:#0d0d0d;--card:#1a1a19;--ink:#f0efec;
--ink2:#c3c2b7;--line:rgba(255,255,255,.10)}
:root:where(:not([data-theme="light"])) svg{--surface:#1a1a19;--ink:#f0efec;--ink2:#c3c2b7;--grid:#2c2c2a;--axis:#383835;
--gsq:#3987e5;--deepseek:#d95926;--minimax:#c94c9c}}
:root[data-theme="dark"]{--page:#0d0d0d;--card:#1a1a19;--ink:#f0efec;--ink2:#c3c2b7;--line:rgba(255,255,255,.10)}
:root[data-theme="dark"] svg{--surface:#1a1a19;--ink:#f0efec;--ink2:#c3c2b7;--grid:#2c2c2a;--axis:#383835;
--gsq:#3987e5;--deepseek:#d95926;--minimax:#c94c9c}
*{box-sizing:border-box}
body{margin:0;background:var(--page);color:var(--ink);font:15px/1.55 system-ui,-apple-system,"Segoe UI",sans-serif}
main{max-width:1000px;margin:0 auto;padding:32px 16px 64px}
h1{font-size:26px;margin:0 0 4px;letter-spacing:-.01em}h2{font-size:19px;margin:36px 0 6px}
.sub,.cap{color:var(--ink2);margin:0 0 14px}.cap{font-size:14px;max-width:760px}
.top{display:flex;justify-content:space-between;gap:12px;align-items:flex-start;flex-wrap:wrap}
button{font:inherit;font-size:13px;color:var(--ink2);background:var(--card);border:1px solid var(--line);
border-radius:8px;padding:5px 10px;cursor:pointer}
.legend{display:flex;flex-wrap:wrap;gap:6px 18px;margin:0 0 10px;font-size:13px;color:var(--ink2)}
.legend i{display:inline-block;width:11px;height:11px;border-radius:50%;margin-right:6px;vertical-align:-1px}
.frame{overflow-x:auto;border:1px solid var(--line);border-radius:12px;background:var(--card)}
.frame svg{display:block;width:100%;min-width:640px;height:auto}
.files{font-size:13px;color:var(--muted);margin:6px 0 0}.files a{color:var(--ink2)}
table{border-collapse:collapse;width:100%;font-size:13.5px}
th,td{padding:8px 10px;border-bottom:1px solid var(--line);text-align:left;white-space:nowrap}td.w{white-space:normal;min-width:220px}
th{color:var(--ink2);font-weight:600}td.n{text-align:right;font-variant-numeric:tabular-nums}
tr:last-child td{border-bottom:none}
#tip{position:fixed;pointer-events:none;max-width:340px;background:var(--card);color:var(--ink);border:1px solid var(--line);
border-radius:8px;padding:8px 10px;font-size:13px;line-height:1.4;box-shadow:0 4px 18px rgba(0,0,0,.18);display:none;z-index:5}
ul{padding-left:20px;color:var(--ink2);font-size:14px}li{margin:4px 0}
"""

TIP_JS = """
(()=>{const t=document.getElementById('tip');
const show=(e,el)=>{t.textContent=el.dataset.tip;t.style.display='block';
const r=el.getBoundingClientRect(),x=(e&&e.clientX)||r.left+r.width/2,y=(e&&e.clientY)||r.top;
t.style.left=Math.min(x+14,innerWidth-t.offsetWidth-8)+'px';t.style.top=Math.max(8,y-t.offsetHeight-12)+'px'};
document.querySelectorAll('.mark').forEach(el=>{el.querySelector('title')?.remove();
el.addEventListener('mousemove',e=>show(e,el));el.addEventListener('mouseleave',()=>t.style.display='none');
el.addEventListener('focus',()=>show(null,el));el.addEventListener('blur',()=>t.style.display='none')});
const b=document.getElementById('theme'),root=document.documentElement;
const cur=()=>root.dataset.theme||(matchMedia('(prefers-color-scheme: dark)').matches?'dark':'light');
const lab=()=>b.textContent=cur()==='dark'?'Light mode':'Dark mode';lab();
b.onclick=()=>{root.dataset.theme=cur()==='dark'?'light':'dark';lab()}})();
"""


def legend_html() -> str:
    used = {FAMILY[k] for k in R.ARMS}
    items = [f"<span><i style='background:var(--sw-{f})'></i>{esc(n)}</span>" for f, n in FAMILIES if f in used]
    return "<div class='legend'>" + "".join(items) + "<span>● local · ■ hosted · hollow = stopped after 6/20</span></div>"


def table_html() -> str:
    head = ["Run", "Runs on", "Score", "Pass rate", "Mean min/task", "Total h", "Decode tok/s", "Output tok/task"]
    o = ["<div class='frame'><table><thead><tr>" + "".join(f"<th>{h}</th>" for h in head) + "</tr></thead><tbody>"]
    for k in R.ARMS:
        s, a = R.S[k], R.D[k]
        o.append(f"<tr><td>{esc(LABEL[k])} <span style='color:var(--muted)'>({esc(a['harness'].split()[0])})</span></td>"
                 f"<td class='w'>{esc(a['runtime'])}</td><td class='n'>{s['passed']}/{s['n']}{' *' if k in PARTIAL else ''}</td>"
                 f"<td class='n'>{s['pct']:.0f}%</td><td class='n'>{s['mean_task_min']:.1f}</td>"
                 f"<td class='n'>{s['total_h']:.1f}</td><td class='n'>{s['tok_s']:.0f}</td>"
                 f"<td class='n'>{s['out_per_task'] / 1000:.0f}k</td></tr>")
    o.append("</tbody></table></div><p class='files'>* stopped after 6 of 20 tasks (API credit used up); not ranked.</p>")
    return "".join(o)


def page() -> str:
    sw = (":root{--sw-gsq:#2a78d6;--sw-unsloth:#14b789;--sw-deepseek:#eb6834;--sw-minimax:#b8338a;--sw-other:#898781}"
          "@media (prefers-color-scheme:dark){:root:not([data-theme='light']){--sw-gsq:#3987e5;--sw-deepseek:#d95926;--sw-minimax:#c94c9c}}"
          ":root[data-theme='dark']{--sw-gsq:#3987e5;--sw-deepseek:#d95926;--sw-minimax:#c94c9c}")
    o = ["<!doctype html><html lang='en'><head><meta charset='utf-8'>",
         "<meta name='viewport' content='width=device-width,initial-scale=1'><title>PatchEval Model Charts</title>",
         f"<style>{STYLE_LIGHT}{CHART_CSS}{PAGE_CSS}{sw}</style></head><body><main>",
         "<div class='top'><div><h1>PatchEval: every model and variant we tested</h1>",
         f"<p class='sub'>BenchKit PatchEval, 20 real Python bug fixes, 30 min per task, pi or mcode agent · updated {R.DATE}</p></div>",
         "<button id='theme' type='button'>Dark mode</button></div>"]
    for stem, fn, title, cap in CHARTS:
        o.append(f"<h2>{esc(title)}</h2><p class='cap'>{esc(cap)}</p>")
        if stem != "outcomes":
            o.append(legend_html())
        o.append(f"<div class='frame'>{fn(False)}</div>"
                 f"<p class='files'>SVG file: <a href='charts/{stem}.svg'>charts/{stem}.svg</a></p>")
    o.append("<h2>Data</h2>" + table_html())
    o.append("<h2>Notes</h2><ul>"
             "<li>Pass rate counts the re-graded <code>pygments-2828</code> as a pass for the older full runs (flawed hidden test, "
             "BenchKit issue #89); the v3.1 run used the fixed test directly.</li>"
             "<li>Local runs: one laptop (RTX 4070 Laptop 8 GB, 125 GB RAM). Hosted speed depends on the gateway's provider.</li>"
             "<li>Only one run per setup: ±1–2 tasks is noise.</li>"
             "<li>The 24-run agent suite is not charted: every Qwen3.8 setup scores 24/24 on it.</li>"
             "<li>Full report: <a href='2026-11-02_PatchEval_Report_local-vs-hosted.html'>PatchEval report</a>. "
             "Rebuild: <code>python3 reports/make_patcheval_charts.py</code>.</li></ul>")
    o.append(f"<div id='tip' role='tooltip'></div><script>{TIP_JS}</script></main></body></html>")
    return "".join(o)


if __name__ == "__main__":
    missing = [k for k in R.ARMS if k not in FAMILY or k not in LABEL]
    if missing:
        raise SystemExit(f"add these arms to FAMILY/LABEL/OFFSETS: {missing}")
    OUT.mkdir(exist_ok=True)
    for stem, fn, *_ in CHARTS:
        (OUT / f"{stem}.svg").write_text(fn(True))
        print(OUT / f"{stem}.svg")
    (HERE / "patcheval-charts.html").write_text(page())
    print(HERE / "patcheval-charts.html")
